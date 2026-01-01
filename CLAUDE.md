# SiYuan Password - Claude Code 项目文档

这是一个思源笔记（SiYuan）的修改版本，主要增强了密码锁定功能。本文档为 Claude Code 实例提供项目上下文和技术指南。

## 项目概览

**项目类型**: Electron 桌面应用 + TypeScript + WebSocket 实时通信
**基础版本**: SiYuan 3.1.15
**主要功能增强**: 笔记本/文档级别的密码保护系统
**包管理器**: pnpm 9.12.1
**构建工具**: Webpack 5
**项目性质**: 思源笔记 Fork 版本，包含解锁功能补丁
**Docker 镜像**: apkdv/siyuan-unlock

---

## 快速命令参考

### 开发与构建
```bash
# 安装依赖
pnpm install

# ⚠️ 应用项目补丁（必须步骤）
cd app && pnpm run apply-patches
# 或者直接运行
bash scripts/apply-patches.sh

# 开发模式（热重载）
cd app && pnpm run dev

# 启动 Electron 应用
cd app && pnpm run start

# TypeScript 编译检查
cd app && pnpm run tsc

# 代码质量检查
cd app && pnpm run lint

# 生产构建
cd app && pnpm run build

# 平台特定构建
cd app && pnpm run dist-darwin     # macOS
cd app && pnpm run dist-win        # Windows
cd app && pnpm run dist-linux      # Linux
cd app && pnpm run dist-appx       # Windows Store
```

### 测试与验证
```bash
# 运行所有 lint 检查
cd app && pnpm run lint

# TypeScript 类型检查
cd app && pnpm run tsc
```

### Docker 部署
```bash
# 构建 Docker 镜像（自动应用补丁）
docker build -t apkdv/siyuan-unlock .

# 运行容器
docker run -d \
  -v /siyuan/workspace:/siyuan/workspace \
  -p 6806:6806 \
  -e PUID=1001 -e PGID=1002 \
  apkdv/siyuan-unlock \
  --workspace=/siyuan/workspace/ \
  --accessAuthCode=your_password
```

**Docker 构建自动应用补丁**:
- ✅ `default-config.patch` - 修改默认云同步配置
- ✅ `disable-update.patch` - 禁用自动更新检查
- ✅ `mock-vip-user.patch` - 模拟 VIP 用户（移除订阅限制）

**补丁详细说明**: 参见 [patches/README.md](patches/README.md)

---

## 项目架构

### 高层架构

```
siyuan-password/
├── app/                          # 主应用程序
│   ├── src/                      # TypeScript 源代码
│   │   ├── index.ts             # 应用入口点，初始化 App 类
│   │   ├── plugin/              # 插件系统（密码锁插件集成点）
│   │   │   ├── index.ts         # Plugin 基类定义
│   │   │   ├── loader.ts        # 插件加载器
│   │   │   ├── EventBus.ts      # 事件总线系统
│   │   │   └── API.ts           # 插件 API 接口
│   │   ├── layout/              # 布局和 UI 管理
│   │   ├── protyle/             # 编辑器核心
│   │   ├── block/               # 块级操作
│   │   ├── util/                # 工具函数
│   │   ├── sync/                # 云同步模块
│   │   └── constants.ts         # 全局常量
│   ├── webpack.*.js             # 多目标构建配置
│   ├── package.json             # 依赖和脚本
│   └── tsconfig.json            # TypeScript 配置
├── patches/                      # 项目补丁文件
│   └── siyuan/                  # 思源核心补丁
│       ├── default-config.patch  # 默认配置修改
│       ├── disable-update.patch  # 禁用自动更新
│       └── mock-vip-user.patch   # 模拟 VIP 用户
├── kernel/                       # 后端内核（Go 语言）
├── android/                      # Android 应用
├── scripts/                      # 构建和部署脚本
├── claudedocs/                   # 设计文档（Claude 专用）
│   ├── 笔记加锁功能设计文档.md      # v2.1 核心设计（已验证）
│   └── 技术实现细节补充文档.md      # 完整技术实现指南
├── Dockerfile                    # Docker 镜像构建配置
├── README.md                     # 用户文档（含 Docker 部署）
└── CLAUDE.md                     # 本文档
```

### 核心技术栈

| 层级 | 技术 | 用途 |
|------|------|------|
| **桌面容器** | Electron | 跨平台桌面应用框架 |
| **编程语言** | TypeScript (ES6+) | 类型安全的主要开发语言 |
| **构建系统** | Webpack 5 | 多目标打包（desktop/mobile/export） |
| **UI 框架** | 原生 DOM + SCSS | 轻量级 UI 实现 |
| **实时通信** | WebSocket | 双向消息传递（同步、插件事件） |
| **数据持久化** | SQLite | 本地数据库（插件使用 `password_locks.db`） |
| **包管理** | pnpm | 高效依赖管理 |

---

## 插件系统架构（密码锁集成）

### Plugin 基类结构

**文件**: `app/src/plugin/index.ts`

```typescript
export class Plugin {
    public eventBus: EventBus;           // 事件总线，监听 ws-main 事件
    public data: any = {};                // 插件持久化数据

    // 生命周期钩子
    onload()          // 插件加载时调用
    onunload()        // 插件禁用时调用
    uninstall()       // 插件卸载时调用
    onLayoutReady()   // 布局加载完成时调用

    // 数据持久化 API
    loadData(storageName)   // 从 /data/storage/petal/{name}/ 加载
    saveData(storageName, data)  // 保存到插件存储目录
    removeData(storageName) // 删除存储数据

    // UI 扩展
    addTopBar(options)      // 添加顶部栏图标
    addStatusBar(options)   // 添加状态栏元素
    addCommand(command)     // 注册命令快捷键
}
```

### WebSocket 事件系统

**文件**: `app/src/index.ts` (App 类)

WebSocket 消息通过 `Model` 类处理，所有插件通过 `eventBus.emit('ws-main', data)` 接收事件：

```typescript
window.siyuan.ws = new Model({
    msgCallback: (data) => {
        this.plugins.forEach((plugin) => {
            plugin.eventBus.emit("ws-main", data);  // 广播给所有插件
        });

        switch (data.cmd) {
            case "reloaddoc":     // 文档重新加载
            case "readonly":      // 只读模式切换
            case "rename":        // 文档/笔记本重命名
            case "removeDoc":     // 文档删除（未在代码中显示）
            case "unmount":       // 笔记本卸载
            case "openFileById":  // 文档打开（关键拦截点）
            case "syncing":       // 云同步状态
            // ... 其他事件
        }
    }
});
```

### 密码锁插件数据存储

**存储路径**: `/data/storage/petal/siyuan-password/password_locks.db`

使用 `Plugin.saveData()` 和 `Plugin.loadData()` API 访问插件专用存储目录。

---

## 密码锁功能设计要点

> 详细设计参见 `claudedocs/笔记加锁功能设计文档.md` (v2.1 - 已源码验证)
> 完整技术实现参见 `claudedocs/技术实现细节补充文档.md`

### v2.1 版本更新要点（2025-12-30）

#### ✅ 源码验证完成，关键问题已解决

1. **笔记本嵌套** ❌ → 已确认不支持
   - Box 结构体无 `parentId` 字段
   - 简化为单层扁平设计
   - 降低复杂度，提高稳定性

2. **云同步机制** ✅ → 已确认自动进行
   - `repository.go` 自动处理 `/storage/petal/` 路径
   - `password_locks.db` 会自动云同步
   - 无需增加自定义同步逻辑

3. **openFileById 拦截** ✅ → Hook 方案已确认可行
   - 采用函数 Hook 在 `openFileById` 处拦截
   - 在文档打开**之前**验证密码
   - 实现位置：`app/src/editor/util.ts:39`

### 关键技术决策

1. **WebSocket 事件聚合模式**（已验证 ✅）
   - **问题**: 多插件直接重写 `ws.onmessage` 会导致事件丢失
   - **解决方案**: 使用 EventBus 模式，所有插件通过 `eventBus.on('ws-main', callback)` 订阅事件
   - **实现位置**: `app/src/plugin/EventBus.ts`
   - **验证结果**: 思源已正确实现，无需修改

2. **内存安全保护**
   - 使用 `WeakMap` 存储解锁状态，防止内存泄漏
   - Session Token + 内部 Key 双重验证机制
   - 敏感数据不直接存储在全局对象
   - 10分钟自动清除解锁状态

3. **云同步策略**（已验证 ✅）
   - **Last-Write-Wins**: 时间戳冲突解决
   - **自动同步**: `/data/storage/petal/` 路径自动云同步
   - **无需监听**: 不需要监听 `syncing` 事件
   - **实现位置**: `kernel/repository.go`

4. **安全机制**
   - bcrypt 密码哈希（成本因子 10）
   - 指数退避防暴力破解（2^n 秒，从第3次失败开始）
   - 三层备份：本地自动备份 + 恢复密钥 + 数据库完整性检查
   - 审计日志完整记录所有操作

### 开发进度调整

**工作量优化**（相比 v2.0）:
- Phase 0: 3周 → 2.5周 (-0.5周)
- Phase 1: 5周 → 4周 (-1周)
- **总计**: 11周 → **9.5周**（提前1周发布）

**源码验证带来的收益**:
- 移除笔记本嵌套复杂度
- 云同步自动完成，无需自定义逻辑
- Hook 方案清晰，实现路径明确

---

## 代码模式与最佳实践

### 1. TypeScript 约定

```typescript
// 使用 interface 定义类型
interface IPluginDockTab {
    icon: string;
    title: string;
    hotkey?: string;
}

// 常量使用大写下划线
const INLINE_TYPE = ["strong", "em", "code"];

// 条件编译（移动端 vs 桌面端）
/// #if !MOBILE
import {Custom} from "../layout/dock/Custom";
/// #else
import {MobileCustom} from "../mobile/dock/MobileCustom";
/// #endif
```

### 2. 事件处理模式

```typescript
// 推荐：使用 EventBus 订阅事件
this.eventBus.on("ws-main", (data) => {
    if (data.cmd === "openFileById") {
        // 拦截文档打开
        const blockId = data.data.id;
        if (isLocked(blockId)) {
            showPasswordDialog();
            return; // 阻止默认行为
        }
    }
});

// 避免：直接重写 onmessage（会导致多插件冲突）
window.siyuan.ws.ws.onmessage = (event) => { /* 不要这样做 */ }
```

### 3. 数据持久化模式

```typescript
// 插件数据保存
class PasswordLockPlugin extends Plugin {
    async saveLocks(locks: PasswordLock[]) {
        await this.saveData("password_locks.db", locks);
    }

    async loadLocks(): Promise<PasswordLock[]> {
        const data = await this.loadData("password_locks.db");
        return data || [];
    }
}
```

### 4. API 调用模式

```typescript
import {fetchPost} from "./util/fetch";

// HTTP API 调用示例
fetchPost("/api/notebook/lsNotebooks", {}, (response) => {
    if (response.code === 0) {
        const notebooks = response.data.notebooks;
        // 处理笔记本列表
    }
});
```

---

## 构建配置

### Webpack 多目标构建

```javascript
// webpack.*.js 文件
webpack.dev.js       // 开发构建（带 source maps）
webpack.desktop.js   // 桌面端生产构建
webpack.mobile.js    // 移动端构建
webpack.export.js    // 导出功能构建
```

### 环境变量与条件编译

代码中使用 `/// #if CONDITION` 实现不同平台的条件编译：

```typescript
/// #if BROWSER
registerServiceWorker();
/// #endif

/// #if MOBILE
// 移动端特定代码
/// #else
// 桌面端特定代码
/// #endif
```

---

## 开发工作流

### 启动开发环境

1. **安装依赖**: `pnpm install`（项目根目录和 `app/` 目录都需要）
2. **启动热重载**: `cd app && pnpm run dev`
3. **启动应用**: 新终端 `cd app && pnpm run start`
4. **修改代码**: 编辑 `app/src/` 下的文件，Webpack 自动重新编译

### 生产构建流程

1. **类型检查**: `cd app && pnpm run tsc`
2. **代码检查**: `cd app && pnpm run lint`
3. **构建**: `cd app && pnpm run build`
4. **打包分发**: `cd app && pnpm run dist-{platform}`

---

## 关键文件位置

| 功能 | 文件路径 |
|------|---------|
| 应用入口 | `app/src/index.ts` |
| 插件基类 | `app/src/plugin/index.ts` |
| 插件加载器 | `app/src/plugin/loader.ts` |
| 事件总线 | `app/src/plugin/EventBus.ts` |
| WebSocket 模型 | `app/src/layout/Model.ts` |
| 常量定义 | `app/src/constants.ts` |
| 工具函数 | `app/src/util/fetch.ts`, `app/src/util/functions.ts` |
| openFileById 函数 | `app/src/editor/util.ts:39` (Hook 拦截点) |
| 后端云同步 | `kernel/repository.go` (自动同步 petal 路径) |
| **设计文档** | |
| 密码锁核心设计 | `claudedocs/笔记加锁功能设计文档.md` (v2.1) |
| 技术实现细节 | `claudedocs/技术实现细节补充文档.md` (完整代码示例) |
| **补丁文件** | |
| 默认配置修改 | `patches/siyuan/default-config.patch` |
| 禁用自动更新 | `patches/siyuan/disable-update.patch` |
| 模拟 VIP 用户 | `patches/siyuan/mock-vip-user.patch` |

---

## 重要技术约束

### 1. 插件存储路径
- **绝对路径**: `/data/storage/petal/{pluginName}/`
- **API**: 必须使用 `Plugin.saveData()` 和 `Plugin.loadData()`
- **格式**: 支持 JSON 对象或原始字符串

### 2. WebSocket 事件
- **监听方式**: 通过 `eventBus.on('ws-main', callback)` 订阅
- **可用事件**: `removeDoc`, `unmount`, `rename`, `openFileById`, `reloaddoc`, `readonly`, `syncing`, `progress`
- **注意**: 不存在 `eventBus` 全局对象（v1.0 设计错误），必须使用插件实例的 `this.eventBus`

### 3. 打包目标
- **Desktop**: Electron 主进程 + 渲染进程
- **Mobile**: Android/iOS WebView
- **Export**: PDF/HTML 导出功能
- **条件编译**: 使用 `/// #if MOBILE` 区分平台代码

---

## 常见问题排查

### 插件未加载
1. 检查插件目录结构是否符合 SiYuan 插件规范
2. 确认 `plugin.json` 配置正确
3. 查看开发者工具控制台错误日志

### WebSocket 事件未触发
1. 确认使用 `this.eventBus.on('ws-main', callback)` 而非全局 `eventBus`
2. 检查 WebSocket 连接状态（`window.siyuan.ws.ws.readyState`）
3. 验证事件名称拼写（如 `openFileById` 而非 `openFile`）

### 数据未持久化
1. 检查存储路径是否正确（`/data/storage/petal/{name}/`）
2. 确认使用 `Plugin.saveData()` 而非直接文件写入
3. 查看 Network 面板确认 `/api/file/putFile` 请求成功

---

## 下一步开发计划

> 详见 `claudedocs/笔记加锁功能设计文档.md` v2.1 版本
> 完整技术实现参见 `claudedocs/技术实现细节补充文档.md`

### 开发路线图（优化后：9.5 周）

#### Week 1-2: Phase 0 - 核心功能实现（2.5 周）

**已简化项**（源码验证结果）:
- ✅ WebSocket 事件聚合：思源已实现，无需修改
- ✅ 云同步策略：自动处理，无需自定义逻辑

**需实现项**:
1. **数据库服务** (Day 1-2)
   - DatabaseService 实现（基于 Plugin.saveData/loadData）
   - 表结构创建和迁移
   - CRUD 操作封装

2. **密码管理器** (Day 3-4)
   - PasswordManager 核心逻辑
   - bcrypt 加密集成
   - 防暴力破解机制

3. **文档打开拦截** (Day 5-6)
   - openFileById Hook 实现
   - 密码验证流程集成

4. **内存安全保护** (Day 7-8)
   - SecureUnlockManager（WeakMap）
   - 10分钟自动清除机制

5. **WebSocket 事件处理** (Day 9-10)
   - removeDoc 事件处理
   - unmount 事件处理

6. **审计日志** (Day 11-12)
   - AuditLogger 实现
   - 日志查询接口

7. **恢复密钥和备份** (Day 13-14)
   - 恢复密钥加密存储
   - 数据库自动备份

8. **集成测试** (Day 15-17)

#### Week 3-6: Phase 1 - UI 和功能完善（4 周）

**简化项**（移除笔记本嵌套）:
- ✅ 无需笔记本关系映射（单层设计）

**需实现项**:
1. **密码对话框 UI** (Week 3)
   - 密码输入对话框
   - 密码设置对话框
   - 错误提示和进度显示

2. **设置界面** (Week 4)
   - 密码锁列表管理
   - 修改/删除密码锁
   - 恢复密钥管理

3. **顶部栏和菜单** (Week 5)
   - 顶部栏图标集成
   - 右键菜单扩展
   - 快捷键注册

4. **审计日志界面** (Week 6)
   - 日志查看界面
   - 日志过滤和搜索

#### Week 7-9: Phase 2 - 质量保证（3 周）

1. **单元测试** (Week 7)
   - 密码管理器测试
   - 数据库服务测试
   - 覆盖率 >80%

2. **集成测试和边缘用例** (Week 8)
   - 文档打开拦截测试
   - WebSocket 事件测试
   - 云同步测试
   - 边缘用例处理

3. **性能测试和优化** (Week 9)
   - bcrypt 性能测试
   - 数据库查询优化
   - 内存管理验证

4. **安全审计** (Week 9)
   - 密码安全检查
   - 内存泄露检查
   - 审计日志完整性

#### Week 10: Beta 测试和发布准备

1. 内部测试和 Bug 修复
2. 用户文档编写
3. Docker 镜像更新
4. 发布准备

### Phase 3: 正式发布 🚀 (Week 10 结束)

**里程碑**:
- ✅ 完整的密码锁功能
- ✅ 通过所有测试
- ✅ 文档完善
- ✅ Docker 镜像发布

---

## 参考资源

### 📚 官方文档

- **思源笔记 API**: [API_zh_CN.md](API_zh_CN.md) - 完整的后端 API 文档
- **思源笔记主仓库**: [siyuan-note/siyuan](https://github.com/siyuan-note/siyuan)
- **插件 API 文档**: [Petal 项目](https://github.com/siyuan-note/petal)
- **社区集市**: [Bazaar](https://github.com/siyuan-note/bazaar) - 插件和主题集市

### 🔧 项目特定资源

- **Docker 镜像**: [apkdv/siyuan-unlock](https://hub.docker.com/r/apkdv/siyuan-unlock)
- **项目 README**: [README.md](README.md) - 用户使用文档
- **Docker 部署文档**: [README.md](README.md#docker-部署) - Docker 部署详细说明

### 📖 本项目的设计文档

1. **核心设计文档** (claudedocs/笔记加锁功能设计文档.md)
   - 功能概述和架构设计
   - 数据结构和表定义
   - 密码验证流程
   - 云同步策略
   - 防暴力破解机制
   - 开发计划（Phase 0-3）
   - ✅ 已通过源码验证

2. **技术实现细节** (claudedocs/技术实现细节补充文档.md)
   - 完整的代码实现示例
   - DatabaseService 实现（CRUD 操作）
   - PasswordManager 核心逻辑
   - DocumentOpenInterceptor Hook 实现
   - WebSocketEventHandler 事件处理
   - UIManager 组件实现
   - 云同步兼容性分析
   - 错误处理和边缘用例
   - 性能优化建议
   - 测试计划和安全审计清单

### 🎯 关键概念速查

| 概念 | 说明 | 参考位置 |
|------|------|--------|
| **Plugin 基类** | 思源插件的基础类 | `app/src/plugin/index.ts` / CLAUDE.md 第115-142行 |
| **EventBus** | 事件总线系统，用于插件间通信 | `app/src/plugin/EventBus.ts` / CLAUDE.md 第215-219行 |
| **openFileById Hook** | 文档打开拦截点 | `app/src/editor/util.ts:39` / CLAUDE.md 第208-211行 |
| **WebSocket 事件** | 实时事件通知（removeDoc, unmount等） | `app/src/index.ts:60-163` / CLAUDE.md 第154-176行 |
| **Plugin.saveData/loadData** | 插件持久化数据存储 API | `/data/storage/petal/{pluginName}/` / CLAUDE.md 第172-175行 |
| **云同步路径** | 自动云同步的目录 | `/data/storage/petal/` / `kernel/repository.go` |
| **WeakMap** | 内存安全的解锁状态管理 | 技术实现文档 第737-802行 |
| **bcrypt** | 密码加密库（成本因子10） | 密码管理器实现 / 技术实现文档 |

---

### 项目相关问题

对于 siyuan-password 项目的问题：
1. 查阅本文档 (CLAUDE.md) 的对应章节
2. 查阅详细设计文档 (claudedocs/*.md)
3. 查阅源码注释和 TypeScript 类型定义
4. 参考思源笔记官方 API 文档

---

## 📖 文档更新说明

### v2.0 (2025-12-31) - 项目优化版

**主要更新**:
1. ✅ 补充项目架构树，增加 `patches/` 和 `kernel/` 目录说明
2. ✅ 更新密码锁功能设计到 v2.1 版本（源码验证完成）
3. ✅ 补充详细的开发路线图（Week 1-10）
4. ✅ 添加关键文件位置表，包含 Hook 拦截点和后端同步位置
5. ✅ 补充技术实现细节文档的完整引用
6. ✅ 说明 v2.1 相比 v2.0 的优化（工作量减少 1.5 周）
7. ✅ 澄清源码验证结果和关键决策的依据

**新增文档**:
- `claudedocs/技术实现细节补充文档.md` - 完整的代码实现指南
  - 插件入口点实现
  - 数据库服务实现（500+ 行代码）
  - 密码管理器实现（700+ 行代码）
  - 文档打开拦截实现
  - WebSocket 事件处理
  - UI 组件实现
  - 云同步兼容性分析
  - 错误处理和边缘用例
  - 完整的测试计划
  - 性能优化建议
  - 安全审计清单

**设计文档更新**:
- `claudedocs/笔记加锁功能设计文档.md` 升级到 v2.1
  - 源码验证标记 ✅/❌
  - v2.1 版本更新日志
  - 简化后的架构（移除嵌套设计）
  - 明确的 Hook 拦截点说明
  - 自动云同步流程确认

### v1.0 (2025-12-30) - 初始版本

基于 SiYuan 3.1.15，包含密码锁功能 v2.0 设计的初始文档。

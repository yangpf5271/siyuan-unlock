FROM node:21 AS NODE_BUILD

WORKDIR /go/src/github.com/siyuan-note/siyuan/
ADD . /go/src/github.com/siyuan-note/siyuan/

# 应用核心补丁（必须在构建之前）
RUN echo "📦 Applying patches..." && \
    git apply --verbose patches/siyuan/default-config.patch && \
    git apply --verbose patches/siyuan/disable-update.patch && \
    git apply --verbose patches/siyuan/mock-vip-user.patch && \
    echo "✅ All patches applied successfully"

RUN apt-get update && \
    apt-get install -y jq
RUN cd app && \
packageManager=$(jq -r '.packageManager' package.json) && \
if [ -n "$packageManager" ]; then \
    npm install -g $packageManager; \
else \
    echo "No packageManager field found in package.json"; \
    npm install -g pnpm; \
fi && \
pnpm install --registry=http://registry.npmjs.org/ --silent && \
pnpm run build
RUN apt-get purge -y jq
RUN apt-get autoremove -y
RUN rm -rf /var/lib/apt/lists/*

FROM golang:1.24-alpine AS GO_BUILD
WORKDIR /go/src/github.com/siyuan-note/siyuan/
COPY --from=NODE_BUILD /go/src/github.com/siyuan-note/siyuan/ /go/src/github.com/siyuan-note/siyuan/
ENV GO111MODULE=on
ENV CGO_ENABLED=1
RUN apk add --no-cache gcc musl-dev && \
    cd kernel && go build --tags fts5 -v -ldflags "-s -w" && \
    mkdir /opt/siyuan/ && \
    mv /go/src/github.com/siyuan-note/siyuan/app/appearance/ /opt/siyuan/ && \
    mv /go/src/github.com/siyuan-note/siyuan/app/stage/ /opt/siyuan/ && \
    mv /go/src/github.com/siyuan-note/siyuan/app/guide/ /opt/siyuan/ && \
    mv /go/src/github.com/siyuan-note/siyuan/app/changelogs/ /opt/siyuan/ && \
    mv /go/src/github.com/siyuan-note/siyuan/kernel/kernel /opt/siyuan/ && \
    mv /go/src/github.com/siyuan-note/siyuan/kernel/entrypoint.sh /opt/siyuan/entrypoint.sh && \
    find /opt/siyuan/ -name .git | xargs rm -rf

FROM alpine:latest
LABEL maintainer="yangpf5271 <yangpf5271@users.noreply.github.com>"
LABEL description="SiYuan Password - Fork from appdev/siyuan-unlock with password lock feature"
LABEL version="3.1.15-password-1.0.0"
LABEL org.opencontainers.image.source="https://github.com/yangpf5271/siyuan-password"
LABEL org.opencontainers.image.description="SiYuan with notebook/document-level password protection"
LABEL org.opencontainers.image.authors="yangpf5271"
LABEL org.opencontainers.image.url="https://github.com/yangpf5271/siyuan-password"
LABEL org.opencontainers.image.licenses="AGPL-3.0"
LABEL org.opencontainers.image.title="SiYuan-Password"

WORKDIR /opt/siyuan/
COPY --from=GO_BUILD /opt/siyuan/ /opt/siyuan/

RUN apk add --no-cache ca-certificates tzdata su-exec && \
    chmod +x /opt/siyuan/entrypoint.sh

ENV TZ=Asia/Shanghai
ENV HOME=/home/siyuan
ENV RUN_IN_CONTAINER=true
EXPOSE 6806

ENTRYPOINT ["/opt/siyuan/entrypoint.sh"]
CMD ["/opt/siyuan/kernel"]

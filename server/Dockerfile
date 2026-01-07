# 快淘帮 WisePick 后端代理服务 Dockerfile
# 使用官方 Dart SDK 镜像进行构建

# 构建阶段
FROM dart:stable AS build

# 设置工作目录
WORKDIR /app

# 复制 pubspec 文件并获取依赖
COPY pubspec.* ./
RUN dart pub get

# 复制源代码
COPY . .

# 预编译应用以提升启动速度
RUN dart compile exe bin/proxy_server.dart -o bin/server

# 运行阶段 - 使用最小化镜像
FROM debian:stable-slim

# 安装运行时依赖（包括 curl 用于健康检查）
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# 创建非 root 用户
RUN useradd -m -s /bin/bash appuser

# 设置工作目录
WORKDIR /app

# 从构建阶段复制编译好的可执行文件
COPY --from=build /app/bin/server /app/bin/server

# 切换到非 root 用户
USER appuser

# 暴露端口
EXPOSE 8080

# 设置环境变量默认值
ENV PORT=8080

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/__settings || exit 1

# 启动命令
CMD ["/app/bin/server"]


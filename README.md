# wisepick_dart_version

简体中文说明文档。

项目简介
- 这是 `wisepick_dart_version` 的仓库（Dart/Flutter 项目）。

前置条件
- 已安装 Dart/Flutter SDK（如适用）
- 已安装 Git

快速开始
1. 克隆仓库：
   ```bash
   git clone <your-repo-url>
   cd wisepick_dart_version
   ```
2. 安装依赖：
   ```bash
   flutter pub get
   ```
3. 运行应用（示例）：
   ```bash
   flutter run
   ```

贡献
- 欢迎提交 Issue 或 PR。请在 PR 中说明变更目的和影响范围。

许可证
- 请在此处添加许可证信息（例如 MIT）。

# wisepick_dart_version

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## 后端推广/转链配置

本项目提供了一个后端 proxy 示例，负责对接京东/淘宝的签名与转链接口。部署到生产环境前，请在后端服务器环境变量中设置下列项（按需）：

- `TAOBAO_APP_SECRET`：当使用官方淘宝签名/SDK 时需要。
- `JD_APP_SECRET`：京东联盟的 secret（可选）。
- `ADMIN_PASSWORD`：后台设置入口的管理员密码（Flutter 客户端会调用 `/admin/login` 校验）。

示例：在 Linux 上启动 proxy 服务前，你可以：

```bash
export TAOBAO_APP_SECRET="your_taobao_secret"
export JD_APP_SECRET="your_jd_secret"
dart run server/bin/proxy_server.dart
```

后端提供 `/sign/taobao`、`/sign/jd` 等端点用于生成/签名推广链接，客户端从返回的 `tpwd` / `clickURL` 中获取最终的推广链接。

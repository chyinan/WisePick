# wisepick proxy server

This small Dart `shelf` proxy forwards requests from the Flutter app to an OpenAI-compatible API provider.

Environment variables
- `OPENAI_API_KEY` (required): API key to forward in `Authorization: Bearer <key>`
- `OPENAI_API_URL` (optional): upstream URL, defaults to `https://api.openai.com/v1/chat/completions`
- `PORT` (optional): server port, defaults to `8080`
- `ADMIN_PASSWORD` (required for后台入口): password checked by `/admin/login`, used by Flutter app to解锁后台设置界面

Run locally

1. cd into `server`
2. `dart pub get`
3. `dart run bin/proxy_server.dart`  # 交互式启动：会在终端提示未配置项
   - 默认监听端口为 `8080`；若该端口已被占用，进程会自动尝试下一个可用端口（最多 10 次）。设置 `PORT` 环境变量可强制绑定到指定端口并跳过自动切换。

Notes: The server now runs in an interactive launcher. If an environment
variable commonly used for third-party integrations is missing or set to a
placeholder, the launcher will prompt you (例如 `请输入京东联盟App Key：`、`请输入京东联盟 Union ID：`、`请输入淘宝推广位 Adzone ID：`、`请输入拼多多 PID：`)。You may press Enter to leave it empty (部分功能可能不可用)。

持久化：交互输入会保存到 `server/.env` 文件（覆盖或合并已有值），以便下次启动时无需重复输入。**注意：该 `.env` 可能包含密钥，请勿提交到版本控制（推荐将其加入 `.gitignore`）。**

特别说明：OpenAI 的 API Key 现在由前端在运行时提供给后端（通过代理请求时携带），后端不再在启动时提示 `OPENAI_API_KEY`。

Configure Flutter app

In `lib/features/chat/chat_service.dart`, replace the mock implementation with a POST to `http://localhost:8080/v1/chat/completions` and forward the OpenAI-compatible request body. Keep using `ApiClient` or `http` as you prefer.

Notes

- This proxy does not implement streaming responses. For streaming, additional handling is required.
- For production, restrict origins and add authentication.
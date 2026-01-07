# wisepick proxy server

快淘帮 WisePick 后端代理服务器，基于 Dart Shelf 框架构建。

## 功能特性

- OpenAI API 代理转发（支持流式和非流式响应）
- 淘宝联盟 API 集成（商品搜索、链接转换）
- 京东联盟 API 集成（商品搜索、推广链接生成）
- 拼多多 API 集成（商品搜索、推广链接生成）
- 统一签名服务
- CORS 跨域支持

## 环境变量

| 变量名 | 必需 | 说明 |
|--------|------|------|
| `PORT` | 否 | 服务器端口，默认 `8080` |
| `ADMIN_PASSWORD` | 是 | 管理员密码，用于后台设置 |
| `OPENAI_API_URL` | 否 | OpenAI API 地址，默认官方地址 |
| `OPENAI_API_KEY` | 否 | OpenAI API Key（也可由前端提供） |
| `TAOBAO_APP_KEY` | 否 | 淘宝联盟 App Key |
| `TAOBAO_APP_SECRET` | 否 | 淘宝联盟 App Secret |
| `TAOBAO_ADZONE_ID` | 否 | 淘宝推广位 ID |
| `JD_APP_KEY` | 否 | 京东联盟 App Key |
| `JD_APP_SECRET` | 否 | 京东联盟 App Secret |
| `JD_UNION_ID` | 否 | 京东联盟 ID |
| `PDD_CLIENT_ID` | 否 | 拼多多 Client ID |
| `PDD_CLIENT_SECRET` | 否 | 拼多多 Client Secret |
| `PDD_PID` | 否 | 拼多多推广位 ID |

---

## 🐳 Docker 部署 (推荐)

### 快速启动

```bash
# 1. 进入 server 目录
cd server

# 2. 创建环境变量文件
cp .env.example .env
# 编辑 .env 文件，填入实际配置值

# 3. 构建并启动容器
docker-compose up -d

# 4. 查看日志
docker-compose logs -f

# 5. 停止服务
docker-compose down
```

### 单独使用 Docker 命令

```bash
# 构建镜像
docker build -t wisepick-proxy .

# 运行容器
docker run -d \
  --name wisepick-proxy \
  -p 8080:8080 \
  -e ADMIN_PASSWORD=your_password \
  -e OPENAI_API_KEY=sk-xxx \
  wisepick-proxy

# 查看日志
docker logs -f wisepick-proxy

# 停止容器
docker stop wisepick-proxy
docker rm wisepick-proxy
```

### 健康检查

```bash
# 检查服务是否正常运行
curl http://localhost:8080/__settings
```

---

## 本地运行 (开发环境)

### 前置要求
- Dart SDK 2.18.0+

### 启动步骤

```bash
# 1. 进入 server 目录
cd server

# 2. 安装依赖
dart pub get

# 3. 运行服务器（交互式启动）
dart run bin/proxy_server.dart
```

**交互式配置**: 首次运行时，如果环境变量未配置，服务器会提示输入相关配置项。配置会自动保存到 `.env` 文件。

**端口自动切换**: 默认端口 `8080`，如被占用会自动尝试下一个可用端口（最多 10 次）。

---

## API 端点

| 端点 | 方法 | 功能 |
|------|------|------|
| `/v1/chat/completions` | POST | OpenAI API 代理 |
| `/sign/taobao` | POST | 淘宝签名服务 |
| `/sign/jd` | POST | 京东签名服务 |
| `/sign/pdd` | POST | 拼多多签名服务 |
| `/taobao/tbk_search` | GET | 淘宝商品搜索 |
| `/taobao/convert` | POST | 淘宝链接转换 |
| `/jd/union/goods/query` | GET | 京东商品搜索 |
| `/jd/union/promotion/bysubunionid` | POST | 京东推广链接生成 |
| `/pdd/authority/query` | POST | 拼多多备案查询 |
| `/pdd/rp/prom/generate` | POST | 拼多多推广链接生成 |
| `/api/products/search` | GET | 统一商品搜索 |
| `/admin/login` | POST | 管理员登录 |
| `/__settings` | GET | 获取配置信息 |
| `/__debug/last_return` | GET | 调试信息查看 |

完整 API 文档请参阅 [docs/api-design.md](../docs/api-design.md)

---

## 注意事项

- `.env` 文件包含敏感信息，请勿提交到版本控制
- 生产环境建议使用 HTTPS
- 生产环境建议限制 CORS 来源
- OpenAI API Key 可由前端在运行时提供

## 相关文档

- [API 设计文档](../docs/api-design.md)
- [后端架构文档](../docs/backend-architecture.md)
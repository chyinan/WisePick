# WisePick 后端 API 文档

基础路径：`http://localhost:9527`

认证方式：`Authorization: Bearer <access_token>`

---

## 认证模块 `/api/v1/auth`

### POST `/register` — 用户注册
**认证**：无需

**请求体**
```json
{
  "email": "user@example.com",
  "password": "Password123",
  "nickname": "昵称",
  "deviceId": "uuid",
  "deviceName": "iPhone 15",
  "deviceType": "mobile"
}
```

**响应 200**
```json
{
  "success": true,
  "message": "注册成功",
  "user": { "id": "uuid", "email": "user@example.com", "nickname": "昵称" },
  "access_token": "eyJ...",
  "refresh_token": "eyJ..."
}
```

**错误码**
| 状态码 | 说明 |
|--------|------|
| 400 | 邮箱格式错误 / 密码不合规 / 邮箱已注册 |

---

### POST `/login` — 用户登录
**认证**：无需

**请求体**
```json
{
  "email": "user@example.com",
  "password": "Password123",
  "deviceId": "uuid",
  "deviceName": "Windows PC",
  "deviceType": "desktop"
}
```

**响应 200**
```json
{
  "success": true,
  "message": "登录成功",
  "user": { "id": "uuid", "email": "user@example.com" },
  "access_token": "eyJ...",
  "refresh_token": "eyJ..."
}
```

**错误码**
| 状态码 | 说明 |
|--------|------|
| 400 | 邮箱或密码错误 / 账号被封禁 / 登录过于频繁（5次/15分钟） |

---

### POST `/refresh` — 刷新 Token
**认证**：无需

**请求体**
```json
{ "refresh_token": "eyJ..." }
```

**响应 200**
```json
{
  "success": true,
  "access_token": "eyJ...",
  "refresh_token": "eyJ..."
}
```

---

### POST `/logout` — 登出（当前设备）
**认证**：Bearer Token

**响应 200**
```json
{ "success": true, "message": "已登出" }
```

---

### POST `/logout-all` — 登出所有设备
**认证**：Bearer Token

**响应 200**
```json
{ "success": true, "message": "已从所有设备登出" }
```

---

### GET `/me` — 获取当前用户信息
**认证**：Bearer Token

**响应 200**
```json
{
  "id": "uuid",
  "email": "user@example.com",
  "nickname": "昵称",
  "emailVerified": false,
  "createdAt": "2024-01-01T00:00:00.000Z"
}
```

---

### PUT `/me` — 更新用户资料
**认证**：Bearer Token

**请求体**
```json
{ "nickname": "新昵称", "avatarUrl": "https://..." }
```

---

### PUT `/me/password` — 修改密码
**认证**：Bearer Token

**请求体**
```json
{ "oldPassword": "OldPass123", "newPassword": "NewPass456" }
```

---

### GET `/sessions` — 获取当前用户的活跃会话
**认证**：Bearer Token

**响应 200**
```json
{
  "sessions": [
    { "id": "uuid", "deviceName": "iPhone 15", "lastActiveAt": "..." }
  ]
}
```

---

### DELETE `/sessions/:id` — 删除指定会话（强制下线）
**认证**：Bearer Token

---

### POST `/security-question` — 设置安全问题
**认证**：Bearer Token

**请求体**
```json
{ "question": "您母亲的名字？", "answer": "张三", "questionOrder": 1 }
```

---

### GET `/security-question` — 获取安全问题（不含答案）
**认证**：Bearer Token

---

### POST `/forgot-password/question` — 忘记密码第一步：获取安全问题
**认证**：无需

**请求体**
```json
{ "email": "user@example.com" }
```

---

### POST `/forgot-password/verify` — 忘记密码第二步：验证安全问题
**认证**：无需

**请求体**
```json
{ "email": "user@example.com", "answer": "张三" }
```

**响应 200**
```json
{ "success": true, "resetToken": "uuid" }
```

---

### POST `/forgot-password/reset` — 忘记密码第三步：重置密码
**认证**：无需

**请求体**
```json
{ "resetToken": "uuid", "newPassword": "NewPass123" }
```

---

## 同步模块 `/api/v1/sync`

所有端点均需 Bearer Token 认证。

### GET `/cart` — 拉取购物车数据
**查询参数**：`since=<ISO8601时间戳>`（可选，增量同步）

**响应 200**
```json
{
  "items": [ { "id": "uuid", "productId": "...", "platform": "taobao" } ],
  "version": 42
}
```

---

### POST `/cart` — 推送购物车变更
**请求体**
```json
{
  "items": [ { "id": "uuid", "action": "upsert", "data": {} } ],
  "clientVersion": 41
}
```

---

### GET `/conversations` — 拉取会话列表

### POST `/conversations` — 推送会话变更

### GET `/version` — 获取同步版本号

### POST `/resolve-conflict` — 解决同步冲突（Last Write Wins）

---

## 管理模块 `/api/v1/admin`

所有端点均需管理员 Bearer Token 认证。

### GET `/users/stats` — 用户统计数据

**响应 200**
```json
{
  "totalUsers": 100,
  "todayNewUsers": 5,
  "weekNewUsers": 20,
  "monthNewUsers": 60,
  "activeUsers": { "daily": 30, "monthly": 80 },
  "verifiedUsers": 70,
  "verificationRate": "70.0"
}
```

---

### GET `/users` — 用户列表（分页）
**查询参数**：`page=1&pageSize=20`

---

### PUT `/users/:id` — 更新用户信息（封禁/解封/改邮箱）
**请求体**
```json
{ "status": "banned" }
```

---

### DELETE `/users/:id` — 删除用户
**查询参数**：`hard=true`（硬删除，默认软删除）

---

### GET `/system/stats` — 系统统计数据

### GET `/recent-users` — 最近注册用户（前10条）

### GET `/activity-chart` — 最近7天活跃度图表数据

### GET `/cart-items` — 购物车数据列表（分页）
**查询参数**：`page=1&pageSize=20&platform=taobao&userId=uuid`

### GET `/cart-items/stats` — 购物车统计数据

### DELETE `/cart-items/:id` — 删除购物车商品

### GET `/conversations` — 会话列表（分页）

### GET `/conversations/:id/messages` — 会话消息列表

### DELETE `/conversations/:id` — 删除会话

### GET `/settings` — 系统设置（环境变量快照）

### PUT `/settings` — 更新系统设置（需重启生效）

### GET `/sessions` — 用户会话列表（分页）
**查询参数**：`activeOnly=true`

### DELETE `/sessions/:id` — 强制下线指定会话

---

## AI 代理模块

### POST `/v1/chat/completions` — AI 聊天代理
**认证**：无需（使用服务端 `OPENAI_API_KEY` 或客户端传入 Key）

**请求体**：标准 OpenAI Chat Completions 格式
```json
{
  "model": "gpt-3.5-turbo",
  "messages": [ { "role": "user", "content": "推荐一款手机" } ],
  "stream": false
}
```

**响应**：透传上游 AI 服务响应（支持流式 SSE）

**错误码**
| 状态码 | 说明 |
|--------|------|
| 500 | 服务端未配置 API Key |

---

## 可靠性模块 `/api/v1/reliability`

### GET `/health` — 健康检查
**认证**：无需

**响应 200**
```json
{ "status": "ok", "uptime": 3600, "database": "connected" }
```

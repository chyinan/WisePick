# Epic 8: 后端代理服务

**Epic ID**: E8  
**创建日期**: 2026-01-06  
**状态**: Draft  
**优先级**: P0

---

## Epic 描述

实现后端代理服务器，包括 AI API 代理转发、淘宝/京东/拼多多签名服务和转链服务。保护 API 密钥安全，统一处理第三方 API 调用。

## 业务价值

- 保护 API 密钥不暴露给前端
- 统一处理签名算法
- 简化前端实现
- 支持 CORS 跨域

## 技术栈

- **语言**: Dart
- **框架**: Shelf + shelf_router
- **HTTP 客户端**: http package

---

## Story 8.1: 代理服务器基础框架

### Status
Draft

### Story
**As a** 开发者,  
**I want** 有一个可运行的代理服务器框架,  
**so that** 前端可以安全调用第三方 API

### Acceptance Criteria

1. 服务器能在指定端口启动
2. 支持 CORS 跨域请求
3. 支持环境变量配置
4. 端口被占用时自动尝试下一个
5. 提供配置信息端点 (/__settings)
6. 支持交互式配置（首次运行）

### Tasks / Subtasks

- [ ] 创建服务器入口 (AC: 1, 4)
  - [ ] 创建 `server/bin/proxy_server.dart`
  - [ ] 配置端口（默认 8080）
  - [ ] 端口占用自动重试
- [ ] 配置 CORS (AC: 2)
  - [ ] 添加 CORS 响应头
  - [ ] 支持 OPTIONS 预检请求
- [ ] 配置路由 (AC: 5)
  - [ ] 使用 shelf_router
  - [ ] 注册各功能端点
- [ ] 环境变量管理 (AC: 3, 6)
  - [ ] 支持 .env 文件
  - [ ] 交互式配置提示
  - [ ] 配置持久化

### Dev Notes

**项目结构**:
```
server/
├── bin/
│   └── proxy_server.dart    # 入口文件
├── lib/
│   ├── config.dart          # 配置管理
│   ├── cors_middleware.dart # CORS 中间件
│   └── routes/
│       ├── ai_routes.dart
│       ├── taobao_routes.dart
│       ├── jd_routes.dart
│       └── pdd_routes.dart
└── pubspec.yaml
```

**CORS 配置**:
```dart
Response corsHeaders(Response response) {
  return response.change(headers: {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, POST, OPTIONS',
    'access-control-allow-headers': 'Origin, Content-Type, Accept, Authorization',
  });
}

Response handleOptions(Request request) {
  return Response.ok('', headers: {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, POST, OPTIONS',
    'access-control-allow-headers': 'Origin, Content-Type, Accept, Authorization',
  });
}
```

**端口重试**:
```dart
Future<void> startServer(int startPort) async {
  for (int port = startPort; port < startPort + 10; port++) {
    try {
      final server = await io.serve(handler, InternetAddress.anyIPv4, port);
      print('Server running on http://localhost:${server.port}');
      return;
    } catch (e) {
      print('Port $port is busy, trying next...');
    }
  }
  throw Exception('No available port found');
}
```

### Testing

**测试文件位置**: `server/test/server_test.dart`

**测试要求**:
- 测试服务器启动
- 测试 CORS 响应头
- 测试配置加载

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 8.2: OpenAI API 代理

### Status
Draft

### Story
**As a** 前端应用,  
**I want** 通过代理调用 OpenAI API,  
**so that** API Key 不暴露在前端

### Acceptance Criteria

1. 支持 POST /v1/chat/completions 端点
2. 支持流式响应 (SSE)
3. 支持非流式响应
4. 转发 Authorization Header
5. 支持自定义上游 API 地址

### Tasks / Subtasks

- [ ] 创建 AI 路由 (AC: 1)
  - [ ] 创建 `server/lib/routes/ai_routes.dart`
  - [ ] 注册 /v1/chat/completions
- [ ] 实现请求转发 (AC: 4, 5)
  - [ ] 读取请求体
  - [ ] 构建上游请求
  - [ ] 转发 Authorization
- [ ] 实现流式响应 (AC: 2)
  - [ ] 检测 stream 参数
  - [ ] 直接转发字节流
- [ ] 实现非流式响应 (AC: 3)
  - [ ] 等待完整响应
  - [ ] 返回 JSON

### Dev Notes

**端点**: `POST /v1/chat/completions`

**请求转发**:
```dart
Future<Response> handleChatCompletions(Request request) async {
  final body = await request.readAsString();
  final jsonBody = jsonDecode(body);
  final isStream = jsonBody['stream'] == true;
  
  final upstreamUrl = Platform.environment['OPENAI_API_URL'] 
    ?? 'https://api.openai.com/v1/chat/completions';
  
  final upstreamRequest = http.Request('POST', Uri.parse(upstreamUrl))
    ..headers['Content-Type'] = 'application/json'
    ..headers['Authorization'] = request.headers['Authorization'] ?? ''
    ..body = body;
  
  final streamedResponse = await upstreamRequest.send();
  
  if (isStream) {
    return Response(
      streamedResponse.statusCode,
      body: streamedResponse.stream,
      headers: {
        'content-type': 'text/event-stream',
        ...corsHeaders,
      },
    );
  } else {
    final responseBody = await streamedResponse.stream.bytesToString();
    return Response.ok(
      responseBody,
      headers: {'content-type': 'application/json', ...corsHeaders},
    );
  }
}
```

### Testing

**测试文件位置**: `server/test/ai_routes_test.dart`

**测试要求**:
- 测试请求转发
- 测试流式响应
- 测试非流式响应

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 8.3: 淘宝联盟签名与转链

### Status
Draft

### Story
**As a** 前端应用,  
**I want** 调用淘宝联盟 API,  
**so that** 能搜索商品和生成推广链接

### Acceptance Criteria

1. 提供签名端点 POST /sign/taobao
2. 提供搜索端点 GET /taobao/tbk_search
3. 提供转链端点 POST /taobao/convert
4. 签名算法正确（MD5）
5. 返回推广链接和口令

### Tasks / Subtasks

- [ ] 创建淘宝路由 (AC: 1, 2, 3)
  - [ ] 创建 `server/lib/routes/taobao_routes.dart`
  - [ ] 注册端点
- [ ] 实现签名算法 (AC: 4)
  - [ ] 参数排序
  - [ ] MD5 签名
  - [ ] 格式：secret + params + secret
- [ ] 实现商品搜索 (AC: 2)
  - [ ] 构建请求参数
  - [ ] 调用淘宝 API
  - [ ] 返回商品列表
- [ ] 实现链接转换 (AC: 3, 5)
  - [ ] 调用转链 API
  - [ ] 返回推广链接
  - [ ] 返回淘宝口令

### Dev Notes

**签名算法**:
```dart
String sign(Map<String, String> params, String appSecret) {
  final sortedKeys = params.keys.toList()..sort();
  final buffer = StringBuffer(appSecret);
  for (final key in sortedKeys) {
    buffer.write(key);
    buffer.write(params[key]);
  }
  buffer.write(appSecret);
  return md5.convert(utf8.encode(buffer.toString())).toString().toUpperCase();
}
```

**环境变量**:
- `TAOBAO_APP_KEY`: 淘宝应用 Key
- `TAOBAO_APP_SECRET`: 淘宝应用密钥
- `TAOBAO_ADZONE_ID`: 淘宝推广位 ID

**端点**:
| 端点 | 方法 | 功能 |
|------|------|------|
| /sign/taobao | POST | 生成签名 |
| /taobao/tbk_search | GET | 商品搜索 |
| /taobao/convert | POST | 链接转换 |

### Testing

**测试文件位置**: `server/test/taobao_routes_test.dart`

**测试要求**:
- 测试签名算法
- 测试搜索接口
- 测试转链接口

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 8.4: 京东联盟签名与转链

### Status
Draft

### Story
**As a** 前端应用,  
**I want** 调用京东联盟 API,  
**so that** 能搜索商品和生成推广链接

### Acceptance Criteria

1. 提供签名端点 POST /sign/jd
2. 提供搜索端点 GET /jd/union/goods/query
3. 提供转链端点 POST /jd/union/promotion/bysubunionid
4. 签名算法正确（MD5）
5. 时间戳使用 GMT+8

### Tasks / Subtasks

- [ ] 创建京东路由 (AC: 1, 2, 3)
  - [ ] 创建 `server/lib/routes/jd_routes.dart`
  - [ ] 注册端点
- [ ] 实现签名算法 (AC: 4, 5)
  - [ ] 参数排序
  - [ ] MD5 签名
  - [ ] GMT+8 时间戳
- [ ] 实现商品搜索 (AC: 2)
  - [ ] 构建请求参数
  - [ ] 调用京东 API
  - [ ] 返回商品列表
- [ ] 实现推广链接生成 (AC: 3)
  - [ ] 构建 promotionCodeReq
  - [ ] 返回 clickURL、shortURL

### Dev Notes

**签名算法** (与淘宝类似):
```dart
String sign(Map<String, String> params, String appSecret) {
  final sortedKeys = params.keys.toList()..sort();
  final buffer = StringBuffer(appSecret);
  for (final key in sortedKeys) {
    buffer.write(key);
    buffer.write(params[key]);
  }
  buffer.write(appSecret);
  return md5.convert(utf8.encode(buffer.toString())).toString().toUpperCase();
}
```

**时间戳 (GMT+8)**:
```dart
String getTimestamp() {
  final now = DateTime.now().toUtc().add(Duration(hours: 8));
  return DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
}
```

**环境变量**:
- `JD_APP_KEY`: 京东应用 Key
- `JD_APP_SECRET`: 京东联盟密钥
- `JD_UNION_ID`: 京东联盟 ID

**端点**:
| 端点 | 方法 | 功能 |
|------|------|------|
| /sign/jd | POST | 生成签名 |
| /jd/union/goods/query | GET | 商品搜索 |
| /jd/union/promotion/bysubunionid | POST | 推广链接生成 |

### Testing

**测试文件位置**: `server/test/jd_routes_test.dart`

**测试要求**:
- 测试签名算法
- 测试时间戳格式
- 测试搜索和转链

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 8.5: 拼多多签名与转链

### Status
Draft

### Story
**As a** 前端应用,  
**I want** 调用拼多多 API,  
**so that** 能搜索商品和生成推广链接

### Acceptance Criteria

1. 提供签名端点 POST /sign/pdd
2. 提供搜索端点 GET /api/products/search
3. 提供转链端点 POST /pdd/rp/prom/generate
4. 提供备案查询端点 POST /pdd/authority/query
5. 签名算法正确（MD5）

### Tasks / Subtasks

- [ ] 创建拼多多路由 (AC: 1, 2, 3, 4)
  - [ ] 创建 `server/lib/routes/pdd_routes.dart`
  - [ ] 注册端点
- [ ] 实现签名算法 (AC: 5)
  - [ ] 参数排序
  - [ ] MD5 签名
- [ ] 实现商品搜索 (AC: 2)
  - [ ] 构建请求参数
  - [ ] 调用拼多多 API
- [ ] 实现推广链接生成 (AC: 3)
  - [ ] goods_sign_list 参数
  - [ ] 返回 mobile_url、url
- [ ] 实现备案查询 (AC: 4)
  - [ ] 查询备案状态
  - [ ] 返回小程序链接

### Dev Notes

**签名算法**:
```dart
String sign(Map<String, String> params, String clientSecret) {
  final sortedKeys = params.keys.toList()..sort();
  final buffer = StringBuffer(clientSecret);
  for (final key in sortedKeys) {
    buffer.write(key);
    buffer.write(params[key]);
  }
  buffer.write(clientSecret);
  return md5.convert(utf8.encode(buffer.toString())).toString().toUpperCase();
}
```

**环境变量**:
- `PDD_CLIENT_ID`: 拼多多客户端 ID
- `PDD_CLIENT_SECRET`: 拼多多客户端密钥
- `PDD_PID`: 拼多多推广位 ID

**端点**:
| 端点 | 方法 | 功能 |
|------|------|------|
| /sign/pdd | POST | 生成签名 |
| /api/products/search | GET | 商品搜索 |
| /pdd/rp/prom/generate | POST | 推广链接生成 |
| /pdd/authority/query | POST | 备案查询 |

### Testing

**测试文件位置**: `server/test/pdd_routes_test.dart`

**测试要求**:
- 测试签名算法
- 测试搜索接口
- 测试转链接口

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |




# 快淘帮 WisePick - API 设计文档

**版本**: 1.0  
**创建日期**: 2024  
**最后更新**: 2024  
**文档状态**: 正式版  
**架构师**: Winston (Architect Agent)

---

## 1. 文档概述

### 1.1 文档目的

本文档详细描述了快淘帮 WisePick 项目的完整 API 设计，包括前端与后端之间的所有 API 接口、请求/响应格式、错误处理、认证授权等。本文档旨在：

- 为前端和后端开发团队提供清晰的 API 接口规范
- 确保 API 实现的一致性和可维护性
- 指导 API 测试和集成开发
- 作为 API 版本管理和变更的参考标准

### 1.2 文档范围

本文档涵盖：

- **API 端点**: 所有后端提供的 RESTful API 端点
- **请求格式**: HTTP 方法、路径、参数、请求体格式
- **响应格式**: 状态码、响应体结构、错误格式
- **认证授权**: API 密钥、签名机制、管理员认证
- **数据模型**: 请求和响应的数据模型定义
- **错误处理**: 错误码、错误消息、处理策略
- **集成示例**: 前端调用示例、curl 示例

### 1.3 目标读者

- 前端开发工程师
- 后端开发工程师
- API 测试工程师
- 系统集成开发者
- 技术负责人

### 1.4 API 基础信息

**基础 URL**: `http://localhost:8080` (开发环境)  
**协议**: HTTP/HTTPS  
**数据格式**: JSON  
**字符编码**: UTF-8  
**CORS**: 支持跨域请求（开发环境允许所有来源）

---

## 2. API 端点总览

### 2.1 端点分类

| 类别 | 端点数量 | 说明 |
|------|---------|------|
| AI 相关 | 1 | OpenAI API 代理 |
| 签名服务 | 3 | 淘宝、京东、拼多多签名 |
| 淘宝联盟 | 2 | 商品搜索、链接转换 |
| 京东联盟 | 4 | 商品搜索、推广链接生成 |
| 拼多多 | 3 | 备案查询、推广链接生成、搜索调试 |
| 商品搜索 | 1 | 统一商品搜索接口 |
| 管理端点 | 5 | 配置、登录、调试 |

### 2.2 端点列表

#### AI 相关端点
- `POST /v1/chat/completions` - OpenAI API 代理转发

#### 签名服务端点
- `POST /sign/taobao` - 淘宝 API 签名
- `POST /sign/jd` - 京东 API 签名
- `POST /sign/pdd` - 拼多多 API 签名

#### 淘宝联盟端点
- `GET /taobao/tbk_search` - 商品搜索
- `POST /taobao/convert` - 链接转换

#### 京东联盟端点
- `GET /jd/union/goods/query` - 商品搜索
- `POST /jd/union/promotion/bysubunionid` - 推广链接生成
- `GET /api/get-jd-promotion` - 获取京东推广链接
- `GET /proxy/test/jd_search` - 测试搜索（调试用）

#### 拼多多端点
- `POST /pdd/authority/query` - 备案查询
- `POST /pdd/rp/prom/generate` - 推广链接生成
- `POST /pdd/search_debug` - 搜索调试

#### 商品搜索端点
- `GET /api/products/search` - 统一商品搜索接口

#### 管理端点
- `POST /admin/login` - 管理员登录
- `GET /__settings` - 获取配置信息
- `GET /__debug/last_return` - 调试信息查看
- `GET /_debug/last_return` - 调试信息查看（别名）
- `GET /debug/last_return` - 调试信息查看（别名）

---

## 3. 通用规范

### 3.1 HTTP 方法

| 方法 | 用途 | 说明 |
|------|------|------|
| GET | 查询数据 | 用于获取资源，参数通过 URL 查询字符串传递 |
| POST | 创建/处理数据 | 用于创建资源或执行操作，数据通过请求体传递 |

### 3.2 HTTP 状态码

| 状态码 | 说明 | 使用场景 |
|--------|------|----------|
| 200 | 成功 | 请求成功处理 |
| 400 | 错误请求 | 请求参数错误或格式不正确 |
| 401 | 未授权 | 认证失败或未提供认证信息 |
| 404 | 未找到 | 请求的资源不存在 |
| 500 | 服务器错误 | 服务器内部错误 |

### 3.3 请求头

**通用请求头**:
```
Content-Type: application/json
Accept: application/json
```

**认证请求头** (AI 代理):
```
Authorization: Bearer <API_KEY>
```

**签名请求头** (签名服务):
```
x-ts: <timestamp>  # 可选，时间戳（ISO 8601 格式）
```

### 3.4 响应格式

**成功响应**:
```json
{
  "data": {...},
  "message": "success"
}
```

**错误响应**:
```json
{
  "error": "错误描述",
  "status": 500,
  "message": "详细错误信息",
  "debug": {...}  // 仅开发环境
}
```

### 3.5 CORS 支持

所有端点支持 CORS，响应头包含：
```
access-control-allow-origin: *
access-control-allow-methods: POST, OPTIONS
access-control-allow-headers: Origin, Content-Type, Accept, Authorization
```

---

## 4. AI 相关 API

### 4.1 OpenAI API 代理

**端点**: `POST /v1/chat/completions`

**功能**: 代理转发 OpenAI 兼容 API 请求，支持流式和非流式响应。

**请求格式**:
```json
{
  "model": "gpt-3.5-turbo",
  "messages": [
    {
      "role": "system",
      "content": "你是一个智能购物助手..."
    },
    {
      "role": "user",
      "content": "推荐一款 800 元左右的 USB DAC"
    }
  ],
  "stream": true,
  "max_tokens": 1000
}
```

**请求参数**:

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| model | string | 是 | AI 模型名称（如 gpt-3.5-turbo） |
| messages | array | 是 | 消息列表，包含 role 和 content |
| stream | boolean | 否 | 是否使用流式响应（默认 false） |
| max_tokens | integer | 否 | 最大 token 数（可选，unlimited 表示不限制） |

**请求头**:
```
Content-Type: application/json
Authorization: Bearer <OPENAI_API_KEY>  # 由前端提供
```

**流式响应** (stream=true):
```
data: {"id":"chatcmpl-...","object":"chat.completion.chunk","created":1234567890,"model":"gpt-3.5-turbo","choices":[{"index":0,"delta":{"content":"推荐"},"finish_reason":null}]}

data: {"id":"chatcmpl-...","object":"chat.completion.chunk","created":1234567890,"model":"gpt-3.5-turbo","choices":[{"index":0,"delta":{"content":"一款"},"finish_reason":null}]}

data: [DONE]
```

**非流式响应** (stream=false):
```json
{
  "id": "chatcmpl-...",
  "object": "chat.completion",
  "created": 1234567890,
  "model": "gpt-3.5-turbo",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "推荐一款 800 元左右的 USB DAC..."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 50,
    "completion_tokens": 200,
    "total_tokens": 250
  }
}
```

**错误响应**:
```json
{
  "error": "OPENAI_API_KEY not set",
  "status": 500
}
```

**配置说明**:
- 后端可通过环境变量 `OPENAI_API_URL` 配置上游 API 地址（默认: `https://api.openai.com/v1/chat/completions`）
- API Key 由前端在请求头中提供，后端也可通过环境变量 `OPENAI_API_KEY` 配置（可选）

**前端调用示例**:
```dart
final response = await apiClient.post(
  '$backendBase/v1/chat/completions',
  data: {
    'model': 'gpt-3.5-turbo',
    'messages': messages,
    'stream': true,
  },
  headers: {
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
  },
  responseType: ResponseType.stream,
);
```

---

## 5. 签名服务 API

### 5.1 淘宝签名服务

**端点**: `POST /sign/taobao`

**功能**: 为淘宝联盟 API 生成 HMAC-SHA256 签名。

**请求格式**:
```json
{
  "url": "https://item.taobao.com/item.htm?id=123456",
  "text": "商品标题"
}
```

**请求参数**:

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| url | string | 是 | 需要签名的 URL 或数据 |
| text | string | 否 | 附加文本（用于生成口令） |

**请求头**:
```
Content-Type: application/json
x-ts: 2024-01-01T00:00:00Z  # 可选，时间戳（ISO 8601）
```

**响应格式**:
```json
{
  "ts": "2024-01-01T00:00:00Z",
  "sign": "abc123def456..."
}
```

**响应参数**:

| 参数 | 类型 | 说明 |
|------|------|------|
| ts | string | 时间戳（ISO 8601 格式） |
| sign | string | HMAC-SHA256 签名结果 |

**签名算法**:
1. 读取请求体数据（JSON 字符串）
2. 获取时间戳（从 Header `x-ts` 或自动生成）
3. 拼接数据：`body + timestamp`
4. 使用 `TAOBAO_APP_SECRET` 计算 HMAC-SHA256
5. 返回签名和时间戳

**配置要求**:
- 环境变量 `TAOBAO_APP_SECRET`: 淘宝应用密钥

**错误响应**:
```json
{
  "error": "secret not configured",
  "status": 500
}
```

### 5.2 京东签名服务

**端点**: `POST /sign/jd`

**功能**: 为京东联盟 API 生成 HMAC-SHA256 签名。

**请求格式**:
```json
{
  "skuId": "1234567890"
}
```

**请求参数**:

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| skuId | string | 是 | 京东商品 SKU ID |

**请求头**:
```
Content-Type: application/json
x-ts: 2024-01-01T00:00:00Z  # 可选，时间戳（ISO 8601）
```

**响应格式**:
```json
{
  "ts": "2024-01-01T00:00:00Z",
  "sign": "abc123def456..."
}
```

**签名算法**: 与淘宝签名相同（HMAC-SHA256）

**配置要求**:
- 环境变量 `JD_APP_SECRET`: 京东联盟密钥

### 5.3 拼多多签名服务

**端点**: `POST /sign/pdd`

**功能**: 为拼多多开放平台 API 生成 MD5 签名。

**请求格式**:
```json
{
  "goods_sign_list": ["商品签名1", "商品签名2"],
  "custom_parameters": "{\"uid\":\"chyinan\"}"
}
```

**请求参数**:

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| goods_sign_list | array | 是 | 商品签名列表 |
| custom_parameters | string | 否 | 自定义参数（JSON 字符串） |

**响应格式**:
```json
{
  "clickURL": "https://mobile.yangkeduo.com/goods.html?goods_id=...",
  "raw": {
    "goods_promotion_url_generate_response": {
      "goods_promotion_url_list": [
        {
          "mobile_url": "移动端链接",
          "url": "PC 端链接"
        }
      ]
    }
  }
}
```

**签名算法**: MD5
1. 读取请求参数
2. 按参数名排序
3. 拼接参数值
4. 使用 `PDD_CLIENT_SECRET` 计算 MD5

**配置要求**:
- 环境变量 `PDD_CLIENT_ID`: 拼多多客户端 ID
- 环境变量 `PDD_CLIENT_SECRET`: 拼多多客户端密钥
- 环境变量 `PDD_PID`: 拼多多推广位 ID

---

## 6. 淘宝联盟 API

### 6.1 商品搜索

**端点**: `GET /taobao/tbk_search`

**功能**: 搜索淘宝联盟商品。

**请求参数** (URL 查询字符串):

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| para | string | 是 | 搜索关键词 |
| page_no | integer | 否 | 页码（默认 1） |
| page_size | integer | 否 | 每页数量（默认 20） |
| cat | string | 否 | 类目 ID |
| sort | string | 否 | 排序方式 |
| adzone_id | string | 否 | 推广位 ID |
| has_coupon | boolean | 否 | 是否有优惠券 |

**请求示例**:
```
GET /taobao/tbk_search?para=USB+DAC&page_no=1&page_size=10
```

**响应格式**:
```json
{
  "tbk_dg_material_optional_response": {
    "result_list": {
      "map_data": [
        {
          "num_iid": "123456789",
          "title": "商品标题",
          "pict_url": "https://img.alicdn.com/...",
          "zk_final_price": "799.00",
          "reserve_price": "999.00",
          "coupon_amount": "100.00",
          "volume": 1000,
          "commission_rate": "500",
          "coupon_share_url": "https://uland.taobao.com/..."
        }
      ]
    },
    "total_results": 100
  }
}
```

**配置要求**:
- 环境变量 `TAOBAO_APP_KEY`: 淘宝应用 Key
- 环境变量 `TAOBAO_APP_SECRET`: 淘宝应用密钥
- 环境变量 `TAOBAO_ADZONE_ID`: 默认推广位 ID（可选）

### 6.2 链接转换

**端点**: `POST /taobao/convert`

**功能**: 将普通商品链接转换为推广链接。

**请求格式**:
```json
{
  "id": "123456789",
  "url": "https://item.taobao.com/item.htm?id=123456789"
}
```

**请求参数**:

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| id | string | 是 | 商品 ID |
| url | string | 是 | 商品链接 |

**响应格式**:
```json
{
  "coupon_share_url": "https://uland.taobao.com/coupon/...",
  "clickURL": "https://s.click.taobao.com/...",
  "tpwd": "￥AbCdEfGhIj￥"
}
```

**响应参数**:

| 参数 | 类型 | 说明 |
|------|------|------|
| coupon_share_url | string | 优惠券分享链接 |
| clickURL | string | 点击链接 |
| tpwd | string | 淘宝口令 |

---

## 7. 京东联盟 API

### 7.1 商品搜索

**端点**: `GET /jd/union/goods/query`

**功能**: 搜索京东联盟商品。

**请求参数** (URL 查询字符串):

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| keyword | string | 是 | 搜索关键词 |
| pageIndex | integer | 否 | 页码（默认 1） |
| pageSize | integer | 否 | 每页数量（默认 10） |
| sortName | string | 否 | 排序字段 |
| sort | string | 否 | 排序方式（asc/desc） |

**请求示例**:
```
GET /jd/union/goods/query?keyword=USB+DAC&pageIndex=1&pageSize=10
```

**响应格式**:
```json
{
  "jd_union_open_goods_query_responce": {
    "queryResult": {
      "data": [
        {
          "skuId": "1234567890",
          "skuName": "商品名称",
          "imageUrl": "https://img14.360buyimg.com/...",
          "priceInfo": {
            "price": 799.00,
            "lowestPrice": 699.00
          },
          "shopInfo": {
            "shopName": "店铺名称"
          },
          "comments": 1000,
          "goodCommentsShare": 0.95,
          "materialUrl": "https://item.jd.com/1234567890.html"
        }
      ]
    },
    "totalCount": 100
  }
}
```

**配置要求**:
- 环境变量 `JD_APP_KEY`: 京东应用 Key
- 环境变量 `JD_APP_SECRET`: 京东联盟密钥
- 环境变量 `JD_UNION_ID`: 京东联盟 ID

### 7.2 推广链接生成

**端点**: `POST /jd/union/promotion/bysubunionid`

**功能**: 通过 subUnionId 生成京东推广链接。

**请求格式**:
```json
{
  "promotionCodeReq": {
    "materialId": "https://item.jd.com/1234567890.html",
    "sceneId": 1,
    "chainType": 3,
    "subUnionId": "子联盟ID（可选）",
    "pid": "PID（可选）"
  }
}
```

**请求参数**:

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| promotionCodeReq | object | 是 | 推广请求对象 |
| promotionCodeReq.materialId | string | 是 | 商品链接或 ID |
| promotionCodeReq.sceneId | integer | 是 | 场景 ID（通常为 1） |
| promotionCodeReq.chainType | integer | 是 | 链接类型（通常为 3） |
| promotionCodeReq.subUnionId | string | 否 | 子联盟 ID |
| promotionCodeReq.pid | string | 否 | PID |

**响应格式**:
```json
{
  "jd_union_open_promotion_bysubunionid_get_responce": {
    "getResult": {
      "data": {
        "clickURL": "https://union.jd.com/...",
        "shortURL": "https://u.jd.com/..."
      }
    }
  }
}
```

**响应参数**:

| 参数 | 类型 | 说明 |
|------|------|------|
| clickURL | string | 推广链接 |
| shortURL | string | 短链接 |

**前端调用示例**:
```dart
final resp = await apiClient.post(
  '$backendBase/jd/union/promotion/bysubunionid',
  data: {
    'promotionCodeReq': {
      'materialId': productLink,
      'sceneId': 1,
      'chainType': 3,
      if (subUnionId != null) 'subUnionId': subUnionId,
      if (pid != null) 'pid': pid,
    }
  },
);
```

### 7.3 获取京东推广链接（简化接口）

**端点**: `GET /api/get-jd-promotion`

**功能**: 简化接口，快速获取京东推广链接。

**请求参数** (URL 查询字符串):

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| skuId | string | 是 | 京东商品 SKU ID |
| subUnionId | string | 否 | 子联盟 ID |
| pid | string | 否 | PID |

**响应格式**: 与 `/jd/union/promotion/bysubunionid` 相同

### 7.4 测试搜索（调试用）

**端点**: `GET /proxy/test/jd_search`

**功能**: 测试京东搜索功能（调试用）。

**请求参数**: 与 `/jd/union/goods/query` 相同

---

## 8. 拼多多 API

### 8.1 备案查询

**端点**: `POST /pdd/authority/query`

**功能**: 查询拼多多备案信息，生成小程序备案链接。

**请求格式**:
```json
{
  "pid": "推广位ID"
}
```

**请求参数**:

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| pid | string | 是 | 拼多多推广位 ID |

**响应格式**:
```json
{
  "authority_url": "https://mobile.yangkeduo.com/..."
}
```

### 8.2 推广链接生成

**端点**: `POST /pdd/rp/prom/generate`

**功能**: 生成拼多多推广链接。

**请求格式**:
```json
{
  "goods_sign_list": ["商品签名1", "商品签名2"],
  "custom_parameters": "{\"uid\":\"chyinan\"}",
  "pid": "推广位ID"
}
```

**请求参数**:

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| goods_sign_list | array | 是 | 商品签名列表 |
| custom_parameters | string | 否 | 自定义参数（JSON 字符串） |
| pid | string | 否 | 推广位 ID（可从环境变量读取） |

**响应格式**:
```json
{
  "goods_promotion_url_generate_response": {
    "goods_promotion_url_list": [
      {
        "mobile_url": "https://mobile.yangkeduo.com/...",
        "url": "https://yangkeduo.com/...",
        "short_url": "https://p.pinduoduo.com/..."
      }
    ]
  }
}
```

### 8.3 搜索调试

**端点**: `POST /pdd/search_debug`

**功能**: 拼多多搜索调试接口。

**请求格式**:
```json
{
  "keyword": "搜索关键词",
  "page": 1,
  "pageSize": 10
}
```

**响应格式**: 返回搜索结果的调试信息

---

## 9. 商品搜索 API

### 9.1 统一商品搜索

**端点**: `GET /api/products/search`

**功能**: 统一商品搜索接口，支持多平台搜索。

**请求参数** (URL 查询字符串):

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| query | string | 是 | 搜索关键词 |
| page_no | integer | 否 | 页码（默认 1） |
| page_size | integer | 否 | 每页数量（默认 20） |
| platform | string | 否 | 平台筛选（taobao/jd/pdd/all，默认 all） |

**请求示例**:
```
GET /api/products/search?query=USB+DAC&page_no=1&page_size=10&platform=all
```

**响应格式**:
```json
{
  "products": [
    {
      "id": "123456789",
      "platform": "jd",
      "title": "商品标题",
      "price": 799.00,
      "originalPrice": 999.00,
      "coupon": 100.00,
      "finalPrice": 699.00,
      "imageUrl": "https://img14.360buyimg.com/...",
      "sales": 1000,
      "rating": 0.95,
      "shopTitle": "店铺名称",
      "link": "https://item.jd.com/123456789.html",
      "commission": 39.95,
      "description": "商品描述"
    }
  ],
  "total": 100,
  "page": 1,
  "pageSize": 10,
  "attempts": {
    "taobao": true,
    "jd": true,
    "pdd": false
  }
}
```

**响应参数**:

| 参数 | 类型 | 说明 |
|------|------|------|
| products | array | 商品列表（ProductModel 数组） |
| total | integer | 总结果数 |
| page | integer | 当前页码 |
| pageSize | integer | 每页数量 |
| attempts | object | 各平台搜索尝试结果 |

**ProductModel 字段说明**:

| 字段 | 类型 | 说明 |
|------|------|------|
| id | string | 商品 ID |
| platform | string | 平台标识（taobao/jd/pdd） |
| title | string | 商品标题 |
| price | number | 价格 |
| originalPrice | number | 原价 |
| coupon | number | 优惠券金额 |
| finalPrice | number | 最终价格 |
| imageUrl | string | 图片 URL |
| sales | integer | 销量 |
| rating | number | 评分（0.0-1.0） |
| shopTitle | string | 店铺名 |
| link | string | 商品链接 |
| commission | number | 佣金 |
| description | string | 描述 |

---

## 10. 管理端点 API

### 10.1 管理员登录

**端点**: `POST /admin/login`

**功能**: 验证管理员密码，用于解锁前端后台设置界面。

**请求格式**:
```json
{
  "password": "管理员密码"
}
```

**请求参数**:

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| password | string | 是 | 管理员密码 |

**请求头**:
```
Content-Type: application/json
```

**响应格式** (成功):
```json
{
  "success": true
}
```

**响应格式** (失败):
```json
{
  "success": false,
  "message": "密码错误"
}
```

**HTTP 状态码**:
- `200`: 登录成功
- `400`: 密码参数缺失
- `401`: 密码错误
- `500`: 服务器配置错误（ADMIN_PASSWORD 未配置）

**安全特性**:
- 使用常量时间比较函数防止时序攻击
- 支持 JSON 和表单格式请求
- 密码通过环境变量 `ADMIN_PASSWORD` 配置

**前端调用示例**:
```dart
final response = await apiClient.post(
  '$backendBase/admin/login',
  data: {'password': password},
);
if (response.data['success'] == true) {
  // 登录成功，解锁后台设置
}
```

### 10.2 获取配置信息

**端点**: `GET /__settings`

**功能**: 获取后端基础配置信息，供前端读取后端地址等配置。

**请求参数**: 无

**响应格式**:
```json
{
  "backend_base": "http://localhost:8080"
}
```

**响应参数**:

| 参数 | 类型 | 说明 |
|------|------|------|
| backend_base | string | 后端基础地址 |

**配置说明**:
- 后端地址可通过环境变量 `BACKEND_BASE` 配置
- 默认值: `http://localhost:8080`

**前端调用示例**:
```dart
final response = await apiClient.get('$backendBase/__settings');
final backendBase = response.data['backend_base'] as String;
```

### 10.3 调试信息查看

**端点**: `GET /__debug/last_return`  
**别名**: `GET /_debug/last_return`  
**别名**: `GET /debug/last_return`

**功能**: 查看最后一次 API 返回的调试信息，用于开发调试。

**请求参数** (URL 查询字符串):

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| history | integer | 否 | 设置为 `1` 时返回历史记录列表 |

**请求示例**:
```
GET /__debug/last_return
GET /__debug/last_return?history=1
```

**响应格式** (单条记录):
```json
{
  "ok": true,
  "path": "/taobao/tbk_search",
  "query": "搜索关键词",
  "body": {...},
  "ts": "2024-01-01T00:00:00Z"
}
```

**响应格式** (历史记录):
```json
{
  "ok": true,
  "history": [
    {
      "path": "/taobao/tbk_search",
      "query": "搜索关键词1",
      "body": {...},
      "ts": "2024-01-01T00:00:00Z"
    },
    {
      "path": "/jd/union/goods/query",
      "query": "搜索关键词2",
      "body": {...},
      "ts": "2024-01-01T01:00:00Z"
    }
  ]
}
```

**响应格式** (无调试信息):
```json
{
  "ok": false,
  "msg": "no debug info"
}
```

**功能说明**:
- 存储最近 20 条调试记录
- 仅用于开发环境调试
- 生产环境建议禁用或限制访问

---

## 11. 错误处理

### 11.1 错误分类

#### 11.1.1 HTTP 状态码

| 状态码 | 说明 | 使用场景 |
|--------|------|----------|
| 200 | 成功 | 请求成功处理 |
| 400 | 错误请求 | 请求参数错误或格式不正确 |
| 401 | 未授权 | 认证失败或未提供认证信息 |
| 404 | 未找到 | 请求的资源不存在 |
| 500 | 服务器错误 | 服务器内部错误或配置错误 |

#### 11.1.2 错误类型

**配置错误**:
- 缺失必需的环境变量（如 `TAOBAO_APP_SECRET`、`JD_APP_SECRET` 等）
- 配置项格式错误
- 响应: `500 Internal Server Error`

**API 错误**:
- 第三方 API 调用失败
- 签名验证失败
- 响应: `400/500` + 错误详情

**请求错误**:
- 参数缺失或格式错误
- 必需参数未提供
- 响应: `400 Bad Request`

**认证错误**:
- API Key 无效或未提供
- 管理员密码错误
- 响应: `401 Unauthorized`

### 11.2 错误响应格式

**标准错误响应**:
```json
{
  "error": "错误描述",
  "status": 500,
  "message": "详细错误信息"
}
```

**配置错误响应**:
```json
{
  "error": "secret not configured",
  "status": 500
}
```

**请求错误响应**:
```json
{
  "error": "query parameter required",
  "status": 400
}
```

**认证错误响应**:
```json
{
  "success": false,
  "message": "密码错误"
}
```

### 11.3 错误处理策略

**前端错误处理**:
- 根据 HTTP 状态码显示不同的错误提示
- 提供重试机制（对于网络错误）
- 记录错误日志便于调试

**后端错误处理**:
- 统一错误响应格式
- 记录详细错误日志（开发环境）
- 保护敏感信息（生产环境）
- 提供友好的错误消息

**常见错误场景**:

1. **网络超时**:
   - 前端: 显示"网络连接超时，请稍后重试"
   - 后端: 记录超时日志，返回 500 错误

2. **API 限流**:
   - 前端: 显示"请求过多，请稍后重试"
   - 后端: 返回 429 错误（如支持）

3. **配置缺失**:
   - 前端: 显示"服务配置错误，请联系管理员"
   - 后端: 返回 500 错误，记录配置缺失日志

---

## 12. 数据模型

### 12.1 ProductModel（商品模型）

**定义**:
```json
{
  "id": "string",
  "platform": "string",
  "title": "string",
  "price": "number",
  "originalPrice": "number",
  "coupon": "number",
  "finalPrice": "number",
  "imageUrl": "string",
  "sales": "integer",
  "rating": "number",
  "shopTitle": "string",
  "link": "string",
  "commission": "number",
  "description": "string"
}
```

**字段说明**:

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| id | string | 是 | 商品 ID（平台唯一标识） |
| platform | string | 是 | 平台标识（taobao/jd/pdd） |
| title | string | 是 | 商品标题 |
| price | number | 是 | 当前价格 |
| originalPrice | number | 否 | 原价 |
| coupon | number | 否 | 优惠券金额 |
| finalPrice | number | 是 | 最终价格（price - coupon） |
| imageUrl | string | 是 | 商品图片 URL |
| sales | integer | 否 | 销量 |
| rating | number | 否 | 评分（0.0-1.0） |
| shopTitle | string | 否 | 店铺名称 |
| link | string | 是 | 商品链接 |
| commission | number | 否 | 佣金金额 |
| description | string | 否 | 商品描述 |

### 12.2 ChatMessage（消息模型）

**定义**:
```json
{
  "id": "string",
  "role": "string",
  "content": "string",
  "timestamp": "string",
  "products": ["array<ProductModel>"]
}
```

**字段说明**:

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| id | string | 是 | 消息 ID |
| role | string | 是 | 角色（user/assistant/system） |
| content | string | 是 | 消息内容 |
| timestamp | string | 是 | 时间戳（ISO 8601） |
| products | array | 否 | 关联商品列表 |

### 12.3 Conversation（会话模型）

**定义**:
```json
{
  "id": "string",
  "title": "string",
  "messages": ["array<ChatMessage>"],
  "createdAt": "string",
  "updatedAt": "string"
}
```

**字段说明**:

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| id | string | 是 | 会话 ID |
| title | string | 是 | 会话标题 |
| messages | array | 是 | 消息列表 |
| createdAt | string | 是 | 创建时间（ISO 8601） |
| updatedAt | string | 是 | 更新时间（ISO 8601） |

### 12.4 签名响应模型

**定义**:
```json
{
  "ts": "string",
  "sign": "string"
}
```

**字段说明**:

| 字段 | 类型 | 说明 |
|------|------|------|
| ts | string | 时间戳（ISO 8601 格式） |
| sign | string | 签名结果（HMAC-SHA256 或 MD5） |

### 12.5 推广链接响应模型

**淘宝推广链接**:
```json
{
  "coupon_share_url": "string",
  "clickURL": "string",
  "tpwd": "string"
}
```

**京东推广链接**:
```json
{
  "clickURL": "string",
  "shortURL": "string"
}
```

**拼多多推广链接**:
```json
{
  "mobile_url": "string",
  "url": "string",
  "short_url": "string"
}
```

---

## 13. 集成示例

### 13.1 前端调用示例

#### 13.1.1 AI 聊天（流式响应）

```dart
import 'package:dio/dio.dart';
import 'dart:convert';

Future<void> streamChat() async {
  final dio = Dio();
  final backendBase = 'http://localhost:8080';
  final apiKey = 'your-openai-api-key';
  
  try {
    final response = await dio.post(
      '$backendBase/v1/chat/completions',
      data: {
        'model': 'gpt-3.5-turbo',
        'messages': [
          {'role': 'user', 'content': '推荐一款 USB DAC'}
        ],
        'stream': true,
      },
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.stream,
      ),
    );
    
    // 处理流式响应
    response.data.stream.listen((chunk) {
      final data = utf8.decode(chunk);
      // 解析 SSE 格式数据
      print(data);
    });
  } catch (e) {
    print('Error: $e');
  }
}
```

#### 13.1.2 商品搜索

```dart
Future<List<Map<String, dynamic>>> searchProducts(String keyword) async {
  final apiClient = ApiClient();
  final backendBase = 'http://localhost:8080';
  
  try {
    final response = await apiClient.get(
      '$backendBase/api/products/search',
      params: {
        'query': keyword,
        'page_no': 1,
        'page_size': 10,
        'platform': 'all',
      },
    );
    
    final products = (response.data['products'] as List)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    
    return products;
  } catch (e) {
    print('Search error: $e');
    return [];
  }
}
```

#### 13.1.3 生成推广链接

```dart
Future<String?> generatePromotionLink(Map<String, dynamic> product) async {
  final apiClient = ApiClient();
  final backendBase = 'http://localhost:8080';
  
  try {
    String? link;
    final platform = product['platform'] as String;
    
    if (platform == 'taobao') {
      final response = await apiClient.post(
        '$backendBase/taobao/convert',
        data: {
          'id': product['id'],
          'url': product['link'],
        },
      );
      link = response.data['coupon_share_url'] ?? 
             response.data['clickURL'] ?? 
             response.data['tpwd'];
    } else if (platform == 'jd') {
      final response = await apiClient.post(
        '$backendBase/jd/union/promotion/bysubunionid',
        data: {
          'promotionCodeReq': {
            'materialId': product['link'],
            'sceneId': 1,
            'chainType': 3,
          },
        },
      );
      link = response.data['jd_union_open_promotion_bysubunionid_get_responce']
                ['getResult']['data']['clickURL'];
    } else if (platform == 'pdd') {
      final response = await apiClient.post(
        '$backendBase/sign/pdd',
        data: {
          'goods_sign_list': [product['id']],
          'custom_parameters': '{"uid":"user123"}',
        },
      );
      link = response.data['clickURL'];
    }
    
    return link;
  } catch (e) {
    print('Generate link error: $e');
    return null;
  }
}
```

### 13.2 cURL 调用示例

#### 13.2.1 AI 聊天

```bash
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [
      {"role": "user", "content": "推荐一款 USB DAC"}
    ],
    "stream": false
  }'
```

#### 13.2.2 商品搜索

```bash
curl -X GET "http://localhost:8080/api/products/search?query=USB+DAC&page_no=1&page_size=10&platform=all"
```

#### 13.2.3 淘宝签名

```bash
curl -X POST http://localhost:8080/sign/taobao \
  -H "Content-Type: application/json" \
  -H "x-ts: 2024-01-01T00:00:00Z" \
  -d '{
    "url": "https://item.taobao.com/item.htm?id=123456",
    "text": "商品标题"
  }'
```

#### 13.2.4 管理员登录

```bash
curl -X POST http://localhost:8080/admin/login \
  -H "Content-Type: application/json" \
  -d '{
    "password": "your_admin_password"
  }'
```

---

## 14. 版本管理

### 14.1 API 版本策略

**当前版本**: v1.0

**版本控制方式**:
- 通过 URL 路径版本控制（如 `/v1/chat/completions`）
- 向后兼容原则：新版本不破坏旧版本接口
- 废弃接口：提前通知，保留过渡期

### 14.2 变更记录

| 版本 | 日期 | 变更内容 |
|------|------|----------|
| 1.0 | 2024 | 初始 API 版本 |

### 14.3 未来规划

**短期规划** (3 个月内):
- 添加 API 限流机制
- 完善错误码体系
- 添加请求日志记录

**中期规划** (6 个月内):
- 引入 API 版本控制
- 添加 API 文档自动生成
- 实现 API 监控和告警

**长期规划** (1 年内):
- 支持 GraphQL 查询
- 实现 API 网关功能
- 添加 API 认证令牌机制

---

## 15. 安全考虑

### 15.1 API 密钥保护

**前端**:
- API Key 存储在本地（Hive），不提交到版本控制
- 用户自行保管，应用不收集
- 支持运行时配置和清除

**后端**:
- 所有密钥通过环境变量配置
- 存储在 `.env` 文件（不提交到版本控制）
- 交互式启动时提示配置

### 15.2 签名安全

**签名算法**:
- 淘宝/京东: HMAC-SHA256
- 拼多多: MD5
- 时间戳包含在签名计算中，防止重放攻击

**安全特性**:
- 签名计算在服务器端完成
- 密钥不暴露给前端
- 使用常量时间比较防止时序攻击

### 15.3 HTTPS 通信

**要求**:
- 生产环境必须使用 HTTPS
- 使用有效的 SSL 证书
- 保护数据传输安全

### 15.4 CORS 配置

**开发环境**:
- 允许所有来源（`*`）
- 便于开发和测试

**生产环境建议**:
- 限制允许的来源
- 配置具体的域名白名单
- 添加请求频率限制

---

## 16. 性能优化

### 16.1 请求优化

**超时控制**:
- 连接超时: 30 秒
- 接收超时: 5 分钟（支持流式响应）
- 避免长时间等待

**并发处理**:
- 支持异步非阻塞处理
- 多平台搜索并行执行
- 使用 Dart 的 `async/await`

### 16.2 缓存策略

**推广链接缓存**:
- 内存缓存 + Hive 持久化
- 缓存有效期: 30 分钟
- 支持强制刷新

**价格缓存**:
- 内存缓存商品价格
- 减少重复 API 调用
- 提升响应速度

### 16.3 响应优化

**流式响应**:
- AI 聊天支持流式响应
- 实时显示，提升用户体验
- 减少等待时间

**数据压缩**:
- 响应数据可考虑压缩（如 gzip）
- 减少网络传输量
- 提升传输速度

---

## 17. 测试指南

### 17.1 API 测试工具

**推荐工具**:
- Postman: API 测试和文档
- cURL: 命令行测试
- Dart `http` package: 单元测试

### 17.2 测试场景

**功能测试**:
- 正常请求流程
- 参数验证
- 错误处理
- 边界条件

**性能测试**:
- 响应时间
- 并发处理
- 负载测试

**安全测试**:
- 认证授权
- 签名验证
- 输入验证

### 17.3 测试示例

**单元测试** (Dart):
```dart
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  test('Admin login with correct password', () async {
    final response = await http.post(
      Uri.parse('http://localhost:8080/admin/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'password': 'test_password'}),
    );
    
    expect(response.statusCode, 200);
    final data = jsonDecode(response.body);
    expect(data['success'], true);
  });
}
```

---

## 18. 附录

### 18.1 环境变量参考

#### 必需配置

- `ADMIN_PASSWORD`: 管理员密码

#### 可选配置（按需）

**OpenAI**:
- `OPENAI_API_URL`: OpenAI API 地址（默认: `https://api.openai.com/v1/chat/completions`）
- `OPENAI_API_KEY`: OpenAI API Key（也可由前端提供）

**淘宝联盟**:
- `TAOBAO_APP_KEY`: 淘宝应用 Key
- `TAOBAO_APP_SECRET`: 淘宝应用密钥
- `TAOBAO_ADZONE_ID`: 淘宝推广位 ID

**京东联盟**:
- `JD_APP_KEY`: 京东应用 Key
- `JD_APP_SECRET`: 京东联盟密钥
- `JD_UNION_ID`: 京东联盟 ID

**拼多多**:
- `PDD_CLIENT_ID`: 拼多多客户端 ID
- `PDD_CLIENT_SECRET`: 拼多多客户端密钥
- `PDD_PID`: 拼多多推广位 ID

**服务器配置**:
- `PORT`: 服务器端口（默认: 8080）
- `BACKEND_BASE`: 后端基础地址（默认: `http://localhost:8080`）

### 18.2 API 端点速查表

| 端点 | 方法 | 功能 | 认证 |
|------|------|------|------|
| `/v1/chat/completions` | POST | AI 聊天代理 | Bearer Token |
| `/sign/taobao` | POST | 淘宝签名 | - |
| `/sign/jd` | POST | 京东签名 | - |
| `/sign/pdd` | POST | 拼多多签名 | - |
| `/taobao/tbk_search` | GET | 淘宝商品搜索 | - |
| `/taobao/convert` | POST | 淘宝链接转换 | - |
| `/jd/union/goods/query` | GET | 京东商品搜索 | - |
| `/jd/union/promotion/bysubunionid` | POST | 京东推广链接 | - |
| `/api/get-jd-promotion` | GET | 京东推广链接（简化） | - |
| `/proxy/test/jd_search` | GET | 京东搜索测试（调试） | - |
| `/pdd/authority/query` | POST | 拼多多备案查询 | - |
| `/pdd/rp/prom/generate` | POST | 拼多多推广链接 | - |
| `/pdd/search_debug` | POST | 拼多多搜索调试 | - |
| `/api/products/search` | GET | 统一商品搜索 | - |
| `/admin/login` | POST | 管理员登录 | - |
| `/__settings` | GET | 获取配置信息 | - |
| `/__debug/last_return` | GET | 调试信息查看 | - |
| `/_debug/last_return` | GET | 调试信息查看（别名） | - |
| `/debug/last_return` | GET | 调试信息查看（别名） | - |

### 18.3 参考文档

- [PRD 文档](../PRD.md) - 产品需求文档
- [架构文档](./architecture.md) - 完整技术架构文档
- [前端架构文档](./frontend-architecture.md) - 前端架构设计文档
- [后端架构文档](./backend-architecture.md) - 后端架构设计文档
- [README](../README.md) - 项目说明文档
- [OpenAI API 文档](https://platform.openai.com/docs) - OpenAI API 官方文档
- [淘宝联盟 API](https://open.taobao.com/) - 淘宝联盟开放平台
- [京东联盟 API](https://union.jd.com/) - 京东联盟开放平台
- [拼多多开放平台](https://open.pinduoduo.com/) - 拼多多开放平台

### 18.4 变更日志

| 版本 | 日期 | 变更内容 | 作者 |
|------|------|----------|------|
| 1.0 | 2024 | 初始 API 设计文档 | CHYINAN (Architect) |

---

**文档维护者**: 架构团队  
**审核者**: 技术团队  
**批准者**: 技术负责人

---

*本文档基于项目实际代码和架构文档编写，反映了当前系统的真实 API 设计状态。*
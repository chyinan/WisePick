# 快淘帮 WisePick - 技术架构文档

**版本**: 1.0  
**创建日期**: 2024  
**最后更新**: 2024  
**文档状态**: 正式版  
**架构师**: Winston (Architect Agent)

---

## 1. 文档概述

### 1.1 文档目的

本文档详细描述了快淘帮 WisePick 项目的技术架构，包括前端 Flutter 应用和后端代理服务的完整技术实现方案。本文档旨在：

- 为开发团队提供清晰的技术实现指南
- 确保新功能开发遵循统一的架构模式
- 指导系统扩展和优化决策
- 作为代码审查和架构评审的参考标准

### 1.2 文档范围

本文档涵盖：

- **前端架构**: Flutter 应用的技术栈、架构模式、组件设计
- **后端架构**: Dart Shelf 代理服务器的设计、API 端点、集成方案
- **数据架构**: 本地存储方案、数据模型、缓存策略
- **集成架构**: 第三方 API 集成、外部服务对接
- **部署架构**: 跨平台部署方案、基础设施要求
- **安全架构**: 数据安全、API 安全、认证授权

### 1.3 目标读者

- 前端开发工程师
- 后端开发工程师
- 系统架构师
- DevOps 工程师
- 技术负责人

---

## 2. 现有项目分析

### 2.1 项目现状

**项目类型**: Brownfield（现有项目增强）  
**主要目的**: 基于 AI 的智能购物推荐应用  
**技术栈**: Flutter (Dart) + Shelf (Dart)  
**架构风格**: 前后端分离，客户端-服务器架构  
**部署方式**: 跨平台客户端 + 独立后端服务

### 2.2 现有技术栈

#### 前端技术栈

| 类别 | 技术 | 版本 | 用途 |
|------|------|------|------|
| 框架 | Flutter | 3.9.2+ | 跨平台 UI 框架 |
| 语言 | Dart | 3.9.2+ | 编程语言 |
| 状态管理 | Riverpod | 2.5.1 | 响应式状态管理 |
| 本地存储 | Hive | 2.2.3 | NoSQL 本地数据库 |
| 网络请求 | Dio | 5.1.2 | HTTP 客户端 |
| UI 框架 | Material Design 3 | - | 设计系统 |
| 字体 | Noto Sans SC | - | 中文字体支持 |

#### 后端技术栈

| 类别 | 技术 | 版本 | 用途 |
|------|------|------|------|
| 语言 | Dart | 3.9.2+ | 编程语言 |
| Web 框架 | Shelf | latest | HTTP 服务器框架 |
| 路由 | shelf_router | latest | 路由管理 |
| HTTP 客户端 | http | latest | 外部 API 调用 |

### 2.3 现有架构模式

1. **MVVM 模式**: 使用 Riverpod 实现 View-ViewModel 分离
2. **Adapter 模式**: 商品搜索适配不同平台 API
3. **Service 层模式**: 业务逻辑封装在 Service 中
4. **Repository 模式**: 数据访问层抽象（部分实现）

### 2.4 项目结构

```
wisepick_dart_version/
├── lib/                          # Flutter 应用源码
│   ├── core/                     # 核心功能模块
│   │   ├── api_client.dart       # API 客户端封装
│   │   ├── config.dart           # 配置管理
│   │   ├── jd_oauth_service.dart # 京东 OAuth 服务
│   │   ├── jd_sign.dart          # 京东签名服务
│   │   ├── pdd_client.dart       # 拼多多客户端
│   │   └── theme/                # 主题配置
│   ├── features/                 # 功能模块（按功能组织）
│   │   ├── chat/                 # 聊天功能模块
│   │   │   ├── chat_service.dart
│   │   │   ├── chat_providers.dart
│   │   │   ├── conversation_model.dart
│   │   │   └── conversation_repository.dart
│   │   ├── products/              # 商品功能模块
│   │   │   ├── product_service.dart
│   │   │   ├── search_service.dart
│   │   │   ├── taobao_adapter.dart
│   │   │   ├── jd_adapter.dart
│   │   │   ├── pdd_adapter.dart
│   │   │   └── product_model.dart
│   │   └── cart/                 # 选品车功能模块
│   │       ├── cart_service.dart
│   │       └── cart_providers.dart
│   ├── screens/                   # 页面组件
│   │   ├── chat_page.dart
│   │   ├── admin_settings_page.dart
│   │   └── user_settings_page.dart
│   ├── services/                  # 业务服务
│   │   ├── api_service.dart
│   │   ├── chat_service.dart
│   │   ├── notification_service.dart
│   │   ├── price_refresh_service.dart
│   │   └── ai_prompt_service.dart
│   ├── widgets/                   # 通用 UI 组件
│   │   ├── product_card.dart
│   │   └── loading_indicator.dart
│   └── models/                    # 数据模型
│       └── message.dart
├── server/                        # 后端代理服务
│   ├── bin/
│   │   └── proxy_server.dart      # 服务器入口
│   └── pubspec.yaml
├── test/                          # 测试文件
├── assets/                        # 资源文件
│   ├── fonts/                     # 字体文件
│   └── icon/                      # 应用图标
└── pubspec.yaml                   # 项目配置
```

### 2.5 现有约束和限制

1. **平台兼容性**: 必须支持 Windows、macOS、Linux、Android、iOS、Web
2. **数据存储**: 使用本地存储（Hive），无云端数据库
3. **API 依赖**: 依赖第三方电商平台 API（淘宝、京东、拼多多）
4. **AI 服务**: 依赖 OpenAI API 或兼容服务
5. **网络限制**: 需要处理网络错误和 API 限流

---

## 3. 系统架构设计

### 3.1 整体架构

快淘帮 WisePick 采用**前后端分离架构**，包含以下主要组件：

```
┌─────────────────────────────────────────────────────────────┐
│                     用户设备层                                │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │ Windows  │  │  macOS   │  │  Linux   │  │  Mobile  │  │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                  Flutter 客户端应用层                         │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  UI 层 (Material Design 3)                          │  │
│  │  ├── ChatPage        ├── CartPage                   │  │
│  │  └── SettingsPage    └── ProductDetailPage          │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  状态管理层 (Riverpod)                                │  │
│  │  ├── ChatProviders  ├── CartProviders               │  │
│  │  └── ThemeProvider  └── SettingsProvider            │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  业务逻辑层 (Services)                                │  │
│  │  ├── ChatService     ├── ProductService             │  │
│  │  ├── CartService     └── NotificationService       │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  数据访问层                                           │  │
│  │  ├── ApiClient       ├── Hive (本地存储)             │  │
│  │  └── Adapters (平台适配器)                            │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                  后端代理服务层 (Shelf)                       │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  API 路由层                                           │  │
│  │  ├── /v1/chat/completions  (AI 代理)                 │  │
│  │  ├── /sign/taobao          (淘宝签名)                │  │
│  │  ├── /sign/jd              (京东签名)                │  │
│  │  └── /sign/pdd              (拼多多签名)              │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  业务处理层                                           │  │
│  │  ├── 签名服务  ├── 转链服务  └── 代理转发             │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    第三方服务层                                │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │ OpenAI   │  │  淘宝联盟 │  │  京东联盟 │  │  拼多多  │  │
│  │   API    │  │   API    │  │   API    │  │   API    │  │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 架构分层说明

#### 3.2.1 客户端架构分层

1. **UI 层 (Presentation Layer)**
   - 职责: 用户界面展示和交互
   - 技术: Flutter Widgets, Material Design 3
   - 特点: 响应式布局，支持深色模式

2. **状态管理层 (State Management Layer)**
   - 职责: 应用状态管理和数据流控制
   - 技术: Riverpod 2.5.1
   - 特点: 响应式编程，依赖注入

3. **业务逻辑层 (Business Logic Layer)**
   - 职责: 业务规则实现和流程控制
   - 技术: Dart Services
   - 特点: 单一职责，可测试

4. **数据访问层 (Data Access Layer)**
   - 职责: 数据获取和持久化
   - 技术: ApiClient, Hive, Adapters
   - 特点: 抽象接口，平台适配

#### 3.2.2 后端架构分层

1. **路由层 (Routing Layer)**
   - 职责: HTTP 请求路由和分发
   - 技术: shelf_router
   - 特点: RESTful API 设计

2. **业务处理层 (Business Processing Layer)**
   - 职责: 业务逻辑处理和 API 调用
   - 技术: Dart Services
   - 特点: 无状态处理，错误处理

3. **集成层 (Integration Layer)**
   - 职责: 第三方 API 集成
   - 技术: http package
   - 特点: 统一错误处理，重试机制

### 3.3 数据流设计

#### 3.3.1 AI 聊天数据流

```
用户输入
  │
  ▼
ChatPage (UI)
  │
  ▼
ChatService.getAiReply()
  │
  ▼
ApiClient.post('/v1/chat/completions')
  │
  ▼
后端 Proxy Server
  │
  ▼
OpenAI API (或兼容服务)
  │
  ▼
流式响应返回
  │
  ▼
ChatPage 实时显示
```

#### 3.3.2 商品搜索数据流

```
用户输入关键词
  │
  ▼
ProductService.searchProducts()
  │
  ├── TaobaoAdapter.search()
  ├── JdAdapter.search()
  └── PddAdapter.search()
  │
  ├── 并行调用各平台 API
  │
  ▼
统一 ProductModel 封装
  │
  ▼
去重和合并（优先京东）
  │
  ▼
UI 展示商品列表
```

#### 3.3.3 推广链接生成数据流

```
用户请求推广链接
  │
  ▼
ProductService.generatePromotionLink()
  │
  ├── 检查缓存（内存 + Hive）
  │   └── 命中则直接返回
  │
  ▼
ApiClient.post('/sign/{platform}')
  │
  ▼
后端处理签名和转链
  │
  ├── 淘宝: /sign/taobao
  ├── 京东: /sign/jd
  └── 拼多多: /sign/pdd
  │
  ▼
返回推广链接
  │
  ▼
缓存（30 分钟有效期）
  │
  ▼
返回给用户
```

---

## 4. 组件架构

### 4.1 前端核心组件

#### 4.1.1 API 客户端组件 (ApiClient)

**位置**: `lib/core/api_client.dart`

**职责**:
- 统一 HTTP 请求封装
- 错误处理和重试机制
- 超时配置（支持流式响应）

**设计要点**:
```dart
class ApiClient {
  final Dio dio;
  
  // 配置超时时间
  // - connectTimeout: 30 秒
  // - receiveTimeout: 5 分钟（支持流式响应）
  
  Future<Response> get(String path, {Map<String, dynamic>? params});
  Future<Response> post(String path, {
    dynamic data,
    Map<String, dynamic>? headers,
    ResponseType? responseType
  });
}
```

**集成点**:
- 所有 Service 层组件通过 ApiClient 发起网络请求
- 支持流式响应（ResponseType.stream）

#### 4.1.2 商品服务组件 (ProductService)

**位置**: `lib/features/products/product_service.dart`

**职责**:
- 多平台商品搜索
- 推广链接生成和缓存
- 商品数据统一封装

**设计模式**: Adapter 模式

**关键接口**:
```dart
class ProductService {
  // 搜索商品
  Future<List<ProductModel>> searchProducts(
    String platform,  // 'taobao' | 'jd' | 'pdd' | 'all'
    String keyword,
    {int page = 1, int pageSize = 10}
  );
  
  // 生成推广链接
  Future<String?> generatePromotionLink(
    ProductModel product,
    {bool forceRefresh = false}
  );
}
```

**集成点**:
- TaobaoAdapter: 淘宝平台适配
- JdAdapter: 京东平台适配
- PddAdapter: 拼多多平台适配
- Hive: 推广链接缓存

#### 4.1.3 聊天服务组件 (ChatService)

**位置**: `lib/features/chat/chat_service.dart`

**职责**:
- AI 对话交互
- 流式响应处理
- 会话管理

**关键接口**:
```dart
class ChatService {
  // 获取 AI 回复（非流式）
  Future<String> getAiReply(
    String prompt,
    {bool includeTitleInstruction = false}
  );
  
  // 获取 AI 回复（流式）
  Future<Stream<String>> getAiReplyStream(
    String prompt,
    {bool includeTitleInstruction = false}
  );
  
  // 生成会话标题
  Future<String> generateConversationTitle(String firstUserMsg);
}
```

**集成点**:
- ApiClient: 网络请求
- AiPromptService: Prompt 构建
- Hive: 会话历史存储

#### 4.1.4 选品车服务组件 (CartService)

**位置**: `lib/features/cart/cart_service.dart`

**职责**:
- 选品车数据管理
- 商品数量调整
- 价格刷新

**关键接口**:
```dart
class CartService {
  Future<void> addItem(ProductModel product, {int quantity = 1});
  Future<void> removeItem(String productId);
  Future<void> setQuantity(String productId, int quantity);
  Future<List<Map<String, dynamic>>> getItems();
}
```

**集成点**:
- Hive: 数据持久化
- PriceRefreshService: 价格自动刷新
- NotificationService: 价格变化通知

### 4.2 后端核心组件

#### 4.2.1 代理服务器 (ProxyServer)

**位置**: `server/bin/proxy_server.dart`

**职责**:
- HTTP 请求路由
- API 代理转发
- 签名和转链服务

**路由设计**:
```dart
Router router = Router()
  ..post('/v1/chat/completions', _handleProxy)
  ..post('/sign/taobao', _handleTaobaoSign)
  ..post('/sign/jd', _handleJdSign)
  ..post('/sign/pdd', _handlePddSign)
  ..post('/taobao/convert', _handleTaobaoConvert)
  ..post('/jd/union/promotion/bysubunionid', _handleJdPromotion)
  ..post('/admin/login', _handleAdminLogin);
```

**关键特性**:
- 支持流式响应转发
- 环境变量配置管理
- 交互式启动（提示未配置项）
- 配置持久化（.env 文件）

#### 4.2.2 签名服务组件

**职责**: 处理各平台 API 签名

**淘宝签名** (`/sign/taobao`):
- 使用 HMAC-SHA256 签名
- 支持时间戳验证
- 返回签名结果

**京东签名** (`/sign/jd`):
- 使用京东联盟 API 签名算法
- 支持多种推广链接生成方式

**拼多多签名** (`/sign/pdd`):
- 使用拼多多开放平台签名算法
- 支持批量商品推广链接生成

---

## 5. 数据模型设计

### 5.1 核心数据模型

#### 5.1.1 商品模型 (ProductModel)

**位置**: `lib/features/products/product_model.dart`

**定义**:
```dart
@HiveType(typeId: 0)
class ProductModel {
  @HiveField(0) final String id;              // 商品 ID
  @HiveField(1) final String platform;        // 平台: 'taobao' | 'jd' | 'pdd'
  @HiveField(2) final String title;           // 商品标题
  @HiveField(3) final double price;           // 价格
  @HiveField(4) final double originalPrice;   // 原价
  @HiveField(5) final double coupon;          // 优惠券金额
  @HiveField(6) final double finalPrice;      // 最终价格
  @HiveField(7) final String imageUrl;       // 图片 URL
  @HiveField(8) final int sales;              // 销量
  @HiveField(9) final double rating;          // 评分 (0.0-1.0)
  @HiveField(13) final String shopTitle;      // 店铺名
  @HiveField(10) final String link;          // 商品链接
  @HiveField(11) final double commission;    // 佣金
  @HiveField(12) final String description;   // 描述
}
```

**特点**:
- 使用 Hive 注解支持序列化
- 统一不同平台的数据格式
- 支持向后兼容（legacy 字段）

#### 5.1.2 消息模型 (ChatMessage)

**位置**: `lib/features/chat/chat_message.dart`

**定义**:
```dart
class ChatMessage {
  final String id;                    // 消息 ID
  final String role;                  // 角色: 'user' | 'assistant'
  final String content;               // 消息内容
  final DateTime timestamp;           // 时间戳
  final List<ProductModel>? products; // 关联商品（可选）
}
```

#### 5.1.3 会话模型 (Conversation)

**位置**: `lib/features/chat/conversation_model.dart`

**定义**:
```dart
class Conversation {
  final String id;                    // 会话 ID
  final String title;                 // 会话标题
  final List<ChatMessage> messages;   // 消息列表
  final DateTime createdAt;           // 创建时间
  final DateTime updatedAt;           // 更新时间
}
```

### 5.2 数据存储设计

#### 5.2.1 Hive 存储结构

**存储 Boxes**:

1. **settings** (应用设置)
   ```dart
   {
     'openai_api': String?,           // OpenAI API Key
     'openai_base': String?,           // OpenAI API 地址
     'openai_model': String?,          // AI 模型名称
     'backend_base': String?,          // 后端代理地址
     'embed_prompts': bool?,           // Prompt 嵌入开关
     'debug_ai_response': bool?,       // 调试模式
     'use_mock_ai': bool?,             // Mock AI 模式
     'max_tokens': String?,             // Max Tokens 配置
     'jd_sub_union_id': String?,       // 京东 subUnionId
     'jd_pid': String?                 // 京东 PID
   }
   ```

2. **cart** (选品车)
   ```dart
   List<Map<String, dynamic>>  // 商品列表
   {
     'id': String,
     'platform': String,
     'title': String,
     'price': double,
     'qty': int,
     // ... 其他 ProductModel 字段
   }
   ```

3. **conversations** (会话历史)
   ```dart
   Map<String, Conversation>  // key: conversationId
   ```

4. **promo_cache** (推广链接缓存)
   ```dart
   Map<String, Map<String, dynamic>>  // key: productId
   {
     'link': String,
     'expiry': int  // 过期时间戳（毫秒）
   }
   ```

#### 5.2.2 缓存策略

**推广链接缓存**:
- **存储位置**: 内存缓存 + Hive 持久化
- **有效期**: 30 分钟
- **刷新策略**: 支持强制刷新（forceRefresh = true）

**价格缓存** (后端):
- **存储位置**: 内存缓存
- **有效期**: 可配置（默认较短）
- **用途**: 减少重复 API 调用

---

## 6. API 设计

### 6.1 前端调用后端 API

#### 6.1.1 AI 聊天接口

**端点**: `POST /v1/chat/completions`

**请求**:
```json
{
  "model": "gpt-3.5-turbo",
  "messages": [
    {"role": "system", "content": "..."},
    {"role": "user", "content": "..."}
  ],
  "stream": true,
  "max_tokens": 1000
}
```

**响应** (流式):
```
data: {"choices": [{"delta": {"content": "..."}}]}

data: {"choices": [{"delta": {"content": "..."}}]}

data: [DONE]
```

**响应** (非流式):
```json
{
  "choices": [{
    "message": {
      "role": "assistant",
      "content": "..."
    }
  }]
}
```

#### 6.1.2 推广链接生成接口

**淘宝转链**: `POST /taobao/convert`
```json
{
  "id": "商品ID",
  "url": "商品链接"
}
```

**响应**:
```json
{
  "coupon_share_url": "推广链接",
  "clickURL": "点击链接",
  "tpwd": "淘宝口令"
}
```

**京东推广**: `POST /jd/union/promotion/bysubunionid`
```json
{
  "promotionCodeReq": {
    "materialId": "商品链接",
    "sceneId": 1,
    "chainType": 3,
    "subUnionId": "子联盟ID（可选）",
    "pid": "PID（可选）"
  }
}
```

**响应**:
```json
{
  "jd_union_open_promotion_bysubunionid_get_responce": {
    "getResult": {
      "data": {
        "clickURL": "推广链接",
        "shortURL": "短链接"
      }
    }
  }
}
```

**拼多多推广**: `POST /sign/pdd`
```json
{
  "goods_sign_list": ["商品ID"],
  "custom_parameters": "{\"uid\":\"chyinan\"}"
}
```

**响应**:
```json
{
  "clickURL": "推广链接",
  "raw": {
    "goods_promotion_url_generate_response": {
      "goods_promotion_url_list": [{
        "mobile_url": "移动端链接",
        "url": "PC 端链接"
      }]
    }
  }
}
```

#### 6.1.3 管理员接口

**登录验证**: `POST /admin/login`
```json
{
  "password": "管理员密码"
}
```

**响应**:
```json
{
  "success": true,
  "token": "认证令牌（可选）"
}
```

### 6.2 第三方 API 集成

#### 6.2.1 OpenAI API

**用途**: AI 对话服务

**集成方式**:
- 直接调用（前端配置 API Key）
- 通过后端代理（后端配置 API Key）

**认证**: Bearer Token (API Key)

**限流处理**:
- 429 错误: 提示用户稍后重试
- 自动重试机制（可配置）

#### 6.2.2 淘宝联盟 API

**用途**: 商品搜索、转链

**集成方式**: 通过后端代理

**认证**: App Key + App Secret

**关键接口**:
- 商品搜索
- 链接转链
- 优惠券查询

#### 6.2.3 京东联盟 API

**用途**: 商品搜索、推广链接生成

**集成方式**: 
- 前端直接调用（部分接口）
- 后端代理（签名和转链）

**认证**: App Key + App Secret + Union ID

**关键接口**:
- 商品搜索
- 推广链接生成
- 订单查询

#### 6.2.4 拼多多 API

**用途**: 商品搜索、推广链接生成

**集成方式**: 前端直接调用 + 后端签名

**认证**: Client ID + Client Secret

**关键接口**:
- 商品搜索
- 推广链接生成

---

## 7. 安全架构

### 7.1 数据安全

#### 7.1.1 API Key 保护

**前端**:
- 存储在 Hive 本地数据库（未加密，但不在版本控制中）
- 用户自行保管，应用不收集
- 支持运行时配置和清除

**后端**:
- 通过环境变量配置
- 存储在 `.env` 文件（不提交到版本控制）
- 交互式启动时提示配置

#### 7.1.2 管理员认证

**实现方式**:
- 密码哈希验证（SHA-256）
- 前端: 本地验证（7 次点击"关于"触发）
- 后端: `/admin/login` 端点验证

**默认密码**: 已哈希存储，需通过环境变量或配置修改

### 7.2 API 安全

#### 7.2.1 请求签名

**淘宝/京东签名**:
- 使用 HMAC-SHA256 签名算法
- 包含时间戳防止重放攻击
- 后端统一处理，前端不暴露密钥

#### 7.2.2 HTTPS 通信

**要求**:
- 生产环境必须使用 HTTPS
- 后端 API 使用 HTTPS
- 第三方 API 调用使用 HTTPS

### 7.3 数据隐私

**本地存储**:
- 所有用户数据存储在本地（Hive）
- 不涉及云端数据同步
- 用户可随时清除数据

**第三方数据**:
- 不存储用户敏感信息
- 商品数据仅用于展示
- 推广链接不包含用户个人信息

---

## 8. 部署架构

### 8.1 前端部署

#### 8.1.1 桌面端部署

**Windows**:
```bash
flutter build windows --release
# 输出: build/windows/runner/Release/wisepick_dart_version.exe
```

**macOS**:
```bash
flutter build macos --release
# 输出: build/macos/Build/Products/Release/wisepick_dart_version.app
```

**Linux**:
```bash
flutter build linux --release
# 输出: build/linux/x64/release/bundle/
```

#### 8.1.2 移动端部署

**Android**:
```bash
flutter build apk --release        # APK
flutter build appbundle --release  # AAB (Google Play)
```

**iOS**:
```bash
flutter build ios --release
# 需要 Xcode 进行签名和发布
```

#### 8.1.3 Web 部署

```bash
flutter build web --release
# 输出: build/web/
# 可部署到: Vercel, Netlify, GitHub Pages 等
```

### 8.2 后端部署

#### 8.2.1 服务器要求

- **操作系统**: Linux (推荐 Ubuntu 20.04+)
- **Dart SDK**: 3.9.2+
- **内存**: 至少 512MB
- **网络**: 可访问外部 API

#### 8.2.2 部署步骤

1. **安装 Dart SDK**
   ```bash
   # Ubuntu/Debian
   sudo apt-get update
   sudo apt-get install dart
   ```

2. **部署代码**
   ```bash
   git clone <repo-url>
   cd wisepick_dart_version/server
   dart pub get
   ```

3. **配置环境变量**
   ```bash
   # 创建 .env 文件
   export TAOBAO_APP_SECRET="..."
   export JD_APP_SECRET="..."
   # ... 其他配置
   ```

4. **启动服务**
   ```bash
   dart run bin/proxy_server.dart
   ```

#### 8.2.3 进程管理

**使用 PM2** (推荐):
```bash
npm install -g pm2
pm2 start "dart run bin/proxy_server.dart" --name wisepick-proxy
pm2 save
pm2 startup
```

**使用 systemd**:
```ini
[Unit]
Description=WisePick Proxy Server
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/path/to/server
Environment="PATH=/usr/lib/dart/bin:$PATH"
ExecStart=/usr/lib/dart/bin/dart run bin/proxy_server.dart
Restart=always

[Install]
WantedBy=multi-user.target
```

#### 8.2.4 反向代理 (Nginx)

```nginx
server {
    listen 80;
    server_name api.yourdomain.com;

    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```

### 8.3 环境配置

#### 8.3.1 开发环境

- **前端**: 本地运行，连接本地后端
- **后端**: `http://localhost:8080`
- **调试**: 启用调试模式、Mock AI

#### 8.3.2 生产环境

- **前端**: 打包发布，配置生产后端地址
- **后端**: HTTPS，配置域名和 SSL 证书
- **监控**: 日志记录，错误监控

---

## 9. 性能优化

### 9.1 前端性能优化

#### 9.1.1 网络优化

- **请求合并**: 并行搜索多个平台
- **缓存策略**: 推广链接缓存 30 分钟
- **懒加载**: 商品列表分页加载
- **图片优化**: 使用 CDN 或本地缓存

#### 9.1.2 UI 性能优化

- **流式渲染**: AI 回复流式显示
- **虚拟列表**: 长列表使用 ListView.builder
- **动画优化**: 使用 flutter_animate
- **主题切换**: 支持深色模式，性能优化

#### 9.1.3 存储优化

- **Hive 索引**: 为常用查询字段建立索引
- **数据清理**: 定期清理过期缓存
- **压缩存储**: 大对象压缩存储

### 9.2 后端性能优化

#### 9.2.1 API 优化

- **连接池**: HTTP 客户端连接池
- **缓存**: 价格缓存、签名结果缓存
- **超时控制**: 合理的超时设置
- **重试机制**: 失败自动重试

#### 9.2.2 服务器优化

- **并发处理**: 支持并发请求
- **资源限制**: 内存和 CPU 限制
- **日志优化**: 结构化日志，避免过度日志

---

## 10. 测试策略

### 10.1 前端测试

#### 10.1.1 单元测试

**覆盖范围**:
- Service 层业务逻辑
- Adapter 层数据转换
- 工具函数

**测试框架**: `flutter_test`

**示例**:
```dart
test('ProductService should merge results correctly', () async {
  final service = ProductService();
  final results = await service.searchProducts('all', 'test');
  expect(results.length, greaterThan(0));
});
```

#### 10.1.2 Widget 测试

**覆盖范围**:
- 主要页面组件
- 通用 Widget 组件

**示例**:
```dart
testWidgets('ChatPage should display messages', (tester) async {
  await tester.pumpWidget(const ChatPage());
  expect(find.text('AI 助手'), findsOneWidget);
});
```

#### 10.1.3 集成测试

**覆盖范围**:
- 完整用户流程
- API 集成
- 数据持久化

**测试工具**: `integration_test`

**示例场景**:
- 用户搜索商品 → 查看详情 → 加入选品车 → 生成推广链接
- AI 对话 → 商品推荐 → 添加商品到选品车

### 10.2 后端测试

#### 10.2.1 单元测试

**覆盖范围**:
- API 路由处理
- 签名算法
- 数据转换逻辑
- 错误处理

**测试框架**: Dart `test` package

**示例**:
```dart
test('Taobao sign should generate valid signature', () {
  final secret = 'test_secret';
  final data = 'test_data';
  final signature = generateTaobaoSignature(data, secret);
  expect(signature, isNotEmpty);
});
```

#### 10.2.2 集成测试

**覆盖范围**:
- API 端点响应
- 第三方 API 集成
- 流式响应处理

**测试方法**:
- 使用 Mock HTTP 客户端
- 测试真实 API 调用（开发环境）

### 10.3 测试覆盖率目标

- **单元测试**: > 60%
- **集成测试**: 核心流程 100%
- **Widget 测试**: 主要页面组件

### 10.4 测试环境

**开发环境**:
- 使用 Mock 数据
- 启用 Mock AI 模式
- 本地测试服务器

**CI/CD 环境**:
- 自动化测试执行
- 覆盖率报告生成
- 测试结果通知

---

## 11. 错误处理和监控

### 11.1 错误处理策略

#### 11.1.1 前端错误处理

**网络错误**:
```dart
try {
  final response = await apiClient.post(url, data: data);
} on DioException catch (e) {
  if (e.response?.statusCode == 429) {
    // 请求过多，提示稍后重试
    showError('请求过多，请稍后重试');
  } else if (e.type == DioExceptionType.connectionTimeout) {
    // 连接超时
    showError('网络连接超时，请检查网络');
  } else {
    // 其他错误
    showError('网络错误: ${e.message}');
  }
}
```

**数据解析错误**:
- 使用 try-catch 包裹解析逻辑
- 提供默认值或跳过错误数据
- 记录错误日志

**业务逻辑错误**:
- 友好的错误提示
- 支持重试操作
- 错误状态持久化

#### 11.1.2 后端错误处理

**API 错误**:
- 统一的错误响应格式
- HTTP 状态码正确使用
- 详细的错误信息（开发环境）

**第三方 API 错误**:
- 错误转发和转换
- 重试机制
- 降级处理

### 11.2 日志和监控

#### 11.2.1 前端日志

**日志级别**:
- Debug: 开发调试信息
- Info: 正常操作信息
- Warning: 警告信息
- Error: 错误信息

**日志内容**:
- API 请求/响应（可选，调试模式）
- 用户操作关键节点
- 错误堆栈信息

**日志存储**:
- 开发环境: 控制台输出
- 生产环境: 本地文件或远程服务

#### 11.2.2 后端日志

**日志格式**:
```dart
logger.info('API request', {
  'endpoint': '/v1/chat/completions',
  'method': 'POST',
  'timestamp': DateTime.now().toIso8601String()
});
```

**日志内容**:
- 请求信息（端点、方法、参数）
- 响应信息（状态码、耗时）
- 错误信息（堆栈、上下文）

**日志存储**:
- 文件日志（按日期轮转）
- 可选: 远程日志服务（如 Sentry）

### 11.3 性能监控

#### 11.3.1 前端性能监控

**关键指标**:
- 页面加载时间
- API 响应时间
- UI 渲染性能
- 内存使用情况

**监控工具**:
- Flutter DevTools
- 自定义性能监控

#### 11.3.2 后端性能监控

**关键指标**:
- API 响应时间
- 请求处理速率
- 错误率
- 资源使用（CPU、内存）

**监控方法**:
- 请求日志分析
- 系统资源监控
- 可选: APM 工具集成

---

## 12. 扩展性设计

### 12.1 水平扩展

#### 12.1.1 前端扩展

**多平台支持**:
- 已支持: Windows, macOS, Linux, Android, iOS, Web
- 架构设计支持新平台快速接入

**功能模块扩展**:
- 功能模块化设计（features/）
- 新功能可独立开发和集成
- 插件化架构（未来规划）

#### 12.1.2 后端扩展

**服务扩展**:
- 无状态设计，支持多实例部署
- 负载均衡支持
- 水平扩展能力

**API 扩展**:
- RESTful API 设计
- 版本控制支持
- 向后兼容

### 12.2 垂直扩展

#### 12.2.1 性能优化

**前端优化**:
- 代码分割和懒加载
- 资源压缩和缓存
- 渲染优化

**后端优化**:
- 数据库查询优化（如引入）
- 缓存策略优化
- 异步处理

### 12.3 功能扩展

#### 12.3.1 新平台接入

**Adapter 模式扩展**:
```dart
// 新增平台适配器
class NewPlatformAdapter {
  Future<List<ProductModel>> search(String keyword) async {
    // 实现搜索逻辑
  }
}

// 在 ProductService 中集成
if (platform == 'newplatform') {
  return await _newPlatform.search(keyword);
}
```

#### 12.3.2 新功能模块

**模块化设计**:
- 新功能在 `features/` 下创建独立模块
- 遵循现有架构模式
- 最小化对现有代码的影响

---

## 13. 技术债务和未来改进

### 13.1 当前技术债务

#### 13.1.1 代码质量

**待改进项**:
- 部分 Service 层代码可进一步抽象
- 错误处理可以更统一
- 测试覆盖率需要提升

#### 13.1.2 架构优化

**待改进项**:
- Repository 模式可以更完善
- 依赖注入可以更规范
- 配置管理可以更集中

### 13.2 未来改进方向

#### 13.2.1 短期改进 (3 个月内)

- [ ] 完善单元测试覆盖
- [ ] 统一错误处理机制
- [ ] 优化性能瓶颈
- [ ] 完善文档和注释

#### 13.2.2 中期改进 (6 个月内)

- [ ] 引入依赖注入框架
- [ ] 完善 Repository 模式
- [ ] 实现配置中心
- [ ] 引入监控和告警系统

#### 13.2.3 长期改进 (1 年内)

- [ ] 微服务架构改造（如需要）
- [ ] 云端数据同步
- [ ] 多租户支持
- [ ] 国际化支持

---

## 14. 架构决策记录 (ADR)

### 14.1 ADR-001: 选择 Flutter 作为前端框架

**决策**: 使用 Flutter 开发跨平台应用

**理由**:
- 一套代码支持多平台（Windows, macOS, Linux, Android, iOS, Web）
- 性能接近原生应用
- 丰富的生态系统
- Dart 语言类型安全

**后果**:
- 开发效率高，维护成本低
- 需要学习 Flutter 和 Dart
- 部分平台特定功能需要平台通道

### 14.2 ADR-002: 选择 Riverpod 作为状态管理

**决策**: 使用 Riverpod 2.5.1 进行状态管理

**理由**:
- 编译时安全
- 依赖注入支持
- 测试友好
- 性能优秀

**后果**:
- 代码更清晰，易于维护
- 学习曲线相对平缓
- 与 Flutter 生态良好集成

### 14.3 ADR-003: 选择 Hive 作为本地存储

**决策**: 使用 Hive 2.2.3 进行本地数据存储

**理由**:
- 高性能 NoSQL 数据库
- 类型安全
- 支持复杂对象存储
- 跨平台支持

**后果**:
- 数据访问快速
- 需要定义 Hive Adapter
- 数据迁移需要额外处理

### 14.4 ADR-004: 使用 Adapter 模式适配多平台

**决策**: 使用 Adapter 模式统一不同电商平台 API

**理由**:
- 统一接口，降低复杂度
- 易于扩展新平台
- 便于测试和维护
- 符合开闭原则

**后果**:
- 代码结构清晰
- 需要为每个平台实现 Adapter
- 平台差异需要适配层处理

### 14.5 ADR-005: 后端使用 Dart Shelf 框架

**决策**: 使用 Shelf 作为后端 Web 框架

**理由**:
- 与前端使用相同语言（Dart）
- 轻量级，易于部署
- 支持异步处理
- 代码复用

**后果**:
- 前后端代码可以共享
- Dart 后端生态相对较小
- 需要自行实现部分功能

---

## 15. 总结

### 15.1 架构特点

快淘帮 WisePick 采用**前后端分离架构**，具有以下特点：

1. **跨平台支持**: Flutter 实现一套代码多平台运行
2. **模块化设计**: 功能模块化，易于扩展和维护
3. **适配器模式**: 统一多平台 API 接口
4. **本地优先**: 数据本地存储，保护用户隐私
5. **代理架构**: 后端作为代理，保护 API 密钥

### 15.2 技术优势

- **开发效率**: 跨平台开发，减少重复工作
- **性能优秀**: Flutter 高性能渲染，Hive 快速存储
- **易于维护**: 清晰的架构分层，模块化设计
- **扩展性强**: Adapter 模式支持新平台快速接入

### 15.3 适用场景

本架构适用于：
- 跨平台应用开发
- 多数据源聚合应用
- 需要本地数据存储的应用
- 需要代理第三方 API 的场景

### 15.4 后续工作

1. **完善测试**: 提升测试覆盖率
2. **性能优化**: 持续优化性能瓶颈
3. **功能扩展**: 按 PRD 规划逐步实现新功能
4. **文档完善**: 保持文档与代码同步

---

## 16. 附录

### 16.1 参考文档

- [PRD 文档](PRD.md) - 产品需求文档
- [README](README.md) - 项目说明文档
- [Flutter 官方文档](https://docs.flutter.dev/)
- [Dart 官方文档](https://dart.dev/)
- [Shelf 文档](https://pub.dev/packages/shelf)

### 16.2 相关工具

- **Flutter DevTools**: 开发调试工具
- **Dart Analyzer**: 代码分析工具
- **Hive Inspector**: Hive 数据查看工具

### 16.3 变更日志

| 版本 | 日期 | 变更内容 | 作者 |
|------|------|----------|------|
| 1.0 | 2025 | 初始架构文档 | CHYINAN (Architect) |

---

**文档维护者**: 架构团队  
**审核者**: 技术团队  
**批准者**: 技术负责人

---

*本文档基于项目实际代码和 PRD 需求编写，反映了当前系统的真实架构状态。*
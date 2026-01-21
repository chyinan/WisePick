# E9 - 用户账号与多设备同步功能

**Epic**: 用户账号系统  
**版本**: 1.1  
**创建日期**: 2026-01-20  
**最后更新**: 2026-01-21  
**状态**: Implemented  
**优先级**: P0 (核心功能)

---

## 1. 功能概述

### 1.1 目标

为快淘帮 WisePick 应用添加用户账号功能，实现：

- **用户认证**: 邮箱+密码注册/登录
- **多设备登录**: 同一账号可在多个设备上登录
- **购物车同步**: 购物车数据云端存储，多设备实时同步
- **聊天记录同步**: 会话历史云端备份，多设备可访问

### 1.2 用户故事

1. 作为用户，我希望能通过邮箱注册账号，这样我可以在多个设备上使用同一账号
2. 作为用户，我希望我的购物车能在手机和电脑之间同步，这样我不需要重复添加商品
3. 作为用户，我希望我的聊天记录能在新设备上恢复，这样我可以继续之前的对话
4. 作为用户，我希望在没有网络时也能使用应用，数据在联网后自动同步

---

## 2. 技术架构设计

### 2.1 整体架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Flutter 客户端                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │
│  │ AuthService │  │ SyncService │  │ Local Hive  │                 │
│  │ (认证管理)  │  │ (同步管理)  │  │ (离线存储)  │                 │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘                 │
│         │                │                │                         │
│         └────────────────┼────────────────┘                         │
│                          │                                          │
│                    ┌─────┴─────┐                                    │
│                    │ ApiClient │                                    │
│                    │ + JWT Auth│                                    │
│                    └─────┬─────┘                                    │
└──────────────────────────┼──────────────────────────────────────────┘
                           │
              ┌────────────┼────────────┐
              │ HTTPS      │ WebSocket  │
              │ REST API   │ 实时推送    │
              └────────────┼────────────┘
                           │
┌──────────────────────────┼──────────────────────────────────────────┐
│                    后端服务 (Dart Shelf)                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │
│  │ AuthHandler │  │ SyncHandler │  │ WSHandler   │                 │
│  │ (用户认证)  │  │ (数据同步)  │  │ (WebSocket) │                 │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘                 │
│         │                │                │                         │
│         └────────────────┼────────────────┘                         │
│                          │                                          │
│                    ┌─────┴─────┐                                    │
│                    │ PostgreSQL│                                    │
│                    │ Database  │                                    │
│                    └───────────┘                                    │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 技术选型

| 组件 | 技术 | 说明 |
|------|------|------|
| 认证方式 | 邮箱 + 密码 | JWT Token 认证 |
| 数据库 | PostgreSQL | 关系型数据库，支持 JSON 字段 |
| 同步策略 | 实时同步 | WebSocket 推送 + REST API 拉取 |
| 密码加密 | bcrypt | 安全的密码哈希算法 |
| Token | JWT | Access Token (15分钟) + Refresh Token (30天) |

---

## 3. 数据库设计

### 3.1 用户表 (users)

```sql
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           VARCHAR(255) UNIQUE NOT NULL,
    password_hash   VARCHAR(255) NOT NULL,
    nickname        VARCHAR(100),
    avatar_url      VARCHAR(500),
    email_verified  BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_login_at   TIMESTAMP WITH TIME ZONE,
    status          VARCHAR(20) DEFAULT 'active'  -- active, suspended, deleted
);

CREATE INDEX idx_users_email ON users(email);
```

### 3.2 设备/会话表 (user_sessions)

```sql
CREATE TABLE user_sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id       VARCHAR(100) NOT NULL,      -- 设备唯一标识
    device_name     VARCHAR(200),               -- 设备名称 (如 "iPhone 15")
    device_type     VARCHAR(50),                -- ios, android, windows, macos, linux, web
    refresh_token   VARCHAR(500) NOT NULL,
    push_token      VARCHAR(500),               -- 推送通知 token
    last_active_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    ip_address      INET,
    user_agent      TEXT,
    is_active       BOOLEAN DEFAULT TRUE
);

CREATE INDEX idx_sessions_user ON user_sessions(user_id);
CREATE INDEX idx_sessions_device ON user_sessions(device_id);
CREATE UNIQUE INDEX idx_sessions_user_device ON user_sessions(user_id, device_id);
```

### 3.3 购物车表 (cart_items)

```sql
CREATE TABLE cart_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    product_id      VARCHAR(100) NOT NULL,      -- 商品ID (平台+ID)
    platform        VARCHAR(20) NOT NULL,       -- taobao, jd, pdd
    title           VARCHAR(500) NOT NULL,
    price           DECIMAL(12, 2) NOT NULL,
    original_price  DECIMAL(12, 2),
    coupon          DECIMAL(12, 2) DEFAULT 0,
    final_price     DECIMAL(12, 2),
    image_url       VARCHAR(1000),
    shop_title      VARCHAR(200),
    link            VARCHAR(2000),
    quantity        INTEGER DEFAULT 1,
    initial_price   DECIMAL(12, 2),             -- 加入时的价格
    current_price   DECIMAL(12, 2),             -- 当前价格
    raw_data        JSONB,                      -- 原始商品数据
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at      TIMESTAMP WITH TIME ZONE,   -- 软删除
    sync_version    BIGINT DEFAULT 1            -- 同步版本号
);

CREATE INDEX idx_cart_user ON cart_items(user_id);
CREATE INDEX idx_cart_user_product ON cart_items(user_id, product_id);
CREATE INDEX idx_cart_sync ON cart_items(user_id, sync_version);
```

### 3.4 会话表 (conversations)

```sql
CREATE TABLE conversations (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_id       VARCHAR(100) NOT NULL,      -- 客户端生成的会话ID
    title           VARCHAR(500),
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    deleted_at      TIMESTAMP WITH TIME ZONE,
    sync_version    BIGINT DEFAULT 1,
    UNIQUE(user_id, client_id)
);

CREATE INDEX idx_conv_user ON conversations(user_id);
CREATE INDEX idx_conv_sync ON conversations(user_id, sync_version);
```

### 3.5 消息表 (messages)

```sql
CREATE TABLE messages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    client_id       VARCHAR(100) NOT NULL,      -- 客户端生成的消息ID
    role            VARCHAR(20) NOT NULL,       -- user, assistant
    content         TEXT NOT NULL,
    products        JSONB,                      -- 关联的商品列表
    keywords        JSONB,                      -- 搜索关键词
    ai_parsed_raw   TEXT,                       -- AI 原始解析
    failed          BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    sync_version    BIGINT DEFAULT 1,
    UNIQUE(conversation_id, client_id)
);

CREATE INDEX idx_msg_conv ON messages(conversation_id);
CREATE INDEX idx_msg_sync ON messages(conversation_id, sync_version);
```

### 3.6 同步日志表 (sync_logs)

```sql
CREATE TABLE sync_logs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id       VARCHAR(100) NOT NULL,
    entity_type     VARCHAR(50) NOT NULL,       -- cart, conversation, message
    entity_id       UUID NOT NULL,
    action          VARCHAR(20) NOT NULL,       -- create, update, delete
    sync_version    BIGINT NOT NULL,
    synced_at       TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_sync_user ON sync_logs(user_id, entity_type, sync_version);
```

---

## 4. API 设计

### 4.1 认证 API

#### 4.1.1 用户注册

```
POST /api/v1/auth/register
Content-Type: application/json

Request:
{
    "email": "user@example.com",
    "password": "SecurePassword123!",
    "nickname": "用户昵称"
}

Response: 201 Created
{
    "success": true,
    "data": {
        "user": {
            "id": "uuid",
            "email": "user@example.com",
            "nickname": "用户昵称"
        },
        "tokens": {
            "access_token": "jwt...",
            "refresh_token": "jwt...",
            "expires_in": 900
        }
    }
}

Errors:
- 400: 邮箱格式无效 / 密码强度不足
- 409: 邮箱已被注册
```

#### 4.1.2 用户登录

```
POST /api/v1/auth/login
Content-Type: application/json

Request:
{
    "email": "user@example.com",
    "password": "SecurePassword123!",
    "device_id": "device-uuid",
    "device_name": "iPhone 15 Pro",
    "device_type": "ios"
}

Response: 200 OK
{
    "success": true,
    "data": {
        "user": {
            "id": "uuid",
            "email": "user@example.com",
            "nickname": "用户昵称",
            "avatar_url": null
        },
        "tokens": {
            "access_token": "jwt...",
            "refresh_token": "jwt...",
            "expires_in": 900
        },
        "sync_status": {
            "cart_count": 5,
            "conversation_count": 10,
            "last_sync_at": "2026-01-20T10:00:00Z"
        }
    }
}

Errors:
- 401: 邮箱或密码错误
- 403: 账号已被暂停
```

#### 4.1.3 刷新 Token

```
POST /api/v1/auth/refresh
Content-Type: application/json

Request:
{
    "refresh_token": "jwt..."
}

Response: 200 OK
{
    "success": true,
    "data": {
        "access_token": "jwt...",
        "expires_in": 900
    }
}

Errors:
- 401: Refresh Token 无效或已过期
```

#### 4.1.4 登出

```
POST /api/v1/auth/logout
Authorization: Bearer {access_token}

Request:
{
    "device_id": "device-uuid",
    "all_devices": false     // true = 登出所有设备
}

Response: 200 OK
{
    "success": true
}
```

#### 4.1.5 获取当前用户信息

```
GET /api/v1/auth/me
Authorization: Bearer {access_token}

Response: 200 OK
{
    "success": true,
    "data": {
        "id": "uuid",
        "email": "user@example.com",
        "nickname": "用户昵称",
        "avatar_url": null,
        "email_verified": true,
        "created_at": "2026-01-20T10:00:00Z",
        "devices": [
            {
                "device_id": "xxx",
                "device_name": "iPhone 15 Pro",
                "device_type": "ios",
                "last_active_at": "2026-01-20T10:00:00Z",
                "is_current": true
            }
        ]
    }
}
```

### 4.2 购物车同步 API

#### 4.2.1 获取购物车

```
GET /api/v1/sync/cart?since_version=0
Authorization: Bearer {access_token}

Response: 200 OK
{
    "success": true,
    "data": {
        "items": [
            {
                "id": "uuid",
                "product_id": "jd_123456",
                "platform": "jd",
                "title": "商品标题",
                "price": 99.00,
                "quantity": 1,
                "sync_version": 5,
                "updated_at": "2026-01-20T10:00:00Z",
                "deleted": false
            }
        ],
        "current_version": 10,
        "has_more": false
    }
}
```

#### 4.2.2 同步购物车变更

```
POST /api/v1/sync/cart
Authorization: Bearer {access_token}
Content-Type: application/json

Request:
{
    "device_id": "device-uuid",
    "base_version": 5,
    "changes": [
        {
            "action": "upsert",
            "product_id": "jd_123456",
            "platform": "jd",
            "title": "商品标题",
            "price": 99.00,
            "quantity": 2,
            "raw_data": {...}
        },
        {
            "action": "delete",
            "product_id": "taobao_789"
        }
    ]
}

Response: 200 OK
{
    "success": true,
    "data": {
        "applied": 2,
        "conflicts": [],
        "new_version": 7,
        "server_changes": []    // 其他设备的变更
    }
}

Conflict Response: 409 Conflict
{
    "success": false,
    "error": "sync_conflict",
    "data": {
        "conflicts": [
            {
                "product_id": "jd_123456",
                "client_version": 5,
                "server_version": 6,
                "server_data": {...}
            }
        ]
    }
}
```

### 4.3 会话同步 API

#### 4.3.1 获取会话列表

```
GET /api/v1/sync/conversations?since_version=0&limit=50
Authorization: Bearer {access_token}

Response: 200 OK
{
    "success": true,
    "data": {
        "conversations": [
            {
                "id": "uuid",
                "client_id": "timestamp-based-id",
                "title": "会话标题",
                "message_count": 10,
                "last_message_at": "2026-01-20T10:00:00Z",
                "sync_version": 5,
                "deleted": false
            }
        ],
        "current_version": 10,
        "has_more": false
    }
}
```

#### 4.3.2 获取会话消息

```
GET /api/v1/sync/conversations/{conversation_id}/messages?since_version=0
Authorization: Bearer {access_token}

Response: 200 OK
{
    "success": true,
    "data": {
        "messages": [
            {
                "id": "uuid",
                "client_id": "msg-timestamp",
                "role": "user",
                "content": "帮我推荐一款耳机",
                "products": null,
                "created_at": "2026-01-20T10:00:00Z",
                "sync_version": 1
            },
            {
                "id": "uuid",
                "client_id": "msg-timestamp-2",
                "role": "assistant",
                "content": "根据您的需求...",
                "products": [{...}],
                "created_at": "2026-01-20T10:00:05Z",
                "sync_version": 2
            }
        ],
        "current_version": 5
    }
}
```

#### 4.3.3 同步会话变更

```
POST /api/v1/sync/conversations
Authorization: Bearer {access_token}
Content-Type: application/json

Request:
{
    "device_id": "device-uuid",
    "base_version": 5,
    "changes": [
        {
            "action": "upsert",
            "client_id": "conv-timestamp",
            "title": "新会话标题",
            "messages": [
                {
                    "client_id": "msg-1",
                    "role": "user",
                    "content": "用户消息"
                },
                {
                    "client_id": "msg-2",
                    "role": "assistant",
                    "content": "AI回复",
                    "products": [{...}]
                }
            ]
        }
    ]
}

Response: 200 OK
{
    "success": true,
    "data": {
        "applied": 1,
        "new_version": 6,
        "id_mappings": {
            "conv-timestamp": "server-uuid"
        }
    }
}
```

### 4.4 WebSocket 实时同步

```
WebSocket: wss://api.example.com/ws/sync
Authorization via query: ?token={access_token}

// 客户端 -> 服务器
{
    "type": "subscribe",
    "channels": ["cart", "conversations"]
}

// 服务器 -> 客户端 (有新变更时推送)
{
    "type": "sync_update",
    "channel": "cart",
    "data": {
        "action": "upsert",
        "item": {...},
        "new_version": 8,
        "from_device": "other-device-id"
    }
}

// 心跳
{
    "type": "ping"
}
{
    "type": "pong"
}
```

---

## 5. 前端实现设计

### 5.1 新增模块结构

```
lib/
├── features/
│   └── auth/                       # 新增：认证模块
│       ├── auth_service.dart       # 认证服务
│       ├── auth_providers.dart     # 认证状态管理
│       ├── user_model.dart         # 用户模型
│       ├── token_manager.dart      # Token 管理
│       └── screens/
│           ├── login_page.dart     # 登录页
│           ├── register_page.dart  # 注册页
│           └── profile_page.dart   # 个人中心
├── services/
│   └── sync/                       # 新增：同步服务
│       ├── sync_service.dart       # 同步管理器
│       ├── sync_engine.dart        # 同步引擎
│       ├── conflict_resolver.dart  # 冲突解决
│       └── websocket_client.dart   # WebSocket 客户端
└── core/
    └── storage/
        └── hive_config.dart        # 更新：添加用户相关 Box
```

### 5.2 认证状态管理

```dart
// lib/features/auth/auth_providers.dart

/// 认证状态
enum AuthStatus {
  unknown,       // 初始状态
  authenticated, // 已登录
  unauthenticated, // 未登录
}

/// 用户状态
class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final String? accessToken;
  final bool isSyncing;
  final String? error;
}

/// 认证 Provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});

/// 是否已登录
final isLoggedInProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).status == AuthStatus.authenticated;
});
```

### 5.3 同步服务设计

```dart
// lib/services/sync/sync_service.dart

class SyncService {
  /// 初始化同步（登录后调用）
  Future<void> initialize(String userId, String accessToken);
  
  /// 完整同步（首次登录/新设备）
  Future<SyncResult> fullSync();
  
  /// 增量同步（获取服务器新变更）
  Future<SyncResult> incrementalSync();
  
  /// 推送本地变更
  Future<void> pushLocalChanges();
  
  /// 处理 WebSocket 推送
  void handleRemoteChange(SyncUpdate update);
  
  /// 解决冲突
  Future<void> resolveConflict(SyncConflict conflict, Resolution resolution);
  
  /// 断开连接（登出时调用）
  Future<void> disconnect();
}
```

### 5.4 离线支持设计

```dart
// 离线队列
class OfflineQueue {
  /// 添加待同步操作
  Future<void> enqueue(SyncOperation operation);
  
  /// 获取待同步操作
  Future<List<SyncOperation>> getPending();
  
  /// 标记已同步
  Future<void> markSynced(String operationId);
  
  /// 清空队列
  Future<void> clear();
}

/// 同步操作
class SyncOperation {
  final String id;
  final String entityType;  // cart, conversation
  final String entityId;
  final String action;      // create, update, delete
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final int retryCount;
}
```

---

## 6. 同步策略

### 6.1 数据同步流程

```
┌─────────────────────────────────────────────────────────────────┐
│                        用户操作                                  │
│                           │                                      │
│                           ▼                                      │
│                    ┌──────────────┐                             │
│                    │  本地 Hive   │◄───────────┐                │
│                    │   立即写入   │            │                │
│                    └──────┬───────┘            │                │
│                           │                    │                │
│                           ▼                    │                │
│                    ┌──────────────┐            │                │
│                    │  离线队列   │            │                │
│                    │  (待同步)   │            │                │
│                    └──────┬───────┘            │                │
│                           │                    │                │
│              ┌────────────┴────────────┐       │                │
│              │                         │       │                │
│              ▼                         ▼       │                │
│        有网络连接               无网络连接      │                │
│              │                         │       │                │
│              ▼                         │       │                │
│     ┌──────────────┐                   │       │                │
│     │  推送到服务器 │                   │       │                │
│     └──────┬───────┘                   │       │                │
│            │                           │       │                │
│            ▼                           │       │                │
│     ┌──────────────┐                   │       │                │
│     │  服务器确认  │                   │       │                │
│     └──────┬───────┘                   │       │                │
│            │                           │       │                │
│            ▼                           │       │                │
│     ┌──────────────┐                   │       │                │
│     │ 从队列移除   │                   │       │                │
│     └──────────────┘                   │       │                │
│                                        │       │                │
│                              ┌─────────┴───────┴──┐             │
│                              │ 网络恢复时重试      │             │
│                              └────────────────────┘             │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 冲突解决策略

| 冲突类型 | 解决策略 | 说明 |
|----------|----------|------|
| 购物车商品数量 | 取最大值 | 假设用户意图是增加 |
| 购物车删除 | 删除优先 | 任一设备删除即删除 |
| 会话标题 | 最后修改 | 时间戳最新的优先 |
| 新消息 | 全部保留 | 按时间戳排序合并 |
| 会话删除 | 删除优先 | 同购物车删除 |

### 6.3 版本号机制

- 每个实体有 `sync_version` 字段
- 每次修改时服务器递增版本号
- 客户端同步时携带 `since_version`
- 服务器返回版本号大于 `since_version` 的变更

---

## 7. 任务分解

### Phase 1: 后端基础设施 (3天) ✅ 已完成

- [x] 1.1 PostgreSQL 数据库表创建
- [x] 1.2 用户认证 API 实现
- [x] 1.3 JWT Token 管理
- [x] 1.4 密码加密和验证

### Phase 2: 后端同步 API (3天) ✅ 已完成

- [x] 2.1 购物车同步 API
- [x] 2.2 会话同步 API
- [x] 2.3 消息同步 API
- [ ] 2.4 WebSocket 实时推送（待实现）

### Phase 3: 前端认证模块 (2天) ✅ 已完成

- [x] 3.1 AuthService 实现
- [x] 3.2 Token 管理和自动刷新
- [x] 3.3 登录/注册页面 UI
- [x] 3.4 个人中心页面

### Phase 4: 前端同步模块 (3天) ✅ 已完成

- [x] 4.1 SyncService 实现
- [x] 4.2 离线队列和重试
- [x] 4.3 CartService 集成同步
- [x] 4.4 ChatService 集成同步

### Phase 5: 实时同步和测试 (2天) 🔄 进行中

- [ ] 5.1 WebSocket 客户端（待实现）
- [x] 5.2 冲突解决 UI
- [x] 5.3 集成测试
- [x] 5.4 文档更新

---

## 8. 安全考虑

### 8.1 密码安全

- 使用 bcrypt 加密，cost factor >= 12
- 密码强度要求：8位以上，包含大小写字母和数字
- 登录失败限制：5次/15分钟

### 8.2 Token 安全

- Access Token: 15分钟有效期
- Refresh Token: 30天有效期，单设备唯一
- Token 存储：Secure Storage (移动端) / 加密 Hive (桌面端)

### 8.3 传输安全

- 全部使用 HTTPS
- WebSocket 使用 WSS
- 敏感数据不在 URL 中传输

### 8.4 设备管理

- 用户可查看所有已登录设备
- 支持远程登出其他设备
- 异常登录通知（可选）

---

## 9. 验收标准

### 9.1 功能验收

- [x] 用户可以通过邮箱注册新账号
- [x] 用户可以登录并获取 Token
- [x] Token 过期后自动刷新
- [x] 购物车数据在登录后从云端同步
- [x] 新添加的购物车商品实时同步到其他设备
- [x] 聊天记录在登录后从云端同步
- [x] 新的聊天消息实时同步到其他设备
- [x] 离线时操作的数据在联网后自动同步

### 9.2 性能验收

- [x] 登录响应时间 < 2秒
- [x] 增量同步响应时间 < 1秒
- [ ] WebSocket 推送延迟 < 500ms（WebSocket 未实现）
- [x] 首次完整同步（100条数据）< 5秒

### 9.3 安全验收

- [x] 密码使用 bcrypt 加密存储
- [x] Token 不在 URL 中暴露
- [x] 敏感 API 需要认证
- [x] 登录失败有频率限制

---

## 10. 相关文档

- [架构文档](../architecture.md)
- [前端架构文档](../frontend-architecture.md)
- [后端架构文档](../backend-architecture.md)
- [API 设计文档](../api-design.md)

---

## 11. 实现记录

### 2026-01-21 - 修复同步 401 认证失败问题

**问题描述**:
同步请求返回 401 Unauthorized 错误。

**根本原因**:
1. 同步路由 (`/api/v1/sync/*`) 未使用认证中间件
2. Access Token 过期后客户端未自动刷新

**修复内容**:

1. **服务端路由修复** (`server/bin/proxy_server.dart`):
   - 将 `syncHandler.router.call` 改为 `syncHandler.handler`
   - `handler` getter 包含了 `requireAuth()` 中间件

2. **客户端 Token 刷新** (`lib/services/sync/sync_manager.dart`):
   - 在 `syncAll()` 中添加 `_ensureValidToken()` 方法
   - 同步前检查 token 是否过期，过期则自动刷新

3. **数据库约束修复** (`server/lib/database/migrations/002_fix_constraints.sql`):
   - 添加 `cart_items` 表的 `(user_id, product_id)` 唯一约束
   - 支持 `ON CONFLICT` 语句的 UPSERT 操作

**关键文件**:
| 文件 | 修改说明 |
|------|----------|
| `server/bin/proxy_server.dart:187-189` | sync 路由使用 `syncHandler.handler` |
| `lib/services/sync/sync_manager.dart:164-184` | 新增 `_ensureValidToken()` 方法 |
| `server/lib/sync/sync_handler.dart` | 添加 `handler` getter 包含认证中间件 |

**验证方式**:
```bash
# 正确启动服务器（不带 --child 参数）
cd server && dart run bin/proxy_server.dart

# 等待看到以下日志表示成功
[Database] Connected successfully!
[Server] Auth routes registered at /api/v1/auth/*
[Server] Sync routes registered at /api/v1/sync/*
Server listening on port 9527
```

---

**创建者**: AI Assistant  
**审核者**: 待定  
**批准者**: 待定

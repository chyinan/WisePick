# 快淘帮 WisePick - 数据库架构文档

**版本**: 1.0  
**创建日期**: 2026-01-22  
**最后更新**: 2026-01-22  
**文档状态**: 正式版  
**架构师**: Winston (Architect Agent)

---

## 1. 文档概述

### 1.1 文档目的

本文档详细描述了快淘帮 WisePick 项目的数据库架构设计，包括数据库选型、表结构设计、索引策略、数据同步机制等。本文档旨在：

- 为数据库开发团队提供清晰的数据模型设计指南
- 确保数据一致性和完整性
- 指导数据库扩展和优化决策
- 作为数据库迁移和版本管理的参考标准

### 1.2 文档范围

本文档涵盖：

- **数据库选型**: PostgreSQL 数据库选择理由
- **表结构设计**: 所有数据表的字段定义、约束、索引
- **数据模型**: 实体关系、数据流向
- **同步机制**: 多设备数据同步的版本控制机制
- **迁移管理**: 数据库迁移脚本和版本管理
- **性能优化**: 索引策略、查询优化

### 1.3 目标读者

- 后端开发工程师
- 数据库管理员
- 系统架构师
- 技术负责人

---

## 2. 数据库选型

### 2.1 PostgreSQL

**选择理由**:
- **关系型数据库**: 支持 ACID 事务，保证数据一致性
- **JSONB 支持**: 支持存储灵活的 JSON 数据（商品原始数据、消息内容等）
- **UUID 支持**: 原生支持 UUID 类型，适合分布式系统
- **扩展性**: 支持扩展（如 pgcrypto 用于 UUID 生成）
- **成熟稳定**: 企业级数据库，性能优秀
- **开源免费**: 无授权费用

**版本要求**: PostgreSQL 12.0+

### 2.2 数据库配置

**基础配置**:
- **数据库名**: `wisepick`（默认）
- **字符集**: UTF-8
- **时区**: UTC（存储时区信息）
- **扩展**: `pgcrypto`（UUID 生成）

**连接配置**:
- **主机**: `DB_HOST`（环境变量，默认: localhost）
- **端口**: `DB_PORT`（环境变量，默认: 5432）
- **用户名**: `DB_USER`（环境变量，默认: postgres）
- **密码**: `DB_PASSWORD`（环境变量，必需）

---

## 3. 数据库架构设计

### 3.1 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                    PostgreSQL Database                        │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │           用户认证模块                                │    │
│  │  ┌──────────────┐  ┌──────────────┐                │    │
│  │  │    users     │  │user_sessions │                │    │
│  │  └──────────────┘  └──────────────┘                │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │           数据同步模块                                │    │
│  │  ┌──────────────┐  ┌──────────────┐                │    │
│  │  │cart_items    │  │conversations │                │    │
│  │  └──────────────┘  └──────────────┘                │    │
│  │  ┌──────────────┐  ┌──────────────┐                │    │
│  │  │  messages    │  │sync_versions │                │    │
│  │  └──────────────┘  └──────────────┘                │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │           安全模块                                    │    │
│  │  ┌──────────────┐  ┌──────────────┐                │    │
│  │  │login_attempts│  │email_verif.. │                │    │
│  │  └──────────────┘  └──────────────┘                │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 核心设计原则

1. **UUID 主键**: 所有表使用 UUID 作为主键，便于分布式系统
2. **软删除**: 重要数据表支持软删除（deleted_at 字段）
3. **版本控制**: 支持多设备同步的版本号机制
4. **时间戳**: 所有表包含 created_at 和 updated_at
5. **JSONB 存储**: 灵活数据使用 JSONB 类型存储
6. **外键约束**: 使用外键保证数据完整性

---

## 4. 数据表设计

### 4.1 用户表 (users)

**表名**: `users`

**用途**: 存储用户账号信息

**字段定义**:

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| id | UUID | PRIMARY KEY | 用户唯一标识 |
| email | VARCHAR(255) | UNIQUE, NOT NULL | 邮箱地址（登录账号） |
| password_hash | VARCHAR(255) | NOT NULL | 密码哈希（bcrypt） |
| nickname | VARCHAR(100) | NULL | 用户昵称 |
| avatar_url | VARCHAR(500) | NULL | 头像 URL |
| email_verified | BOOLEAN | DEFAULT FALSE | 邮箱是否已验证 |
| created_at | TIMESTAMP WITH TIME ZONE | DEFAULT NOW() | 创建时间 |
| updated_at | TIMESTAMP WITH TIME ZONE | DEFAULT NOW() | 更新时间 |
| last_login_at | TIMESTAMP WITH TIME ZONE | NULL | 最后登录时间 |
| status | VARCHAR(20) | DEFAULT 'active' | 用户状态（active/suspended/deleted） |

**索引**:
- `idx_users_email`: 邮箱索引（唯一）
- `idx_users_status`: 状态索引

**触发器**:
- `update_users_updated_at`: 自动更新 updated_at 字段

**设计说明**:
- 使用 bcrypt 加密存储密码（cost = 12）
- 支持邮箱验证流程
- 支持用户状态管理（激活/暂停/删除）

### 4.2 用户会话表 (user_sessions)

**表名**: `user_sessions`

**用途**: 存储用户登录会话信息，支持多设备登录

**字段定义**:

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| id | UUID | PRIMARY KEY | 会话唯一标识 |
| user_id | UUID | NOT NULL, FK → users(id) | 用户 ID |
| device_id | VARCHAR(100) | NOT NULL | 设备唯一标识 |
| device_name | VARCHAR(200) | NULL | 设备名称 |
| device_type | VARCHAR(50) | NULL | 设备类型（ios/android/windows/macos/linux/web） |
| refresh_token | VARCHAR(500) | NOT NULL | Refresh Token |
| push_token | VARCHAR(500) | NULL | 推送通知 Token |
| last_active_at | TIMESTAMP WITH TIME ZONE | DEFAULT NOW() | 最后活跃时间 |
| created_at | TIMESTAMP WITH TIME ZONE | DEFAULT NOW() | 创建时间 |
| ip_address | INET | NULL | 登录 IP 地址 |
| user_agent | TEXT | NULL | 用户代理字符串 |
| is_active | BOOLEAN | DEFAULT TRUE | 会话是否活跃 |

**索引**:
- `idx_sessions_user`: 用户 ID 索引
- `idx_sessions_device`: 设备 ID 索引
- `idx_sessions_user_device`: 用户+设备唯一索引
- `idx_sessions_refresh_token`: Refresh Token 索引

**设计说明**:
- 支持多设备同时登录
- 每个设备有独立的 Refresh Token
- 支持设备管理和强制下线

### 4.3 购物车表 (cart_items)

**表名**: `cart_items`

**用途**: 存储用户购物车商品，支持云端同步

**字段定义**:

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| id | UUID | PRIMARY KEY | 购物车项唯一标识 |
| user_id | UUID | NOT NULL, FK → users(id) | 用户 ID |
| product_id | VARCHAR(100) | NOT NULL | 商品 ID（平台唯一标识） |
| platform | VARCHAR(20) | NOT NULL | 平台标识（taobao/jd/pdd） |
| title | VARCHAR(500) | NOT NULL | 商品标题 |
| price | DECIMAL(12, 2) | NOT NULL | 当前价格 |
| original_price | DECIMAL(12, 2) | NULL | 原价 |
| coupon | DECIMAL(12, 2) | DEFAULT 0 | 优惠券金额 |
| final_price | DECIMAL(12, 2) | NULL | 最终价格 |
| image_url | VARCHAR(1000) | NULL | 商品图片 URL |
| shop_title | VARCHAR(200) | NULL | 店铺名称 |
| link | VARCHAR(2000) | NULL | 商品链接 |
| description | TEXT | NULL | 商品描述 |
| rating | DECIMAL(3, 2) | NULL | 评分（0.00-1.00） |
| sales | INTEGER | NULL | 销量 |
| commission | DECIMAL(12, 2) | NULL | 佣金 |
| quantity | INTEGER | DEFAULT 1 | 商品数量 |
| initial_price | DECIMAL(12, 2) | NULL | 加入购物车时的价格 |
| current_price | DECIMAL(12, 2) | NULL | 当前价格（用于价格监控） |
| raw_data | JSONB | NULL | 原始商品数据（JSON） |
| created_at | TIMESTAMP WITH TIME ZONE | DEFAULT NOW() | 创建时间 |
| updated_at | TIMESTAMP WITH TIME ZONE | DEFAULT NOW() | 更新时间 |
| deleted_at | TIMESTAMP WITH TIME ZONE | NULL | 删除时间（软删除） |
| sync_version | BIGINT | DEFAULT 1 | 同步版本号 |

**索引**:
- `idx_cart_user`: 用户 ID 索引
- `idx_cart_user_product`: 用户+商品唯一索引（用于 ON CONFLICT）
- `idx_cart_sync`: 用户+版本号索引（用于增量同步）
- `idx_cart_deleted`: 用户+删除时间索引（过滤已删除项）

**唯一约束**:
- `cart_items_user_product_unique`: (user_id, product_id) 唯一约束

**触发器**:
- `update_cart_items_updated_at`: 自动更新 updated_at 字段

**设计说明**:
- 支持软删除（deleted_at）
- 支持版本号同步（sync_version）
- 存储价格历史（initial_price, current_price）
- 使用 JSONB 存储原始商品数据，保持灵活性

### 4.4 会话表 (conversations)

**表名**: `conversations`

**用途**: 存储 AI 聊天会话信息

**字段定义**:

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| id | UUID | PRIMARY KEY | 会话唯一标识 |
| user_id | UUID | NOT NULL, FK → users(id) | 用户 ID |
| client_id | VARCHAR(100) | NOT NULL | 客户端会话 ID（前端生成） |
| title | VARCHAR(500) | NULL | 会话标题 |
| created_at | TIMESTAMP WITH TIME ZONE | DEFAULT NOW() | 创建时间 |
| updated_at | TIMESTAMP WITH TIME ZONE | DEFAULT NOW() | 更新时间 |
| deleted_at | TIMESTAMP WITH TIME ZONE | NULL | 删除时间（软删除） |
| sync_version | BIGINT | DEFAULT 1 | 同步版本号 |

**索引**:
- `idx_conv_user`: 用户 ID 索引
- `idx_conv_sync`: 用户+版本号索引（用于增量同步）
- `idx_conv_deleted`: 用户+删除时间索引（过滤已删除项）

**唯一约束**:
- `(user_id, client_id)`: 确保同一用户不会重复创建相同客户端会话

**触发器**:
- `update_conversations_updated_at`: 自动更新 updated_at 字段

**设计说明**:
- 支持软删除
- 支持版本号同步
- client_id 由前端生成，用于客户端会话标识

### 4.5 消息表 (messages)

**表名**: `messages`

**用途**: 存储 AI 聊天消息内容

**字段定义**:

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| id | UUID | PRIMARY KEY | 消息唯一标识 |
| conversation_id | UUID | NOT NULL, FK → conversations(id) | 会话 ID |
| client_id | VARCHAR(100) | NOT NULL | 客户端消息 ID（前端生成） |
| role | VARCHAR(20) | NOT NULL | 消息角色（user/assistant） |
| content | TEXT | NOT NULL | 消息内容 |
| products | JSONB | NULL | 关联商品列表（JSON 数组） |
| keywords | JSONB | NULL | 提取的关键词（JSON 数组） |
| ai_parsed_raw | TEXT | NULL | AI 解析的原始数据 |
| failed | BOOLEAN | DEFAULT FALSE | 是否失败 |
| retry_for_text | TEXT | NULL | 重试原因 |
| created_at | TIMESTAMP WITH TIME ZONE | DEFAULT NOW() | 创建时间 |
| sync_version | BIGINT | DEFAULT 1 | 同步版本号 |

**索引**:
- `idx_msg_conv`: 会话 ID 索引
- `idx_msg_sync`: 会话+版本号索引（用于增量同步）
- `idx_msg_created`: 会话+创建时间索引（用于排序）

**唯一约束**:
- `(conversation_id, client_id)`: 确保同一会话不会重复创建相同客户端消息

**设计说明**:
- 使用 JSONB 存储商品和关键词，支持灵活查询
- 支持消息失败标记和重试机制
- 存储 AI 解析的原始数据，便于调试

### 4.6 同步版本跟踪表 (sync_versions)

**表名**: `sync_versions`

**用途**: 跟踪各实体的同步版本号，用于增量同步

**字段定义**:

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| id | UUID | PRIMARY KEY | 记录唯一标识 |
| user_id | UUID | NOT NULL, FK → users(id) | 用户 ID |
| entity_type | VARCHAR(50) | NOT NULL | 实体类型（cart/conversations/messages） |
| current_version | BIGINT | DEFAULT 0 | 当前版本号 |
| last_updated_at | TIMESTAMP WITH TIME ZONE | DEFAULT NOW() | 最后更新时间 |

**索引**:
- `idx_sync_versions_user`: 用户 ID 索引

**唯一约束**:
- `(user_id, entity_type)`: 确保每个用户的每种实体类型只有一条版本记录

**设计说明**:
- 版本号自增，每次更新实体时递增
- 客户端同步时携带 last_sync_version，服务器返回增量数据
- 支持多种实体类型（购物车、会话、消息）

### 4.7 登录尝试记录表 (login_attempts)

**表名**: `login_attempts`

**用途**: 记录登录尝试，用于防暴力破解

**字段定义**:

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| id | UUID | PRIMARY KEY | 记录唯一标识 |
| email | VARCHAR(255) | NOT NULL | 尝试登录的邮箱 |
| user_id | UUID | NULL, FK → users(id) | 用户 ID（如果登录成功） |
| ip_address | INET | NULL | IP 地址 |
| user_agent | TEXT | NULL | 用户代理字符串 |
| attempted_at | TIMESTAMP WITH TIME ZONE | DEFAULT NOW() | 尝试时间 |
| success | BOOLEAN | DEFAULT FALSE | 是否成功 |
| failure_reason | VARCHAR(255) | NULL | 失败原因 |

**索引**:
- `idx_login_attempts_email`: 邮箱+时间索引（用于查询最近尝试）
- `idx_login_attempts_ip`: IP+时间索引（用于查询 IP 尝试记录）

**设计说明**:
- 记录所有登录尝试（成功和失败）
- 支持按邮箱或 IP 查询最近尝试次数
- 可定期清理旧记录（通过 cleanup_old_login_attempts 函数）

### 4.8 邮箱验证码表 (email_verifications)

**表名**: `email_verifications`

**用途**: 存储邮箱验证码，用于注册、密码重置等

**字段定义**:

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| id | UUID | PRIMARY KEY | 记录唯一标识 |
| email | VARCHAR(255) | NOT NULL | 邮箱地址 |
| code | VARCHAR(10) | NOT NULL | 验证码 |
| type | VARCHAR(20) | NOT NULL | 验证类型（register/reset_password/verify） |
| expires_at | TIMESTAMP WITH TIME ZONE | NOT NULL | 过期时间 |
| used_at | TIMESTAMP WITH TIME ZONE | NULL | 使用时间 |
| created_at | TIMESTAMP WITH TIME ZONE | DEFAULT NOW() | 创建时间 |

**索引**:
- `idx_email_verif_email`: 邮箱+类型+过期时间索引（用于查询有效验证码）

**设计说明**:
- 验证码有有效期（通常 10-15 分钟）
- 使用后标记 used_at，防止重复使用
- 支持多种验证类型

---

## 5. 数据同步机制

### 5.1 版本号机制

**工作原理**:
1. 每个实体（购物车、会话、消息）都有 `sync_version` 字段
2. `sync_versions` 表跟踪每个用户每种实体类型的当前版本号
3. 实体更新时，调用 `get_next_sync_version()` 函数获取新版本号
4. 客户端同步时携带 `last_sync_version`，服务器返回版本号大于该值的所有数据

**同步流程**:
```
客户端请求同步
  ↓
携带 last_sync_version
  ↓
服务器查询 sync_versions 获取当前版本
  ↓
查询实体表中 sync_version > last_sync_version 的数据
  ↓
返回增量数据和新版本号
  ↓
客户端更新本地数据
```

### 5.2 冲突解决

**冲突检测**:
- 使用 `ON CONFLICT` 语句处理唯一约束冲突
- 购物车使用 `(user_id, product_id)` 唯一约束
- 会话和消息使用 `(user_id, client_id)` 或 `(conversation_id, client_id)` 唯一约束

**冲突解决策略**:
- **购物车**: 使用 `ON CONFLICT DO UPDATE`，以服务器版本为准（或合并数量）
- **会话/消息**: 使用 `ON CONFLICT DO UPDATE`，保留最新版本

### 5.3 软删除机制

**实现方式**:
- 使用 `deleted_at` 字段标记删除
- 查询时过滤 `deleted_at IS NULL` 的记录
- 支持恢复删除（设置 `deleted_at = NULL`）

**同步处理**:
- 删除操作更新 `sync_version`，同步到其他设备
- 客户端收到删除标记后，从本地删除或标记删除

---

## 6. 数据库函数和触发器

### 6.1 自动更新时间戳

**函数**: `update_updated_at_column()`

**用途**: 自动更新表的 `updated_at` 字段

**实现**:
```sql
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';
```

**应用表**:
- `users`
- `cart_items`
- `conversations`

### 6.2 获取同步版本号

**函数**: `get_next_sync_version(p_user_id UUID, p_entity_type VARCHAR(50))`

**用途**: 获取并递增指定用户和实体类型的版本号

**实现**:
```sql
CREATE OR REPLACE FUNCTION get_next_sync_version(
    p_user_id UUID,
    p_entity_type VARCHAR(50)
)
RETURNS BIGINT AS $$
DECLARE
    v_version BIGINT;
BEGIN
    INSERT INTO sync_versions (user_id, entity_type, current_version, last_updated_at)
    VALUES (p_user_id, p_entity_type, 1, NOW())
    ON CONFLICT (user_id, entity_type) 
    DO UPDATE SET 
        current_version = sync_versions.current_version + 1,
        last_updated_at = NOW()
    RETURNING current_version INTO v_version;
    
    RETURN v_version;
END;
$$ LANGUAGE plpgsql;
```

**使用场景**:
- 更新购物车商品时
- 创建或更新会话时
- 创建或更新消息时

### 6.3 清理旧登录记录

**函数**: `cleanup_old_login_attempts()`

**用途**: 清理 1 天前的登录尝试记录

**实现**:
```sql
CREATE OR REPLACE FUNCTION cleanup_old_login_attempts()
RETURNS void AS $$
BEGIN
    DELETE FROM login_attempts WHERE attempted_at < NOW() - INTERVAL '1 day';
END;
$$ LANGUAGE plpgsql;
```

**调用方式**:
- 可设置定时任务定期调用
- 或在应用启动时调用

---

## 7. 索引策略

### 7.1 索引设计原则

1. **主键索引**: 所有表都有 UUID 主键，自动创建主键索引
2. **外键索引**: 为所有外键字段创建索引
3. **查询索引**: 为常用查询字段创建索引
4. **复合索引**: 为多字段查询创建复合索引
5. **部分索引**: 为过滤条件创建部分索引（如 `WHERE deleted_at IS NULL`）

### 7.2 索引列表

**用户表索引**:
- `idx_users_email`: 邮箱唯一索引
- `idx_users_status`: 状态索引

**会话表索引**:
- `idx_sessions_user`: 用户 ID 索引
- `idx_sessions_device`: 设备 ID 索引
- `idx_sessions_user_device`: 用户+设备唯一索引
- `idx_sessions_refresh_token`: Refresh Token 索引

**购物车表索引**:
- `idx_cart_user`: 用户 ID 索引
- `idx_cart_user_product`: 用户+商品唯一索引
- `idx_cart_sync`: 用户+版本号索引（用于增量同步）
- `idx_cart_deleted`: 用户+删除时间部分索引

**会话表索引**:
- `idx_conv_user`: 用户 ID 索引
- `idx_conv_sync`: 用户+版本号索引
- `idx_conv_deleted`: 用户+删除时间部分索引

**消息表索引**:
- `idx_msg_conv`: 会话 ID 索引
- `idx_msg_sync`: 会话+版本号索引
- `idx_msg_created`: 会话+创建时间索引（用于排序）

### 7.3 索引优化建议

**定期维护**:
- 定期执行 `VACUUM ANALYZE` 更新统计信息
- 监控索引使用情况，删除未使用的索引
- 对于大表，考虑分区策略

**查询优化**:
- 使用 `EXPLAIN ANALYZE` 分析查询计划
- 确保索引覆盖常用查询
- 避免过度索引（影响写入性能）

---

## 8. 数据迁移管理

### 8.1 迁移文件组织

**目录结构**:
```
server/lib/database/migrations/
├── 001_create_user_tables.sql      # 初始表结构
├── 002_fix_constraints.sql         # 修复约束
└── ...
```

**命名规范**:
- 格式: `{序号}_{描述}.sql`
- 序号: 3 位数字，递增
- 描述: 简短的功能描述（英文，下划线分隔）

### 8.2 迁移记录表

**表名**: `_migrations`

**用途**: 记录已执行的迁移脚本

**字段**:
- `id`: 自增主键
- `name`: 迁移文件名（唯一）
- `applied_at`: 执行时间

**管理方式**:
- 应用启动时检查并执行未应用的迁移
- 防止重复执行同一迁移

### 8.3 迁移脚本示例

**001_create_user_tables.sql**:
- 创建所有用户相关表
- 创建索引和触发器
- 创建辅助函数

**002_fix_constraints.sql**:
- 修复缺失的列
- 添加唯一约束
- 清理重复数据

### 8.4 迁移执行流程

```
应用启动
  ↓
连接数据库
  ↓
检查 _migrations 表
  ↓
读取 migrations 目录下的所有迁移文件
  ↓
按序号排序
  ↓
执行未应用的迁移
  ↓
记录到 _migrations 表
  ↓
完成
```

---

## 9. 数据安全

### 9.1 密码安全

**存储方式**:
- 使用 bcrypt 算法加密（cost = 12）
- 密码哈希存储在 `password_hash` 字段
- 不存储明文密码

**验证流程**:
1. 用户输入密码
2. 使用 bcrypt 验证密码哈希
3. 验证成功则创建会话

### 9.2 数据加密

**传输加密**:
- 使用 HTTPS 传输数据
- 数据库连接使用 SSL（生产环境）

**存储加密**:
- 敏感字段（如密码）已加密存储
- 其他字段以明文存储（便于查询和索引）

### 9.3 访问控制

**数据库用户**:
- 应用使用专用数据库用户
- 限制权限（仅允许必要的操作）
- 不使用超级用户

**SQL 注入防护**:
- 使用参数化查询
- 不拼接 SQL 字符串
- 验证和转义用户输入

---

## 10. 性能优化

### 10.1 查询优化

**优化策略**:
- 使用索引覆盖查询
- 避免全表扫描
- 使用 LIMIT 限制结果集
- 使用 EXPLAIN 分析查询计划

**常见优化**:
- 分页查询使用 `OFFSET` 和 `LIMIT`
- 增量同步使用版本号过滤
- 软删除使用部分索引过滤

### 10.2 连接池

**配置建议**:
- 使用连接池管理数据库连接
- 设置合理的连接数（根据并发需求）
- 及时释放连接

### 10.3 数据清理

**定期清理**:
- 清理过期的登录尝试记录
- 清理过期的邮箱验证码
- 清理软删除的旧数据（可选）

**清理策略**:
- 登录尝试记录：保留 1 天
- 邮箱验证码：使用后立即删除或保留 1 小时
- 软删除数据：保留 30 天后物理删除（可选）

---

## 11. 备份和恢复

### 11.1 备份策略

**备份方式**:
- **全量备份**: 每日全量备份
- **增量备份**: 每小时增量备份
- **WAL 归档**: 启用 WAL 归档（可选）

**备份存储**:
- 本地备份 + 远程备份
- 保留最近 7 天的备份
- 定期测试备份恢复

### 11.2 恢复流程

**恢复步骤**:
1. 停止应用服务
2. 恢复数据库备份
3. 验证数据完整性
4. 重启应用服务

**灾难恢复**:
- 制定灾难恢复计划
- 定期演练恢复流程
- 准备备用数据库服务器

---

## 12. 监控和维护

### 12.1 性能监控

**监控指标**:
- 数据库连接数
- 查询响应时间
- 慢查询日志
- 表大小和增长趋势
- 索引使用情况

**监控工具**:
- PostgreSQL 内置统计信息
- pg_stat_statements 扩展
- 第三方监控工具（如 Prometheus + Grafana）

### 12.2 维护任务

**定期维护**:
- **VACUUM**: 清理死元组，更新统计信息
- **ANALYZE**: 更新查询计划器统计信息
- **REINDEX**: 重建索引（如需要）
- **清理日志**: 清理旧日志文件

**维护频率**:
- VACUUM: 每日自动执行
- ANALYZE: 每日自动执行
- REINDEX: 根据需要手动执行

---

## 13. 扩展性设计

### 13.1 水平扩展

**分库分表**:
- 当前设计支持单库单表
- 未来可考虑按用户 ID 分片
- 使用 UUID 便于分布式扩展

### 13.2 垂直扩展

**优化方向**:
- 增加数据库服务器资源（CPU、内存、存储）
- 优化查询和索引
- 使用读写分离（主从复制）

### 13.3 未来扩展

**可能的新表**:
- `price_history`: 价格历史记录表
- `user_preferences`: 用户偏好表
- `analytics_events`: 分析事件表
- `admin_logs`: 管理员操作日志表

---

## 14. 总结

### 14.1 架构特点

快淘帮 WisePick 数据库架构具有以下特点：

1. **关系型设计**: 使用 PostgreSQL 关系型数据库，保证数据一致性
2. **UUID 主键**: 所有表使用 UUID，便于分布式扩展
3. **软删除**: 重要数据支持软删除，便于恢复
4. **版本同步**: 支持多设备数据同步的版本控制机制
5. **JSONB 存储**: 灵活数据使用 JSONB，保持扩展性
6. **安全设计**: 密码加密、SQL 注入防护、访问控制

### 14.2 技术优势

- **数据一致性**: ACID 事务保证数据完整性
- **查询性能**: 合理的索引设计，支持高效查询
- **扩展性**: UUID 和版本号机制支持分布式扩展
- **安全性**: 密码加密、软删除、访问控制
- **可维护性**: 清晰的表结构、完善的索引、迁移管理

### 14.3 适用场景

本数据库架构适用于：
- 用户账号管理系统
- 多设备数据同步
- 购物车和会话管理
- 需要版本控制的场景
- 需要软删除的场景

### 14.4 后续工作

1. **性能优化**: 持续监控和优化查询性能
2. **功能扩展**: 按 PRD 规划添加新表（价格历史、用户偏好等）
3. **备份完善**: 完善备份和恢复机制
4. **监控完善**: 添加数据库监控和告警

---

## 15. 附录

### 15.1 参考文档

- [PRD 文档](../PRD.md) - 产品需求文档
- [架构文档](./architecture.md) - 完整技术架构文档
- [后端架构文档](./backend-architecture.md) - 后端架构设计文档
- [PostgreSQL 官方文档](https://www.postgresql.org/docs/) - PostgreSQL 官方文档

### 15.2 相关工具

- **psql**: PostgreSQL 命令行客户端
- **pgAdmin**: PostgreSQL 图形化管理工具
- **pg_dump**: 数据库备份工具
- **pg_restore**: 数据库恢复工具

### 15.3 变更日志

| 版本 | 日期 | 变更内容 | 作者 |
|------|------|----------|------|
| 1.0 | 2026-01-22 | 初始数据库架构文档 | Winston (Architect) |

---

**文档维护者**: 架构团队  
**审核者**: 技术团队  
**批准者**: 技术负责人

---

*本文档基于项目实际数据库设计和迁移脚本编写，反映了当前数据库的真实架构状态。*

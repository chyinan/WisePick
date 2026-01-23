# 快淘帮 WisePick - 前端架构设计文档

**版本**: 2.0  
**创建日期**: 2024  
**最后更新**: 2026-01-22  
**文档状态**: 正式版  
**架构师**: Winston (Architect Agent)

---

## 1. 文档概述

### 1.1 文档目的

本文档详细描述了快淘帮 WisePick 项目的前端架构设计，包括 Flutter 应用的技术栈、架构模式、核心模块设计、数据流、状态管理等。本文档旨在：

- 为前端开发团队提供清晰的技术实现指南
- 确保新功能开发遵循统一的架构模式
- 指导前端系统扩展和优化决策
- 作为代码审查和架构评审的参考标准

### 1.2 文档范围

本文档涵盖：

- **技术栈**: Flutter、Dart、Riverpod、Hive 等核心技术选型
- **架构模式**: MVVM、Adapter、Service 层等设计模式
- **核心模块**: 聊天、商品、购物车等业务模块设计
- **状态管理**: Riverpod 状态管理架构
- **数据流**: 用户交互到数据持久化的完整流程
- **UI 架构**: Material Design 3 组件设计
- **性能优化**: 前端性能优化策略

### 1.3 目标读者

- 前端开发工程师
- Flutter 开发者
- 系统架构师
- 技术负责人

---

## 2. 技术栈

### 2.1 核心技术

| 类别 | 技术 | 版本 | 用途 |
|------|------|------|------|
| 框架 | Flutter | 3.9.2+ | 跨平台 UI 框架 |
| 语言 | Dart | 3.9.2+ | 编程语言 |
| 状态管理 | Riverpod | 2.5.1 | 响应式状态管理 |
| 本地存储 | Hive | 2.2.3 | NoSQL 本地数据库 |
| 网络请求 | Dio | 5.1.2 | HTTP 客户端 |
| UI 框架 | Material Design 3 | - | 设计系统 |

### 2.2 辅助技术

| 类别 | 技术 | 用途 |
|------|------|------|
| 字体 | Noto Sans SC | 中文字体支持 |
| 窗口管理 | window_manager | 桌面端窗口控制 |
| URL 启动 | url_launcher | 外部链接打开 |
| 加密 | crypto | 密码哈希 |
| 图表库 | fl_chart | 数据可视化 |
| PDF生成 | pdf / printing | 报告生成 |
| Excel导出 | excel | 数据导出 |

### 2.3 技术选型理由

**Flutter**:
- 一套代码支持多平台（Windows、macOS、Linux、Android、iOS、Web）
- 性能接近原生应用
- 丰富的生态系统
- Dart 语言类型安全

**Riverpod**:
- 编译时安全
- 依赖注入支持
- 测试友好
- 性能优秀

**Hive**:
- 高性能 NoSQL 数据库
- 类型安全
- 支持复杂对象存储
- 跨平台支持

---

## 3. 整体架构

### 3.1 架构分层

前端应用采用**分层架构模式**，从下至上分为：

```
┌─────────────────────────────────────────────────────────────┐
│                    UI 层 (Presentation Layer)                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  ChatPage    │  │  CartPage    │  │ SettingsPage │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ ProductCard  │  │ LoadingWidget│  │ HomeDrawer   │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              状态管理层 (State Management Layer)             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ChatProviders │  │CartProviders │  │ThemeProvider │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              业务逻辑层 (Business Logic Layer)               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ ChatService  │  │ProductService│  │ CartService  │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │SearchService │  │PriceRefresh  │  │Notification  │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              数据访问层 (Data Access Layer)                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  ApiClient   │  │     Hive     │  │  Adapters    │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │TaobaoAdapter │  │  JdAdapter  │  │ PddAdapter   │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 架构模式

#### 3.2.1 MVVM 模式

使用 Riverpod 实现 View-ViewModel 分离：

- **View**: Flutter Widget（UI 组件）
- **ViewModel**: Riverpod Provider（状态管理）
- **Model**: 数据模型（ProductModel、ChatMessage 等）

#### 3.2.2 Adapter 模式

统一不同电商平台 API 接口：

- **TaobaoAdapter**: 淘宝平台适配器
- **JdAdapter**: 京东平台适配器
- **PddAdapter**: 拼多多平台适配器
- **统一接口**: ProductService 提供统一 API

#### 3.2.3 Service 层模式

业务逻辑封装在 Service 中：

- **ChatService**: 聊天业务逻辑
- **ProductService**: 商品业务逻辑
- **CartService**: 购物车业务逻辑
- **SearchService**: 搜索业务逻辑

#### 3.2.4 Repository 模式

数据访问层抽象（部分实现）：

- **ConversationRepository**: 会话数据访问
- **Hive**: 本地数据持久化

---

## 4. 核心模块设计

### 4.1 应用入口模块

#### 4.1.1 应用初始化

**职责**:
- Flutter 框架初始化
- Hive 数据库初始化
- 平台特定配置（桌面端窗口管理）
- 通知服务初始化
- 后台服务启动（价格刷新）

**初始化流程**:
1. WidgetsFlutterBinding.ensureInitialized()
2. 桌面端窗口配置（window_manager）
3. NotificationService 初始化
4. Hive 初始化并注册适配器
5. 启动 PriceRefreshService
6. 运行应用（ProviderScope）

#### 4.1.2 应用根组件

**WisePickApp**:
- MaterialApp 配置
- 主题管理（深色模式支持）
- 路由配置
- 全局 ProviderScope

**HomePage**:
- 响应式布局（桌面端 NavigationRail，移动端 BottomNavigationBar）
- 页面切换管理
- 管理员入口（7 次点击"关于"触发）

### 4.2 聊天模块 (Chat Feature)

#### 4.2.1 模块结构

```
features/chat/
├── chat_service.dart          # 聊天业务逻辑
├── chat_providers.dart        # Riverpod 状态管理
├── chat_message.dart         # 消息数据模型
├── conversation_model.dart    # 会话数据模型
└── conversation_repository.dart  # 会话数据访问
```

#### 4.2.2 ChatService 设计

**核心职责**:
- AI 对话交互（流式/非流式）
- 会话管理（创建、切换、删除）
- 消息历史管理
- 会话标题生成

**关键方法**:
- `getAiReply()`: 获取 AI 回复（非流式）
- `getAiReplyStream()`: 获取 AI 回复（流式）
- `generateConversationTitle()`: 生成会话标题

**技术特性**:
- 支持直接调用 OpenAI API 或通过后端代理
- 支持 Mock AI 模式（离线开发）
- 可配置 Prompt 嵌入、Max Tokens 等
- 流式响应处理（SSE）

#### 4.2.3 ChatProviders 设计

**状态管理**:
- `currentConversationProvider`: 当前会话
- `conversationsProvider`: 所有会话列表
- `messagesProvider`: 当前会话消息列表
- `isLoadingProvider`: 加载状态

**数据流**:
```
用户输入 → ChatPage → ChatProviders → ChatService → ApiClient → 后端/OpenAI
                                                              ↓
用户界面 ← ChatPage ← ChatProviders ← ChatService ← 流式响应
```

#### 4.2.4 ChatPage 设计

**UI 组件**:
- 消息列表（ListView）
- 输入框（TextField）
- 发送按钮
- 会话切换侧边栏
- 商品卡片展示（AI 推荐的商品）

**交互流程**:
1. 用户输入消息
2. 发送到 ChatService
3. 显示加载状态
4. 流式显示 AI 回复
5. 解析商品推荐（JSON）
6. 保存会话历史

### 4.3 商品模块 (Products Feature)

#### 4.3.1 模块结构

```
features/products/
├── product_service.dart       # 商品业务逻辑
├── search_service.dart         # 搜索业务逻辑
├── product_model.dart          # 商品数据模型
├── product_detail_page.dart    # 商品详情页
├── taobao_adapter.dart         # 淘宝适配器
├── jd_adapter.dart             # 京东适配器
├── pdd_adapter.dart            # 拼多多适配器
└── jd_models.dart              # 京东数据模型
```

#### 4.3.2 ProductService 设计

**核心职责**:
- 多平台商品搜索
- 推广链接生成和缓存
- 商品数据统一封装

**关键方法**:
- `searchProducts()`: 搜索商品（支持单平台或全平台）
- `generatePromotionLink()`: 生成推广链接

**搜索策略**:
- 单平台搜索：直接调用对应 Adapter
- 全平台搜索：并行调用所有 Adapter，合并结果
- 去重策略：优先保留京东结果
- 排序策略：京东优先，然后淘宝，最后拼多多

**推广链接缓存**:
- 内存缓存（Map）
- Hive 持久化缓存
- 缓存有效期：30 分钟
- 支持强制刷新

#### 4.3.3 Adapter 设计模式

**统一接口**:
所有 Adapter 实现统一的搜索接口，返回 `List<ProductModel>`

**TaobaoAdapter**:
- 调用淘宝联盟 API
- 集成 `TaobaoItemDetailService` 获取详情
- 数据转换为 ProductModel

**JdAdapter**:
- 调用京东联盟 API
- **Scraper 支持**: 当官方 API 不可用时，通过 `JdProductServiceExtension` 调用后端爬虫
- **OAuth 认证**: 集成 `JdOAuthService` 处理授权流程

**PddAdapter**:
- 调用拼多多开放平台 API
- 集成 `PddGoodsDetailService` 获取详情

#### 4.3.4 ProductModel 设计

**数据字段**:
- `id`: 商品 ID
- `platform`: 平台标识（'taobao' | 'jd' | 'pdd'）
- `title`: 商品标题
- `price`: 价格
- `originalPrice`: 原价
- `coupon`: 优惠券金额
- `finalPrice`: 最终价格
- `imageUrl`: 图片 URL
- `sales`: 销量
- `rating`: 评分
- `shopTitle`: 店铺名
- `link`: 商品链接
- `commission`: 佣金
- `description`: 描述

**序列化**:
- 使用 Hive 注解支持序列化
- 支持向后兼容（legacy 字段）

### 4.4 购物车模块 (Cart Feature)

#### 4.4.1 模块结构

```
features/cart/
├── cart_service.dart          # 购物车业务逻辑
├── cart_providers.dart       # Riverpod 状态管理
└── cart_page.dart            # 购物车页面
```

### 4.5 数据分析模块 (Analytics Feature)（新增）

#### 4.5.1 模块结构

```
features/analytics/
├── analytics_service.dart     # 数据分析业务逻辑
├── analytics_providers.dart   # Riverpod 状态管理
├── analytics_models.dart      # 数据模型
├── analytics_page.dart        # 数据分析页面
└── widgets/                   # 图表组件
    ├── consumption_structure_chart.dart  # 消费结构图表
    ├── preferences_chart.dart            # 偏好分析图表
    └── shopping_time_heatmap.dart        # 购物时间热力图
```

#### 4.5.2 AnalyticsService 设计

**核心职责**:
- 消费结构分析（品类分布、价格区间、平台偏好）
- 智能偏好分析（基于历史购物行为）
- 购物欲望时间分析（24小时分布、工作日/周末对比）
- 购物报告生成（PDF导出）

**关键方法**:
- `getConsumptionStructure()`: 计算消费结构分析
- `getUserPreferences()`: 分析用户偏好
- `getShoppingTimeAnalysis()`: 分析购物时间分布
- `generateReport()`: 生成购物报告（PDF）

**数据来源**:
- 购物车历史数据（Hive）
- 会话历史数据（Hive，提取创建时间）
- 云端数据（如已登录，从后端获取）

#### 4.5.3 AnalyticsProviders 设计

**状态管理**:
- `consumptionStructureProvider`: 消费结构分析数据
- `userPreferencesProvider`: 用户偏好数据
- `shoppingTimeProvider`: 购物时间分析数据
- `isLoadingProvider`: 加载状态

#### 4.5.4 AnalyticsPage 设计

**UI 组件**:
- 数据面板（总消费、商品数量等）
- 消费结构图表（饼图、柱状图）
- 偏好分析展示
- 购物时间热力图
- 报告生成按钮

**交互流程**:
1. 选择时间范围
2. 加载分析数据
3. 展示图表和统计
4. 生成报告（PDF导出）

### 4.6 价格历史模块 (Price History Feature)（新增）

#### 4.6.1 模块结构

```
features/price_history/
├── price_history_service.dart    # 价格历史业务逻辑
├── price_history_providers.dart   # Riverpod 状态管理
├── price_history_model.dart       # 数据模型
├── price_history_page.dart        # 价格历史页面
└── widgets/
    └── price_chart_widget.dart     # 价格曲线图组件
```

#### 4.6.2 PriceHistoryService 设计

**核心职责**:
- 价格历史数据管理（记录、查询）
- 价格趋势分析
- 最佳购买时机推荐

**关键方法**:
- `recordPriceHistory()`: 记录价格历史（与价格监控服务集成）
- `getPriceHistory()`: 获取价格历史数据
- `analyzePriceTrend()`: 分析价格趋势
- `getBestBuyTime()`: 推荐最佳购买时机

**数据存储**:
- Hive Box: `price_history`
- 云端存储（如已登录）：PostgreSQL

#### 4.6.3 PriceHistoryPage 设计

**UI 组件**:
- 商品选择器
- 价格曲线图（支持多商品对比）
- 价格统计信息（最高价、最低价、平均价）
- 购买时机建议
- 时间范围选择

**交互流程**:
1. 选择商品（从购物车或搜索）
2. 选择时间范围
3. 加载价格历史数据
4. 展示价格曲线图
5. 显示购买建议

### 4.7 购物决策模块 (Decision Feature)（新增）

#### 4.7.1 模块结构

```
features/decision/
├── decision_service.dart      # 购物决策业务逻辑
├── decision_providers.dart    # Riverpod 状态管理
├── decision_models.dart       # 数据模型
├── compare_page.dart          # 商品对比页面
└── widgets/
    ├── comparison_table.dart  # 对比表格组件
    └── score_card.dart        # 评分卡片组件
```

#### 4.7.2 DecisionService 设计

**核心职责**:
- 多商品对比分析
- 购买建议评分计算
- 替代商品推荐
- 决策理由生成

**关键方法**:
- `compareProducts()`: 对比多个商品
- `calculateScore()`: 计算购买建议评分
- `findAlternatives()`: 查找替代商品
- `generateReasoning()`: 生成决策理由（调用 AI）

**评分算法**:
- 价格评分（0-25分）：价格合理性、性价比
- 评价评分（0-25分）：用户评价、好评率
- 销量评分（0-20分）：销量数据、市场认可度
- 历史趋势评分（0-15分）：价格趋势、稳定性
- 平台评分（0-15分）：平台信誉、服务质量

#### 4.7.3 ComparePage 设计

**UI 组件**:
- 商品选择器（支持2-5个商品）
- 对比表格（价格、评分、销量、参数等）
- 评分卡片（综合评分、各维度得分）
- 决策理由展示
- 替代商品推荐列表

**交互流程**:
1. 选择要对比的商品
2. 加载商品详细信息
3. 计算评分和对比数据
4. 展示对比表格和评分
5. 显示决策理由和替代商品

### 4.8 管理员后台模块说明（新增）

**重要说明**: 管理员后台是**独立的 Flutter Web 项目**，不在主应用中。

#### 4.8.1 独立项目结构

管理员后台作为独立项目 `wisepick_admin`，项目结构如下：

```
wisepick_admin/                    # 独立项目根目录
├── lib/
│   ├── main.dart                  # 应用入口
│   ├── app.dart                   # 应用根组件
│   ├── features/
│   │   └── dashboard/             # 仪表板模块
│   │       ├── dashboard_page.dart
│   │       ├── dashboard_service.dart
│   │       ├── dashboard_providers.dart
│   │       └── widgets/
│   ├── core/
│   │   ├── api_client.dart        # API客户端（调用后端）
│   │   ├── auth/
│   │   │   ├── login_page.dart    # 管理员登录页面
│   │   │   └── auth_service.dart
│   │   └── theme/
│   │       └── app_theme.dart
│   └── models/
├── web/
│   ├── index.html
│   └── manifest.json
└── pubspec.yaml
```

**与主应用的关系**:
- 完全独立的 Flutter 项目
- 通过 HTTP API 调用后端服务
- 可独立部署到不同域名
- 共享后端 API 接口

#### 4.8.2 DashboardService 设计（独立项目）

**核心职责**:
- 调用后端管理API获取数据
- 处理API响应和错误
- 数据格式转换

**关键方法**:
- `getUserStats()`: 调用 `/api/v1/admin/users/stats`
- `getSystemStats()`: 调用 `/api/v1/admin/system/stats`
- `getSearchKeywords()`: 调用 `/api/v1/admin/search/keywords`
- `exportData()`: 调用 `/api/v1/admin/export` 或前端生成Excel/CSV

**API客户端**:
- 使用 Dio 进行HTTP请求
- 自动添加JWT Token到请求头
- 401错误自动跳转到登录页
- 统一的错误处理

**权限控制**:
- 登录页面验证管理员身份
- JWT Token存储在 secure_storage
- 路由守卫检查登录状态

#### 4.8.3 DashboardPage 设计（独立项目）

**页面结构**:
- 登录页面（未登录时显示）
- 仪表板主页面（登录后显示）

**仪表板UI组件**:
- 数据面板（用户数、活跃用户、留存率等）
- 系统统计图表（API调用、搜索成功率等）
- 搜索热词排行榜
- 数据导出按钮
- 时间范围选择器

**交互流程**:
1. 访问独立Web应用
2. 检查登录状态（读取JWT Token）
3. 未登录：显示登录页面
4. 已登录：显示仪表板
5. 选择时间范围
6. 调用后端API加载统计数据
7. 展示数据面板和图表
8. 导出数据（如需要）

**部署方式**:
- 独立构建：`flutter build web --release`
- 独立部署：可部署到 `admin.wisepick.com` 或子路径
- 独立更新：不影响主应用

#### 4.4.2 CartService 设计

**核心职责**:
- 购物车数据管理（添加、删除、更新）
- 商品数量管理
- 价格跟踪（初始价格、当前价格）

**关键方法**:
- `addOrUpdateItem()`: 添加或更新商品
- `removeItem()`: 删除商品
- `setQuantity()`: 设置商品数量
- `getAllItems()`: 获取所有商品
- `clear()`: 清空购物车

**数据存储**:
- 使用 Hive Box: `cart_box`
- 存储格式：`{product fields..., 'qty': int, 'initial_price': double, 'current_price': double}`
- 支持原始 JSON 存储（`raw_json` 字段）

#### 4.4.3 CartProviders 设计

**状态管理**:
- `cartItemsProvider`: 购物车商品列表
- `selectedItemsProvider`: 选中的商品
- `totalPriceProvider`: 总价计算

#### 4.4.4 CartPage 设计

**UI 组件**:
- 商品列表（按店铺分组）
- 商品卡片（显示价格、数量、选择状态）
- 底部结算栏（总价、批量操作）
- 全选/取消全选
- 批量删除
- 批量复制推广链接

**交互流程**:
1. 加载购物车数据
2. 按店铺分组显示
3. 用户选择商品
4. 调整数量
5. 结算（复制推广链接）

### 4.9 设置模块 (Settings Feature)

#### 4.9.1 模块结构

```
screens/
├── admin_settings_page.dart      # 管理员设置页面
└── user_settings_page.dart       # 用户设置页面
```

#### 4.5.2 AdminSettingsPage 设计

**核心功能**:
- OpenAI API Key 配置
- 后端代理地址配置
- AI 模型选择（支持获取可用模型列表）
- Prompt 嵌入开关
- 调试模式（显示原始 JSON 响应）
- Mock AI 模式（离线开发）
- Max Tokens 配置
- 京东联盟参数配置（subUnionId、pid）

**配置存储**:
- 使用 Hive Box: `settings`
- 所有配置项持久化存储
- 支持配置验证和重置

#### 4.5.3 UserSettingsPage 设计

**核心功能**:
- 主题设置（深色模式）
- 外观偏好设置
- 应用信息展示

### 4.10 核心服务模块 (Core Services)

#### 4.6.1 ApiClient 设计

**位置**: `lib/core/api_client.dart`

**核心职责**:
- 统一 HTTP 请求封装
- 错误处理和重试机制
- 超时配置（支持流式响应）

**关键特性**:
- 连接超时：30 秒
- 接收超时：5 分钟（支持流式响应）
- 支持 GET、POST 请求
- 支持自定义 headers 和 responseType

#### 4.6.2 Config 设计

**位置**: `lib/core/config.dart`

**核心职责**:
- 全局配置管理
- 环境变量读取
- 默认值配置

**配置项**:
- 淘宝联盟配置（App Key、App Secret、Adzone ID）
- 京东联盟配置（App Key、App Secret、Union ID）
- 拼多多配置（Client ID、Client Secret、PID）
- OpenAI API Key（可选）

#### 4.6.3 PriceRefreshService 设计

**位置**: `lib/services/price_refresh_service.dart`

**核心职责**:
- 后台自动刷新购物车商品价格
- 价格变化检测
- 价格变化通知

**刷新策略**:
- 单例模式，防止重复执行
- 遍历购物车所有商品
- 按平台调用对应服务获取最新价格
- 对比价格变化，触发通知

**技术特性**:
- 异步执行，不阻塞 UI
- 错误处理和日志记录
- 支持扩展新平台

#### 4.6.4 NotificationService 设计

**位置**: `lib/services/notification_service.dart`

**核心职责**:
- 跨平台本地通知
- 价格变化通知
- 系统通知集成

**平台支持**:
- Android: FlutterLocalNotificationsPlugin
- iOS/macOS: Darwin 通知
- Linux: Linux 通知
- Windows: WindowsNotification（需要 App ID）

**通知类型**:
- 价格降价通知
- 系统消息通知

#### 4.6.5 AiPromptService 设计

**位置**: `lib/services/ai_prompt_service.dart`

**核心职责**:
- AI Prompt 构建
- 消息格式化
- 上下文管理

**功能特性**:
- 支持系统消息、用户消息、助手消息
- 可配置 Prompt 嵌入
- 支持会话标题生成指令

### 4.7 主题模块 (Theme Module)

#### 4.7.1 模块结构

```
core/theme/
├── app_theme.dart          # 主题配置
└── theme_provider.dart     # 主题状态管理
```

#### 4.7.2 ThemeProvider 设计

**核心职责**:
- 主题模式管理（Light、Dark、System）
- 主题状态持久化
- 主题切换

**状态管理**:
- 使用 Riverpod StateNotifierProvider
- 状态持久化到 Hive
- 支持系统主题跟随

#### 4.7.3 AppTheme 设计

**核心职责**:
- Material Design 3 主题配置
- 浅色主题定义
- 深色主题定义
- 颜色方案配置

**设计特性**:
- 遵循 Material Design 3 规范
- 支持动态颜色（Dynamic Color）
- 中文字体支持（Noto Sans SC）

### 4.8 通用组件模块 (Widgets Module)

#### 4.8.1 ProductCard 设计

**位置**: `lib/widgets/product_card.dart`

**核心职责**:
- 商品信息展示
- 商品卡片 UI
- 商品操作（加入购物车、查看详情）

**显示内容**:
- 商品图片
- 商品标题
- 价格信息（原价、现价、优惠券）
- 销量、评分
- 店铺名称
- 操作按钮

#### 4.8.2 LoadingIndicator 设计

**位置**: `lib/widgets/loading_indicator.dart`

**核心职责**:
- 加载状态指示器
- 统一的加载 UI
- 加载动画

---

## 5. 状态管理架构

### 5.1 Riverpod 架构设计

#### 5.1.1 Provider 类型

**StateNotifierProvider**:
- 用于复杂状态管理
- 支持状态变更通知
- 示例：ThemeProvider、CartProviders

**FutureProvider**:
- 用于异步数据加载
- 自动处理加载状态
- 示例：商品列表加载

**StreamProvider**:
- 用于流式数据
- 实时数据更新
- 示例：AI 流式回复

**StateProvider**:
- 用于简单状态
- 轻量级状态管理
- 示例：UI 状态标志

#### 5.1.2 Provider 组织方式

**按功能模块组织**:
- `chat_providers.dart`: 聊天相关状态
- `cart_providers.dart`: 购物车相关状态
- `theme_provider.dart`: 主题状态

**命名规范**:
- Provider 名称：`{feature}Provider`
- 示例：`currentConversationProvider`、`cartItemsProvider`

### 5.2 状态管理流程

#### 5.2.1 状态读取

```
Widget → ref.watch(provider) → Provider → State
```

#### 5.2.2 状态更新

```
Widget → ref.read(provider.notifier) → StateNotifier → State 更新 → UI 重建
```

#### 5.2.3 状态持久化

```
Provider → Service → Hive → 持久化存储
```

### 5.3 状态依赖关系

#### 5.3.1 Provider 依赖

- `cartItemsProvider` 依赖 `CartService`
- `currentConversationProvider` 依赖 `ChatService`
- `themeProvider` 依赖 Hive 存储

#### 5.3.2 状态同步

- 购物车状态与 Hive 存储同步
- 会话状态与 Hive 存储同步
- 主题状态与 Hive 存储同步

---

## 6. 数据流设计

### 6.1 用户交互数据流

#### 6.1.1 AI 聊天数据流

```
用户输入
  ↓
ChatPage (UI)
  ↓
ChatProviders (State)
  ↓
ChatService (Business Logic)
  ↓
ApiClient (Network)
  ↓
后端/OpenAI API
  ↓
流式响应返回
  ↓
ChatService 解析
  ↓
ChatProviders 更新状态
  ↓
ChatPage 实时显示
```

#### 6.1.2 商品搜索数据流

```
用户输入关键词
  ↓
ProductService.searchProducts()
  ↓
并行调用 Adapters
  ├── TaobaoAdapter.search()
  ├── JdAdapter.search()
  └── PddAdapter.search()
  ↓
各平台 API 调用
  ↓
数据转换为 ProductModel
  ↓
结果合并和去重
  ↓
返回统一商品列表
  ↓
UI 展示
```

#### 6.1.3 推广链接生成数据流

```
用户请求推广链接
  ↓
ProductService.generatePromotionLink()
  ↓
检查缓存（内存 + Hive）
  ├── 命中 → 直接返回
  └── 未命中 → 继续
  ↓
ApiClient.post('/sign/{platform}')
  ↓
后端处理签名和转链
  ↓
返回推广链接
  ↓
缓存（30 分钟有效期）
  ↓
返回给用户
```

#### 6.1.4 购物车操作数据流

```
用户操作（添加/删除/更新）
  ↓
CartPage (UI)
  ↓
CartProviders (State)
  ↓
CartService (Business Logic)
  ↓
Hive 存储更新
  ↓
CartProviders 状态更新
  ↓
CartPage UI 刷新
```

### 6.2 后台服务数据流

#### 6.2.1 价格刷新数据流

```
PriceRefreshService 启动
  ↓
读取购物车所有商品
  ↓
按平台分组
  ↓
调用对应平台 API 获取最新价格
  ↓
对比价格变化
  ├── 价格下降 → 触发通知
  └── 价格未变 → 更新缓存
  ↓
更新 Hive 存储
  ↓
通知 UI 更新（通过 Provider）
```

### 6.3 数据持久化流程

#### 6.3.1 会话数据持久化

```
ConversationRepository
  ↓
Hive Box: 'conversations'
  ↓
自动保存（每次消息后）
```

#### 6.3.2 购物车数据持久化

```
CartService
  ↓
Hive Box: 'cart_box'
  ↓
实时保存（每次操作后）
```

#### 6.3.3 设置数据持久化

```
Settings Page
  ↓
Hive Box: 'settings'
  ↓
保存时持久化
```

---

## 7. UI 架构设计

### 7.1 Material Design 3

#### 7.1.1 设计系统

**颜色方案**:
- Primary Color: 主色调
- Secondary Color: 次要色调
- Surface Color: 表面颜色
- Error Color: 错误颜色

**组件库**:
- Material 3 组件
- 自定义组件扩展
- 响应式布局组件

#### 7.1.2 响应式设计

**断点策略**:
- 桌面端：宽度 > 800px，使用 NavigationRail
- 移动端：宽度 ≤ 800px，使用 BottomNavigationBar

**布局适配**:
- 使用 LayoutBuilder 检测屏幕尺寸
- 动态切换导航组件
- 内容区域自适应

#### 7.1.3 深色模式支持

**实现方式**:
- 使用 ThemeProvider 管理主题模式
- 支持 Light、Dark、System 三种模式
- 主题状态持久化到 Hive

**主题切换**:
- 系统级主题跟随
- 手动切换主题
- 实时预览效果

### 7.2 页面组件设计

#### 7.2.1 ChatPage

**布局结构**:
- 顶部：会话标题和切换按钮
- 中间：消息列表（可滚动）
- 底部：输入框和发送按钮
- 侧边栏：会话列表（可选）

**交互设计**:
- 流式消息显示动画
- 商品卡片嵌入消息流
- 消息复制和分享
- 会话管理操作

#### 7.2.2 CartPage

**布局结构**:
- 顶部：购物车标题和操作栏
- 中间：商品列表（按店铺分组）
- 底部：结算栏（总价、批量操作）

**交互设计**:
- 商品卡片选择
- 数量调整（+/- 按钮）
- 批量选择和操作
- 价格变化高亮显示

#### 7.2.3 ProductDetailPage

**布局结构**:
- 顶部：商品图片轮播
- 中间：商品信息（标题、价格、描述）
- 底部：操作按钮（加入购物车、复制链接）

**交互设计**:
- 图片放大查看
- 价格信息展示（原价、现价、优惠券）
- 推广链接生成和复制
- 一键加入购物车
- 外部链接跳转

---

## 8. 性能优化策略

### 8.1 网络性能优化

#### 8.1.1 请求优化

**并行请求**:
- 多平台商品搜索使用 `Future.wait()` 并行执行
- 减少总等待时间
- 提升用户体验

**请求缓存**:
- 推广链接缓存（30 分钟有效期）
- 内存缓存 + Hive 持久化缓存
- 减少重复 API 调用

**超时控制**:
- 连接超时：30 秒
- 接收超时：5 分钟（支持流式响应）
- 避免长时间等待

#### 8.1.2 数据优化

**分页加载**:
- 商品列表支持分页
- 默认每页 10 条
- 按需加载更多

**数据去重**:
- 搜索结果自动去重
- 优先保留高质量结果（京东优先）
- 减少重复数据展示

### 8.2 UI 性能优化

#### 8.2.1 渲染优化

**流式渲染**:
- AI 回复流式显示
- 实时更新 UI
- 提升响应速度感知

**列表优化**:
- 使用 `ListView.builder` 懒加载
- 虚拟滚动，只渲染可见项
- 减少内存占用

**图片优化**:
- 图片懒加载
- 使用缓存机制
- 压缩图片资源

#### 8.2.2 状态管理优化

**选择性更新**:
- 使用 `ref.watch()` 精确监听状态
- 避免不必要的 UI 重建
- 提升渲染性能

**状态缓存**:
- Provider 自动缓存
- 减少重复计算
- 优化状态读取

### 8.3 存储性能优化

#### 8.3.1 Hive 优化

**索引优化**:
- 为常用查询字段建立索引
- 提升查询速度

**数据清理**:
- 定期清理过期缓存
- 删除无用数据
- 控制存储大小

**批量操作**:
- 批量写入数据
- 减少 I/O 操作
- 提升存储性能

### 8.4 启动性能优化

#### 8.4.1 初始化优化

**异步初始化**:
- 后台服务异步启动
- 不阻塞 UI 渲染
- 快速显示首屏

**延迟加载**:
- 非关键功能延迟加载
- 按需初始化服务
- 减少启动时间

---

## 9. 错误处理

### 9.1 网络错误处理

#### 9.1.1 错误类型

**连接错误**:
- 网络不可用
- 连接超时
- DNS 解析失败

**HTTP 错误**:
- 4xx 客户端错误（401、404、429 等）
- 5xx 服务器错误（500、502、503 等）

**处理策略**:
- 显示友好的错误提示
- 提供重试机制
- 记录错误日志

#### 9.1.2 错误提示

**用户友好提示**:
- "网络连接失败，请检查网络设置"
- "请求过多，请稍后重试"（429 错误）
- "API Key 无效，请检查配置"（401 错误）
- "服务器错误，请稍后重试"（500 错误）

### 9.2 数据错误处理

#### 9.2.1 数据解析错误

**处理方式**:
- 使用 try-catch 包裹解析逻辑
- 提供默认值或跳过错误数据
- 记录错误日志便于调试

#### 9.2.2 数据验证

**验证规则**:
- 验证 API 响应格式
- 验证数据完整性
- 处理缺失字段

### 9.3 业务逻辑错误处理

#### 9.3.1 状态错误

**处理方式**:
- 检查状态有效性
- 提供默认状态
- 状态恢复机制

#### 9.3.2 用户操作错误

**处理方式**:
- 输入验证
- 操作确认
- 错误提示和引导

### 9.4 错误日志

#### 9.4.1 日志记录

**记录内容**:
- 错误类型和消息
- 错误堆栈信息
- 上下文信息（用户操作、状态等）

**日志级别**:
- Debug: 开发调试信息
- Info: 正常操作信息
- Warning: 警告信息
- Error: 错误信息

---

## 10. 测试策略

### 10.1 单元测试

#### 10.1.1 Service 层测试

**测试范围**:
- ChatService 业务逻辑
- ProductService 搜索和缓存
- CartService 数据管理
- 各 Adapter 数据转换

**测试工具**:
- `flutter_test` 框架
- Mock 对象模拟依赖

**测试示例**:
- 测试商品搜索功能
- 测试推广链接缓存
- 测试购物车操作

#### 10.1.2 工具函数测试

**测试范围**:
- 数据转换函数
- 工具类方法
- 验证逻辑

### 10.2 Widget 测试

#### 10.2.1 组件测试

**测试范围**:
- 主要页面组件（ChatPage、CartPage、SettingsPage）
- 通用组件（ProductCard、LoadingIndicator）
- 交互逻辑验证

**测试工具**:
- `flutter_test` Widget 测试框架
- `WidgetTester` 模拟用户交互

**测试示例**:
- 测试页面渲染
- 测试用户交互
- 测试状态更新

#### 10.2.2 集成测试

**测试范围**:
- 完整用户流程
- API 集成
- 数据持久化

**测试场景**:
- 用户搜索商品 → 查看详情 → 加入购物车 → 生成推广链接
- AI 对话 → 商品推荐 → 添加商品到购物车
- 购物车操作 → 价格刷新 → 通知触发

### 10.3 测试覆盖率目标

**覆盖率要求**:
- 单元测试：> 60%
- Widget 测试：主要页面组件
- 集成测试：核心流程 100%

**测试环境**:
- 开发环境：使用 Mock 数据
- CI/CD 环境：自动化测试执行

---

## 11. 扩展性设计

### 11.1 新平台接入

#### 11.1.1 Adapter 模式扩展

**扩展步骤**:
1. 创建新的 Adapter 类（如 `NewPlatformAdapter`）
2. 实现统一的搜索接口
3. 在 `ProductService` 中集成新 Adapter
4. 添加平台标识和配置

**设计优势**:
- 统一接口，易于扩展
- 不影响现有代码
- 符合开闭原则

#### 11.1.2 平台配置扩展

**配置管理**:
- 在 `Config` 类中添加新平台配置
- 支持环境变量配置
- 管理员设置页面扩展

### 11.2 新功能模块扩展

#### 11.2.1 模块化设计

**扩展方式**:
- 在 `features/` 目录下创建新模块
- 遵循现有架构模式
- 最小化对现有代码的影响

**模块结构**:
```
features/new_feature/
├── new_feature_service.dart
├── new_feature_providers.dart
└── new_feature_page.dart
```

#### 11.2.2 状态管理扩展

**Provider 扩展**:
- 创建新的 Provider 文件
- 遵循命名规范
- 与现有 Provider 解耦

### 11.3 UI 组件扩展

#### 11.3.1 通用组件扩展

**扩展方式**:
- 在 `widgets/` 目录下添加新组件
- 遵循 Material Design 3 规范
- 支持主题和响应式

#### 11.3.2 页面扩展

**扩展方式**:
- 在 `screens/` 目录下添加新页面
- 使用统一的导航方式
- 支持响应式布局

### 11.4 性能扩展

#### 11.4.1 缓存策略扩展

**扩展方式**:
- 添加新的缓存类型
- 实现统一的缓存接口
- 支持缓存失效策略

#### 11.4.2 数据优化扩展

**扩展方式**:
- 实现数据压缩
- 添加数据预加载
- 优化数据序列化

---

## 12. 数据存储架构

### 12.1 Hive 存储设计

#### 12.1.1 Box 组织

**存储 Boxes**:
- `settings`: 应用设置
- `cart_box`: 购物车数据
- `conversations`: 会话历史
- `promo_cache`: 推广链接缓存

#### 12.1.2 数据模型

**序列化支持**:
- 使用 Hive 注解（@HiveType、@HiveField）
- 支持类型安全
- 支持版本迁移

**数据格式**:
- 简单类型：String、int、double、bool
- 复杂类型：Map、List
- 自定义类型：ProductModel 等

### 12.2 存储策略

#### 12.2.1 持久化策略

**实时保存**:
- 购物车操作立即保存
- 会话消息自动保存
- 设置变更立即保存

**批量保存**:
- 大量数据批量写入
- 减少 I/O 操作
- 提升性能

#### 12.2.2 缓存策略

**内存缓存**:
- 推广链接内存缓存
- 快速访问
- 临时存储

**持久化缓存**:
- Hive 持久化缓存
- 应用重启后保留
- 长期存储

### 12.3 数据迁移

#### 12.3.1 版本管理

**版本控制**:
- Hive Adapter 版本号
- 支持数据迁移
- 向后兼容

#### 12.3.2 迁移策略

**迁移方式**:
- 自动迁移旧数据
- 保持数据完整性
- 错误处理

---

## 13. 安全架构

### 13.1 数据安全

#### 13.1.1 API Key 保护

**存储方式**:
- 本地 Hive 存储
- 不提交到版本控制
- 用户自行保管

**访问控制**:
- 管理员入口密码验证
- 配置访问权限控制

#### 13.1.2 敏感数据保护

**保护策略**:
- 本地存储，不涉及云端
- 用户可随时清除数据
- 不收集用户个人信息

### 13.2 网络安全

#### 13.2.1 HTTPS 通信

**要求**:
- 生产环境使用 HTTPS
- API 调用使用 HTTPS
- 保护数据传输安全

#### 13.2.2 请求安全

**安全措施**:
- API Key 通过 Header 传递
- 后端代理保护密钥
- 请求签名验证（后端处理）

### 13.3 应用安全

#### 13.3.1 管理员验证

**验证方式**:
- 密码哈希验证（SHA-256）
- 7 次点击"关于"触发
- 本地验证，不涉及网络

#### 13.3.2 输入验证

**验证规则**:
- 用户输入验证
- 防止恶意输入
- 错误提示和引导

---

## 14. 总结

### 14.1 架构特点

快淘帮 WisePick 前端架构具有以下特点：

1. **分层清晰**: UI 层、状态管理层、业务逻辑层、数据访问层职责明确
2. **模块化设计**: 功能模块化，易于维护和扩展
3. **状态管理**: 使用 Riverpod 实现响应式状态管理
4. **跨平台支持**: Flutter 实现一套代码多平台运行
5. **本地优先**: 数据本地存储，保护用户隐私
6. **性能优化**: 多层次的性能优化策略

### 14.2 技术优势

- **开发效率**: 跨平台开发，减少重复工作
- **性能优秀**: Flutter 高性能渲染，Hive 快速存储
- **易于维护**: 清晰的架构分层，模块化设计
- **扩展性强**: Adapter 模式支持新平台快速接入
- **用户体验**: 流式响应、响应式布局、深色模式

### 14.3 适用场景

本架构适用于：
- 跨平台应用开发
- 多数据源聚合应用
- 需要本地数据存储的应用
- 需要实时交互的应用

### 14.4 后续工作

1. **完善测试**: 提升测试覆盖率
2. **性能优化**: 持续优化性能瓶颈
3. **功能扩展**: 按 PRD 规划逐步实现新功能
4. **文档完善**: 保持文档与代码同步

---

## 15. 附录

### 15.1 参考文档

- [PRD 文档](../PRD.md) - 产品需求文档
- [架构文档](./architecture.md) - 完整技术架构文档
- [README](../README.md) - 项目说明文档
- [Flutter 官方文档](https://docs.flutter.dev/)
- [Dart 官方文档](https://dart.dev/)
- [Riverpod 文档](https://riverpod.dev/)
- [Hive 文档](https://docs.hivedb.dev/)

### 15.2 相关工具

- **Flutter DevTools**: 开发调试工具
- **Dart Analyzer**: 代码分析工具
- **Hive Inspector**: Hive 数据查看工具
- **Riverpod Inspector**: Riverpod 状态调试工具

### 15.3 项目结构参考

```
lib/
├── core/                    # 核心功能
│   ├── api_client.dart      # API 客户端
│   ├── config.dart          # 配置管理
│   └── theme/               # 主题配置
├── features/                # 功能模块
│   ├── chat/                # 聊天功能
│   ├── products/            # 商品功能
│   └── cart/                # 购物车功能
├── screens/                 # 页面组件
├── services/                # 业务服务
├── widgets/                 # 通用组件
└── models/                  # 数据模型
```

### 15.4 变更日志

| 版本 | 日期 | 变更内容 | 作者 |
|------|------|----------|------|
| 2.0 | 2026-01-22 | 新增数据分析、价格历史、购物决策、管理员后台模块架构说明 | Winston (Architect) |
| 1.0 | 2024 | 初始前端架构文档 | CHYINAN (Architect) |

---

**文档维护者**: 架构团队  
**审核者**: 技术团队  
**批准者**: 技术负责人

---

*本文档基于项目实际代码和 PRD 需求编写，反映了当前前端系统的真实架构状态。*
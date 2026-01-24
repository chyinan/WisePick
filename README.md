# 快淘帮 WisePick

<div align="center">

![Version](https://img.shields.io/badge/version-1.1.0-blue.svg)
![Flutter](https://img.shields.io/badge/Flutter-3.9.2+-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.9.2+-0175C2?logo=dart)
![License](https://img.shields.io/badge/license-MIT-green.svg)
<br><br>
<img src="logo.png" width="200" alt="WisePick LOGO"/>
<br><br>
<img src="screenshot.png" width="800" alt="WisePick Screenshot"/>

**基于 AI 的智能购物推荐应用**

通过自然语言对话帮助用户在多平台（淘宝、京东、拼多多）中快速找到心仪商品

[功能特性](#-核心功能) • [快速开始](#-快速开始) • [技术架构](#-技术架构) • [配置说明](#-配置说明)

</div>

---

## 📖 项目简介

快淘帮 WisePick 是一款基于 AI 的智能购物推荐应用，通过自然语言对话帮助用户在多平台（淘宝、京东、拼多多）中快速找到心仪商品，并提供推广链接生成、购物车管理等一站式购物辅助服务。

### 核心价值

- 🤖 **智能推荐**: 基于 AI 理解用户需求，提供个性化商品推荐
- 🔍 **多平台聚合**: 统一搜索淘宝、京东、拼多多三大电商平台
- 🔗 **推广链接**: 自动生成联盟推广链接，支持佣金收益
- 🛒 **选品管理**: 提供购物车功能，方便用户收藏和比价
- 💰 **价格监控**: 自动刷新商品价格，降价时及时通知
- 📊 **价格历史**: 记录商品价格变化历史，提供趋势分析和购买时机建议
- ⚖️ **商品比价**: 多商品对比功能，智能评分系统，帮助做出最佳购买决策
- 🕷️ **高级爬虫**: 内置京东联盟高级网页爬虫，模拟人类行为，规避风控
- 👤 **用户账号**: 支持邮箱注册登录，多设备管理
- ☁️ **云端同步**: 购物车和会话记录自动云端同步，多端无缝切换
- 🎛️ **独立管理后台**: 独立的管理员后台应用，提供用户管理、数据统计、系统监控等功能

---

## ✨ 核心功能

### 1. AI 助手聊天
- 自然语言对话，理解用户购物需求
- 流式响应，实时显示 AI 回复
- 智能识别用户意图（推荐请求 vs 普通问答）
- 支持结构化 JSON 推荐和自然语言回复
- 会话历史管理，支持多会话切换

### 2. 多平台商品搜索
- 支持淘宝、京东、拼多多三大平台
- 并行搜索，统一展示结果
- 搜索结果去重和合并（优先显示京东结果）
- 支持分页加载和平台筛选
- **智能搜索增强**: 自动生成搜索候选词，提升匹配准确度

### 3. 购物车管理
- 商品添加/删除，按店铺分组显示
- 商品数量调整，批量选择/取消选择
- 价格自动刷新（支持官方 API 和高级爬虫两种模式）
- 价格变化通知
- 批量复制推广链接

### 4. 价格历史功能
- **自动记录**: 商品加入购物车时自动记录初始价格，价格刷新时记录变化
- **价格趋势分析**: 提供价格走势图表，显示最高价、最低价、平均价
- **趋势判断**: 自动分析价格趋势（上涨/下跌/稳定），计算价格波动率
- **购买时机建议**: 基于历史价格数据，智能推荐最佳购买时机
- **多商品价格对比**: 支持同时对比多个商品的价格历史
- **时间范围筛选**: 支持查看近一周、近一月、近三月、近一年的价格历史

### 5. 商品比价功能
- **多商品对比**: 支持同时对比多个商品的详细信息
- **智能评分系统**: 基于价格、评分、销量、平台等多维度综合评分（0-100分）
- **对比维度**: 价格、原价、折扣率、评分、销量、店铺、规格参数等
- **推荐商品**: 自动推荐综合评分最高的商品
- **替代商品推荐**: 基于商品类别和价格区间推荐相似商品
- **可视化对比**: 清晰的对比表格，高亮显示最优和最差项

### 6. 推广链接生成
- 自动生成联盟推广链接（淘宝、京东、拼多多）
- 链接缓存机制（30 分钟有效期）
- 支持复制链接和口令（tpwd）

### 7. 京东联盟高级爬虫
- **模拟人类行为**: 贝塞尔曲线鼠标移动、随机滚动、模拟输入延迟
- **反检测机制**: Stealth 模式、指纹随机化
- **Cookie 管理**: 自动检测过期、支持手动登录刷新
- **并发控制**: 浏览器池管理，平衡性能与风险

### 8. 用户账号系统
- 邮箱注册与登录
- JWT Token 认证（Access Token + Refresh Token）
- 多设备登录管理
- 安全的密码加密存储（bcrypt）
- 个人资料编辑（昵称、头像）

### 9. 云端数据同步
- **购物车数据同步**: 多端购物车数据实时同步，支持增量更新
- **会话历史同步**: AI 聊天会话记录云端备份，多设备无缝切换
- **增量同步机制**: 基于版本号的增量同步，减少数据传输量
- **冲突检测与解决**: 自动检测数据冲突，采用"Last Write Wins"策略解决
- **离线支持**: 支持离线使用，变更自动保存到本地队列，联网后自动同步
- **同步状态显示**: 实时显示同步状态（同步中/成功/失败/离线）
- **自动同步**: 数据变更后自动触发同步，支持防抖机制避免频繁请求
- **版本管理**: 每个数据项都有版本号，确保数据一致性

### 10. 管理员功能

#### 9.1. 应用内管理员设置
- OpenAI API Key 配置
- 后端代理地址配置
- AI 模型选择
- 调试模式和 Mock AI 模式
- 京东爬虫参数配置（Cookie、并发数等）

#### 9.2. 独立管理员后台（wisepick_admin）
独立的 Web 管理后台应用，提供完整的管理功能：

**用户管理**
- 用户列表查看和搜索
- 用户信息编辑（昵称、邮箱、角色等）
- 用户删除和批量操作
- 用户注册时间、最后登录时间统计

**数据统计**
- 用户统计：总用户数、活跃用户数、新增用户趋势
- 购物车统计：总商品数、商品分布、热门商品
- 会话统计：总会话数、消息数、活跃度分析
- 搜索热词统计：热门搜索关键词排行

**系统监控**
- 系统健康状态监控
- API 调用统计
- 错误日志查看
- 性能指标监控

**数据管理**
- 购物车数据查看和管理
- 会话记录查看和删除
- 登录设备管理
- 数据导出功能

**系统设置**
- 系统参数配置
- 安全设置
- 数据备份和恢复

---

## 🚀 快速开始

### 前置条件

- **Flutter SDK**: 3.9.2 或更高版本
- **Dart SDK**: 3.9.2 或更高版本
- **Git**: 用于版本控制
- **IDE**: 推荐使用 VS Code 或 Android Studio（安装 Flutter 插件）

### 安装步骤

1. **克隆仓库**
   ```bash
   git clone <your-repo-url>
   cd wisepick_dart_version
   ```

2. **安装依赖**
   ```bash
   flutter pub get
   ```

3. **运行应用**
   ```bash
   # 桌面端（Windows/macOS/Linux）
   flutter run -d windows
   flutter run -d macos
   flutter run -d linux
   
   # 移动端（Android/iOS）
   flutter run -d android
   flutter run -d ios
   
   # Web
   flutter run -d chrome
   ```

### 构建发布版本

```bash
# 桌面端
flutter build windows
flutter build macos
flutter build linux

# 移动端
flutter build apk --release        # Android APK
flutter build ios --release         # iOS
flutter build web --release         # Web
```

### 启动管理员后台

管理员后台是一个独立的 Web 应用，提供完整的管理功能：

1. **进入管理员后台目录**
   ```bash
   cd wisepick_admin
   ```

2. **安装依赖**
   ```bash
   flutter pub get
   ```

3. **运行管理员后台**
   ```bash
   # Web 模式（推荐）
   flutter run -d chrome
   
   # 或构建 Web 版本
   flutter build web --release
   ```

4. **访问管理员后台**
   - 开发模式：`http://localhost:端口号`
   - 生产模式：部署构建后的 `build/web` 目录到 Web 服务器

**注意**: 管理员后台需要后端服务运行，并配置正确的 API 地址。

---

## 🏗️ 技术架构

### 前端技术栈

- **框架**: Flutter 3.9.2+
- **语言**: Dart 3.9.2+
- **状态管理**: Riverpod 2.5.1
- **本地存储**: Hive 2.2.3
- **网络请求**: Dio 5.1.2
- **UI 组件**: Material Design 3
- **字体**: Noto Sans SC（中文字体支持）

### 后端技术栈

- **语言**: Dart
- **框架**: Shelf
- **数据库**: PostgreSQL（用户账号和同步数据存储）
- **认证**: JWT（Access Token + Refresh Token）
- **浏览器自动化**: Playwright (用于京东高级爬虫)
- **功能**: 代理服务器、API 签名、转链、高级网页抓取、用户认证、数据同步

### 项目结构

```
wisepick_dart_version/
├── lib/                      # Flutter 应用源码
│   ├── core/                 # 核心功能（API 客户端、配置、OAuth）
│   ├── features/             # 功能模块
│   │   ├── auth/             # 用户认证（登录、注册、Token管理）
│   │   ├── chat/             # AI 聊天
│   │   ├── cart/             # 购物车
│   │   ├── products/         # 商品搜索
│   │   ├── price_history/    # 价格历史（记录、趋势分析、购买建议）
│   │   ├── decision/         # 商品比价（对比、评分、推荐）
│   │   └── admin/            # 管理员功能（应用内设置）
│   ├── screens/              # 页面组件
│   ├── services/             # 业务服务
│   │   ├── sync/             # 数据同步（购物车、会话）
│   │   └── price_refresh_service.dart  # 价格刷新服务
│   ├── widgets/              # 通用组件
│   └── models/               # 数据模型
├── server/                   # 后端代理服务
│   ├── bin/
│   │   ├── proxy_server.dart # 代理服务器入口
│   │   └── .env              # 环境变量配置
│   ├── lib/
│   │   ├── auth/             # 用户认证模块（JWT、中间件）
│   │   ├── sync/             # 数据同步服务
│   │   ├── db/               # 数据库连接
│   │   ├── jd_scraper/       # 京东高级爬虫模块
│   │   ├── admin/            # 管理员后台 API
│   │   ├── price_history/    # 价格历史服务
│   │   └── decision/         # 商品比价服务
│   └── pubspec.yaml
├── wisepick_admin/           # 独立管理员后台应用（Web）
│   ├── lib/
│   │   ├── features/
│   │   │   ├── dashboard/    # 数据概览
│   │   │   ├── users/        # 用户管理
│   │   │   ├── cart/         # 购物车数据管理
│   │   │   ├── conversations/# 会话记录管理
│   │   │   └── settings/     # 系统设置
│   │   └── core/
│   │       └── api_client.dart  # API 客户端
│   └── pubspec.yaml
├── test/                     # 测试文件
├── assets/                   # 资源文件
└── pubspec.yaml              # 项目配置
```

---

## ⚙️ 配置说明

### 前端配置

应用支持通过管理员设置页面配置以下选项：

- **OpenAI API Key**: 用于直接调用 OpenAI API（可选，也可通过后端代理）
- **后端代理地址**: 后端服务器地址（默认: `http://localhost:9527`）
- **AI 模型**: 选择使用的 AI 模型（默认: `gpt-3.5-turbo`）
- **Max Tokens**: 限制 AI 回复的最大 token 数（可选: unlimited/300/800/1000/2000）
- **Prompt 嵌入**: 是否启用增强的 Prompt（默认: 开启）
- **调试模式**: 显示原始 JSON 响应（默认: 关闭）
- **Mock AI**: 使用模拟 AI 响应（用于离线开发，默认: 关闭）

### 后端配置

后端代理服务器需要配置以下环境变量（通过 `.env` 文件或系统环境变量）：

#### 必需配置

- `ADMIN_PASSWORD`: 管理员密码（用于后台设置入口验证）

#### 数据库配置（用户账号和云端同步）

- `DB_HOST`: PostgreSQL 数据库主机（默认: `localhost`）
- `DB_PORT`: 数据库端口（默认: `5432`）
- `DB_NAME`: 数据库名称（默认: `wisepick`）
- `DB_USER`: 数据库用户名（默认: `postgres`）
- `DB_PASSWORD`: 数据库密码

#### JWT 认证配置

- `JWT_SECRET`: Access Token 签名密钥（必需，建议使用随机字符串）
- `JWT_REFRESH_SECRET`: Refresh Token 签名密钥（必需，建议使用随机字符串）

#### 可选配置（按需）

**淘宝联盟**
- `TAOBAO_APP_SECRET`: 淘宝应用密钥（使用官方淘宝签名/SDK 时需要）

**京东联盟**
- `JD_APP_KEY`: 京东应用 Key
- `JD_APP_SECRET`: 京东联盟密钥
- `JD_UNION_ID`: 京东联盟 ID

**拼多多**
- `PDD_CLIENT_ID`: 拼多多客户端 ID
- `PDD_CLIENT_SECRET`: 拼多多客户端密钥
- `PDD_PID`: 拼多多推广位 ID

**服务器配置**
- `PORT`: 服务器端口（默认: 9527）

### 启动后端服务

1. **安装 PostgreSQL**
   
   下载并安装 PostgreSQL 数据库：https://www.postgresql.org/download/
   
   创建数据库：
   ```sql
   CREATE DATABASE wisepick;
   ```
   
   > 注意：首次启动服务时会自动创建所需的表结构。

2. **进入服务器目录**
   ```bash
   cd server
   ```

3. **安装依赖**
   ```bash
   dart pub get
   ```

4. **配置环境变量**
   
   创建 `server/bin/.env` 文件（或使用系统环境变量）：
   ```bash
   # 数据库配置
   DB_HOST=localhost
   DB_PORT=5432
   DB_NAME=wisepick
   DB_USER=postgres
   DB_PASSWORD=your_db_password
   
   # JWT 认证配置
   JWT_SECRET=your-jwt-secret-random-string
   JWT_REFRESH_SECRET=your-refresh-secret-random-string
   
   # 电商联盟配置（可选）
   TAOBAO_APP_SECRET=your_taobao_secret
   JD_APP_SECRET=your_jd_secret
   JD_APP_KEY=your_jd_app_key
   JD_UNION_ID=your_jd_union_id
   PDD_CLIENT_ID=your_pdd_client_id
   PDD_CLIENT_SECRET=your_pdd_client_secret
   PDD_PID=your_pdd_pid
   
   # 其他配置
   ADMIN_PASSWORD=your_admin_password
   PORT=9527
   ```

5. **启动服务**
   ```bash
   dart run bin/proxy_server.dart
   ```
   
   服务启动后，会在终端提示未配置项（交互式启动）。配置会保存到 `server/.env` 文件中。

   **注意**: `.env` 文件可能包含密钥，请勿提交到版本控制（推荐将其加入 `.gitignore`）。

### 后端 API 端点

后端提供以下 API 端点：

- `POST /v1/chat/completions`: OpenAI API 代理转发（支持流式响应）
- `POST /sign/taobao`: 淘宝联盟签名和转链
- `POST /taobao/convert`: 淘宝链接转换
- `POST /sign/jd`: 京东联盟签名
- `POST /jd/union/promotion/bysubunionid`: 京东联盟推广链接生成
- `POST /jd/product`: 获取单个商品信息（通过爬虫）
- `POST /jd/products/batch`: 批量获取商品信息（通过爬虫）
- `GET /jd/cookie/status`: 检查爬虫 Cookie 状态
- `POST /jd/cookie/update`: 更新爬虫 Cookie
- `POST /jd/cookie/refresh`: 触发手动登录刷新 Cookie
- `POST /sign/pdd`: 拼多多推广链接生成
- `POST /admin/login`: 管理员登录验证

#### 用户认证 API

- `POST /api/v1/auth/register`: 用户注册（邮箱、密码）
- `POST /api/v1/auth/login`: 用户登录（返回 Access Token 和 Refresh Token）
- `POST /api/v1/auth/refresh`: 刷新 Access Token
- `POST /api/v1/auth/logout`: 退出登录（使当前 Token 失效）
- `POST /api/v1/auth/logout-all`: 退出所有设备
- `GET /api/v1/auth/me`: 获取当前用户信息
- `PUT /api/v1/auth/profile`: 更新用户资料
- `PUT /api/v1/auth/password`: 修改密码
- `GET /api/v1/auth/sessions`: 获取登录设备列表

#### 数据同步 API

- `POST /api/v1/sync/cart/pull`: 拉取购物车数据（增量同步）
- `POST /api/v1/sync/cart/push`: 推送购物车数据
- `POST /api/v1/sync/cart/sync`: 双向同步购物车数据（推荐使用）
- `GET /api/v1/sync/cart/version`: 获取购物车当前版本号
- `POST /api/v1/sync/conversations/pull`: 拉取会话数据
- `POST /api/v1/sync/conversations/push`: 推送会话数据
- `POST /api/v1/sync/conversations/sync`: 双向同步会话数据（推荐使用）
- `GET /api/v1/sync/conversations/version`: 获取会话当前版本号

#### 价格历史 API

- `GET /api/v1/price-history/<productId>`: 获取商品价格历史
- `POST /api/v1/price-history/batch`: 批量获取多个商品的价格历史

#### 商品比价 API

- `POST /api/v1/decision/compare`: 商品对比分析
- `POST /api/v1/decision/score`: 计算商品购买决策评分
- `POST /api/v1/decision/alternatives`: 获取替代商品推荐

#### 管理员后台 API

- `GET /api/v1/admin/users/stats`: 获取用户统计数据
- `GET /api/v1/admin/system/stats`: 获取系统监控数据
- `GET /api/v1/admin/recent-users`: 获取最近注册用户
- `GET /api/v1/admin/activity-chart`: 获取用户活跃度图表数据
- `GET /api/v1/admin/users`: 获取用户列表
- `DELETE /api/v1/admin/users/<id>`: 删除用户
- `PUT /api/v1/admin/users/<id>`: 更新用户信息
- `GET /api/v1/admin/cart-items`: 获取购物车数据列表
- `GET /api/v1/admin/cart-items/stats`: 获取购物车统计
- `DELETE /api/v1/admin/cart-items/<id>`: 删除购物车商品
- `GET /api/v1/admin/conversations`: 获取会话列表
- `GET /api/v1/admin/conversations/<id>/messages`: 获取会话消息
- `DELETE /api/v1/admin/conversations/<id>`: 删除会话
- `GET /api/v1/admin/settings`: 获取系统设置
- `PUT /api/v1/admin/settings`: 更新系统设置
- `GET /api/v1/admin/sessions`: 获取登录设备列表
- `DELETE /api/v1/admin/sessions/<id>`: 删除登录设备

---

## 🧪 开发指南

### 运行测试

```bash
# 运行所有测试
flutter test

# 运行特定测试文件
flutter test test/chat_service_test.dart

# 生成测试覆盖率报告
flutter test --coverage
```

### 代码规范

项目遵循 Flutter/Dart 最佳实践：

- 使用 `analysis_options.yaml` 配置代码分析规则
- 遵循 Dart 官方代码风格指南
- 使用 `flutter_lints` 包进行代码检查

### 调试模式

在管理员设置页面可以启用以下调试选项：

- **调试 AI 响应**: 显示原始 JSON 响应
- **Mock AI**: 使用模拟 AI 响应（不调用真实 API）
- **显示商品 JSON**: 在商品卡片中显示原始 JSON 数据

---

## 📱 支持的平台

- ✅ **桌面端**: Windows 10+, macOS 10.14+, Linux (主流发行版)
- ✅ **移动端**: Android 5.0+, iOS 12.0+
- ✅ **Web**: Chrome 90+, Safari 14+, Firefox 88+

---

## 🤝 贡献

欢迎提交 Issue 或 Pull Request！

### 贡献流程

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

### 提交规范

请在 PR 中说明：
- 变更目的和影响范围
- 测试情况
- 相关 Issue（如有）

---

## 📄 许可证

本项目采用 MIT 许可证。详情请参阅 [LICENSE](LICENSE) 文件。

---

## 📚 相关文档

- [产品需求文档 (PRD)](PRD.md) - 完整的产品需求文档
- [Flutter 官方文档](https://docs.flutter.dev/)
- [OpenAI API 文档](https://platform.openai.com/docs)
- [淘宝联盟 API](https://open.taobao.com/)
- [京东联盟 API](https://union.jd.com/)
- [拼多多开放平台](https://open.pinduoduo.com/)

---

## 👥 作者

- **chyinan** - [GitHub](https://github.com/chyinan)

---

## 🙏 致谢

感谢所有为本项目做出贡献的开发者和用户！

---

<div align="center">

**如果这个项目对你有帮助，请给一个 ⭐ Star！**

Made with ❤️ by the Asakawa Kaede(CHYINAN)

</div>

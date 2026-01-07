# 快淘帮 WisePick

<div align="center">

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![Flutter](https://img.shields.io/badge/Flutter-3.9.2+-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.9.2+-0175C2?logo=dart)
![License](https://img.shields.io/badge/license-MIT-green.svg)

**基于 AI 的智能购物推荐应用**

通过自然语言对话帮助用户在多平台（淘宝、京东、拼多多）中快速找到心仪商品

[功能特性](#-核心功能) • [快速开始](#-快速开始) • [技术架构](#-技术架构) • [配置说明](#-配置说明)

</div>

---

## 📖 项目简介

快淘帮 WisePick 是一款基于 AI 的智能购物推荐应用，通过自然语言对话帮助用户在多平台（淘宝、京东、拼多多）中快速找到心仪商品，并提供推广链接生成、选品车管理等一站式购物辅助服务。

### 核心价值

- 🤖 **智能推荐**: 基于 AI 理解用户需求，提供个性化商品推荐
- 🔍 **多平台聚合**: 统一搜索淘宝、京东、拼多多三大电商平台
- 🔗 **推广链接**: 自动生成联盟推广链接，支持佣金收益
- 🛒 **选品管理**: 提供选品车功能，方便用户收藏和比价
- 💰 **价格监控**: 自动刷新商品价格，降价时及时通知

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

### 3. 选品车管理
- 商品添加/删除，按店铺分组显示
- 商品数量调整，批量选择/取消选择
- 价格自动刷新（后台服务）
- 价格变化通知
- 批量复制推广链接

### 4. 推广链接生成
- 自动生成联盟推广链接（淘宝、京东、拼多多）
- 链接缓存机制（30 分钟有效期）
- 支持复制链接和口令（tpwd）

### 5. 管理员设置
- OpenAI API Key 配置
- 后端代理地址配置
- AI 模型选择
- 调试模式和 Mock AI 模式

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
- **功能**: 代理服务器、API 签名、转链

### 项目结构

```
wisepick_dart_version/
├── lib/                      # Flutter 应用源码
│   ├── core/                 # 核心功能
│   │   ├── api_client.dart   # API 客户端
│   │   ├── config.dart       # 配置管理
│   │   ├── jd_oauth_service.dart
│   │   └── theme/            # 主题配置
│   ├── features/             # 功能模块
│   │   ├── chat/             # 聊天功能
│   │   ├── products/         # 商品功能
│   │   └── cart/             # 选品车功能
│   ├── screens/              # 页面组件
│   │   ├── chat_page.dart
│   │   ├── admin_settings_page.dart
│   │   └── user_settings_page.dart
│   ├── services/             # 业务服务
│   │   ├── api_service.dart
│   │   ├── chat_service.dart
│   │   └── notification_service.dart
│   ├── widgets/              # 通用组件
│   └── models/               # 数据模型
├── server/                   # 后端代理服务
│   ├── bin/
│   │   └── proxy_server.dart # 代理服务器入口
│   └── pubspec.yaml
├── test/                     # 测试文件
├── assets/                   # 资源文件
│   ├── fonts/                # 字体文件
│   └── icon/                 # 应用图标
└── pubspec.yaml              # 项目配置
```

---

## ⚙️ 配置说明

### 前端配置

应用支持通过管理员设置页面配置以下选项：

- **OpenAI API Key**: 用于直接调用 OpenAI API（可选，也可通过后端代理）
- **后端代理地址**: 后端服务器地址（默认: `http://localhost:8080`）
- **AI 模型**: 选择使用的 AI 模型（默认: `gpt-3.5-turbo`）
- **Max Tokens**: 限制 AI 回复的最大 token 数（可选: unlimited/300/800/1000/2000）
- **Prompt 嵌入**: 是否启用增强的 Prompt（默认: 开启）
- **调试模式**: 显示原始 JSON 响应（默认: 关闭）
- **Mock AI**: 使用模拟 AI 响应（用于离线开发，默认: 关闭）

### 后端配置

后端代理服务器需要配置以下环境变量（通过 `.env` 文件或系统环境变量）：

#### 必需配置

- `ADMIN_PASSWORD`: 管理员密码（用于后台设置入口验证）

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
- `PORT`: 服务器端口（默认: 8080）

### 启动后端服务

1. **进入服务器目录**
   ```bash
   cd server
   ```

2. **安装依赖**
   ```bash
   dart pub get
   ```

3. **配置环境变量**
   
   创建 `.env` 文件（或使用系统环境变量）：
   ```bash
   export TAOBAO_APP_SECRET="your_taobao_secret"
   export JD_APP_SECRET="your_jd_secret"
   export JD_APP_KEY="your_jd_app_key"
   export JD_UNION_ID="your_jd_union_id"
   export PDD_CLIENT_ID="your_pdd_client_id"
   export PDD_CLIENT_SECRET="your_pdd_client_secret"
   export PDD_PID="your_pdd_pid"
   export ADMIN_PASSWORD="your_admin_password"
   export PORT=8080
   ```

4. **启动服务**
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
- `POST /sign/pdd`: 拼多多推广链接生成
- `POST /admin/login`: 管理员登录验证

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

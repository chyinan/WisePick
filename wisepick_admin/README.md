# WisePick Admin

快淘帮管理员后台，基于 Flutter Web 构建，用于管理用户、购物车、会话数据及系统可靠性监控。

## 功能模块

- **仪表盘**：核心数据统计概览
- **用户管理**：查看和管理注册用户
- **购物车管理**：查看用户购物车数据
- **会话管理**：查看 AI 聊天会话记录
- **可靠性监控**：服务健康评分、指标图表、混沌测试控制、依赖关系图
- **系统设置**：后端配置、AI 参数调整

## 快速开始

```bash
cd wisepick_admin
flutter pub get
flutter run -d chrome
```

## 构建发布

```bash
flutter build web --release
```

## 技术栈

- Flutter Web
- Material 3（Indigo 主题）
- Google Fonts（Inter 字体）

## 后端依赖

需要后端代理服务运行在 `http://localhost:9527`，详见根目录 `server/` 下的配置说明。

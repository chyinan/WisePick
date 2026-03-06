# 快淘帮 WisePick 可视化架构图

本目录包含项目的全套架构图，使用 Mermaid 语法编写，可在以下工具中直接渲染：
- VS Code（安装 Mermaid Preview 插件）
- GitHub / GitLab（原生支持）
- Notion、Obsidian、Typora

---

## 图表目录

| 文件 | 内容 | 适用场景 |
|------|------|----------|
| [01-system-architecture.md](./01-system-architecture.md) | 系统整体架构图 | 答辩总览、技术选型说明 |
| [02-module-dependencies.md](./02-module-dependencies.md) | 功能模块依赖图 | 代码结构说明、模块化设计展示 |
| [03-data-flow.md](./03-data-flow.md) | 核心数据流图（4张） | 业务流程说明、技术实现讲解 |
| [04-resilience-infrastructure.md](./04-resilience-infrastructure.md) | 弹性基础设施工作流（4张） | 工程质量亮点、可靠性设计展示 |

---

## 各图说明

### 图1：系统整体架构
展示三层架构全貌：Flutter 客户端 → Dart/Shelf 后端代理 → 第三方服务，以及独立的管理员后台。

### 图2：功能模块依赖
展示 11 个业务模块与核心基础设施之间的依赖关系，体现模块化设计和职责分离。

### 图3：核心数据流（4张子图）
- **3a** AI 聊天推荐链路：用户输入 → 流式 AI 响应 → 商品卡片渲染
- **3b** 商品搜索链路：三平台并行搜索 → 统一 ProductModel → 去重排序
- **3c** 推广链接生成：缓存命中判断 → 平台签名 → 30分钟缓存
- **3d** 数据同步链路：离线队列 → 版本号冲突解决 → Last Write Wins

### 图4：弹性基础设施（4张子图）
- **4a** 断路器状态机：CLOSED → OPEN → HALF_OPEN 三态转换
- **4b** 重试策略与预算：错误分类 → 退避策略 → 预算控制
- **4c** 自适应配置与 SLO：指标采集 → SLO 目标 → 错误预算 → 自适应调整
- **4d** 自愈服务流程：健康检查 → 根因分析 → 自动恢复 → 混沌工程测试

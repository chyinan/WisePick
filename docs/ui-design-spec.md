# 快淘帮 WisePick - UI 设计规范文档

**版本**: 1.0  
**创建日期**: 2026-01-22  
**最后更新**: 2026-01-22  
**文档状态**: 正式版  
**设计者**: Sally (UX Expert Agent)

---

## 1. 文档概述

### 1.1 文档目的

本文档详细描述了快淘帮 WisePick 项目新增功能模块的 UI 设计规范，包括设计理念、颜色系统、响应式布局策略、组件结构、交互设计等。本文档旨在：

- 为前端开发团队提供统一的 UI 设计标准
- 确保新增功能模块的视觉和交互一致性
- 指导 UI 组件的实现和代码编写
- 为 DEV 工程师 Agent 提供详细的编码提示词

### 1.2 文档范围

本文档涵盖以下新增功能模块的 UI 设计：

- **数据分析与洞察模块**: 消费结构分析、偏好分析、购物时间分析
- **价格历史与趋势模块**: 价格曲线图、趋势分析、购买时机建议
- **购物决策助手增强模块**: 商品对比、评分系统、决策理由
- **管理员后台模块**: 数据统计面板、系统监控、搜索热词

### 1.3 架构说明

#### 1.3.1 管理员后台实现方式

**重要说明**: 管理员后台是 **独立的 Flutter Web 项目**，与主应用（快淘帮 WisePick）完全分离。

**架构关系**:
```
┌─────────────────────────────────────┐
│  快淘帮 WisePick（主应用）           │
│  ├── 普通用户功能                    │
│  ├── 数据分析模块                    │
│  ├── 价格历史模块                    │
│  └── 购物决策模块                    │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│  管理员后台（独立 Web 项目）         │
│  ├── 用户数据统计                    │
│  ├── 系统监控                        │
│  ├── 搜索热词分析                    │
│  └── 数据导出                        │
└─────────────────────────────────────┘
            │ HTTP 请求
            ▼
┌─────────────────────────────────────┐
│  后端服务（Dart Shelf）              │
│  ├── 管理 API 接口                   │
│  │   ├── /api/v1/admin/users/stats   │
│  │   ├── /api/v1/admin/system/stats  │
│  │   └── /api/v1/admin/search/...   │
│  └── 权限验证（JWT Token）           │
└─────────────────────────────────────┘
```

**项目结构**:
```
wisepick_dart_version/          # 主应用项目
├── lib/
│   └── features/
│       ├── analytics/
│       ├── price_history/
│       └── decision/
└── ...

wisepick_admin/                 # 管理员后台（独立项目）
├── lib/
│   ├── main.dart
│   ├── features/
│   │   └── dashboard/
│   │       ├── dashboard_page.dart
│   │       ├── dashboard_service.dart
│   │       └── widgets/
│   ├── core/
│   │   ├── api_client.dart
│   │   ├── auth/
│   │   └── theme/
│   └── models/
├── web/
│   ├── index.html
│   └── manifest.json
└── pubspec.yaml
```

**实现方式**:
- **独立项目**: 创建新的 Flutter 项目 `wisepick_admin`
- **技术栈**: Flutter Web + Riverpod + Material Design 3
- **后端**: `server/lib/admin/admin_service.dart` - 提供 RESTful API
- **通信**: 通过 HTTP 请求调用后端管理 API
- **认证**: 使用 JWT Token 验证管理员权限
- **部署**: 独立的 Web 应用，可部署到不同域名（如 `admin.wisepick.com`）

**优势**:
- ✅ 代码完全分离，不影响主应用
- ✅ 独立部署和更新
- ✅ 独立的权限控制
- ✅ 可以有不同的 UI 风格（如果需要）
- ✅ 便于团队协作（不同团队维护）

#### 1.3.2 Flutter Web 支持

**是的，Flutter 完全支持 Web 平台！**

**技术说明**:
- Flutter 可以将 Dart 代码编译成 JavaScript，在浏览器中运行
- 项目已配置 Web 支持（`web/` 目录、`pubspec.yaml` 配置）
- 管理员后台可以作为 Web 应用访问

**构建和部署**:
```bash
# 构建 Web 版本
flutter build web --release

# 输出目录: build/web/
# 可部署到: Vercel, Netlify, GitHub Pages, 或任何静态托管服务
```

**Web 特性**:
- ✅ 支持所有 Flutter Widget 和 Material Design 3
- ✅ 支持响应式布局（桌面端、平板、移动端）
- ✅ 支持深色模式
- ✅ 支持图表渲染（fl_chart）
- ✅ 支持 HTTP 请求（调用后端 API）
- ⚠️ 部分平台特定功能受限（如本地通知、文件系统访问）

**管理员后台 Web 访问**:
- 可以通过浏览器访问：`https://yourdomain.com/admin`
- 需要管理员登录验证
- 所有功能在 Web 端正常工作

**Web 与桌面端的区别**:
- **相同点**: 代码完全一致，UI 组件、状态管理、API 调用都相同
- **不同点**: 
  - Web 端通过浏览器运行（编译成 JavaScript）
  - 桌面端是原生应用（Windows/macOS/Linux 可执行文件）
  - 部分功能在 Web 端可能受限（如文件系统直接访问）

**推荐部署方案**:
1. **开发环境**: 
   - 主应用: `flutter run -d windows` (桌面端) 或 `flutter run -d chrome` (Web)
   - 管理员后台: `cd wisepick_admin && flutter run -d chrome`
   
2. **生产环境**: 
   - **主应用**: 构建桌面端或 Web 版本
   - **管理员后台**: 
     - 构建: `cd wisepick_admin && flutter build web --release`
     - 部署到独立域名: `admin.wisepick.com` 或 `wisepick.com/admin`
     - 可部署到: Vercel、Netlify、GitHub Pages 或自己的 Web 服务器

**独立部署的优势**:
- ✅ 管理员后台可以独立更新，不影响主应用
- ✅ 可以使用不同的域名和 SSL 证书
- ✅ 可以设置独立的访问控制（如 IP 白名单）
- ✅ 代码完全分离，便于维护

### 1.4 目标读者

- 前端开发工程师
- UI/UX 设计师
- DEV 工程师 Agent
- 技术负责人

---

## 2. 设计理念

### 2.1 核心设计原则

#### 2.1.1 用户为中心
- **数据可视化优先**: 复杂数据通过图表直观展示，降低认知负担
- **信息层次清晰**: 重要信息突出，次要信息弱化
- **操作流程简化**: 减少用户操作步骤，提升效率

#### 2.1.2 一致性原则
- **视觉一致性**: 遵循 Material Design 3 设计规范
- **交互一致性**: 相同功能使用相同的交互模式
- **代码一致性**: 使用统一的组件和代码规范

#### 2.1.3 可访问性
- **深色模式支持**: 所有新功能模块支持深色模式
- **响应式布局**: 适配不同屏幕尺寸（桌面端、移动端、平板）
- **无障碍设计**: 支持屏幕阅读器，合理的对比度

#### 2.1.4 性能优化
- **渐进式加载**: 数据量大时使用分页或懒加载
- **图表优化**: 使用 fl_chart 高效渲染图表
- **缓存策略**: 合理使用缓存减少重复计算

---

## 3. 颜色系统定义

### 3.1 基础颜色系统

基于 Material Design 3 和现有主题配置：

#### 3.1.1 主色调
- **Primary Color**: `#6750A4` (紫色) - 主要操作按钮、强调元素
- **Secondary Color**: `#625B71` (灰紫色) - 次要操作、辅助信息
- **Primary Container**: 主色容器背景（浅色模式自动生成）
- **On Primary**: 主色上的文字颜色（自动生成）

#### 3.1.2 语义化颜色
- **Success**: `#2E7D32` (绿色) - 成功状态、正向指标
- **Warning**: `#F57C00` (橙色) - 警告信息、需要注意
- **Error**: `#B3261E` (红色) - 错误状态、负向指标
- **Info**: 使用 Primary Color - 信息提示

#### 3.1.3 平台品牌色
- **淘宝**: `#FF5722` (橙红色)
- **京东**: `#E53935` (红色)
- **拼多多**: `#FF4E4E` (粉红色)

#### 3.1.4 图表颜色方案

**数据分析模块图表配色**:
```dart
// 消费结构分析 - 饼图/柱状图
final chartColors = [
  Color(0xFF6750A4), // 主色
  Color(0xFF625B71), // 次色
  Color(0xFFE53935), // 京东红
  Color(0xFFFF5722), // 淘宝橙
  Color(0xFFFF4E4E), // 拼多多粉
  Color(0xFF2E7D32), // 成功绿
  Color(0xFFF57C00), // 警告橙
];

// 价格趋势 - 折线图
final priceLineColors = [
  Color(0xFF6750A4), // 主商品
  Color(0xFFE53935), // 对比商品1
  Color(0xFFFF5722), // 对比商品2
  Color(0xFF2E7D32), // 对比商品3
];

// 热力图 - 购物时间分析
final heatmapColors = [
  Color(0xFFE8EAF6), // 最低值（浅色）
  Color(0xFFC5CAE9),
  Color(0xFF9FA8DA),
  Color(0xFF7986CB),
  Color(0xFF5C6BC0),
  Color(0xFF3F51B5),
  Color(0xFF6750A4), // 最高值（深色）
];
```

#### 3.1.5 深色模式适配

深色模式下颜色自动调整：
- **Primary**: `#D0BCFF` (浅紫色)
- **Secondary**: `#CCC2DC` (浅灰紫色)
- **Success**: `#81C784` (浅绿色)
- **Warning**: `#FFB74D` (浅橙色)
- **Error**: `#F2B8B5` (浅红色)

**使用方式**:
```dart
// 通过 Theme 获取颜色
final colorScheme = Theme.of(context).colorScheme;
final primaryColor = colorScheme.primary;
final successColor = Theme.of(context).successColor; // 扩展颜色
```

---

## 4. 响应式布局策略

### 4.1 断点定义

```dart
// 响应式断点
class Breakpoints {
  static const double mobile = 600;      // 移动端
  static const double tablet = 900;      // 平板
  static const double desktop = 1200;    // 桌面端
  static const double wide = 1800;       // 宽屏
}
```

### 4.2 布局策略

#### 4.2.1 数据分析页面布局

**移动端 (≤ 600px)**:
- 单列布局，垂直堆叠
- 图表全宽显示
- 卡片间距 16px

**平板 (601px - 1200px)**:
- 2 列布局（数据面板 + 图表）
- 图表可并排显示（2个图表一行）

**桌面端 (> 1200px)**:
- 3 列布局（侧边栏 + 主内容 + 详情面板）
- 图表网格布局（2x2 或 3x2）
- 固定侧边栏宽度 240px

#### 4.2.2 价格历史页面布局

**移动端**:
- 商品选择器：下拉选择或底部弹窗
- 图表：全宽，高度 300px
- 统计信息：垂直堆叠

**桌面端**:
- 左侧：商品列表（固定宽度 280px）
- 右侧：图表区域（自适应宽度）
- 底部：统计信息面板（全宽）

#### 4.2.3 商品对比页面布局

**移动端**:
- 商品选择：横向滚动卡片
- 对比表格：水平滚动
- 评分卡片：垂直堆叠

**桌面端**:
- 顶部：商品选择器（横向排列）
- 中间：对比表格（固定列宽，水平滚动）
- 底部：评分和决策理由（2列布局）

#### 4.2.4 管理员后台布局

**移动端**:
- 数据面板：垂直堆叠卡片
- 图表：全宽，可切换显示
- 表格：水平滚动

**桌面端**:
- 顶部：数据概览面板（4列网格）
- 中间：主要图表区域（2x2 网格）
- 底部：详细数据表格（全宽）

### 4.3 响应式实现示例

```dart
// 使用 LayoutBuilder 实现响应式
LayoutBuilder(
  builder: (context, constraints) {
    if (constraints.maxWidth < Breakpoints.mobile) {
      return MobileLayout();
    } else if (constraints.maxWidth < Breakpoints.desktop) {
      return TabletLayout();
    } else {
      return DesktopLayout();
    }
  },
)
```

---

## 5. 组件结构设计

### 5.1 通用组件规范

#### 5.1.1 卡片组件 (Card)

**设计规范**:
- 圆角: 12dp
- 背景色: `colorScheme.surfaceContainerLow`
- 内边距: 16dp
- 无阴影 (elevation: 0)
- 支持点击交互（可选）

**代码示例**:
```dart
Card(
  margin: EdgeInsets.all(16),
  child: Padding(
    padding: EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 内容
      ],
    ),
  ),
)
```

#### 5.1.2 数据面板组件 (StatCard)

**用途**: 显示单个统计数据（如总消费、商品数量等）

**设计规范**:
- 标题: 14sp, `onSurfaceVariant`, FontWeight.w500
- 数值: 24sp, `onSurface`, FontWeight.w600
- 单位/描述: 12sp, `onSurfaceVariant`, FontWeight.w400
- 图标: 24dp, 主色或语义色

**布局结构**:
```
┌─────────────────┐
│  [图标]  标题    │
│                  │
│      数值        │
│    单位/描述     │
└─────────────────┘
```

#### 5.1.3 图表容器组件 (ChartContainer)

**设计规范**:
- 背景: Card 组件
- 标题栏: 16dp 内边距，显示标题和操作按钮
- 图表区域: 自适应高度，最小 200px
- 图例: 底部显示，水平排列

**代码结构**:
```dart
Card(
  child: Column(
    children: [
      // 标题栏
      Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('图表标题', style: Theme.of(context).textTheme.titleMedium),
            IconButton(icon: Icon(Icons.more_vert), onPressed: () {}),
          ],
        ),
      ),
      // 图表区域
      Container(
        height: 300,
        padding: EdgeInsets.all(16),
        child: ChartWidget(),
      ),
      // 图例（可选）
      if (showLegend) LegendWidget(),
    ],
  ),
)
```

### 5.2 数据分析模块组件

#### 5.2.1 消费结构图表组件

**组件名称**: `ConsumptionStructureChart`

**功能**: 展示品类分布、价格区间、平台偏好

**图表类型**:
- 品类分布: 饼图 (PieChart)
- 价格区间: 柱状图 (BarChart)
- 平台偏好: 饼图或柱状图

**交互**:
- 点击图例切换显示/隐藏
- 悬停显示详细数值
- 点击扇形/柱子显示详情弹窗

#### 5.2.2 偏好分析卡片组件

**组件名称**: `PreferenceCard`

**显示内容**:
- 偏好品类标签（Chip 组件）
- 价格偏好区间（进度条或范围显示）
- 平台偏好（图标 + 百分比）
- 购物频率（文字描述）

**布局**:
```
┌─────────────────────────┐
│ 智能偏好分析            │
├─────────────────────────┤
│ 偏好品类:               │
│ [电子产品] [数码配件]   │
│                         │
│ 价格偏好: ¥100-500      │
│ [━━━━━━━━━━━━━━━━]      │
│                         │
│ 平台偏好:               │
│ 🛒 京东 60%  🛒 淘宝 40%│
└─────────────────────────┘
```

#### 5.2.3 购物时间热力图组件

**组件名称**: `ShoppingTimeHeatmap`

**功能**: 24小时时间分布热力图

**布局**:
- X轴: 24小时（0-23）
- Y轴: 星期（周一至周日）
- 颜色深浅表示对话频率

**交互**:
- 悬停显示具体数值
- 点击查看该时段详情

### 5.3 价格历史模块组件

#### 5.3.1 价格曲线图组件

**组件名称**: `PriceHistoryChart`

**功能**: 显示商品价格历史趋势

**图表类型**: 折线图 (LineChart)

**特性**:
- 支持多商品对比（多条折线）
- 显示价格标注点（最高价、最低价）
- 支持缩放和平移
- 时间范围选择器

**数据点交互**:
- 点击数据点显示详情（价格、日期）
- 长按显示十字准线

#### 5.3.2 价格统计面板组件

**组件名称**: `PriceStatsPanel`

**显示内容**:
- 当前价格
- 历史最高价
- 历史最低价
- 平均价格
- 价格变化趋势（上涨/下跌/平稳）

**布局**: 水平排列的 StatCard 组件

#### 5.3.3 购买时机建议卡片

**组件名称**: `BuyingTimeSuggestionCard`

**显示内容**:
- 建议类型（立即购买/建议等待/建议观望）
- 建议理由（文字说明）
- 置信度（进度条）

**颜色编码**:
- 立即购买: Success 绿色
- 建议等待: Warning 橙色
- 建议观望: Info 蓝色

### 5.4 购物决策模块组件

#### 5.4.1 商品对比表格组件

**组件名称**: `ProductComparisonTable`

**功能**: 多商品参数对比表格

**表格结构**:
- 第一列: 对比维度（价格、评分、销量等）
- 后续列: 各商品数据
- 支持排序（点击列头）
- 差异高亮（不同值用不同颜色）

**响应式**:
- 移动端: 水平滚动
- 桌面端: 固定列宽，自适应

#### 5.4.2 评分卡片组件

**组件名称**: `ScoreCard`

**功能**: 显示商品综合评分和各维度得分

**布局**:
```
┌─────────────────────────┐
│ 综合评分: 85/100 ⭐⭐⭐⭐│
├─────────────────────────┤
│ 价格评分:    20/25  ████│
│ 评价评分:    22/25  ████│
│ 销量评分:    18/20  ████│
│ 趋势评分:    12/15  ███ │
│ 平台评分:    13/15  ███ │
└─────────────────────────┘
```

**视觉设计**:
- 综合评分: 大号字体，主色
- 各维度: 进度条显示得分比例
- 颜色: 高分绿色，中分橙色，低分红色

#### 5.4.3 决策理由卡片组件

**组件名称**: `DecisionReasoningCard`

**功能**: 显示 AI 生成的购买建议理由

**设计**:
- 标题: "推荐理由"
- 内容: 多段落文字，支持 Markdown 格式
- 图标: 信息图标（主色）
- 可展开/收起（长文本时）

### 5.5 管理员后台模块组件

#### 5.5.1 数据统计面板组件

**组件名称**: `StatsDashboard`

**功能**: 显示关键统计数据

**布局**: 网格布局（响应式）
- 移动端: 1列
- 平板: 2列
- 桌面端: 4列

**数据项**: StatCard 组件

#### 5.5.2 搜索热词列表组件

**组件名称**: `HotKeywordsList`

**功能**: 显示热门搜索词排行榜

**设计**:
- 列表项: ListTile
- 排名: 左侧显示序号（1-20）
- 关键词: 中间显示
- 搜索次数: 右侧显示，带趋势图标（↑↓）

**交互**:
- 点击关键词跳转到搜索页面
- 支持排序（按搜索次数/趋势）

#### 5.5.3 系统监控图表组件

**组件名称**: `SystemMonitorChart`

**功能**: 显示系统使用情况（API调用、错误率等）

**图表类型**:
- 折线图: 时间趋势
- 柱状图: 分类统计
- 饼图: 比例分布

---

## 6. 交互设计规范

### 6.1 通用交互模式

#### 6.1.1 加载状态

**加载指示器**:
- 使用 `CircularProgressIndicator`（主色）
- 位置: 内容区域居中
- 尺寸: 40dp（大），24dp（小）

**骨架屏** (Skeleton Loading):
- 数据加载时显示占位内容
- 使用 `shimmer` 动画效果
- 保持布局结构不变

**代码示例**:
```dart
// 加载状态
if (isLoading) {
  return Center(
    child: CircularProgressIndicator(
      color: Theme.of(context).colorScheme.primary,
    ),
  );
}

// 骨架屏
SkeletonLoader(
  child: Column(
    children: [
      SkeletonItem(height: 200), // 图表占位
      SkeletonItem(height: 100), // 卡片占位
    ],
  ),
)
```

#### 6.1.2 空状态

**空状态设计**:
- 图标: 48dp，`onSurfaceVariant` 颜色
- 标题: 16sp，`onSurface`，FontWeight.w500
- 描述: 14sp，`onSurfaceVariant`
- 操作按钮（可选）: FilledButton

**布局**:
```
┌─────────────────┐
│                 │
│      [图标]      │
│                 │
│      标题        │
│     描述文字     │
│                 │
│   [操作按钮]     │
└─────────────────┘
```

#### 6.1.3 错误状态

**错误提示**:
- 使用 SnackBar 或 AlertDialog
- 错误图标: 红色
- 错误消息: 清晰明确
- 重试按钮: 提供重试操作

**代码示例**:
```dart
// SnackBar 错误提示
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Row(
      children: [
        Icon(Icons.error_outline, color: Colors.white),
        SizedBox(width: 8),
        Expanded(child: Text('加载失败，请重试')),
      ],
    ),
    action: SnackBarAction(
      label: '重试',
      onPressed: () => retry(),
    ),
    backgroundColor: Theme.of(context).colorScheme.error,
  ),
);
```

### 6.2 图表交互

#### 6.2.1 图表悬停交互

**实现方式**:
- 使用 `fl_chart` 的 `onChartTouchInteraction` 回调
- 显示 Tooltip 显示详细数据
- Tooltip 样式: 卡片背景，圆角 8dp

**代码示例**:
```dart
LineChart(
  lineTouchData: LineTouchData(
    touchTooltipData: LineTouchTooltipData(
      getTooltipColor: (touchedSpot) => Colors.white,
      tooltipRoundedRadius: 8,
      tooltipPadding: EdgeInsets.all(8),
    ),
  ),
)
```

#### 6.2.2 图表缩放和平移

**实现方式**:
- 使用 `InteractiveViewer` 包裹图表
- 支持双指缩放（移动端）
- 支持鼠标滚轮缩放（桌面端）
- 支持拖拽平移

**代码示例**:
```dart
InteractiveViewer(
  minScale: 0.5,
  maxScale: 3.0,
  child: LineChart(chartData),
)
```

#### 6.2.3 图例交互

**实现方式**:
- 点击图例项切换显示/隐藏对应数据系列
- 使用动画过渡（200ms）
- 视觉反馈: 未选中项降低透明度（0.3）

### 6.3 数据筛选和排序

#### 6.3.1 时间范围选择

**组件**: `TimeRangePicker`

**交互方式**:
- 点击按钮打开日期选择器
- 预设选项: 今天、本周、本月、自定义
- 使用 `showDateRangePicker` 或自定义底部弹窗

**设计**:
```
┌─────────────────────┐
│ 时间范围: 本周  ▼   │
└─────────────────────┘
```

#### 6.3.2 数据排序

**交互方式**:
- 点击列头切换排序（升序/降序/无排序）
- 显示排序图标（↑↓）
- 动画过渡（150ms）

### 6.4 页面导航和路由

#### 6.4.1 页面跳转

**动画**: 使用 Material 页面转场动画
- 进入: 从右侧滑入
- 退出: 向左侧滑出
- 持续时间: 300ms

**代码示例**:
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => TargetPage(),
  ),
);
```

#### 6.4.2 底部弹窗

**使用场景**: 移动端选择器、操作菜单

**设计规范**:
- 顶部圆角: 28dp
- 最大高度: 屏幕高度的 90%
- 拖拽指示器: 顶部显示
- 背景: `colorScheme.surface`

**代码示例**:
```dart
showModalBottomSheet(
  context: context,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (context) => BottomSheetContent(),
);
```

### 6.5 表单交互

#### 6.5.1 输入框交互

**焦点状态**:
- 未聚焦: 无边框，背景色填充
- 聚焦: 2dp 主色边框
- 错误: 红色边框

**验证反馈**:
- 实时验证（onChanged）
- 错误提示: 输入框下方显示红色文字
- 成功提示: 绿色对勾图标（可选）

#### 6.5.2 按钮交互

**按钮状态**:
- 正常: 主色背景
- 悬停: 颜色加深 10%（桌面端）
- 按下: 颜色加深 20%
- 禁用: 透明度 0.38

**动画**:
- 按下缩放: 0.95
- 持续时间: 100ms

### 6.6 数据导出交互

#### 6.6.1 导出操作流程

1. 点击导出按钮
2. 显示格式选择（PDF/Excel/CSV）
3. 显示加载状态
4. 完成提示（SnackBar）
5. 打开文件或保存对话框

**代码示例**:
```dart
// 导出按钮
FilledButton.icon(
  icon: Icon(Icons.download),
  label: Text('导出数据'),
  onPressed: () async {
    // 显示格式选择
    final format = await showDialog<ExportFormat>(...);
    if (format != null) {
      // 显示加载
      showDialog(context: context, builder: (_) => LoadingDialog());
      // 执行导出
      await exportData(format);
      // 关闭加载，显示成功
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出成功')),
      );
    }
  },
)
```

---

## 7. DEV 工程师编码提示词

### 7.1 通用编码规范

#### 7.1.1 文件组织

**主应用目录结构** (wisepick_dart_version):
```
lib/features/
├── analytics/              # 数据分析模块
│   ├── analytics_page.dart
│   ├── analytics_service.dart
│   ├── analytics_providers.dart
│   └── widgets/
│       ├── consumption_structure_chart.dart
│       ├── preferences_card.dart
│       └── shopping_time_heatmap.dart
├── price_history/          # 价格历史模块
│   ├── price_history_page.dart
│   ├── price_history_service.dart
│   ├── price_history_providers.dart
│   └── widgets/
│       ├── price_chart_widget.dart
│       └── price_stats_panel.dart
└── decision/               # 购物决策模块
    ├── compare_page.dart
    ├── decision_service.dart
    ├── decision_providers.dart
    └── widgets/
        ├── comparison_table.dart
        └── score_card.dart
```

**管理员后台项目结构** (wisepick_admin - 独立项目):
```
wisepick_admin/
├── lib/
│   ├── main.dart                    # 应用入口
│   ├── app.dart                     # 应用根组件
│   ├── features/
│   │   └── dashboard/               # 仪表板模块
│   │       ├── dashboard_page.dart
│   │       ├── dashboard_service.dart
│   │       ├── dashboard_providers.dart
│   │       └── widgets/
│   │           ├── stats_dashboard.dart
│   │           ├── user_stats_panel.dart
│   │           ├── system_stats_panel.dart
│   │           ├── hot_keywords_list.dart
│   │           └── export_dialog.dart
│   ├── core/
│   │   ├── api_client.dart          # API 客户端（调用后端）
│   │   ├── auth/
│   │   │   ├── login_page.dart      # 管理员登录页面
│   │   │   └── auth_service.dart    # 认证服务
│   │   └── theme/
│   │       └── app_theme.dart       # 主题配置（可复用主应用主题）
│   └── models/
│       ├── user_stats.dart
│       ├── system_stats.dart
│       └── search_keyword.dart
├── web/
│   ├── index.html
│   └── manifest.json
└── pubspec.yaml
```

#### 7.1.2 代码风格

**命名规范**:
- 文件名: `snake_case.dart`
- 类名: `PascalCase`
- 变量/方法名: `camelCase`
- 常量: `UPPER_SNAKE_CASE`

**导入顺序**:
```dart
// 1. Dart 标准库
import 'dart:async';

// 2. Flutter 框架
import 'package:flutter/material.dart';

// 3. 第三方包
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 4. 项目内部
import 'package:wisepick/core/theme/app_theme.dart';
import 'package:wisepick/features/analytics/analytics_service.dart';
```

#### 7.1.3 主题和颜色使用

**必须使用 Theme 获取颜色**:
```dart
// ✅ 正确
final colorScheme = Theme.of(context).colorScheme;
final primaryColor = colorScheme.primary;
final cardColor = colorScheme.surfaceContainerLow;

// ❌ 错误 - 不要硬编码颜色
final primaryColor = Color(0xFF6750A4);
```

**使用扩展颜色**:
```dart
// ✅ 正确
final successColor = Theme.of(context).successColor;
final taobaoColor = Theme.of(context).taobaoColor;

// ❌ 错误
final successColor = Color(0xFF2E7D32);
```

### 7.2 数据分析模块编码提示词

#### 7.2.1 AnalyticsPage 实现提示词

```
创建一个数据分析页面 (AnalyticsPage)，要求：

1. 页面结构：
   - 使用 Scaffold，AppBar 标题为"数据分析"
   - 主体使用 SingleChildScrollView，支持滚动
   - 响应式布局：使用 LayoutBuilder 检测屏幕宽度
   - 移动端（≤600px）：单列布局，垂直堆叠
   - 桌面端（>600px）：2-3列网格布局

2. 顶部数据面板：
   - 使用 Row/GridView 显示 4 个 StatCard
   - 显示：总消费、商品数量、平均单价、最常购买平台
   - 每个 StatCard 包含：图标、标题、数值、单位
   - 使用 colorScheme.primary 作为图标颜色

3. 图表区域：
   - 消费结构图表（饼图）：使用 PieChart from fl_chart
   - 价格区间图表（柱状图）：使用 BarChart
   - 平台偏好图表（饼图）：使用 PieChart
   - 每个图表包裹在 ChartContainer 中
   - 图表颜色使用预定义的 chartColors 数组

4. 偏好分析卡片：
   - 使用 PreferenceCard 组件
   - 显示偏好品类（Chip 列表）
   - 显示价格偏好区间（RangeSlider 或文字）
   - 显示平台偏好（图标 + 百分比）

5. 购物时间热力图：
   - 使用 ShoppingTimeHeatmap 组件
   - 24小时 x 7天的网格布局
   - 每个格子根据数值显示不同颜色深度
   - 点击格子显示详情弹窗

6. 状态管理：
   - 使用 Riverpod FutureProvider 加载数据
   - 显示加载状态（CircularProgressIndicator）
   - 显示空状态（EmptyState widget）
   - 显示错误状态（ErrorWidget with retry）

7. 交互功能：
   - 时间范围选择器（顶部）
   - 刷新按钮（AppBar actions）
   - 导出报告按钮（底部 FAB 或 AppBar）

8. 代码要求：
   - 使用 const 构造函数优化性能
   - 使用 ConsumerWidget 或 Consumer 访问 Provider
   - 所有颜色从 Theme 获取，支持深色模式
   - 遵循 Material Design 3 规范
   - 添加必要的注释
```

#### 7.2.2 ConsumptionStructureChart 实现提示词

```
创建一个消费结构图表组件，要求：

1. 组件定义：
   - 类名：ConsumptionStructureChart
   - 继承：StatelessWidget
   - 参数：consumptionData (Map<String, dynamic>)

2. 图表类型：
   - 使用 fl_chart 的 PieChart
   - 显示品类分布数据
   - 支持点击图例切换显示/隐藏

3. 数据格式：
   ```dart
   {
     'categories': [
       {'name': '电子产品', 'value': 1500.0, 'count': 5},
       {'name': '服装', 'value': 800.0, 'count': 3},
       ...
     ]
   }
   ```

4. 颜色方案：
   - 使用预定义的 chartColors 数组
   - 循环使用颜色（如果类别超过颜色数量）

5. 图例设计：
   - 底部水平排列
   - 每个图例项：颜色块 + 名称 + 数值 + 百分比
   - 点击图例项切换对应扇形显示/隐藏
   - 未选中项降低透明度到 0.3

6. 交互功能：
   - 点击扇形显示详情弹窗（名称、金额、数量、占比）
   - 悬停显示 Tooltip
   - 动画过渡（200ms）

7. 样式要求：
   - 图表容器：Card，圆角 12dp，内边距 16dp
   - 标题：16sp，FontWeight.w600，colorScheme.onSurface
   - 图表高度：300dp（移动端），400dp（桌面端）

8. 代码示例结构：
   ```dart
   class ConsumptionStructureChart extends StatelessWidget {
     final Map<String, dynamic> consumptionData;
     
     const ConsumptionStructureChart({required this.consumptionData});
     
     @override
     Widget build(BuildContext context) {
       final colorScheme = Theme.of(context).colorScheme;
       // 实现代码
     }
   }
   ```
```

### 7.3 价格历史模块编码提示词

#### 7.3.1 PriceHistoryPage 实现提示词

```
创建价格历史页面，要求：

1. 页面布局：
   - 移动端：垂直布局
     * 顶部：商品选择器（下拉或底部弹窗）
     * 中间：价格曲线图（全宽，高度 300dp）
     * 底部：价格统计面板（垂直堆叠）
   - 桌面端：水平布局
     * 左侧：商品列表（固定宽度 280dp，可滚动）
     * 右侧：图表区域（自适应宽度）
     * 底部：统计面板（全宽，水平排列）

2. 商品选择器：
   - 显示购物车中的商品列表
   - 支持多选（最多5个商品对比）
   - 每个商品项显示：缩略图、标题、当前价格
   - 选中状态：主色边框，主色背景（透明度0.1）

3. 价格曲线图：
   - 使用 LineChart from fl_chart
   - 支持多条折线（多商品对比）
   - X轴：时间（日期格式）
   - Y轴：价格（货币格式）
   - 显示网格线（浅色）
   - 显示数据点（可点击）
   - 支持缩放和平移（InteractiveViewer）

4. 价格统计面板：
   - 使用 StatCard 组件
   - 显示：当前价格、历史最高、历史最低、平均价格
   - 价格变化趋势：上涨（绿色↑）、下跌（红色↓）、平稳（灰色→）

5. 购买时机建议：
   - 使用 BuyingTimeSuggestionCard
   - 根据价格趋势显示建议
   - 颜色编码：立即购买（绿色）、建议等待（橙色）、建议观望（蓝色）

6. 时间范围选择：
   - 顶部显示时间范围选择器
   - 预设：7天、30天、90天、全部
   - 自定义范围：日期选择器

7. 状态管理：
   - selectedProductsProvider: 选中的商品列表
   - priceHistoryProvider: 价格历史数据（FutureProvider）
   - timeRangeProvider: 时间范围（StateProvider）

8. 交互功能：
   - 商品选择/取消选择
   - 时间范围切换
   - 图表缩放和平移
   - 数据点点击查看详情
   - 导出价格历史（CSV/Excel）

9. 代码要求：
   - 使用 ConsumerWidget
   - 所有颜色从 Theme 获取
   - 支持深色模式
   - 添加加载和错误状态处理
```

#### 7.3.2 PriceChartWidget 实现提示词

```
创建价格曲线图组件，要求：

1. 组件定义：
   - 类名：PriceChartWidget
   - 参数：priceHistoryList (List<PriceHistoryEntry>), selectedProducts (List<String>)

2. 图表实现：
   - 使用 fl_chart 的 LineChart
   - 多条折线（每个商品一条）
   - 折线颜色：使用 priceLineColors 数组
   - 折线宽度：2.0
   - 数据点：显示圆点（半径 4.0）

3. 交互功能：
   - 触摸交互：显示 Tooltip（价格、日期）
   - 点击数据点：显示详情弹窗
   - 缩放：使用 InteractiveViewer（minScale: 0.5, maxScale: 3.0）
   - 平移：拖拽移动

4. 坐标轴：
   - X轴：时间轴，显示日期（格式：MM/dd）
   - Y轴：价格轴，显示货币（格式：¥XXX）
   - 网格线：浅色，透明度 0.1

5. 标注：
   - 最高价标注：绿色标记 + 文字
   - 最低价标注：红色标记 + 文字
   - 当前价格标注：主色标记 + 文字

6. 图例：
   - 顶部或底部显示
   - 每个商品：颜色线 + 商品名称
   - 点击切换显示/隐藏

7. 样式：
   - 容器：Card，圆角 12dp
   - 内边距：16dp
   - 背景：colorScheme.surfaceContainerLow
   - 图表区域：白色或透明背景

8. 性能优化：
   - 大量数据时使用采样（每N个点显示一个）
   - 使用 const 构造函数
   - 避免不必要的重建
```

### 7.4 购物决策模块编码提示词

#### 7.4.1 ComparePage 实现提示词

```
创建商品对比页面，要求：

1. 页面结构：
   - AppBar：标题"商品对比"，操作按钮（添加商品、清除）
   - 主体：SingleChildScrollView
   - 响应式布局

2. 商品选择区域：
   - 顶部横向滚动区域
   - 显示已选商品卡片（最多5个）
   - 每个卡片：缩略图、标题、价格、删除按钮
   - 添加商品按钮：显示商品选择弹窗

3. 对比表格：
   - 使用 DataTable 或自定义 Table
   - 第一列：对比维度（价格、评分、销量、店铺、参数等）
   - 后续列：各商品数据
   - 差异高亮：不同值使用不同背景色
   - 支持排序（点击列头）

4. 评分卡片区域：
   - 每个商品一个 ScoreCard
   - 显示综合评分（大号字体）
   - 显示各维度得分（进度条）
   - 颜色编码：高分绿色、中分橙色、低分红色

5. 决策理由卡片：
   - 显示 AI 生成的推荐理由
   - 支持展开/收起（长文本）
   - 使用 Markdown 格式（可选）

6. 替代商品推荐：
   - 底部显示替代商品列表
   - 每个替代商品：卡片形式
   - 显示相似度百分比
   - 点击跳转到商品详情

7. 状态管理：
   - selectedProductsProvider: 选中的商品列表
   - comparisonDataProvider: 对比数据（FutureProvider）
   - scoresProvider: 评分数据（FutureProvider）

8. 交互功能：
   - 添加/删除商品
   - 表格排序
   - 查看商品详情
   - 生成购买建议
   - 导出对比结果

9. 代码要求：
   - 使用 ConsumerWidget
   - 支持深色模式
   - 添加加载和错误状态
   - 优化大表格性能（虚拟滚动）
```

#### 7.4.2 ComparisonTable 实现提示词

```
创建商品对比表格组件，要求：

1. 组件定义：
   - 类名：ComparisonTable
   - 参数：products (List<ProductModel>), comparisonData (Map)

2. 表格结构：
   - 使用 DataTable 或自定义 Table
   - 固定第一列（对比维度）
   - 后续列可水平滚动（移动端）
   - 列宽：桌面端固定，移动端自适应

3. 对比维度：
   - 价格、原价、优惠券、最终价格
   - 评分、销量、店铺
   - 商品参数（动态，根据商品类型）

4. 差异高亮：
   - 找出每行的最大值和最小值
   - 最大值：绿色背景（透明度0.1）
   - 最小值：红色背景（透明度0.1）
   - 相同值：无背景色

5. 排序功能：
   - 点击列头切换排序
   - 显示排序图标（↑↓）
   - 动画过渡

6. 响应式设计：
   - 移动端：水平滚动容器
   - 桌面端：固定布局，列宽自适应

7. 样式：
   - 表头：16sp，FontWeight.w600
   - 数据：14sp，FontWeight.w400
   - 行高：48dp
   - 边框：1dp，colorScheme.outlineVariant

8. 代码示例：
   ```dart
   class ComparisonTable extends StatelessWidget {
     final List<ProductModel> products;
     final Map<String, dynamic> comparisonData;
     
     @override
     Widget build(BuildContext context) {
       return SingleChildScrollView(
         scrollDirection: Axis.horizontal,
         child: DataTable(
           columns: _buildColumns(),
           rows: _buildRows(),
         ),
       );
     }
   }
   ```
```

### 7.5 管理员后台模块编码提示词

#### 7.5.0 项目初始化提示词

```
创建独立的管理员后台 Flutter Web 项目，完整步骤：

1. 创建新项目：
   ```bash
   flutter create wisepick_admin --platforms=web
   cd wisepick_admin
   ```

2. 配置 pubspec.yaml：
   ```yaml
   dependencies:
     flutter:
       sdk: flutter
     flutter_riverpod: ^2.5.1
     dio: ^5.1.2
     fl_chart: ^0.65.0
     excel: ^2.1.0
     flutter_secure_storage: ^9.2.4
     intl: ^0.18.0
     google_fonts: ^5.0.0
   ```

3. 创建项目结构：
   ```
   lib/
   ├── main.dart
   ├── app.dart
   ├── core/
   │   ├── api_client.dart
   │   ├── config.dart
   │   ├── auth/
   │   │   ├── login_page.dart
   │   │   └── auth_service.dart
   │   └── theme/
   │       └── app_theme.dart
   ├── features/
   │   └── dashboard/
   │       ├── dashboard_page.dart
   │       ├── dashboard_service.dart
   │       ├── dashboard_providers.dart
   │       └── widgets/
   └── models/
   ```

4. 配置 API 客户端（lib/core/api_client.dart）：
   - 基础 URL: 从环境变量或配置文件读取
   - JWT Token: 从 secure_storage 读取，自动添加到请求头
   - 错误处理: 401 自动跳转到登录页
   - 超时设置: 30秒

5. 创建登录页面（lib/core/auth/login_page.dart）：
   - 用户名/密码输入框
   - 登录按钮
   - 调用后端 /api/v1/admin/login
   - 成功后保存 Token，跳转到仪表板

6. 配置路由（lib/app.dart）：
   - 检查登录状态
   - 未登录: 显示登录页
   - 已登录: 显示仪表板

7. 环境配置（lib/core/config.dart）：
   ```dart
   class Config {
     static const String apiBaseUrl = String.fromEnvironment(
       'API_BASE_URL',
       defaultValue: 'http://localhost:9527',
     );
   }
   ```

8. 运行项目：
   ```bash
   flutter run -d chrome
   ```

9. 构建生产版本：
   ```bash
   flutter build web --release --base-href=/admin/
   ```
```

### 7.5 管理员后台模块编码提示词（续）

#### 7.5.1 管理员后台项目创建提示词

```
【重要】管理员后台是独立的 Flutter Web 项目，需要创建新项目。

1. 创建新项目：
   ```bash
   flutter create wisepick_admin
   cd wisepick_admin
   ```

2. 配置 pubspec.yaml：
   - 添加依赖：flutter_riverpod, dio, fl_chart, excel 等
   - 配置 Web 平台支持

3. 项目结构：
   - 参考上面的"管理员后台项目结构"
   - 创建 core/、features/、models/ 目录

4. 配置 API 客户端：
   - 创建 lib/core/api_client.dart
   - 配置后端 API 地址（环境变量或配置文件）
   - 实现 JWT Token 认证（从登录获取，存储到 secure_storage）

5. 创建登录页面：
   - lib/core/auth/login_page.dart
   - 管理员用户名/密码登录
   - 调用后端 /api/v1/admin/login 接口
   - 保存 JWT Token

6. 创建主题配置：
   - 可以复用主应用的主题配置
   - 或创建独立的管理后台主题（更专业的数据可视化风格）
```

#### 7.5.2 AdminDashboardPage 实现提示词

```
创建管理员后台仪表板页面，要求：

【重要】这是独立项目中的页面，通过 HTTP 请求调用后端 API 获取数据。

1. 权限验证：
   - 页面入口需要管理员登录验证
   - 检查 JWT Token 是否有效
   - 检查 Token 中是否包含管理员权限
   - 未登录或权限不足：跳转到登录页面或显示权限错误
   - Token 验证通过 AdminService.verifyAdminToken() 方法

2. 页面布局：
   - AppBar：标题"管理员后台"，操作按钮（刷新、导出、设置）
   - 主体：响应式网格布局
   - 移动端：单列
   - 平板：2列
   - 桌面端：4列（顶部统计面板）

3. 数据统计面板：
   - 使用 StatsDashboard 组件
   - 显示：总用户数、日活、周活、月活
   - 显示：API调用次数、成功率、错误率
   - 显示：搜索总数、成功率
   - 每个统计项：StatCard 组件

4. 图表区域：
   - 用户增长趋势图（折线图）
   - API调用趋势图（折线图）
   - 搜索热词词云或柱状图
   - 错误类型分布（饼图）

5. 数据表格：
   - 用户列表表格（可排序、分页）
   - 搜索记录表格
   - 错误日志表格

6. 时间范围选择：
   - 顶部时间选择器
   - 预设：今天、本周、本月、自定义

7. 数据导出：
   - 导出按钮：Excel/CSV 格式
   - 显示加载状态
   - 完成提示

8. 状态管理：
   - userStatsProvider: 用户统计数据
   - systemStatsProvider: 系统统计数据
   - searchKeywordsProvider: 搜索热词
   - timeRangeProvider: 时间范围

9. 实时更新：
   - 定时刷新（每30秒）
   - 手动刷新按钮
   - 显示最后更新时间

10. 代码要求：
    - 使用 ConsumerWidget
    - 支持深色模式
    - 添加权限检查
    - 优化大数据表格性能
    - 添加错误处理
```

---

## 8. 样式和动画规范

### 8.1 动画规范

#### 8.1.1 页面转场动画

**标准转场**: Material 默认转场（300ms）
**自定义转场**: 使用 `PageRouteBuilder`

#### 8.1.2 组件动画

**淡入淡出**: `FadeTransition` (200ms)
**缩放**: `ScaleTransition` (150ms)
**滑动**: `SlideTransition` (200ms)

#### 8.1.3 图表动画

**fl_chart 动画**:
```dart
LineChart(
  lineChartData: LineChartData(
    lineBarsData: [...],
    // 动画配置
    showingTooltipIndicators: [...],
  ),
  duration: Duration(milliseconds: 300),
  curve: Curves.easeInOut,
)
```

### 8.2 间距规范

**标准间距**:
- 页面内边距: 16dp
- 卡片间距: 16dp
- 组件内部间距: 8dp / 12dp / 16dp
- 大间距: 24dp / 32dp

**使用方式**:
```dart
// ✅ 使用常量
const EdgeInsets.all(16)
const EdgeInsets.symmetric(horizontal: 16, vertical: 8)

// ❌ 避免硬编码
EdgeInsets.all(15.5)
```

### 8.3 字体规范

**字体大小**:
- 超大标题: 32sp (Display Large)
- 大标题: 24sp (Headline)
- 标题: 20sp (Title Large)
- 副标题: 16sp (Title Medium)
- 正文: 14sp (Body Large)
- 小字: 12sp (Body Small)
- 标签: 10sp (Label Small)

**使用方式**:
```dart
// ✅ 使用 Theme textTheme
Theme.of(context).textTheme.headlineMedium
Theme.of(context).textTheme.bodyLarge

// ❌ 避免硬编码
TextStyle(fontSize: 16)
```

---

## 9. 测试和验证

### 9.1 视觉测试清单

- [ ] 所有页面支持深色模式
- [ ] 响应式布局在不同屏幕尺寸正常显示
- [ ] 图表颜色符合设计规范
- [ ] 交互反馈及时且明显
- [ ] 加载和错误状态正确显示
- [ ] 空状态有友好的提示

### 9.2 交互测试清单

- [ ] 所有按钮有明确的点击反馈
- [ ] 图表交互（缩放、平移、点击）正常工作
- [ ] 表单验证和错误提示正确
- [ ] 页面转场动画流畅
- [ ] 数据导出功能正常

### 9.3 性能测试

- [ ] 大数据量图表渲染流畅（>1000 数据点）
- [ ] 页面滚动流畅（60 FPS）
- [ ] 图表交互响应及时（<100ms）
- [ ] 数据加载有适当的加载指示

---

## 10. 附录

### 10.1 参考资源

- [Material Design 3 指南](https://m3.material.io/)
- [Flutter 官方文档](https://docs.flutter.dev/)
- [fl_chart 文档](https://pub.dev/packages/fl_chart)
- [Riverpod 文档](https://riverpod.dev/)

### 10.2 设计工具

- Figma: UI 设计稿
- Material Theme Builder: 颜色方案生成
- Flutter Inspector: 调试工具

### 10.3 变更日志

| 版本 | 日期 | 变更内容 | 作者 |
|------|------|----------|------|
| 1.0 | 2026-01-22 | 初始 UI 设计规范文档 | Sally (UX Expert) |

---

**文档维护者**: UX 设计团队  
**审核者**: 前端开发团队  
**批准者**: 技术负责人

---

*本文档为新增功能模块的 UI 设计规范，确保开发团队实现一致的视觉和交互体验。*

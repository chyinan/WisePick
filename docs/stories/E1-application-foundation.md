# Epic 1: 应用基础架构

**Epic ID**: E1  
**创建日期**: 2026-01-06  
**状态**: Draft  
**优先级**: P0

---

## Epic 描述

建立快淘帮 WisePick 应用的基础框架，包括应用入口、主题系统、响应式导航和本地存储配置。这是所有其他功能的基础。

## 业务价值

- 确保应用具有统一的视觉风格和用户体验
- 支持跨平台运行（Windows、macOS、Linux、Android、iOS、Web）
- 为后续功能开发提供稳定的基础架构

## 验收标准概览

1. 应用能在所有目标平台启动运行
2. 深色/浅色主题切换正常工作
3. 响应式导航在不同屏幕尺寸下正确显示
4. 本地数据能够持久化存储

---

## Story 1.1: 应用入口与初始化

### Status
Draft

### Story
**As a** 用户,  
**I want** 应用能快速启动并正确初始化所有服务,  
**so that** 我可以立即开始使用应用功能

### Acceptance Criteria

1. 应用启动时间 < 2 秒
2. WidgetsFlutterBinding 正确初始化
3. 桌面端窗口配置正确（最小尺寸、标题）
4. 通知服务初始化成功
5. Hive 数据库初始化成功
6. 价格刷新服务在后台启动
7. 应用使用 ProviderScope 包裹

### Tasks / Subtasks

- [ ] 创建 `main.dart` 入口文件 (AC: 1, 2)
  - [ ] 配置 `WidgetsFlutterBinding.ensureInitialized()`
  - [ ] 添加桌面端窗口配置（使用 window_manager）
  - [ ] 设置最小窗口尺寸 800x600
  - [ ] 设置窗口标题 "快淘帮 WisePick"
- [ ] 初始化核心服务 (AC: 3, 4, 5)
  - [ ] 调用 `NotificationService.init()`
  - [ ] 初始化 Hive 并注册适配器
  - [ ] 打开必要的 Hive Box
- [ ] 配置应用启动 (AC: 6, 7)
  - [ ] 启动 `PriceRefreshService`
  - [ ] 使用 `ProviderScope` 包裹 `runApp()`
  - [ ] 创建 `WisePickApp` 根组件

### Dev Notes

**技术栈**:
- Flutter 3.9.2+
- Riverpod 2.5.1 (状态管理)
- Hive 2.2.3 (本地存储)
- window_manager (桌面窗口管理)

**文件结构**:
```
lib/
├── main.dart              # 应用入口
├── app.dart               # WisePickApp 组件
└── services/
    ├── notification_service.dart
    └── price_refresh_service.dart
```

**关键代码参考**:
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 桌面端窗口配置
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(800, 600),
      title: '快淘帮 WisePick',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  
  // 初始化服务
  await NotificationService.init();
  await Hive.initFlutter();
  // 注册适配器...
  
  // 启动后台服务
  PriceRefreshService.instance.start();
  
  runApp(ProviderScope(child: WisePickApp()));
}
```

### Testing

**测试文件位置**: `test/main_test.dart`

**测试要求**:
- 测试服务初始化顺序
- 测试 Hive Box 打开成功
- 测试桌面端窗口配置

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 1.2: Material Design 3 主题系统

### Status
Draft

### Story
**As a** 用户,  
**I want** 应用有统一的视觉风格并支持深色模式,  
**so that** 我有舒适一致的视觉体验

### Acceptance Criteria

1. 使用 Material Design 3 设计规范
2. 主色调为 #6750A4 (紫色)
3. 支持浅色和深色主题
4. 支持跟随系统主题设置
5. 中文字体使用 Noto Sans SC
6. 组件圆角符合规范（按钮 20dp、卡片 12dp、输入框 8dp）
7. 主题状态持久化存储

### Tasks / Subtasks

- [ ] 创建主题配置文件 (AC: 1, 2, 3)
  - [ ] 创建 `lib/core/theme/app_theme.dart`
  - [ ] 定义浅色主题 `lightTheme()`
  - [ ] 定义深色主题 `darkTheme()`
  - [ ] 配置 ColorScheme.fromSeed()
- [ ] 配置组件主题覆盖 (AC: 6)
  - [ ] AppBar 主题（透明背景、无阴影）
  - [ ] Card 主题（圆角 12dp）
  - [ ] FilledButton 主题（圆角 20dp）
  - [ ] InputDecoration 主题（圆角 8dp）
  - [ ] BottomSheet 主题（顶部圆角 28dp）
- [ ] 配置字体 (AC: 5)
  - [ ] 添加 Noto Sans SC 字体文件到 assets
  - [ ] 在 pubspec.yaml 中配置字体
  - [ ] 设置 fontFamily
- [ ] 创建主题状态管理 (AC: 4, 7)
  - [ ] 创建 `lib/core/theme/theme_provider.dart`
  - [ ] 实现 ThemeNotifier (StateNotifier)
  - [ ] 支持 light/dark/system 三种模式
  - [ ] 持久化到 Hive

### Dev Notes

**颜色方案**:
- Primary: #6750A4
- Secondary: #625B71
- Error: #B3261E
- Success: #2E7D32
- Warning: #F57C00

**平台品牌色**:
- 淘宝: #FF5722
- 京东: #E53935
- 拼多多: #FF4E4E

**文件结构**:
```
lib/core/theme/
├── app_theme.dart         # 主题配置
└── theme_provider.dart    # 主题状态管理
```

**关键代码参考**:
```dart
class AppTheme {
  static const _primaryColor = Color(0xFF6750A4);
  
  static ThemeData lightTheme({Color? seedColor}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor ?? _primaryColor,
      brightness: Brightness.light,
    );
    
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: 'NotoSansSC',
      // 组件主题配置...
    );
  }
}
```

### Testing

**测试文件位置**: `test/core/theme/app_theme_test.dart`

**测试要求**:
- 测试浅色主题颜色正确
- 测试深色主题颜色正确
- 测试主题切换功能
- 测试主题持久化

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 1.3: 响应式导航框架

### Status
Draft

### Story
**As a** 用户,  
**I want** 应用在不同设备上有合适的导航方式,  
**so that** 我在手机和电脑上都能方便地使用

### Acceptance Criteria

1. 桌面端（宽度 > 800dp）使用 NavigationRail 左侧导航
2. 移动端（宽度 ≤ 800dp）使用 BottomNavigationBar 底部导航
3. 导航项包含：AI 助手、选品车（带数量徽章）、设置
4. 页面切换使用 IndexedStack 保持状态
5. 导航图标使用 outlined/filled 区分选中状态
6. 选品车图标显示商品数量徽章

### Tasks / Subtasks

- [ ] 创建响应式布局组件 (AC: 1, 2)
  - [ ] 创建 `lib/widgets/responsive_layout.dart`
  - [ ] 实现 ScreenSize 枚举
  - [ ] 使用 LayoutBuilder 检测屏幕尺寸
- [ ] 创建 HomePage 框架 (AC: 3, 4)
  - [ ] 创建 `lib/screens/home_page.dart`
  - [ ] 配置 NavigationDestination 列表
  - [ ] 使用 IndexedStack 管理页面
- [ ] 实现自适应导航 (AC: 5)
  - [ ] 桌面端显示 NavigationRail
  - [ ] 移动端显示 NavigationBar
  - [ ] 配置图标的 outlined/filled 变体
- [ ] 实现选品车徽章 (AC: 6)
  - [ ] 使用 Badge Widget 显示数量
  - [ ] 监听选品车状态更新徽章

### Dev Notes

**断点定义**:
- compact: < 600dp (手机)
- medium: 600-839dp (平板竖屏)
- expanded: 840-1199dp (平板横屏/小桌面)
- large: >= 1200dp (大桌面)

**导航项配置**:
```dart
[
  NavigationDestination(
    icon: Icon(Icons.smart_toy_outlined),
    selectedIcon: Icon(Icons.smart_toy),
    label: 'AI 助手',
  ),
  NavigationDestination(
    icon: Badge(
      label: Text('$cartCount'),
      child: Icon(Icons.shopping_cart_outlined),
    ),
    selectedIcon: Badge(
      label: Text('$cartCount'),
      child: Icon(Icons.shopping_cart),
    ),
    label: '选品车',
  ),
  NavigationDestination(
    icon: Icon(Icons.settings_outlined),
    selectedIcon: Icon(Icons.settings),
    label: '设置',
  ),
]
```

**文件结构**:
```
lib/
├── screens/
│   └── home_page.dart
└── widgets/
    └── responsive_layout.dart
```

### Testing

**测试文件位置**: `test/screens/home_page_test.dart`

**测试要求**:
- 测试不同屏幕尺寸下导航类型
- 测试页面切换功能
- 测试徽章数量更新

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 1.4: Hive 本地存储配置

### Status
Draft

### Story
**As a** 用户,  
**I want** 我的设置和数据能够保存在本地,  
**so that** 下次打开应用时不会丢失

### Acceptance Criteria

1. 配置所有必要的 Hive Box
2. 注册自定义 TypeAdapter
3. 支持 ProductModel 序列化存储
4. 支持 CartItem 序列化存储
5. 支持 Conversation 序列化存储
6. 设置数据能够持久化

### Tasks / Subtasks

- [ ] 配置 Hive 初始化 (AC: 1)
  - [ ] 在 main.dart 中调用 Hive.initFlutter()
  - [ ] 定义 Box 名称常量
- [ ] 创建 TypeAdapter (AC: 2, 3, 4, 5)
  - [ ] ProductModel Adapter
  - [ ] CartItem Adapter
  - [ ] Conversation Adapter
  - [ ] ChatMessage Adapter
- [ ] 配置存储 Box (AC: 1, 6)
  - [ ] settings Box
  - [ ] cart_box Box
  - [ ] conversations Box
  - [ ] promo_cache Box

### Dev Notes

**Box 配置**:
| Box 名称 | 用途 | TypeAdapter |
|----------|------|-------------|
| settings | 应用设置 | - |
| cart_box | 选品车数据 | ProductModelAdapter |
| conversations | 会话历史 | ConversationAdapter |
| promo_cache | 推广链接缓存 | - |

**Hive 注解示例**:
```dart
@HiveType(typeId: 0)
class ProductModel {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final String platform;
  
  // ...
}
```

**初始化顺序**:
1. Hive.initFlutter()
2. 注册所有 TypeAdapter
3. 打开所有 Box

### Testing

**测试文件位置**: `test/core/storage_test.dart`

**测试要求**:
- 测试数据序列化/反序列化
- 测试数据持久化
- 测试 Box 打开/关闭

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |




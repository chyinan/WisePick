# Epic 6: 用户设置

**Epic ID**: E6  
**创建日期**: 2026-01-06  
**状态**: Draft  
**优先级**: P1

---

## Epic 描述

实现用户可访问的设置功能，包括主题切换、通知偏好等基础设置项。

## 业务价值

- 提供个性化体验
- 提升用户满意度
- 支持无障碍需求

## 依赖关系

- 依赖 Epic 1（应用基础架构）

---

## Story 6.1: 用户设置页面

### Status
Draft

### Story
**As a** 用户,  
**I want** 有一个设置页面,  
**so that** 我可以自定义应用行为

### Acceptance Criteria

1. 设置项使用分组卡片布局
2. 外观设置分组：深色模式开关
3. 通知设置分组：价格变化通知开关
4. 关于分组：版本信息、开源许可
5. 设置变更立即生效
6. 设置持久化存储

### Tasks / Subtasks

- [ ] 创建设置页面 (AC: 1)
  - [ ] 创建 `lib/screens/user_settings_page.dart`
  - [ ] 使用 ListView + Card 布局
- [ ] 实现外观设置 (AC: 2)
  - [ ] 深色模式开关
  - [ ] 绑定 ThemeProvider
- [ ] 实现通知设置 (AC: 3)
  - [ ] 价格变化通知开关
  - [ ] 存储到 Hive
- [ ] 实现关于分组 (AC: 4)
  - [ ] 版本号显示
  - [ ] 开源许可跳转
- [ ] 实现状态管理 (AC: 5, 6)
  - [ ] 立即应用更改
  - [ ] 持久化到 Hive

### Dev Notes

**页面布局**:
```
┌─────────────────────────────────────┐
│  设置                                │
├─────────────────────────────────────┤
│  ┌───────────────────────────────┐  │
│  │  外观设置                      │  │
│  │  ─────────────────────────    │  │
│  │  深色模式               [开关] │  │
│  └───────────────────────────────┘  │
│                                     │
│  ┌───────────────────────────────┐  │
│  │  通知设置                      │  │
│  │  ─────────────────────────    │  │
│  │  价格变化通知           [开关] │  │
│  └───────────────────────────────┘  │
│                                     │
│  ┌───────────────────────────────┐  │
│  │  关于                          │  │
│  │  ─────────────────────────    │  │
│  │  版本 1.0.0                   │  │
│  │  开源许可                   > │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

**设置卡片组件**:
```dart
Card(
  margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          '外观设置',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      SwitchListTile(
        title: Text('深色模式'),
        subtitle: Text('跟随系统或手动切换'),
        value: isDarkMode,
        onChanged: (value) => toggleDarkMode(value),
      ),
    ],
  ),
)
```

### Testing

**测试文件位置**: `test/screens/user_settings_page_test.dart`

**测试要求**:
- 测试页面渲染
- 测试开关状态
- 测试持久化

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 6.2: 主题切换功能

### Status
Draft

### Story
**As a** 用户,  
**I want** 切换深色/浅色主题,  
**so that** 我能在不同环境下舒适使用

### Acceptance Criteria

1. 支持浅色模式
2. 支持深色模式
3. 支持跟随系统设置
4. 切换立即生效
5. 设置持久化

### Tasks / Subtasks

- [ ] 实现主题切换 (AC: 1, 2, 3)
  - [ ] ThemeProvider 支持三种模式
  - [ ] light / dark / system
- [ ] 实现立即切换 (AC: 4)
  - [ ] MaterialApp 监听状态
  - [ ] 自动重建 UI
- [ ] 实现持久化 (AC: 5)
  - [ ] 保存到 Hive
  - [ ] 启动时读取

### Dev Notes

**ThemeProvider 实现**:
```dart
enum AppThemeMode { light, dark, system }

class ThemeNotifier extends StateNotifier<AppThemeMode> {
  final Box _settingsBox;
  
  ThemeNotifier(this._settingsBox) 
    : super(_loadThemeMode(_settingsBox));
  
  static AppThemeMode _loadThemeMode(Box box) {
    final String? saved = box.get('theme_mode');
    return AppThemeMode.values.firstWhere(
      (e) => e.name == saved,
      orElse: () => AppThemeMode.system,
    );
  }
  
  void setThemeMode(AppThemeMode mode) {
    state = mode;
    _settingsBox.put('theme_mode', mode.name);
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, AppThemeMode>((ref) {
  final box = Hive.box('settings');
  return ThemeNotifier(box);
});
```

**MaterialApp 配置**:
```dart
Consumer(
  builder: (context, ref, child) {
    final themeMode = ref.watch(themeProvider);
    return MaterialApp(
      themeMode: themeMode.toFlutterThemeMode(),
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      // ...
    );
  },
)
```

### Testing

**测试文件位置**: `test/core/theme/theme_provider_test.dart`

**测试要求**:
- 测试主题切换
- 测试持久化
- 测试系统跟随

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |




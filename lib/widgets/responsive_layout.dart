import 'package:flutter/material.dart';

/// 屏幕尺寸枚举
/// 
/// 断点定义：
/// - compact: < 600dp (手机)
/// - medium: 600-839dp (平板竖屏)
/// - expanded: 840-1199dp (平板横屏/小桌面)
/// - large: >= 1200dp (大桌面)
enum ScreenSize {
  compact,
  medium,
  expanded,
  large,
}

/// 响应式布局组件
/// 
/// 使用 LayoutBuilder 自动检测屏幕尺寸，并根据不同尺寸渲染不同布局
class ResponsiveLayout extends StatelessWidget {
  /// 构建函数，接收 BuildContext 和 ScreenSize
  final Widget Function(BuildContext context, ScreenSize screenSize) builder;

  const ResponsiveLayout({
    super.key,
    required this.builder,
  });

  /// 根据宽度获取屏幕尺寸类型
  static ScreenSize getScreenSize(double width) {
    if (width < 600) return ScreenSize.compact;
    if (width < 840) return ScreenSize.medium;
    if (width < 1200) return ScreenSize.expanded;
    return ScreenSize.large;
  }

  /// 判断是否为桌面端（宽度 > 800dp）
  static bool isDesktop(double width) => width > 800;

  /// 判断是否为移动端（宽度 <= 800dp）
  static bool isMobile(double width) => width <= 800;

  /// 判断是否为紧凑模式（宽度 < 600dp）
  static bool isCompact(double width) => width < 600;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = getScreenSize(constraints.maxWidth);
        return builder(context, screenSize);
      },
    );
  }
}

/// 响应式布局扩展方法
extension ResponsiveLayoutExtension on BuildContext {
  /// 获取当前屏幕尺寸类型
  ScreenSize get screenSize {
    final width = MediaQuery.of(this).size.width;
    return ResponsiveLayout.getScreenSize(width);
  }

  /// 判断是否为桌面端
  bool get isDesktop {
    final width = MediaQuery.of(this).size.width;
    return ResponsiveLayout.isDesktop(width);
  }

  /// 判断是否为移动端
  bool get isMobile {
    final width = MediaQuery.of(this).size.width;
    return ResponsiveLayout.isMobile(width);
  }

  /// 判断是否为紧凑模式
  bool get isCompact {
    final width = MediaQuery.of(this).size.width;
    return ResponsiveLayout.isCompact(width);
  }
}

/// 自适应 Scaffold 组件
/// 
/// 根据屏幕尺寸自动切换导航模式：
/// - 桌面端：NavigationRail
/// - 移动端：NavigationBar (底部导航)
class AdaptiveScaffold extends StatelessWidget {
  /// 导航项列表
  final List<NavigationDestination> destinations;

  /// 页面列表（与 destinations 一一对应）
  final List<Widget> pages;

  /// 当前选中索引
  final int selectedIndex;

  /// 导航项选择回调
  final ValueChanged<int> onDestinationSelected;

  /// 顶部 leading widget（用于 NavigationRail）
  final Widget? leading;

  /// 顶部 trailing widget（用于 NavigationRail）
  final Widget? trailing;

  const AdaptiveScaffold({
    super.key,
    required this.destinations,
    required this.pages,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.leading,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      builder: (context, screenSize) {
        // 判断是否使用桌面端导航
        final useRail = screenSize == ScreenSize.expanded ||
            screenSize == ScreenSize.large;

        if (useRail) {
          // 桌面端：使用 NavigationRail
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onDestinationSelected,
                  labelType: NavigationRailLabelType.all,
                  extended: screenSize == ScreenSize.large,
                  leading: leading,
                  trailing: trailing,
                  destinations: destinations
                      .map((d) => NavigationRailDestination(
                            icon: d.icon,
                            selectedIcon: d.selectedIcon,
                            label: Text(d.label),
                          ))
                      .toList(),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: pages[selectedIndex],
                ),
              ],
            ),
          );
        }

        // 移动端：使用 NavigationBar
        return Scaffold(
          body: pages[selectedIndex],
          bottomNavigationBar: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            destinations: destinations,
          ),
        );
      },
    );
  }
}

/// 响应式网格布局
/// 
/// 根据屏幕尺寸自动调整列数
class ResponsiveGridView extends StatelessWidget {
  /// 子组件列表
  final List<Widget> children;

  /// 紧凑模式列数（默认 1）
  final int compactColumns;

  /// 中等模式列数（默认 2）
  final int mediumColumns;

  /// 展开模式列数（默认 3）
  final int expandedColumns;

  /// 大屏模式列数（默认 4）
  final int largeColumns;

  /// 间距（默认 16）
  final double spacing;

  /// 交叉轴间距（默认等于 spacing）
  final double? crossAxisSpacing;

  /// 子组件宽高比（默认 1）
  final double childAspectRatio;

  const ResponsiveGridView({
    super.key,
    required this.children,
    this.compactColumns = 1,
    this.mediumColumns = 2,
    this.expandedColumns = 3,
    this.largeColumns = 4,
    this.spacing = 16,
    this.crossAxisSpacing,
    this.childAspectRatio = 1,
  });

  int _getColumns(ScreenSize size) {
    switch (size) {
      case ScreenSize.compact:
        return compactColumns;
      case ScreenSize.medium:
        return mediumColumns;
      case ScreenSize.expanded:
        return expandedColumns;
      case ScreenSize.large:
        return largeColumns;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      builder: (context, screenSize) {
        final columns = _getColumns(screenSize);
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: crossAxisSpacing ?? spacing,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: children.length,
          itemBuilder: (context, index) => children[index],
        );
      },
    );
  }
}




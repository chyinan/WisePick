import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// macOS 风格的窗口控制按钮（红黄绿交通灯）
/// 
/// 功能：
/// - 红色按钮：关闭窗口
/// - 黄色按钮：最小化窗口
/// - 绿色按钮：最大化/还原窗口
class MacOSWindowButtons extends StatefulWidget {
  const MacOSWindowButtons({super.key});

  @override
  State<MacOSWindowButtons> createState() => _MacOSWindowButtonsState();
}

class _MacOSWindowButtonsState extends State<MacOSWindowButtons> {
  bool _isHovering = false;
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    _checkMaximized();
  }

  Future<void> _checkMaximized() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final maximized = await windowManager.isMaximized();
      if (mounted) {
        setState(() => _isMaximized = maximized);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 非桌面端不显示
    if (kIsWeb || !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return const SizedBox.shrink();
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 最小化按钮（左）
            _TrafficLightButton(
              color: const Color(0xFFFFBD2E),
              hoverColor: const Color(0xFFFFBD2E),
              icon: Icons.remove,
              isHovering: _isHovering,
              onPressed: () => windowManager.minimize(),
              tooltip: '最小化',
            ),
            const SizedBox(width: 8),
            // 最大化按钮（中）
            _TrafficLightButton(
              color: const Color(0xFF28C840),
              hoverColor: const Color(0xFF28C840),
              icon: _isMaximized ? Icons.fullscreen_exit : Icons.fullscreen,
              isHovering: _isHovering,
              onPressed: () async {
                if (_isMaximized) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
                _checkMaximized();
              },
              tooltip: _isMaximized ? '还原' : '最大化',
            ),
            const SizedBox(width: 8),
            // 关闭按钮（右）
            _TrafficLightButton(
              color: const Color(0xFFFF5F57),
              hoverColor: const Color(0xFFFF5F57),
              icon: Icons.close,
              isHovering: _isHovering,
              onPressed: () => windowManager.close(),
              tooltip: '关闭',
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个交通灯按钮
class _TrafficLightButton extends StatefulWidget {
  final Color color;
  final Color hoverColor;
  final IconData icon;
  final bool isHovering;
  final VoidCallback onPressed;
  final String tooltip;

  const _TrafficLightButton({
    required this.color,
    required this.hoverColor,
    required this.icon,
    required this.isHovering,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  State<_TrafficLightButton> createState() => _TrafficLightButtonState();
}

class _TrafficLightButtonState extends State<_TrafficLightButton> {
  bool _isButtonHovering = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isButtonHovering = true),
        onExit: (_) => setState(() => _isButtonHovering = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.4),
                  blurRadius: _isButtonHovering ? 6 : 2,
                  spreadRadius: _isButtonHovering ? 1 : 0,
                ),
              ],
              border: Border.all(
                color: widget.color.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: widget.isHovering || _isButtonHovering
                ? Center(
                    child: Icon(
                      widget.icon,
                      size: 10,
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// 自定义标题栏 - 包含 macOS 风格按钮和可拖拽区域
class MacOSTitleBar extends StatelessWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Color? backgroundColor;

  const MacOSTitleBar({
    super.key,
    this.title,
    this.actions,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    // 非桌面端不显示
    if (kIsWeb || !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final bgColor = backgroundColor ?? theme.colorScheme.surface;

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 左侧操作按钮
          if (actions != null) ...actions!,
          // 可拖拽区域
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: () async {
                final isMaximized = await windowManager.isMaximized();
                if (isMaximized) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              child: title != null
                  ? Center(child: title)
                  : const SizedBox.expand(),
            ),
          ),
          // 窗口控制按钮放在右边（符合 Windows 习惯）
          const MacOSWindowButtons(),
        ],
      ),
    );
  }
}


import 'package:flutter/material.dart';
import 'dart:ui' as ui;

/// Shimmer 闪烁效果组件
/// 
/// 提供从左到右的高光扫过效果，用于骨架屏加载动画
class ShimmerEffect extends StatefulWidget {
  /// 要应用 shimmer 效果的子组件
  final Widget child;
  
  /// 基础颜色（默认使用 surfaceVariant）
  final Color? baseColor;
  
  /// 高光颜色（默认使用 surface）
  final Color? highlightColor;
  
  /// 动画时长（默认 1500ms）
  final Duration duration;

  const ShimmerEffect({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  State<ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<ShimmerEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.baseColor ??
        Theme.of(context).colorScheme.surfaceVariant;
    final highlightColor = widget.highlightColor ??
        Theme.of(context).colorScheme.surface;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [baseColor, highlightColor, baseColor],
              stops: [
                (_controller.value - 0.3).clamp(0.0, 1.0),
                _controller.value.clamp(0.0, 1.0),
                (_controller.value + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: widget.child,
        );
      },
    );
  }
}

/// 骨架屏基础组件 - 矩形
class SkeletonBox extends StatelessWidget {
  /// 宽度（默认 double.infinity）
  final double? width;
  
  /// 高度（必需）
  final double height;
  
  /// 圆角半径（默认 4dp）
  final double borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 4,
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

/// 骨架屏基础组件 - 圆形
class SkeletonCircle extends StatelessWidget {
  /// 直径
  final double diameter;

  const SkeletonCircle({
    super.key,
    required this.diameter,
  });

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// 商品卡片骨架屏
class ProductCardSkeleton extends StatelessWidget {
  /// 是否展开到全宽
  final bool expandToFullWidth;

  const ProductCardSkeleton({
    super.key,
    this.expandToFullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      width: expandToFullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 商品图片骨架
          const SkeletonBox(
            width: 96,
            height: 96,
            borderRadius: 8,
          ),
          const SizedBox(width: 12),
          // 商品信息骨架
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题骨架
                const SkeletonBox(
                  height: 16,
                  borderRadius: 4,
                ),
                const SizedBox(height: 8),
                const SkeletonBox(
                  height: 14,
                  width: 200,
                  borderRadius: 4,
                ),
                const Spacer(),
                // 价格骨架
                Row(
                  children: [
                    const SkeletonBox(
                      height: 20,
                      width: 80,
                      borderRadius: 4,
                    ),
                    const SizedBox(width: 8),
                    const SkeletonBox(
                      height: 14,
                      width: 60,
                      borderRadius: 4,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 平台标识骨架
                const SkeletonBox(
                  height: 20,
                  width: 50,
                  borderRadius: 4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 消息气泡骨架屏
class MessageBubbleSkeleton extends StatelessWidget {
  /// 是否为用户消息（影响对齐方式）
  final bool isUser;

  const MessageBubbleSkeleton({
    super.key,
    this.isUser = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const SkeletonCircle(diameter: 32),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: isUser
                    ? const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(4),
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      )
                    : const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(height: 14, borderRadius: 4),
                  const SizedBox(height: 6),
                  const SkeletonBox(height: 14, width: 250, borderRadius: 4),
                  const SizedBox(height: 6),
                  const SkeletonBox(height: 14, width: 180, borderRadius: 4),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            const SkeletonCircle(diameter: 32),
          ],
        ],
      ),
    );
  }
}


import 'dart:async';

import 'package:flutter/material.dart';

/// 商品图片轮播组件，支持自动播放和全屏预览
class ProductImageGallery extends StatefulWidget {
  final List<String> images;
  final bool isLoading;
  final String? imageError;
  final bool wide;

  const ProductImageGallery({
    super.key,
    required this.images,
    this.isLoading = false,
    this.imageError,
    this.wide = false,
  });

  @override
  State<ProductImageGallery> createState() => _ProductImageGalleryState();
}

class _ProductImageGalleryState extends State<ProductImageGallery> {
  late final PageController _pageController;
  int _currentIndex = 0;
  Timer? _autoPlayTimer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    if (widget.images.length > 1) _startAutoPlay();
  }

  @override
  void didUpdateWidget(ProductImageGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.images != widget.images) {
      _stopAutoPlay();
      setState(() => _currentIndex = 0);
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      if (widget.images.length > 1) _startAutoPlay();
    }
  }

  @override
  void dispose() {
    _stopAutoPlay();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || widget.images.length <= 1 || !_pageController.hasClients) return;
      final next = (_currentIndex + 1) % widget.images.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOut,
      );
    });
  }

  void _stopAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
  }

  String _heroTag(int index) => 'product_gallery_image_$index';

  Future<void> _openFullScreen(int initialIndex) async {
    if (!mounted || widget.images.isEmpty) return;
    final controller = PageController(initialPage: initialIndex);
    int current = initialIndex;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      barrierLabel: '关闭预览',
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, _, __) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Material(
              color: Colors.black,
              child: SafeArea(
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: controller,
                      itemCount: widget.images.length,
                      onPageChanged: (v) => setDialogState(() => current = v),
                      itemBuilder: (_, index) {
                        return InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 4.0,
                          child: Center(
                            child: Hero(
                              tag: _heroTag(index),
                              child: Image.network(
                                widget.images[index],
                                fit: BoxFit.contain,
                                loadingBuilder: (_, child, progress) {
                                  if (progress == null) return child;
                                  return Center(
                                    child: CircularProgressIndicator(
                                      value: progress.expectedTotalBytes != null
                                          ? progress.cumulativeBytesLoaded /
                                              progress.expectedTotalBytes!
                                          : null,
                                      color: Colors.white,
                                    ),
                                  );
                                },
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.broken_image,
                                  color: Colors.white54,
                                  size: 56,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: IconButton(
                        onPressed: () => Navigator.of(ctx).maybePop(),
                        icon: const Icon(Icons.close, color: Colors.white, size: 28),
                        tooltip: '关闭',
                      ),
                    ),
                    if (widget.images.length > 1) ...[
                      Positioned(
                        bottom: 20,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${current + 1} / ${widget.images.length}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12, top: 0, bottom: 0,
                        child: Center(
                          child: IconButton(
                            onPressed: current > 0
                                ? () => controller.previousPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut)
                                : null,
                            icon: Icon(Icons.chevron_left,
                                color: current > 0 ? Colors.white : Colors.white30,
                                size: 48),
                            tooltip: '上一张',
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12, top: 0, bottom: 0,
                        child: Center(
                          child: IconButton(
                            onPressed: current < widget.images.length - 1
                                ? () => controller.nextPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut)
                                : null,
                            icon: Icon(Icons.chevron_right,
                                color: current < widget.images.length - 1
                                    ? Colors.white
                                    : Colors.white30,
                                size: 48),
                            tooltip: '下一张',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double width = widget.wide ? 360 : double.infinity;
    final double height = widget.wide ? 360 : 240;
    final borderRadius = BorderRadius.circular(12);

    Widget content;
    if (widget.images.isEmpty) {
      content = Center(
        child: widget.isLoading
            ? const CircularProgressIndicator()
            : Icon(Icons.image_not_supported,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    } else {
      content = PageView.builder(
        key: ValueKey(widget.images.length),
        controller: _pageController,
        onPageChanged: (index) {
          if (!mounted) return;
          setState(() => _currentIndex = index);
        },
        itemCount: widget.images.length,
        itemBuilder: (ctx, index) {
          return GestureDetector(
            onTap: () => _openFullScreen(index),
            child: Hero(
              tag: _heroTag(index),
              child: Image.network(
                widget.images[index],
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(Icons.broken_image,
                      size: 42,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          );
        },
      );
    }

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: borderRadius,
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: content,
            ),
          ),
          if (widget.images.length > 1)
            Positioned(
              left: 0, right: 0, bottom: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.images.length, (idx) {
                  final active = idx == _currentIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 6,
                    width: active ? 16 : 6,
                    decoration: BoxDecoration(
                      color: active
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white70,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  );
                }),
              ),
            ),
          if (widget.isLoading)
            Positioned(
              top: 12, right: 12,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                ),
              ),
            ),
          if (widget.imageError != null)
            Positioned(
              top: 12, left: 12,
              child: Tooltip(
                message: widget.imageError!,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: Colors.orangeAccent, size: 14),
                      SizedBox(width: 4),
                      Text('图片加载失败',
                          style: TextStyle(fontSize: 10, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

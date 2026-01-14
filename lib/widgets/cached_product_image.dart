import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 缓存商品图片组件
/// 
/// 使用 cached_network_image 库自动缓存网络图片到本地磁盘，
/// 避免每次进入聊天记录都需要重新加载图片。
/// 
/// 缓存策略：
/// - 图片会自动缓存到本地磁盘
/// - 下次加载时优先从缓存读取，极大提升加载速度
/// - 缓存有效期默认 30 天
class CachedProductImage extends StatelessWidget {
  /// 图片 URL
  final String imageUrl;
  
  /// 图片宽度
  final double? width;
  
  /// 图片高度
  final double? height;
  
  /// 图片填充模式
  final BoxFit fit;
  
  /// 圆角半径
  final double borderRadius;
  
  /// 占位图标大小
  final double? placeholderIconSize;
  
  /// 错误图标大小
  final double? errorIconSize;

  const CachedProductImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 0,
    this.placeholderIconSize,
    this.errorIconSize,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconSize = errorIconSize ?? (width != null ? width! * 0.3 : 24.0);
    
    if (imageUrl.isEmpty) {
      return _buildPlaceholder(theme, iconSize);
    }
    
    // 获取设备像素比，用于计算高清缓存尺寸
    // 使用 2.5x 确保在高分屏上也清晰
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final cacheScale = (devicePixelRatio * 1.5).clamp(2.0, 3.0);
    
    Widget image = CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      // 加载中显示渐变动画占位符
      placeholder: (context, url) => _buildLoadingPlaceholder(theme),
      // 加载失败显示错误图标
      errorWidget: (context, url, error) => _buildErrorPlaceholder(theme, iconSize),
      // 淡入动画时长
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: const Duration(milliseconds: 200),
      // 内存缓存配置 - 使用 2.5~3x 分辨率确保清晰度
      memCacheWidth: width != null ? (width! * cacheScale).toInt() : null,
      memCacheHeight: height != null ? (height! * cacheScale).toInt() : null,
    );
    
    if (borderRadius > 0) {
      image = ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: image,
      );
    }
    
    return image;
  }
  
  /// 构建加载中占位符
  Widget _buildLoadingPlaceholder(ThemeData theme) {
    return Container(
      width: width,
      height: height,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
  
  /// 构建错误占位符
  Widget _buildErrorPlaceholder(ThemeData theme, double iconSize) {
    return Container(
      width: width,
      height: height,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.broken_image_outlined,
        size: iconSize,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
  
  /// 构建空图片占位符
  Widget _buildPlaceholder(ThemeData theme, double iconSize) {
    Widget placeholder = Container(
      width: width,
      height: height,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.image_not_supported_outlined,
        size: iconSize,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
    
    if (borderRadius > 0) {
      placeholder = ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: placeholder,
      );
    }
    
    return placeholder;
  }
}


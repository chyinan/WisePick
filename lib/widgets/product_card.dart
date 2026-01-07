import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wisepick_dart_version/features/products/jd_price_provider.dart';
import '../features/products/product_model.dart';

/// 商品卡片显示模式
enum ProductCardMode {
  /// 紧凑模式（列表视图）- 固定高度 120dp
  compact,
  
  /// 展开模式（详情弹窗）- 更大的尺寸，显示更多信息
  expanded,
  
  /// 聊天嵌入模式 - 适合嵌入消息流，更紧凑
  chat,
}

/// 优化后的商品卡片组件
/// 风格：Clean, Info-dense, Desktop-friendly
class ProductCard extends ConsumerStatefulWidget {
  final ProductModel product;
  final VoidCallback? onTap;
  final ValueChanged<ProductModel>? onFavorite;
  final bool expandToFullWidth;
  final ProductCardMode mode;

  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.onFavorite,
    this.expandToFullWidth = false,
    this.mode = ProductCardMode.compact,
  });
  
  /// 紧凑模式构造函数
  const ProductCard.compact({
    super.key,
    required this.product,
    this.onTap,
    this.onFavorite,
    this.expandToFullWidth = false,
  }) : mode = ProductCardMode.compact;
  
  /// 展开模式构造函数
  const ProductCard.expanded({
    super.key,
    required this.product,
    this.onTap,
    this.onFavorite,
    this.expandToFullWidth = true,
  }) : mode = ProductCardMode.expanded;
  
  /// 聊天嵌入模式构造函数
  const ProductCard.chat({
    super.key,
    required this.product,
    this.onTap,
    this.onFavorite,
    this.expandToFullWidth = false,
  }) : mode = ProductCardMode.chat;

  @override
  ConsumerState<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends ConsumerState<ProductCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(
        parent: _scaleController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _scaleController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _scaleController.reverse();
    widget.onTap?.call();
  }

  void _handleTapCancel() {
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final jdPrices = ref.watch(jdPriceCacheProvider);
    final cachedPrice = jdPrices[widget.product.id];
    final theme = Theme.of(context);
    
    // Determine platform color
    Color platformColor;
    String platformName;
    switch (widget.product.platform) {
      case 'pdd':
        platformColor = const Color(0xFFE02E24);
        platformName = '拼多多';
        break;
      case 'jd':
        platformColor = const Color(0xFFE4393C);
        platformName = '京东';
        break;
      case 'taobao':
        platformColor = const Color(0xFFFF5000);
        platformName = '淘宝';
        break;
      default:
        platformColor = Colors.grey;
        platformName = '未知';
    }

    // 根据模式调整尺寸和布局
    Widget cardContent;
    switch (widget.mode) {
      case ProductCardMode.compact:
        cardContent = _buildCompactCard(context, ref, theme, platformColor, platformName, cachedPrice);
        break;
      case ProductCardMode.expanded:
        cardContent = _buildExpandedCard(context, ref, theme, platformColor, platformName, cachedPrice);
        break;
      case ProductCardMode.chat:
        cardContent = _buildChatCard(context, ref, theme, platformColor, platformName, cachedPrice);
        break;
    }

    // 添加缩放动画
    if (widget.onTap == null) {
      return cardContent;
    }
    
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: cardContent,
          );
        },
      ),
    );
  }

  /// 紧凑模式布局
  Widget _buildCompactCard(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    Color platformColor,
    String platformName,
    double? cachedPrice,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        hoverColor: theme.colorScheme.primary.withOpacity(0.04),
        child: SizedBox(
          height: 120, // 固定高度，保持整齐
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 图片区域
              SizedBox(
                width: 120,
                height: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: widget.product.imageUrl.isNotEmpty
                      ? Image.network(
                          widget.product.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        )
                      : Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.image_not_supported_outlined),
                        ),
                ),
              ),
              
              // 内容区域
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 标题
                      Text(
                        widget.product.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 15,
                          height: 1.3,
                        ),
                      ),
                      
                      // 底部栏：价格 + 平台 + 操作
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // 价格
                          Text(
                            widget.product.platform == 'jd'
                                ? (cachedPrice != null ? '¥${cachedPrice.toStringAsFixed(2)}' : '¥--.--')
                                : '¥${widget.product.price > 0 ? widget.product.price.toStringAsFixed(2) : '询价'}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(width: 8),
                          
                          // 平台标签
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: platformColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: platformColor.withOpacity(0.5), width: 0.5),
                            ),
                            child: Text(
                              platformName,
                              style: TextStyle(
                                color: platformColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          
                          const Spacer(),
                          
                          // 收藏按钮 (如果提供)
                          if (widget.onFavorite != null)
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => widget.onFavorite?.call(widget.product),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Icon(
                                    Icons.favorite_border,
                                    size: 20,
                                    color: theme.colorScheme.secondary,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 展开模式布局（显示更多信息）
  Widget _buildExpandedCard(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    Color platformColor,
    String platformName,
    double? cachedPrice,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        hoverColor: theme.colorScheme.primary.withOpacity(0.04),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 图片区域（更大）
                  SizedBox(
                    width: 160,
                    height: 160,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: widget.product.imageUrl.isNotEmpty
                          ? Image.network(
                              widget.product.imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: theme.colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.broken_image_outlined),
                              ),
                            )
                          : Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.image_not_supported_outlined),
                            ),
                    ),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // 内容区域
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 标题（更多行）
                        Text(
                          widget.product.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 18,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        
                        const SizedBox(height: 12),
                        
                        // 价格信息（更详细）
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              widget.product.platform == 'jd'
                                  ? (cachedPrice != null ? '¥${cachedPrice.toStringAsFixed(2)}' : '¥--.--')
                                  : '¥${widget.product.price > 0 ? widget.product.price.toStringAsFixed(2) : '询价'}',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (widget.product.originalPrice > 0 && widget.product.originalPrice > widget.product.price) ...[
                              const SizedBox(width: 8),
                              Text(
                                '¥${widget.product.originalPrice.toStringAsFixed(2)}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  decoration: TextDecoration.lineThrough,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                        
                        const SizedBox(height: 8),
                        
                        // 平台和店铺信息
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: platformColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: platformColor.withOpacity(0.5), width: 0.5),
                              ),
                              child: Text(
                                platformName,
                                style: TextStyle(
                                  color: platformColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (widget.product.shopTitle.isNotEmpty)
                              Text(
                                widget.product.shopTitle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              // 底部操作栏
              if (widget.onFavorite != null) ...[
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => widget.onFavorite?.call(widget.product),
                      icon: Icon(Icons.favorite_border, size: 20),
                      label: const Text('收藏'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 聊天嵌入模式布局（更紧凑）
  Widget _buildChatCard(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    Color platformColor,
    String platformName,
    double? cachedPrice,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: widget.onTap,
        hoverColor: theme.colorScheme.primary.withOpacity(0.04),
        child: SizedBox(
          height: 100, // 更紧凑的高度
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 图片区域（更小）
              SizedBox(
                width: 100,
                height: 100,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: widget.product.imageUrl.isNotEmpty
                      ? Image.network(
                          widget.product.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.broken_image_outlined, size: 24),
                          ),
                        )
                      : Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.image_not_supported_outlined, size: 24),
                        ),
                ),
              ),
              
              // 内容区域
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 标题（单行）
                      Text(
                        widget.product.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontSize: 14,
                          height: 1.3,
                        ),
                      ),
                      
                      // 底部栏：价格 + 平台
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 价格
                          Text(
                            widget.product.platform == 'jd'
                                ? (cachedPrice != null ? '¥${cachedPrice.toStringAsFixed(2)}' : '¥--.--')
                                : '¥${widget.product.price > 0 ? widget.product.price.toStringAsFixed(2) : '询价'}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 6),
                          
                          // 平台标签（更小）
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: platformColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: platformColor.withOpacity(0.5), width: 0.5),
                            ),
                            child: Text(
                              platformName,
                              style: TextStyle(
                                color: platformColor,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

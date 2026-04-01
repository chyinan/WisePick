import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/products/product_model.dart';
import 'cached_product_image.dart';

/// 商品卡片显示模式
enum ProductCardMode {
  /// 紧凑模式（列表视图）
  compact,

  /// 展开模式（详情弹窗）
  expanded,

  /// 聊天嵌入模式
  chat,

  /// 购物车内嵌模式 - 含数量控制 "- 1 +"
  cartInline,
}

/// 优化后的商品卡片组件
/// 风格：Clean, Info-dense, Desktop-friendly
class ProductCard extends ConsumerStatefulWidget {
  final ProductModel product;
  final VoidCallback? onTap;
  final ValueChanged<ProductModel>? onFavorite;
  final bool expandToFullWidth;
  final ProductCardMode mode;
  /// 购物车内嵌模式的商品数量
  final int? quantity;
  /// 购物车内嵌模式的数量变化回调 (newQty)
  final ValueChanged<int>? onQuantityChanged;

  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.onFavorite,
    this.expandToFullWidth = false,
    this.mode = ProductCardMode.compact,
    this.quantity,
    this.onQuantityChanged,
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
        cardContent = _buildCompactCard(context, ref, theme, platformColor, platformName);
        break;
      case ProductCardMode.expanded:
        cardContent = _buildExpandedCard(context, ref, theme, platformColor, platformName);
        break;
      case ProductCardMode.chat:
        cardContent = _buildChatCard(context, ref, theme, platformColor, platformName);
        break;
      case ProductCardMode.cartInline:
        cardContent = _buildCartInlineCard(context, ref, theme, platformColor, platformName);
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
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        hoverColor: theme.colorScheme.primary.withValues(alpha: 0.04),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 手机端 (<400px)：缩小图片；平板端：保持适中；桌面端：保持固定
            final maxWidth = constraints.maxWidth;
            final bool isNarrowMobile = maxWidth < 400;
            final bool isMobile = maxWidth < 600;

            // 图片尺寸响应式
            final imageSize = isNarrowMobile ? 90.0 : (isMobile ? 100.0 : 120.0);
            // 固定高度随图片等比缩放
            final cardHeight = imageSize;
            // 价格字体大小响应式
            final priceFontSize = isNarrowMobile ? 14.0 : (isMobile ? 16.0 : 18.0);
            // 下架价格字体
            final offShelfPriceFontSize = isNarrowMobile ? 10.0 : 12.0;

            final outerPadding = EdgeInsets.symmetric(
            horizontal: isNarrowMobile ? 8.0 : 12.0,
            vertical: isNarrowMobile ? 8.0 : 10.0);
        return SizedBox(
          height: imageSize,
          child: Padding(
            padding: outerPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 图片区域（使用缓存图片组件）
                CachedProductImage(
                  imageUrl: widget.product.imageUrl,
                  width: imageSize,
                  height: imageSize,
                  fit: BoxFit.cover,
                  borderRadius: 12,
                ),

              const SizedBox(width: 8),

              // 内容区域
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(isNarrowMobile ? 8.0 : 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 标题（手机端减少行数）
                      Text(
                        widget.product.title,
                        maxLines: isNarrowMobile ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: isNarrowMobile ? 13.0 : 15.0,
                          height: 1.3,
                        ),
                      ),

                      // 底部栏：价格 + 平台 + 操作
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // 价格
                          Text(
                            _getPriceText(widget.product),
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: _isOffShelf(widget.product)
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: _isOffShelf(widget.product)
                                  ? offShelfPriceFontSize
                                  : priceFontSize,
                            ),
                          ),
                          SizedBox(width: isNarrowMobile ? 4.0 : 8.0),

                          // 平台标签（手机端更小）
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isNarrowMobile ? 4.0 : 6.0,
                              vertical: isNarrowMobile ? 1.0 : 2.0,
                            ),
                            decoration: BoxDecoration(
                              color: platformColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: platformColor.withValues(alpha: 0.5),
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              platformName,
                              style: TextStyle(
                                color: platformColor,
                                fontSize: isNarrowMobile ? 9.0 : 10.0,
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
                                  padding: EdgeInsets.all(isNarrowMobile ? 4.0 : 8.0),
                                  child: Icon(
                                    Icons.favorite_border,
                                    size: isNarrowMobile ? 16.0 : 20.0,
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
        );
          },
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
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        hoverColor: theme.colorScheme.primary.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 图片区域（更大，使用缓存图片组件）
                  CachedProductImage(
                    imageUrl: widget.product.imageUrl,
                    width: 160,
                    height: 160,
                    fit: BoxFit.cover,
                    borderRadius: 12,
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
                              _getPriceText(widget.product),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: _isOffShelf(widget.product) 
                                    ? theme.colorScheme.error 
                                    : theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: _isOffShelf(widget.product) ? 14 : null,
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
                                color: platformColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: platformColor.withValues(alpha: 0.5), width: 0.5),
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
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: widget.onTap,
        hoverColor: theme.colorScheme.primary.withValues(alpha: 0.04),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            final bool isNarrowMobile = maxWidth < 300;
            final bool isMobile = maxWidth < 450;

            // 图片尺寸响应式：窄屏手机更小
            final imageSize = isNarrowMobile ? 70.0 : (isMobile ? 80.0 : 100.0);
            final cardHeight = imageSize;
            final priceFontSize = isNarrowMobile ? 12.0 : (isMobile ? 14.0 : 16.0);
            final offShelfPriceSize = isNarrowMobile ? 9.0 : 11.0;

            return Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 图片区域
                      CachedProductImage(
                        imageUrl: widget.product.imageUrl,
                        width: imageSize,
                        fit: BoxFit.cover,
                        borderRadius: 8,
                        errorIconSize: isNarrowMobile ? 18.0 : 24.0,
                      ),

                      const SizedBox(width: 8),

                      // 内容区域
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(isNarrowMobile ? 6.0 : 10.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // 标题（单行）
                              Text(
                                widget.product.title,
                                maxLines: isNarrowMobile ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontSize: isNarrowMobile ? 12.0 : 14.0,
                                  height: 1.3,
                                ),
                              ),

                              // 底部栏：价格 + 平台
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // 价格
                                  Text(
                                    _getPriceText(widget.product),
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: _isOffShelf(widget.product)
                                          ? theme.colorScheme.error
                                          : theme.colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: _isOffShelf(widget.product)
                                          ? offShelfPriceSize
                                          : priceFontSize,
                                    ),
                                  ),
                                  SizedBox(width: isNarrowMobile ? 4.0 : 6.0),

                                  // 平台标签（更小）
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isNarrowMobile ? 2.0 : 4.0,
                                      vertical: 1.0,
                                    ),
                                    decoration: BoxDecoration(
                                      color: platformColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(3),
                                      border: Border.all(
                                        color: platformColor.withValues(alpha: 0.5),
                                        width: 0.5,
                                      ),
                                    ),
                                    child: Text(
                                      platformName,
                                      style: TextStyle(
                                        color: platformColor,
                                        fontSize: isNarrowMobile ? 8.0 : 9.0,
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
              ],
            );
          },
        ),
      ),
    );
  }

  /// 购物车内嵌模式布局 - 商品卡片内含水平数量控制 "- 1 +"
  Widget _buildCartInlineCard(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    Color platformColor,
    String platformName,
  ) {
    final qty = widget.quantity ?? 1;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        hoverColor: theme.colorScheme.primary.withValues(alpha: 0.04),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            final bool isNarrowMobile = maxWidth < 360;
            final bool isMobile = maxWidth < 480;

            // 图片尺寸响应式
            final imageSize = isNarrowMobile ? 90.0 : (isMobile ? 100.0 : 120.0);
            // 价格字体大小
            final priceFontSize = isNarrowMobile ? 14.0 : (isMobile ? 16.0 : 18.0);
            final offShelfPriceSize = isNarrowMobile ? 10.0 : 12.0;

            return Column(
              children: [
                // 上部：图片 + 信息
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 图片
                      CachedProductImage(
                        imageUrl: widget.product.imageUrl,
                        width: imageSize,
                        fit: BoxFit.cover,
                        borderRadius: 12,
                      ),
                      const SizedBox(width: 8),
                      // 商品信息
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(isNarrowMobile ? 8.0 : 12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // 标题
                              Text(
                                widget.product.title,
                                maxLines: isNarrowMobile ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontSize: isNarrowMobile ? 13.0 : 15.0,
                                  height: 1.3,
                                ),
                              ),
                              // 价格 + 平台
                              Row(
                                children: [
                                  Text(
                                    _getPriceText(widget.product),
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      color: _isOffShelf(widget.product)
                                          ? theme.colorScheme.error
                                          : theme.colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: _isOffShelf(widget.product)
                                          ? offShelfPriceSize
                                          : priceFontSize,
                                    ),
                                  ),
                                  SizedBox(width: isNarrowMobile ? 4.0 : 8.0),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isNarrowMobile ? 4.0 : 6.0,
                                      vertical: isNarrowMobile ? 1.0 : 2.0,
                                    ),
                                    decoration: BoxDecoration(
                                      color: platformColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: platformColor.withValues(alpha: 0.5),
                                        width: 0.5,
                                      ),
                                    ),
                                    child: Text(
                                      platformName,
                                      style: TextStyle(
                                        color: platformColor,
                                        fontSize: isNarrowMobile ? 9.0 : 10.0,
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
                // 下部：水平数量控制 "- 1 +"
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isNarrowMobile ? 8.0 : 12.0,
                    vertical: isNarrowMobile ? 6.0 : 8.0,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
                    border: Border(
                      top: BorderSide(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 减号按钮
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: qty > 1 ? () => widget.onQuantityChanged?.call(qty - 1) : null,
                          child: Container(
                            width: isNarrowMobile ? 32.0 : 36.0,
                            height: isNarrowMobile ? 28.0 : 32.0,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: qty > 1
                                    ? theme.colorScheme.outlineVariant
                                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(
                              Icons.remove,
                              size: isNarrowMobile ? 14.0 : 16.0,
                              color: qty > 1
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                      ),
                      // 数量显示
                      Container(
                        width: isNarrowMobile ? 40.0 : 48.0,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.symmetric(
                            horizontal: BorderSide(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                        child: Text(
                          '$qty',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // 加号按钮
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => widget.onQuantityChanged?.call(qty + 1),
                          child: Container(
                            width: isNarrowMobile ? 32.0 : 36.0,
                            height: isNarrowMobile ? 28.0 : 32.0,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(
                              Icons.add,
                              size: isNarrowMobile ? 14.0 : 16.0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 判断商品是否下架/无货
bool _isOffShelf(ProductModel product) {
  return product.price < 0.01 && product.finalPrice < 0.01;
}

/// 获取价格显示文本
String _getPriceText(ProductModel product) {
  if (_isOffShelf(product)) {
    return '￥--.--';
  }
  if (product.price > 0) {
    return '¥${product.price.toStringAsFixed(2)}';
  }
  if (product.finalPrice > 0) {
    return '¥${product.finalPrice.toStringAsFixed(2)}';
  }
  return '询价';
}

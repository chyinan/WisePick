import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wisepick_dart_version/features/products/jd_price_provider.dart';
import '../features/products/product_model.dart';

/// 优化后的商品卡片组件
/// 风格：Clean, Info-dense, Desktop-friendly
class ProductCard extends ConsumerWidget {
  final ProductModel product;
  final VoidCallback? onTap;
  final ValueChanged<ProductModel>? onFavorite;
  final bool expandToFullWidth;

  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.onFavorite,
    this.expandToFullWidth = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jdPrices = ref.watch(jdPriceCacheProvider);
    final cachedPrice = jdPrices[product.id];
    final theme = Theme.of(context);
    
    // Determine platform color
    Color platformColor;
    String platformName;
    switch (product.platform) {
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

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
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
                child: product.imageUrl.isNotEmpty
                    ? Image.network(
                        product.imageUrl,
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
                        product.title,
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
                            product.platform == 'jd'
                                ? (cachedPrice != null ? '¥${cachedPrice.toStringAsFixed(2)}' : '¥--.--')
                                : '¥${product.price > 0 ? product.price.toStringAsFixed(2) : '询价'}',
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
                          if (onFavorite != null)
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => onFavorite?.call(product),
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
}

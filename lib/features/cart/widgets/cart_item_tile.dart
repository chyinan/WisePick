import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wisepick_dart_version/features/products/product_model.dart';
import 'package:wisepick_dart_version/features/products/product_detail_page.dart';
import 'package:wisepick_dart_version/features/cart/cart_providers.dart';
import 'package:wisepick_dart_version/widgets/cached_product_image.dart';

/// 桌面端购物车单条商品行
class CartItemTile extends ConsumerStatefulWidget {
  final Map<String, dynamic> item;
  const CartItemTile({super.key, required this.item});

  @override
  ConsumerState<CartItemTile> createState() => _CartItemTileState();
}

class _CartItemTileState extends ConsumerState<CartItemTile> {
  bool _isHovered = false;

  double _getEffectivePrice(ProductModel p) =>
      p.price > 0 ? p.price : p.finalPrice > 0 ? p.finalPrice : p.originalPrice;

  Color _platformColor(String platform) {
    switch (platform) {
      case 'pdd': return const Color(0xFFE02E24);
      case 'jd': return const Color(0xFFE4393C);
      case 'taobao': return const Color(0xFFFF5000);
      default: return Colors.grey;
    }
  }

  String _platformName(String platform) {
    switch (platform) {
      case 'pdd': return '拼多多';
      case 'jd': return '京东';
      case 'taobao': return '淘宝';
      default: return '其他';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = widget.item;
    final p = ProductModel.fromMap(m);
    final qty = int.tryParse(m['qty']?.toString() ?? '1') ?? 1;
    final sel = ref.watch(cartSelectionProvider);
    final isSelected = sel[p.id] ?? false;
    final effectivePrice = _getEffectivePrice(p);
    final subtotal = effectivePrice * qty;
    final platformColor = _platformColor(p.platform);
    final platformName = _platformName(p.platform);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _isHovered
              ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
              : (isSelected
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.1)
                  : null),
          border: Border(
              bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3))),
        ),
        child: InkWell(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => ProductDetailPage(product: p))),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (v) {
                      final map = Map<String, bool>.from(sel);
                      map[p.id] = v ?? false;
                      ref.read(cartSelectionProvider.notifier).state = map;
                    },
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedProductImage(
                    imageUrl: p.imageUrl,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: platformColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: platformColor.withValues(alpha: 0.5),
                                  width: 0.5),
                            ),
                            child: Text(platformName,
                                style: TextStyle(
                                    color: platformColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600)),
                          ),
                          if (p.shopTitle.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(p.shopTitle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: Column(
                    children: [
                      Text('¥${effectivePrice.toStringAsFixed(2)}',
                          style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold)),
                      if (p.originalPrice > 0 &&
                          p.originalPrice > effectivePrice)
                        Text('¥${p.originalPrice.toStringAsFixed(2)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                                decoration: TextDecoration.lineThrough,
                                color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CartQuantityButton(
                        icon: Icons.remove,
                        onPressed: qty > 1
                            ? () {
                                ref
                                    .read(cartServiceProvider)
                                    .setQuantity(p.id, qty - 1);
                                ref.invalidate(cartItemsProvider);
                              }
                            : null,
                      ),
                      Container(
                        width: 40,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.symmetric(
                            horizontal: BorderSide(
                                color: theme.colorScheme.outlineVariant),
                          ),
                        ),
                        child: Text('$qty',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w500)),
                      ),
                      CartQuantityButton(
                        icon: Icons.add,
                        onPressed: () {
                          ref
                              .read(cartServiceProvider)
                              .setQuantity(p.id, qty + 1);
                          ref.invalidate(cartItemsProvider);
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: Text('¥${subtotal.toStringAsFixed(2)}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.bold)),
                ),
                SizedBox(
                  width: 80,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _isHovered ? 1.0 : 0.3,
                    child: IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: theme.colorScheme.error),
                      tooltip: '删除',
                      onPressed: () => _confirmDelete(context, ref, p),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, ProductModel p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "${p.title}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(cartServiceProvider).removeItem(p.id);
              ref.invalidate(cartItemsProvider);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 数量调整按钮
class CartQuantityButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  const CartQuantityButton({super.key, required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onPressed,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon,
              size: 16,
              color: onPressed != null
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurface.withValues(alpha: 0.3)),
        ),
      ),
    );
  }
}

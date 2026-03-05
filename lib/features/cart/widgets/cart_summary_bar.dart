import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wisepick_dart_version/features/products/product_model.dart';
import 'package:wisepick_dart_version/features/cart/cart_providers.dart';
import 'package:wisepick_dart_version/widgets/error_snackbar.dart';

/// 购物车底部结算栏
class CartSummaryBar extends ConsumerWidget {
  final List<Map<String, dynamic>> list;
  final bool isDesktop;
  const CartSummaryBar({super.key, required this.list, this.isDesktop = false});

  double _getEffectivePrice(ProductModel p) =>
      p.price > 0 ? p.price : p.finalPrice > 0 ? p.finalPrice : p.originalPrice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sel = ref.watch(cartSelectionProvider);
    double total = 0;
    int count = 0;
    double totalOriginal = 0;
    for (final m in list) {
      if (sel[m['id']] == true) {
        final p = ProductModel.fromMap(m);
        final qty = int.tryParse(m['qty']?.toString() ?? '1') ?? 1;
        final effectivePrice = _getEffectivePrice(p);
        total += effectivePrice * qty;
        totalOriginal +=
            (p.originalPrice > 0 ? p.originalPrice : effectivePrice) * qty;
        count += qty;
      }
    }
    final savings = totalOriginal - total;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 24 : 16,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, -2))
        ],
        border: Border(
            top: BorderSide(
                color: theme.colorScheme.outlineVariant.withOpacity(0.5))),
      ),
      child: isDesktop
          ? _buildDesktopLayout(context, ref, theme, total, count, savings)
          : _buildMobileLayout(context, ref, theme, total, count),
    );
  }

  Widget _buildMobileLayout(BuildContext context, WidgetRef ref,
      ThemeData theme, double total, int count) {
    final sel = ref.watch(cartSelectionProvider);
    final allSelected =
        list.isNotEmpty && list.every((m) => sel[m['id']] == true);

    return Row(
      children: [
        Semantics(
          label: '全选所有商品',
          child: Checkbox(
            value: allSelected,
            onChanged: (v) {
              final map = <String, bool>{};
              for (final m in list) map[m['id']] = v ?? false;
              ref.read(cartSelectionProvider.notifier).state = map;
            },
          ),
        ),
        const Text('全选'),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('合计: ¥${total.toStringAsFixed(2)}',
                style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold)),
            Text('已选 $count 件', style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(width: 16),
        Semantics(
          label: '去结算，已选 $count 件商品，合计 ¥${total.toStringAsFixed(2)}',
          button: true,
          enabled: count > 0,
          child: ElevatedButton(
            onPressed: count > 0
                ? () => _showCheckoutDialog(
                    context, list, ref.read(cartSelectionProvider))
                : null,
            child: const Text('去结算'),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(BuildContext context, WidgetRef ref,
      ThemeData theme, double total, int count, double savings) {
    final sel = ref.watch(cartSelectionProvider);

    return Row(
      children: [
        const Spacer(flex: 2),
        Expanded(
          flex: 3,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text('已选 $count 件',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.primary)),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              if (savings > 0) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('已优惠',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    Text('¥${savings.toStringAsFixed(2)}',
                        style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.green,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(width: 24),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('合计（不含运费）',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('¥',
                          style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.bold)),
                      Text(total.toStringAsFixed(2),
                          style: theme.textTheme.headlineSmall?.copyWith(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 24),
              Semantics(
                label:
                    '去结算，已选 $count 件商品，合计 ¥${total.toStringAsFixed(2)}',
                button: true,
                enabled: count > 0,
                child: FilledButton(
                  onPressed: count > 0
                      ? () => _showCheckoutDialog(context, list, sel)
                      : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16),
                    textStyle: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  child: Text('结算 ($count)'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showCheckoutDialog(BuildContext context,
      List<Map<String, dynamic>> list, Map<String, bool> sel) {
    final selectedItems = list.where((m) => sel[m['id']] == true).toList();
    showDialog(
      context: context,
      builder: (ctx) => CartCheckoutDialog(selectedItems: selectedItems),
    );
  }
}

/// 商品链接弹窗（支持异步获取推广链接）
class CartCheckoutDialog extends StatefulWidget {
  final List<Map<String, dynamic>> selectedItems;
  const CartCheckoutDialog({super.key, required this.selectedItems});

  @override
  State<CartCheckoutDialog> createState() => _CartCheckoutDialogState();
}

class _CartCheckoutDialogState extends State<CartCheckoutDialog> {
  final Map<String, String> _promotionLinks = {};
  final Map<String, bool> _loadingStates = {};

  Future<void> _fetchAndCopyLink(ProductModel p) async {
    setState(() => _loadingStates[p.id] = true);
    try {
      String link = p.link;
      if (link.isEmpty && p.platform == 'jd') {
        link = 'https://item.jd.com/${p.id}.html';
      }
      _promotionLinks[p.id] = link;
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) showInfoSnackBar(context, '已复制: $link');
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _loadingStates[p.id] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('商品链接'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            children: widget.selectedItems.map((m) {
              final p = ProductModel.fromMap(m);
              final isLoading = _loadingStates[p.id] ?? false;
              final cachedLink = _promotionLinks[p.id];
              return ListTile(
                title: Text(p.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: cachedLink != null
                    ? Text(cachedLink,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12))
                    : null,
                trailing: isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child:
                            CircularProgressIndicator(strokeWidth: 2))
                    : TextButton(
                        onPressed: () => _fetchAndCopyLink(p),
                        child: const Text('复制'),
                      ),
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

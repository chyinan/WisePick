import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wisepick_dart_version/features/products/product_model.dart';
import 'package:wisepick_dart_version/features/products/product_detail_page.dart';
import 'package:wisepick_dart_version/features/cart/cart_providers.dart';
import 'package:wisepick_dart_version/widgets/product_card.dart';
import 'package:wisepick_dart_version/features/products/product_service.dart';
import 'package:wisepick_dart_version/services/price_refresh_service.dart';

class CartPage extends ConsumerWidget {
  const CartPage({super.key});

  String _extractLink(Map<String, dynamic> m, ProductModel p) {
     if (p.link.isNotEmpty) return p.link;
     // fallback logic same as before
     // ... simplified for brevity, relying on product service helper if needed or just returning link
     return p.link;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(cartItemsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('我的购物车')),
      body: asyncList.when(
        data: (List<Map<String, dynamic>> list) {
          if (list.isEmpty) {
             return Center(
                child: Column(
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                      Icon(Icons.shopping_cart_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 16),
                      Text('购物车空空如也', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.outline)),
                   ],
                ),
             );
          }
          
          // Grouping
          final Map<String, List<Map<String, dynamic>>> groups = {};
          for (final m in list) {
             final raw = (m['shop_title'] as String?) ?? (m['shopTitle'] as String?) ?? '其他店铺';
             final shop = raw.trim().isNotEmpty ? raw.trim() : '其他店铺';
             groups.putIfAbsent(shop, () => []).add(m);
          }

          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    // 刷新价格
                    await PriceRefreshService().refreshCartPrices();
                    // 刷新购物车数据
                    ref.invalidate(cartItemsProvider);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: groups.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (ctx, index) {
                      final shopName = groups.keys.elementAt(index);
                      final items = groups[shopName]!;
                      
                      return _CartGroupCard(shopName: shopName, items: items);
                    },
                  ),
                ),
              ),
              _CartBottomBar(list: list),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('加载错误: $e')),
      ),
    );
  }
}

class _CartGroupCard extends ConsumerWidget {
  final String shopName;
  final List<Map<String, dynamic>> items;

  const _CartGroupCard({required this.shopName, required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Shop Header
            Consumer(builder: (context, ref, _) {
               final sel = ref.watch(cartSelectionProvider);
               final allSelected = items.every((m) => sel[m['id']] == true);
               return Row(
                 children: [
                      Semantics(
                        label: '全选 $shopName 店铺商品',
                        child: Checkbox(
                          value: allSelected,
                          onChanged: (v) {
                            final map = Map<String, bool>.from(sel);
                            for (final m in items) {
                              map[m['id']] = v ?? false;
                            }
                            ref.read(cartSelectionProvider.notifier).state = map;
                          },
                        ),
                      ),
                    const SizedBox(width: 8),
                    const Icon(Icons.store, size: 20),
                    const SizedBox(width: 8),
                    Text(shopName, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                 ],
               );
            }),
            const Divider(),
            // Items
            ...items.map((m) {
              final p = ProductModel.fromMap(m);
              final qty = m['qty'] as int? ?? 1;
              return Dismissible(
                key: Key(p.id),
                direction: DismissDirection.endToStart,
                background: Container(
                   alignment: Alignment.centerRight,
                   padding: const EdgeInsets.only(right: 20),
                   color: Colors.red,
                   child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) {
                   ref.read(cartServiceProvider).removeItem(p.id);
                   ref.refresh(cartItemsProvider);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                       Consumer(builder: (context, ref, _) {
                          final sel = ref.watch(cartSelectionProvider);
                          return Checkbox(
                             value: sel[p.id] ?? false,
                             onChanged: (v) {
                                final map = Map<String, bool>.from(sel);
                                map[p.id] = v ?? false;
                                ref.read(cartSelectionProvider.notifier).state = map;
                             },
                          );
                       }),
                       Expanded(
                          child: ProductCard(
                             product: p, 
                             expandToFullWidth: true, 
                             onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(product: p))),
                          ),
                       ),
                       // Quantity Controls - simplified for vertical space
                       Column(
                         children: [
                            IconButton(
                               icon: const Icon(Icons.add_circle_outline), 
                               onPressed: () {
                                  ref.read(cartServiceProvider).setQuantity(p.id, qty + 1);
                                  ref.refresh(cartItemsProvider);
                               }
                            ),
                            Text('$qty'),
                            IconButton(
                               icon: const Icon(Icons.remove_circle_outline), 
                               onPressed: () {
                                  if (qty > 1) {
                                     ref.read(cartServiceProvider).setQuantity(p.id, qty - 1);
                                     ref.refresh(cartItemsProvider);
                                  }
                               }
                            ),
                         ],
                       )
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _CartBottomBar extends ConsumerWidget {
  final List<Map<String, dynamic>> list;
  const _CartBottomBar({required this.list});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sel = ref.watch(cartSelectionProvider);
    double total = 0;
    int count = 0;
    for (final m in list) {
       if (sel[m['id']] == true) {
          final p = ProductModel.fromMap(m);
          final qty = m['qty'] as int? ?? 1;
          total += p.price * qty;
          count += qty;
       }
    }

    return Container(
       padding: const EdgeInsets.all(16),
       decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))],
       ),
       child: Row(
          children: [
             Consumer(builder: (context, ref, _) {
                final allSelected = list.isNotEmpty && list.every((m) => sel[m['id']] == true);
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
                   ],
                );
             }),
             const Spacer(),
             Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                   Text('合计: ¥${total.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                   Text('已选 $count 件', style: Theme.of(context).textTheme.bodySmall),
                ],
             ),
             const SizedBox(width: 16),
             Semantics(
               label: '去结算，已选 $count 件商品，合计 ¥${total.toStringAsFixed(2)}',
               button: true,
               enabled: count > 0,
               child: ElevatedButton(
                 onPressed: count > 0 ? () => _showCheckoutDialog(context, list, sel) : null,
                 child: const Text('去结算'),
               ),
             ),
          ],
       ),
    );
  }

  void _showCheckoutDialog(BuildContext context, List<Map<String, dynamic>> list, Map<String, bool> sel) {
     final selectedItems = list.where((m) => sel[m['id']] == true).toList();
     showDialog(
        context: context,
        builder: (ctx) => _CheckoutLinkDialog(selectedItems: selectedItems),
     );
  }
}

/// 商品链接弹窗（支持异步获取推广链接）
class _CheckoutLinkDialog extends StatefulWidget {
  final List<Map<String, dynamic>> selectedItems;
  const _CheckoutLinkDialog({required this.selectedItems});

  @override
  State<_CheckoutLinkDialog> createState() => _CheckoutLinkDialogState();
}

class _CheckoutLinkDialogState extends State<_CheckoutLinkDialog> {
  final Map<String, String> _promotionLinks = {};
  final Map<String, bool> _loadingStates = {};
  final _dio = Dio();

  Future<String> _getBackendBase() async {
    String backend = 'http://localhost:9527';
    try {
      if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
      final box = Hive.box('settings');
      final String? b = box.get('backend_base') as String?;
      if (b != null && b.trim().isNotEmpty) {
        backend = b.trim();
      } else {
        backend = Platform.environment['BACKEND_BASE'] ?? backend;
      }
    } catch (_) {}
    return backend;
  }

  Future<void> _fetchAndCopyLink(ProductModel p) async {
    setState(() => _loadingStates[p.id] = true);
    
    try {
      String? link = p.link;
      
      // 如果是京东商品且没有有效链接，调用后端获取推广链接
      if (p.platform == 'jd' && (link.isEmpty || !link.contains('u.jd.com'))) {
        final backend = await _getBackendBase();
        try {
          final response = await _dio.get(
            '$backend/api/get-jd-promotion',
            queryParameters: {'sku': p.id},
          );
          
          if (response.data != null && response.data is Map) {
            final data = response.data as Map<String, dynamic>;
            // 尝试从响应中提取推广链接
            link = data['promotionLink'] as String? ??
                   data['shortLink'] as String? ??
                   data['link'] as String? ??
                   '';
          }
        } catch (e) {
          debugPrint('获取京东推广链接失败: $e');
        }
      }
      
      // 如果仍然没有链接，使用原始商品链接作为备用
      if (link == null || link.isEmpty) {
        if (p.platform == 'jd') {
          link = 'https://item.jd.com/${p.id}.html';
        } else {
          link = p.link;
        }
      }
      
      _promotionLinks[p.id] = link;
      
      // 复制到剪贴板
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已复制: $link')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取链接失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loadingStates[p.id] = false);
      }
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
                title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: cachedLink != null 
                    ? Text(cachedLink, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))
                    : null,
                trailing: isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
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

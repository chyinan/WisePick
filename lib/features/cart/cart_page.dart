import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wisepick_dart_version/features/products/product_model.dart';
import 'package:wisepick_dart_version/features/products/product_detail_page.dart';
import 'package:wisepick_dart_version/features/cart/cart_providers.dart';
import 'package:wisepick_dart_version/widgets/product_card.dart';
// cart_service 的引用在 providers 中已存在，这里暂不直接导入
// import 'cart_service.dart';
import 'package:hive/hive.dart';

/// 购物车页：展示本地购物车（替代收藏页）
class CartPage extends ConsumerWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(cartItemsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('购物车', style: Theme.of(context).textTheme.titleMedium), centerTitle: true, backgroundColor: colorScheme.surface, foregroundColor: colorScheme.onSurface, elevation: 0),
      body: asyncList.when(
        data: (List<Map<String, dynamic>> list) {
          if (list.isEmpty) return Center(child: Text('购物车为空', style: Theme.of(context).textTheme.bodyMedium));
          return Column(
            children: <Widget>[
              Expanded(
                child: Builder(builder: (context) {
                  // 将 list 按 shop_title 分组显示
                  final Map<String, List<Map<String, dynamic>>> groups = {};
                  for (final m in list) {
                    try {
                      final raw = (m['shop_title'] as String?) ?? (m['shopTitle'] as String?) ?? '';
                      final shop = raw.trim().isNotEmpty ? raw.trim() : '其他店铺';
                      groups.putIfAbsent(shop, () => <Map<String, dynamic>>[]).add(m);
                    } catch (_) {
                      groups.putIfAbsent('其他店铺', () => <Map<String, dynamic>>[]).add(m);
                    }
                  }
                  final keys = groups.keys.toList();

                  return ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: keys.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, gidx) {
                      final shop = keys[gidx];
                      final items = groups[shop]!;
                      return Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              // 店铺头部（包含店铺选择）
                              Consumer(builder: (c, ref2, _) {
                                final sel = ref2.watch(cartSelectionProvider);
                                final allSelected = items.isNotEmpty && items.every((m) => sel[m['id'] as String] == true);
                                return Row(children: <Widget>[
                                  Checkbox(
                                      value: allSelected,
                                      onChanged: (v) {
                                        final map = Map<String, bool>.from(sel);
                                        for (final m in items) {
                                          map[m['id'] as String] = v ?? false;
                                        }
                                        ref2.read(cartSelectionProvider.notifier).state = map;
                                      }),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(shop, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600))),
                                ]);
                              }),
                              const SizedBox(height: 8),
                              // 店铺内商品列表
                              Column(children: items.map((m) {
                                final p = ProductModel.fromMap(m);
                                final int qty = (m['qty'] as int?) ?? 1;
                                return Dismissible(
                                  key: ValueKey(p.id),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 20),
                                    color: Theme.of(context).colorScheme.error,
                                    child: Icon(Icons.delete, color: Theme.of(context).colorScheme.onError),
                                  ),
                                  onDismissed: (_) async {
                                    final cartSvc = ref.read(cartServiceProvider);
                                    await cartSvc.removeItem(p.id);
                                    final _ = ref.refresh(cartItemsProvider);
                                  },
                                  child: Card(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    margin: const EdgeInsets.symmetric(vertical: 8),
                                    elevation: 0,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 10.0),
                                      child: Row(
                                        children: <Widget>[
                                          Consumer(builder: (c, ref2, _) {
                                            final sel = ref2.watch(cartSelectionProvider);
                                            final checked = sel[p.id] ?? false;
                                            return Checkbox(
                                                value: checked,
                                                onChanged: (v) {
                                                  final map = Map<String, bool>.from(sel);
                                                  map[p.id] = v ?? false;
                                                  ref2.read(cartSelectionProvider.notifier).state = map;
                                                });
                                          }),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: ProductCard(
                                              product: p,
                                              onTap: () {
                                                final String? aiRaw = m['aiParsedRaw'] as String? ?? m['raw_json'] as String?;
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(builder: (_) => ProductDetailPage(product: p, aiParsedRaw: aiRaw)),
                                                );
                                              },
                                              expandToFullWidth: true,
                                              alignRight: true,
                                            ),
                                          ),
                                          Column(children: <Widget>[
                                            IconButton(
                                              onPressed: () async {
                                                final cartSvc = ref.read(cartServiceProvider);
                                                await cartSvc.setQuantity(p.id, qty + 1);
                                                final _ = ref.refresh(cartItemsProvider);
                                              },
                                              icon: Icon(Icons.add_circle_outline, color: colorScheme.primary),
                                            ),
                                            Text('$qty', style: Theme.of(context).textTheme.bodyMedium),
                                            IconButton(
                                              onPressed: () async {
                                                final cartSvc = ref.read(cartServiceProvider);
                                                if (qty > 1) {
                                                  await cartSvc.setQuantity(p.id, qty - 1);
                                                } else {
                                                  await cartSvc.removeItem(p.id);
                                                }
                                                final _ = ref.refresh(cartItemsProvider);
                                              },
                                              icon: Icon(Icons.remove_circle_outline, color: colorScheme.primary),
                                            ),
                                          ])
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList()),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }),
              ),

              // 结算栏
              _CartCheckoutBar(list: list),
            ],
          );
        },
        loading: () => Center(child: CircularProgressIndicator(color: colorScheme.primary)),
        error: (e, st) => Center(child: Text('加载失败：$e', style: Theme.of(context).textTheme.bodyMedium)),
      ),
    );
  }
}

/// 结算栏组件：计算选中项总价并显示结算按钮
class _CartCheckoutBar extends ConsumerWidget {
  final List<Map<String, dynamic>> list;

  const _CartCheckoutBar({required this.list});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(cartSelectionProvider);

    double total = 0.0;
    int count = 0;
    for (final m in list) {
      final id = m['id'] as String;
      final selected = selection[id] ?? false;
      if (selected) {
        final p = ProductModel.fromMap(m);
        final int qty = (m['qty'] as int?) ?? 1;
        total += p.price * qty;
        count += qty;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)]),
      child: Row(
        children: <Widget>[
          // 全选按钮
          Consumer(builder: (c, ref2, _) {
            final sel = ref2.watch(cartSelectionProvider);
            final allSelected = list.isNotEmpty && list.every((m) => sel[m['id'] as String] == true);
            return Row(children: <Widget>[
              Checkbox(value: allSelected, onChanged: (v) {
                final map = <String, bool>{};
                for (final m in list) {
                  map[m['id'] as String] = v ?? false;
                }
                ref2.read(cartSelectionProvider.notifier).state = map;
              }),
              Text('全选', style: Theme.of(context).textTheme.bodyMedium),
            ]);
          }),

          const SizedBox(width: 12),
          Expanded(child: Text('已选 $count 件  合计：¥${total.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodyMedium)),
          ElevatedButton(
              onPressed: count > 0
                  ? () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('结算'),
                          content: Text('确认购买 $count 件，合计 ¥${total.toStringAsFixed(2)}？'),
                          actions: <Widget>[
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('取消', style: Theme.of(context).textTheme.labelLarge)),
                            ElevatedButton(
                                onPressed: () async {
                                  // 占位结算逻辑：清空购物车并关闭
                                  final cartSvc = ref.read(cartServiceProvider);
                                  await cartSvc.clear();
                                  final _ = ref.refresh(cartItemsProvider);
                                  Navigator.of(ctx).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已提交订单（模拟）')));
                                },
                                child: const Text('确认'))
                          ],
                        ),
                      );
                    }
                  : null,
              child: const Text('结算'))
        ],
      ),
    );
  }
}


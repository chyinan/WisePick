import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wisepick_dart_version/features/products/product_model.dart';
import 'package:wisepick_dart_version/features/products/product_detail_page.dart';
import 'package:wisepick_dart_version/features/cart/cart_providers.dart';
import 'package:wisepick_dart_version/widgets/product_card.dart';
// cart_service 的引用在 providers 中已存在，这里暂不直接导入
// import 'cart_service.dart';
import 'package:hive/hive.dart';
import 'package:wisepick_dart_version/features/products/product_service.dart';

// 尝试从存储的 Map 或 ProductModel 中提取可用的商品链接（对 PDD/其他平台做更多容错）
String _extractLink(Map<String, dynamic> m, ProductModel p) {
  String? tryStr(dynamic s) {
    if (s == null) return null;
    if (s is String) {
      final t = s.trim();
      return t.isEmpty ? null : t;
    }
    return null;
  }

  // 优先使用模型中的 link
  final fromModel = tryStr(p.link);
  if (fromModel != null) return fromModel;

  // 常见顶层字段
  final keys = ['link', 'sourceUrl', 'source_url', 'url', 'coupon_click_url', 'click_url', 'mobile_url', 'item_url'];
  for (final k in keys) {
    final v = tryStr(m[k]);
    if (v != null) return v;
  }

  // raw_json 或 aiParsedRaw 里寻找 http/https/duoduo/pdd 等链接
  final raw = tryStr(m['raw_json'] ?? m['aiParsedRaw']);
  if (raw != null) {
    try {
      final decoded = json.decode(raw);
      String? _search(dynamic node) {
        if (node == null) return null;
        if (node is String) {
          final s = node.trim();
          if (s.startsWith('http') || s.startsWith('duoduo://') || s.startsWith('pdd://')) return s;
          final idx = s.indexOf('http');
          if (idx >= 0) return s.substring(idx);
          return null;
        }
        if (node is Map) {
          for (final v in node.values) {
            final r = _search(v);
            if (r != null) return r;
          }
        }
        if (node is List) {
          for (final e in node) {
            final r = _search(e);
            if (r != null) return r;
          }
        }
        return null;
      }

      final found = _search(decoded);
      if (found != null) return found;
    } catch (_) {}
  }

  // 退回原始字段
  return tryStr(m['link'] as String?) ?? '';
}

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
                                                  // 当数量为 1 且用户再次点击减少时，先弹出确认对话框
                                                  final shouldRemove = await showDialog<bool>(
                                                    context: context,
                                                    builder: (ctx) => AlertDialog(
                                                      title: const Text('确认移除'),
                                                      content: const Text('确认要移除该商品吗？'),
                                                      actions: [
                                                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
                                                        TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('移除')),
                                                      ],
                                                    ),
                                                  );
                                                  if (shouldRemove == true) {
                                                    await cartSvc.removeItem(p.id);
                                                  }
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
                      // 显示已选择商品名称与可复制链接的对话框
                      final sel = ref.read(cartSelectionProvider);
                      final selectedItems = <Map<String, dynamic>>[];
                      for (final m in list) {
                        final id = m['id'] as String;
                        if (sel[id] == true) selectedItems.add(m);
                      }

                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('商品购买链接（点击复制）'),
                          content: SizedBox(
                            width: double.maxFinite,
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: selectedItems.map((m) {
                                  final p = ProductModel.fromMap(m);
                                  final link = _extractLink(m, p);
                                  final title = ProductModel.normalizeTitle(p.title);
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: Text(title)),
                                        const SizedBox(width: 8),
                                        GestureDetector(
                                          onTap: () async {
                                            String toCopy = link;

                                            // 如果提取到的是图片链接，则不要直接复制图片链接（常见于 PDD raw 数据）
                                            final imgRe = RegExp(r"\.(jpe?g|png|gif|webp|bmp)(\?|$)", caseSensitive: false);
                                            if (toCopy.isNotEmpty && (imgRe.hasMatch(toCopy) || toCopy.contains('img.pddpic.com') || toCopy.contains('/mms-material-img/'))) {
                                              toCopy = '';
                                            }

                                            // 如果没有链接且是拼多多商品，尝试在线生成推广链接
                                            if (toCopy.isEmpty && p.platform == 'pdd') {
                                              try {
                                                final svc = ProductService();
                                                final gen = await svc.generatePromotionLink(p);
                                                if (gen != null && gen.isNotEmpty) toCopy = gen;
                                              } catch (_) {}
                                            }

                                            if (toCopy.isNotEmpty) {
                                              try {
                                                await Clipboard.setData(ClipboardData(text: toCopy));
                                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制: ${toCopy.length > 50 ? toCopy.substring(0, 50) + '...' : toCopy}')));
                                              } catch (_) {
                                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('复制失败')));
                                              }
                                            } else {
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法获取购买链接')));
                                            }
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: Theme.of(context).colorScheme.primary),
                                            child: const Text('复制', style: TextStyle(color: Colors.white)),
                                          ),
                                        )
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          actions: <Widget>[
                            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('关闭', style: Theme.of(context).textTheme.labelLarge)),
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


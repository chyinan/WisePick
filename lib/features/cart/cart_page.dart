import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wisepick_dart_version/features/products/product_model.dart';
import 'package:wisepick_dart_version/features/products/product_detail_page.dart';
import 'package:wisepick_dart_version/features/cart/cart_providers.dart';
import 'package:wisepick_dart_version/features/auth/auth_providers.dart';
import 'package:wisepick_dart_version/services/sync/sync_manager.dart';
import 'package:wisepick_dart_version/widgets/product_card.dart';
import 'package:wisepick_dart_version/widgets/error_view.dart';
import 'package:wisepick_dart_version/services/price_refresh_service.dart';
import 'widgets/cart_summary_bar.dart';
import 'widgets/cart_item_tile.dart';
/// 桌面端宽度阈值
const double _kDesktopBreakpoint = 800.0;

class CartPage extends ConsumerWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(cartItemsProvider);
    return Scaffold(
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
                      const SizedBox(height: 8),
                      Text('去 AI 助手页面发现心仪商品吧', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
                   ],
                ),
             );
          }
          
          // 使用 LayoutBuilder 实现响应式布局
          return LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= _kDesktopBreakpoint;
              
              // Grouping
              final Map<String, List<Map<String, dynamic>>> groups = {};
              for (final m in list) {
                 final raw = (m['shop_title'] as String?) ?? (m['shopTitle'] as String?) ?? '其他店铺';
                 final shop = raw.trim().isNotEmpty ? raw.trim() : '其他店铺';
                 groups.putIfAbsent(shop, () => []).add(m);
              }

              return Column(
                children: [
                  // 桌面端顶部操作栏
          if (isDesktop) _DesktopCartHeader(list: list),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        // 刷新价格
                        await PriceRefreshService().refreshCartPrices();
                        ref.invalidate(cartItemsProvider);
                        
                        // 如果已登录，同步云端数据
                        final isLoggedIn = ref.read(isLoggedInProvider);
                        if (isLoggedIn) {
                          try {
                            final syncManager = ref.read(syncManagerProvider.notifier);
                            await syncManager.syncCart();
                            // 同步后重新加载本地数据
                            ref.invalidate(cartItemsProvider);
                          } catch (e, st) {
                            dev.log('Cart sync error (non-blocking): $e', name: 'CartPage', error: e, stackTrace: st);
                          }
                        }
                      },
                      child: isDesktop 
                        ? _DesktopCartList(groups: groups, list: list)
                        : _MobileCartList(groups: groups),
                    ),
                  ),
                  CartSummaryBar(list: list, isDesktop: isDesktop),
                ],
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(cartItemsProvider),
        ),
      ),
    );
  }
}

/// 桌面端顶部操作栏
class _DesktopCartHeader extends ConsumerWidget {
  final List<Map<String, dynamic>> list;
  const _DesktopCartHeader({required this.list});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sel = ref.watch(cartSelectionProvider);
    final allSelected = list.isNotEmpty && list.every((m) => sel[m['id']] == true);
    final selectedCount = list.where((m) => sel[m['id']] == true).length;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          // 标题
          Text('我的购物车', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('${list.length} 件', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
          ),
          const Spacer(),
          // 全选
          Semantics(
            label: '全选所有商品',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                final map = <String, bool>{};
                final newValue = !allSelected;
                for (final m in list) map[m['id']] = newValue;
                ref.read(cartSelectionProvider.notifier).state = map;
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Checkbox(
                      value: allSelected,
                      onChanged: (v) {
                        final map = <String, bool>{};
                        for (final m in list) map[m['id']] = v ?? false;
                        ref.read(cartSelectionProvider.notifier).state = map;
                      },
                    ),
                    const SizedBox(width: 4),
                    Text('全选', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // 批量删除
          if (selectedCount > 0) 
            TextButton.icon(
              onPressed: () => _showBatchDeleteDialog(context, ref, list, sel),
              icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              label: Text('删除选中 ($selectedCount)', style: TextStyle(color: theme.colorScheme.error)),
            ),
          const SizedBox(width: 16),
          // 刷新价格
          TextButton.icon(
            onPressed: () async {
              await PriceRefreshService().refreshCartPrices();
              ref.invalidate(cartItemsProvider);
            },
            icon: const Icon(Icons.refresh),
            label: const Text('刷新价格'),
          ),
        ],
      ),
    );
  }

  void _showBatchDeleteDialog(BuildContext context, WidgetRef ref, List<Map<String, dynamic>> list, Map<String, bool> sel) {
    final selectedItems = list.where((m) => sel[m['id']] == true).toList();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${selectedItems.length} 件商品吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              for (final m in selectedItems) {
                ref.read(cartServiceProvider).removeItem(m['id']);
              }
              ref.invalidate(cartItemsProvider);
              ref.read(cartSelectionProvider.notifier).state = {};
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 桌面端购物车列表 - 表格式布局
class _DesktopCartList extends ConsumerWidget {
  final Map<String, List<Map<String, dynamic>>> groups;
  final List<Map<String, dynamic>> list;
  const _DesktopCartList({required this.groups, required this.list});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: groups.length,
      itemBuilder: (ctx, index) {
        final shopName = groups.keys.elementAt(index);
        final items = groups[shopName]!;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 店铺头部
              _DesktopShopHeader(shopName: shopName, items: items),
              const Divider(height: 1),
              // 表头
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: theme.colorScheme.surfaceContainerLowest,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final availableWidth = constraints.maxWidth;
                    final scale = (availableWidth / 544).clamp(0.6, 1.0);

                    return Row(
                      children: [
                        SizedBox(width: 48 * scale),
                        SizedBox(width: 80 * scale),
                        SizedBox(width: 16 * scale),
                        Expanded(
                            flex: 3,
                            child: Text('商品信息',
                                style: theme.textTheme.labelMedium
                                    ?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant))),
                        SizedBox(
                            width: 100 * scale,
                            child: Text('单价',
                                style: theme.textTheme.labelMedium
                                    ?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant),
                                textAlign: TextAlign.center)),
                        SizedBox(
                            width: 120 * scale,
                            child: Text('数量',
                                style: theme.textTheme.labelMedium
                                    ?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant),
                                textAlign: TextAlign.center)),
                        SizedBox(
                            width: 100 * scale,
                            child: Text('小计',
                                style: theme.textTheme.labelMedium
                                    ?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant),
                                textAlign: TextAlign.center)),
                        SizedBox(width: 80 * scale),
                      ],
                    );
                  },
                ),
              ),
              // 商品列表
              ...items.map((m) => CartItemTile(item: m)),
            ],
          ),
        );
      },
    );
  }
}

/// 桌面端店铺头部
class _DesktopShopHeader extends ConsumerWidget {
  final String shopName;
  final List<Map<String, dynamic>> items;
  const _DesktopShopHeader({required this.shopName, required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sel = ref.watch(cartSelectionProvider);
    final allSelected = items.every((m) => sel[m['id']] == true);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
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
          Icon(Icons.store, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(shopName, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('${items.length} 件商品', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}


/// 移动端购物车列表 - 原有卡片式布局
class _MobileCartList extends StatelessWidget {
  final Map<String, List<Map<String, dynamic>>> groups;
  const _MobileCartList({required this.groups});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (ctx, index) {
        final shopName = groups.keys.elementAt(index);
        final items = groups[shopName]!;
        return _CartGroupCard(shopName: shopName, items: items);
      },
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
                    Expanded(
                      child: Text(shopName, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                    ),
                 ],
               );
            }),
            const Divider(),
            // Items
            ...items.map((m) {
              final p = ProductModel.fromMap(m);
              final qty = int.tryParse(m['qty']?.toString() ?? '1') ?? 1;
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
                   ref.invalidate(cartItemsProvider);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final maxWidth = constraints.maxWidth;
                      final bool isNarrowMobile = maxWidth < 360;
                      final bool isMobile = maxWidth < 480;

                      // 数量控制按钮和复选框的尺寸响应式
                      final checkboxWidth = isNarrowMobile ? 40.0 : (isMobile ? 44.0 : 48.0);
                      final qtyButtonSize = isNarrowMobile ? 28.0 : 32.0;
                      final qtyIconSize = isNarrowMobile ? 14.0 : 16.0;
                      final qtyTextStyle = Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500);
                      final qtyContainerWidth = isNarrowMobile ? 24.0 : 28.0;

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 复选框
                          SizedBox(
                            width: checkboxWidth,
                            child: Consumer(builder: (context, ref, _) {
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
                          ),
                          // 商品卡片
                          Expanded(
                            child: ProductCard(
                              product: p,
                              expandToFullWidth: true,
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(product: p))),
                            ),
                          ),
                          // 数量控制（手机端缩小）
                          SizedBox(
                            width: qtyButtonSize + 4,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(4),
                                    onTap: () {
                                      ref.read(cartServiceProvider).setQuantity(p.id, qty + 1);
                                      ref.invalidate(cartItemsProvider);
                                    },
                                    child: Container(
                                      width: qtyButtonSize,
                                      height: qtyButtonSize,
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Icon(Icons.add, size: qtyIconSize),
                                    ),
                                  ),
                                ),
                                Container(
                                  width: qtyContainerWidth,
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  decoration: BoxDecoration(
                                    border: Border.symmetric(
                                      horizontal: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                                    ),
                                  ),
                                  child: Text('$qty', textAlign: TextAlign.center, style: qtyTextStyle),
                                ),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(4),
                                    onTap: qty > 1
                                      ? () {
                                          ref.read(cartServiceProvider).setQuantity(p.id, qty - 1);
                                          ref.invalidate(cartItemsProvider);
                                        }
                                      : null,
                                    child: Container(
                                      width: qtyButtonSize,
                                      height: qtyButtonSize,
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: qty > 1
                                            ? Theme.of(context).colorScheme.outlineVariant
                                            : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Icon(
                                        Icons.remove,
                                        size: qtyIconSize,
                                        color: qty > 1
                                          ? null
                                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        ],
                      );
                    },
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wisepick_dart_version/features/products/product_model.dart';
import 'package:wisepick_dart_version/features/products/product_detail_page.dart';
import 'package:wisepick_dart_version/features/products/jd_price_provider.dart';
import 'package:wisepick_dart_version/features/cart/cart_providers.dart';
import 'package:wisepick_dart_version/features/auth/auth_providers.dart';
import 'package:wisepick_dart_version/services/sync/sync_manager.dart';
import 'package:wisepick_dart_version/widgets/product_card.dart';
import 'package:wisepick_dart_version/widgets/cached_product_image.dart';
import 'package:wisepick_dart_version/services/price_refresh_service.dart';
import 'package:wisepick_dart_version/services/jd_scraper_client.dart';

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
                        ref.invalidate(jdPriceCacheProvider); // 刷新京东价格缓存
                        
                        // 如果已登录，同步云端数据
                        final isLoggedIn = ref.read(isLoggedInProvider);
                        if (isLoggedIn) {
                          try {
                            final syncManager = ref.read(syncManagerProvider.notifier);
                            await syncManager.syncCart();
                            // 同步后重新加载本地数据
                            ref.invalidate(cartItemsProvider);
                          } catch (_) {
                            // 忽略同步错误
                          }
                        }
                      },
                      child: isDesktop 
                        ? _DesktopCartList(groups: groups, list: list)
                        : _MobileCartList(groups: groups),
                    ),
                  ),
                  _CartBottomBar(list: list, isDesktop: isDesktop),
                ],
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('加载错误: $e')),
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
        border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5))),
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
              ref.invalidate(jdPriceCacheProvider); // 刷新京东价格缓存
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
                child: Row(
                  children: [
                    const SizedBox(width: 48), // Checkbox 占位
                    const SizedBox(width: 80), // 图片占位
                    const SizedBox(width: 16),
                    Expanded(flex: 3, child: Text('商品信息', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
                    SizedBox(width: 100, child: Text('单价', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant), textAlign: TextAlign.center)),
                    SizedBox(width: 120, child: Text('数量', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant), textAlign: TextAlign.center)),
                    SizedBox(width: 100, child: Text('小计', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant), textAlign: TextAlign.center)),
                    const SizedBox(width: 80), // 操作占位
                  ],
                ),
              ),
              // 商品列表
              ...items.map((m) => _DesktopCartItem(item: m)),
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

/// 桌面端购物车商品项 - 横向表格行布局
class _DesktopCartItem extends ConsumerStatefulWidget {
  final Map<String, dynamic> item;
  const _DesktopCartItem({required this.item});

  @override
  ConsumerState<_DesktopCartItem> createState() => _DesktopCartItemState();
}

class _DesktopCartItemState extends ConsumerState<_DesktopCartItem> {
  bool _isHovered = false;

  /// 获取京东商品的缓存价格（如果有）
  double? _getJdCachedPrice(ProductModel p, WidgetRef ref) {
    if (p.platform == 'jd') {
      final jdPrices = ref.watch(jdPriceCacheProvider);
      return jdPrices[p.id];
    }
    return null;
  }

  /// 获取商品的有效价格：京东商品优先从 jdPriceCacheProvider 获取最新爬取价格
  double _getEffectivePrice(ProductModel p, double? jdCachedPrice) {
    if (p.platform == 'jd' && jdCachedPrice != null) {
      return jdCachedPrice;
    }
    // 对于非京东商品或没有缓存价格的情况，使用原价格
    return p.price > 0 ? p.price : p.finalPrice > 0 ? p.finalPrice : p.originalPrice;
  }

  /// 判断京东商品是否下架（只有已爬取且价格为 0 才是下架）
  bool _isJdOffShelf(ProductModel p, double? jdCachedPrice) {
    return p.platform == 'jd' && jdCachedPrice != null && jdCachedPrice < 0.01;
  }

  /// 判断京东商品是否未爬取价格
  bool _isJdPriceNotFetched(ProductModel p, double? jdCachedPrice) {
    return p.platform == 'jd' && jdCachedPrice == null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = widget.item;
    final p = ProductModel.fromMap(m);
    final qty = int.tryParse(m['qty']?.toString() ?? '1') ?? 1;
    final sel = ref.watch(cartSelectionProvider);
    final isSelected = sel[p.id] ?? false;
    final jdCachedPrice = _getJdCachedPrice(p, ref);
    final effectivePrice = _getEffectivePrice(p, jdCachedPrice);
    final subtotal = effectivePrice * qty;
    final isOffShelf = _isJdOffShelf(p, jdCachedPrice);
    final isPriceNotFetched = _isJdPriceNotFetched(p, jdCachedPrice);
    
    // 获取平台颜色
    Color platformColor;
    String platformName;
    switch (p.platform) {
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
        platformName = '其他';
    }
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _isHovered 
            ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.5) 
            : (isSelected ? theme.colorScheme.primaryContainer.withOpacity(0.1) : null),
          border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.3))),
        ),
        child: InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(product: p))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // 选择框
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
                // 商品图片
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
                // 商品信息
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
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
                              style: TextStyle(color: platformColor, fontSize: 10, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (p.shopTitle.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              p.shopTitle,
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // 单价
                SizedBox(
                  width: 100,
                  child: Column(
                    children: [
                      // 京东商品：区分未爬取、下架、正常价格三种状态
                      if (isOffShelf)
                        // 已爬取且价格为 0：下架/无货
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '下架/无货',
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )
                      else if (isPriceNotFetched)
                        // 京东商品未爬取：显示 ¥--.--
                        Text(
                          '¥--.--',
                          style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                        )
                      else
                        // 正常价格
                        Text(
                          '¥${effectivePrice.toStringAsFixed(2)}',
                          style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                        ),
                      if (!isOffShelf && !isPriceNotFetched && p.originalPrice > 0 && p.originalPrice > effectivePrice)
                        Text(
                          '¥${p.originalPrice.toStringAsFixed(2)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            decoration: TextDecoration.lineThrough,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                // 数量控制 - 水平布局
                SizedBox(
                  width: 120,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _QuantityButton(
                        icon: Icons.remove,
                        onPressed: qty > 1 ? () {
                          ref.read(cartServiceProvider).setQuantity(p.id, qty - 1);
                          ref.invalidate(cartItemsProvider);
                        } : null,
                      ),
                      Container(
                        width: 40,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.symmetric(
                            horizontal: BorderSide(color: theme.colorScheme.outlineVariant),
                          ),
                        ),
                        child: Text(
                          '$qty',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                      _QuantityButton(
                        icon: Icons.add,
                        onPressed: () {
                          ref.read(cartServiceProvider).setQuantity(p.id, qty + 1);
                          ref.invalidate(cartItemsProvider);
                        },
                      ),
                    ],
                  ),
                ),
                // 小计
                SizedBox(
                  width: 100,
                  child: (isOffShelf || isPriceNotFetched)
                    ? Text(
                        '--',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      )
                    : Text(
                        '¥${subtotal.toStringAsFixed(2)}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.error, fontWeight: FontWeight.bold),
                      ),
                ),
                // 操作按钮
                SizedBox(
                  width: 80,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _isHovered ? 1.0 : 0.3,
                    child: IconButton(
                      icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
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
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 数量调整按钮
class _QuantityButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  const _QuantityButton({required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onPressed,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            size: 16,
            color: onPressed != null ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withOpacity(0.3),
          ),
        ),
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
                    Text(shopName, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
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
                                  ref.invalidate(cartItemsProvider);
                               }
                            ),
                            Text('$qty'),
                            IconButton(
                               icon: const Icon(Icons.remove_circle_outline), 
                               onPressed: () {
                                  if (qty > 1) {
                                     ref.read(cartServiceProvider).setQuantity(p.id, qty - 1);
                                     ref.invalidate(cartItemsProvider);
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
  final bool isDesktop;
  const _CartBottomBar({required this.list, this.isDesktop = false});

  /// 获取商品的有效价格：京东商品优先从 jdPriceCacheProvider 获取最新爬取价格
  double _getEffectivePrice(ProductModel p, Map<String, double> jdPrices) {
    if (p.platform == 'jd') {
      final cachedPrice = jdPrices[p.id];
      // 有缓存价格时使用缓存价格（包括 0，表示下架）
      if (cachedPrice != null) {
        return cachedPrice;
      }
    }
    // 对于非京东商品或没有缓存价格的情况，使用原价格
    return p.price > 0 ? p.price : p.finalPrice > 0 ? p.finalPrice : p.originalPrice;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sel = ref.watch(cartSelectionProvider);
    final jdPrices = ref.watch(jdPriceCacheProvider);
    double total = 0;
    int count = 0;
    double totalOriginal = 0;
    for (final m in list) {
       if (sel[m['id']] == true) {
          final p = ProductModel.fromMap(m);
          final qty = int.tryParse(m['qty']?.toString() ?? '1') ?? 1;
          final effectivePrice = _getEffectivePrice(p, jdPrices);
          total += effectivePrice * qty;
          totalOriginal += (p.originalPrice > 0 ? p.originalPrice : effectivePrice) * qty;
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, -2))],
          border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.5))),
       ),
       child: isDesktop ? _buildDesktopLayout(context, ref, theme, total, count, savings) : _buildMobileLayout(context, ref, theme, total, count),
    );
  }
  
  Widget _buildMobileLayout(BuildContext context, WidgetRef ref, ThemeData theme, double total, int count) {
    final sel = ref.watch(cartSelectionProvider);
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
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('合计: ¥${total.toStringAsFixed(2)}', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
            Text('已选 $count 件', style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(width: 16),
        Semantics(
          label: '去结算，已选 $count 件商品，合计 ¥${total.toStringAsFixed(2)}',
          button: true,
          enabled: count > 0,
          child: ElevatedButton(
            onPressed: count > 0 ? () => _showCheckoutDialog(context, list, ref.read(cartSelectionProvider)) : null,
            child: const Text('去结算'),
          ),
        ),
      ],
    );
  }
  
  Widget _buildDesktopLayout(BuildContext context, WidgetRef ref, ThemeData theme, double total, int count, double savings) {
    final sel = ref.watch(cartSelectionProvider);
    
    return Row(
      children: [
        // 左侧空间（与列表对齐）
        const Spacer(flex: 2),
        // 结算信息区
        Expanded(
          flex: 3,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // 已选信息
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text('已选 $count 件', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary)),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              // 优惠信息（如有）
              if (savings > 0) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('已优惠', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    Text('¥${savings.toStringAsFixed(2)}', style: theme.textTheme.titleSmall?.copyWith(color: Colors.green, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(width: 24),
              ],
              // 合计金额
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('合计（不含运费）', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('¥', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.error, fontWeight: FontWeight.bold)),
                      Text(
                        total.toStringAsFixed(2),
                        style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.error, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 24),
              // 结算按钮
              Semantics(
                label: '去结算，已选 $count 件商品，合计 ¥${total.toStringAsFixed(2)}',
                button: true,
                enabled: count > 0,
                child: FilledButton(
                  onPressed: count > 0 ? () => _showCheckoutDialog(context, list, sel) : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    textStyle: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
  final JdScraperClient _jdScraperClient = JdScraperClient();

  Future<void> _fetchAndCopyLink(ProductModel p) async {
    setState(() => _loadingStates[p.id] = true);
    
    try {
      String? link = p.link;
      
      // 如果是京东商品且没有有效链接，使用新的双源爬取 API 获取推广链接
      if (p.platform == 'jd' && (link.isEmpty || !link.contains('u.jd.com'))) {
        try {
          final result = await _jdScraperClient.getProductEnhanced(p.id);
          
          if (result.isSuccess && result.data != null) {
            final info = result.data!;
            // 获取推广链接（优先短链接）
            link = info.effectivePromotionLink ?? '';
          } else if (result.errorMessage != null && mounted) {
            // 显示用户友好的错误消息
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(result.errorMessage!)),
            );
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

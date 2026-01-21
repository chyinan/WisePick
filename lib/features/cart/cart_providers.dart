import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'cart_service.dart';
import '../auth/auth_providers.dart';
import '../../services/sync/sync_manager.dart';
import '../../services/sync/cart_sync_client.dart';
import '../products/product_model.dart';

final cartServiceProvider = Provider<CartService>((ref) => CartService());

final cartItemsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final svc = ref.read(cartServiceProvider);
  return svc.getAllItems();
});

/// 简单的 Provider 保存购物车界面的本地选择状态（非持久化）
final cartSelectionProvider = StateProvider<Map<String, bool>>((ref) => <String, bool>{});

/// 购物车商品数量 Provider（用于导航徽章显示）
final cartCountProvider = Provider<int>((ref) {
  final itemsAsync = ref.watch(cartItemsProvider);
  return itemsAsync.whenOrNull(data: (items) => items.length) ?? 0;
});

/// 带云端同步的购物车操作管理器
class SyncedCartNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final CartService _cartService;
  final Ref _ref;

  SyncedCartNotifier(this._cartService, this._ref) : super(const AsyncValue.loading()) {
    _loadItems();
  }  Future<void> _loadItems() async {
    state = const AsyncValue.loading();
    try {
      final items = await _cartService.getAllItems();
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 刷新购物车（从本地重新加载）
  Future<void> refresh() async {
    await _loadItems();
  }

  /// 添加或更新商品到购物车
  Future<void> addOrUpdateItem(ProductModel product, {int qty = 1, String? rawJson}) async {
    await _cartService.addOrUpdateItem(product, qty: qty, rawJson: rawJson);
    
    // 重新加载本地数据
    await _loadItems();    // 如果已登录，添加待同步变更并触发同步
    final isLoggedIn = _ref.read(isLoggedInProvider);
    if (isLoggedIn) {
      try {
        final syncManager = _ref.read(syncManagerProvider.notifier);
        final item = product.toMap();
        item['qty'] = qty;
        await syncManager.addCartChange(item);
        // 延迟同步（可以用防抖机制优化）
        syncManager.scheduleSyncCart();
      } catch (_) {}
    }
  }

  /// 设置商品数量
  Future<void> setQuantity(String productId, int qty) async {
    await _cartService.setQuantity(productId, qty);
    await _loadItems();    // 如果已登录，同步变更
    final isLoggedIn = _ref.read(isLoggedInProvider);
    if (isLoggedIn) {
      try {
        final items = await _cartService.getAllItems();
        final item = items.firstWhere(
          (i) => i['id'] == productId,
          orElse: () => <String, dynamic>{},
        );
        if (item.isNotEmpty) {
          final syncManager = _ref.read(syncManagerProvider.notifier);
          await syncManager.addCartChange(item);
          syncManager.scheduleSyncCart();
        }
      } catch (_) {}
    }
  }  /// 删除商品
  Future<void> removeItem(String productId) async {
    // 先获取商品信息用于同步
    Map<String, dynamic>? itemToDelete;
    final isLoggedIn = _ref.read(isLoggedInProvider);
    if (isLoggedIn) {
      try {
        final items = await _cartService.getAllItems();
        itemToDelete = items.firstWhere(
          (i) => i['id'] == productId,
          orElse: () => <String, dynamic>{},
        );
      } catch (_) {}
    }

    await _cartService.removeItem(productId);
    await _loadItems();

    // 同步删除操作
    if (isLoggedIn && itemToDelete != null && itemToDelete.isNotEmpty) {
      try {
        final syncManager = _ref.read(syncManagerProvider.notifier);
        await syncManager.addCartChange(itemToDelete, isDeleted: true);
        syncManager.scheduleSyncCart();
      } catch (_) {}
    }
  }

  /// 清空购物车
  Future<void> clear() async {
    // 先获取所有商品用于同步删除
    final isLoggedIn = _ref.read(isLoggedInProvider);
    List<Map<String, dynamic>> itemsToDelete = [];
    if (isLoggedIn) {
      try {
        itemsToDelete = await _cartService.getAllItems();
      } catch (_) {}
    }

    await _cartService.clear();
    await _loadItems();

    // 同步所有删除操作
    if (isLoggedIn && itemsToDelete.isNotEmpty) {
      try {
        final syncManager = _ref.read(syncManagerProvider.notifier);
        for (final item in itemsToDelete) {
          await syncManager.addCartChange(item, isDeleted: true);
        }
        syncManager.scheduleSyncCart();
      } catch (_) {}
    }
  }

  /// 从云端同步购物车数据（登录后调用）
  Future<void> syncFromCloud() async {
    final isLoggedIn = _ref.read(isLoggedInProvider);
    if (!isLoggedIn) return;

    try {
      final syncManager = _ref.read(syncManagerProvider.notifier);
      await syncManager.syncCart();
      // 同步完成后重新加载本地数据
      await _loadItems();
    } catch (_) {}
  }
}

/// 带同步功能的购物车 Provider
final syncedCartProvider = StateNotifierProvider<SyncedCartNotifier, AsyncValue<List<Map<String, dynamic>>>>((ref) {
  final cartService = ref.watch(cartServiceProvider);
  return SyncedCartNotifier(cartService, ref);
});

/// 购物车同步客户端 Provider
final cartSyncClientProvider = Provider<CartSyncClient>((ref) {
  return CartSyncClient();
});

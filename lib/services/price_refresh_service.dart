import 'dart:async';
import 'dart:developer';

import 'package:hive/hive.dart';

import '../features/cart/cart_service.dart';
import '../features/products/taobao_item_detail_service.dart';
import 'notification_service.dart';
import '../core/storage/hive_config.dart';

class PriceRefreshService {
  PriceRefreshService({
    CartService? cartService,
    TaobaoItemDetailService? taobaoService,
    NotificationService? notificationService,
  })  : _cartService = cartService ?? CartService(),
        _taobaoService = taobaoService ?? TaobaoItemDetailService(),
        _notificationService =
            notificationService ?? NotificationService.instance;

  final CartService _cartService;
  final TaobaoItemDetailService _taobaoService;
  final NotificationService _notificationService;

  static bool _isRunning = false;

  Future<void> refreshCartPrices() async {
    if (_isRunning) return;
    _isRunning = true;
    try {
      final box = await Hive.openBox(CartService.boxName);
      for (final key in box.keys) {
        final dynamic raw = box.get(key);
        if (raw is! Map) continue;
        final Map<String, dynamic> item = raw.map((dynamic k, dynamic v) {
          return MapEntry(k.toString(), v);
        });

        final platform = (item['platform'] ?? '').toString();
        if (platform == 'taobao') {
          await _handleTaobaoItem(box, key.toString(), item);
        }
        // 未来可在此扩展其他平台的价格刷新
      }
    } catch (e, st) {
      log('刷新价格失败: $e', stackTrace: st);
    } finally {
      _isRunning = false;
    }
  }

  Future<void> _handleTaobaoItem(
    Box box,
    String productId,
    Map<String, dynamic> item,
  ) async {
    try {
      final detail = await _taobaoService.fetchDetail(productId);
      final latestPrice = detail.preferredPrice;
      if (latestPrice == null) return;

      final double initialPrice = _extractInitialPrice(item) ?? latestPrice;
      final double? lastKnownPrice = _extractCurrentPrice(item);
      final bool priceDropped = latestPrice < initialPrice - 0.009;
      final double dropAmount =
          priceDropped ? (initialPrice - latestPrice) : 0.0;

      item['initial_price'] ??= initialPrice;
      item['current_price'] = latestPrice;
      item['price'] = latestPrice;
      item['final_price'] = latestPrice;
      item['last_price_refresh'] = DateTime.now().millisecondsSinceEpoch;
      await box.put(productId, item);

      await _persistTaobaoCache(productId, detail);

      if (priceDropped && dropAmount >= 0.01) {
        // 检查通知开关设置
        final box = await Hive.openBox(HiveConfig.settingsBox);
        final notificationEnabled = box.get(
          HiveConfig.priceNotificationEnabledKey,
          defaultValue: true,
        ) as bool;
        
        if (notificationEnabled) {
          await _notificationService.showPriceDropNotification(
            title: (item['title'] ?? '商品').toString(),
            dropAmount: dropAmount,
            latestPrice: latestPrice,
          );
        }
      } else if (lastKnownPrice == null || (latestPrice - lastKnownPrice).abs() >= 0.01) {
        // 如果只是普通更新也写入日志，方便排查
        log('更新淘宝商品 $productId 价格: $lastKnownPrice -> $latestPrice');
      }
    } catch (e) {
      log('刷新淘宝商品 $productId 价格失败: $e');
    }
  }

  double? _extractInitialPrice(Map<String, dynamic> item) {
    final dynamic value =
        item['initial_price'] ?? item['price'] ?? item['final_price'];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  double? _extractCurrentPrice(Map<String, dynamic> item) {
    final dynamic value =
        item['current_price'] ?? item['price'] ?? item['final_price'];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  Future<void> _persistTaobaoCache(
    String productId,
    TaobaoItemDetail detail,
  ) async {
    try {
      if (!Hive.isBoxOpen('taobao_item_cache')) {
        await Hive.openBox('taobao_item_cache');
      }
      final cacheBox = Hive.box('taobao_item_cache');
      if (detail.images.isNotEmpty) {
        await cacheBox.put('${productId}_images', detail.images);
      }
      final latestPrice = detail.preferredPrice;
      if (latestPrice != null) {
        await cacheBox.put('${productId}_price', latestPrice);
        await cacheBox.put(
            '${productId}_price_updated_at', DateTime.now().millisecondsSinceEpoch);
      }
    } catch (e) {
      log('写入淘宝缓存失败: $e');
    }
  }
}



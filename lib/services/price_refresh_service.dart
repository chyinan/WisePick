import 'dart:async';
import 'dart:developer';

import 'package:hive/hive.dart';
import 'package:wisepick_dart_version/features/price_history/price_history_service.dart';

import '../features/cart/cart_service.dart';
import '../features/products/taobao_item_detail_service.dart';
import 'notification_service.dart';
import '../core/storage/hive_config.dart';

class PriceRefreshService {
  PriceRefreshService({
    TaobaoItemDetailService? taobaoService,
    NotificationService? notificationService,
    PriceHistoryService? priceHistoryService,
  })  : _taobaoService = taobaoService ?? TaobaoItemDetailService(),
        _notificationService =
            notificationService ?? NotificationService.instance,
        _priceHistoryService = priceHistoryService ?? PriceHistoryService();

  final TaobaoItemDetailService _taobaoService;
  final NotificationService _notificationService;
  final PriceHistoryService _priceHistoryService;

  /// Global mutex — intentionally `static` so that multiple [PriceRefreshService]
  /// instances (e.g. from different call-sites) share the same guard and cannot
  /// run concurrently.  Do NOT change to an instance field.
  static bool _isRunning = false;
  
  /// 价格比较阈值（1 分钱）- 避免浮点精度问题
  static const double _priceComparisonEpsilon = 0.01;
  
  /// 最小降价通知金额（1 分钱）
  static const double _minDropAmountForNotification = 0.01;

  /// Delay between processing each cart item to avoid bursting
  /// upstream API rate limits when the cart has many items.
  static const Duration _interItemDelay = Duration(milliseconds: 500);

  Future<void> refreshCartPrices() async {
    if (_isRunning) return;
    _isRunning = true;
    try {
      // Use HiveConfig.getBox for safe open-if-needed semantics.
      final box = await HiveConfig.getBox(CartService.boxName);
      bool isFirstItem = true;
      for (final key in box.keys) {
        final dynamic raw = box.get(key);
        if (raw is! Map) continue;
        final Map<String, dynamic> item = raw.map((dynamic k, dynamic v) {
          return MapEntry(k.toString(), v);
        });

        final platform = (item['platform'] ?? '').toString();
        if (platform == 'taobao') {
          // Rate-limit: pause between items to avoid bursting upstream APIs
          if (!isFirstItem) {
            await Future.delayed(_interItemDelay);
          }
          isFirstItem = false;
          await _handleTaobaoItem(box, key.toString(), item);
        }
        // 未来可在此扩展其他平台的价格刷新（如拼多多）
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

      // Re-read from box after the await to avoid overwriting concurrent
      // changes (e.g. quantity updates by the user during the network call).
      final dynamic freshRaw = box.get(productId);
      if (freshRaw == null) {
        // Item was deleted while we were fetching — don't resurrect it.
        log('淘宝商品 $productId 在刷新期间被删除，跳过更新');
        return;
      }
      final Map<String, dynamic> freshItem = freshRaw is Map
          ? freshRaw.map((dynamic k, dynamic v) => MapEntry(k.toString(), v))
          : item;

      final double initialPrice = _extractInitialPrice(freshItem) ?? latestPrice;
      final double? lastKnownPrice = _extractCurrentPrice(freshItem);
      final double dropAmount = initialPrice - latestPrice;
      // 使用 epsilon 比较避免浮点精度问题
      final bool priceDropped = dropAmount >= _priceComparisonEpsilon;

      freshItem['initial_price'] ??= initialPrice;
      freshItem['current_price'] = latestPrice;
      freshItem['price'] = latestPrice;
      freshItem['final_price'] = latestPrice;
      freshItem['last_price_refresh'] = DateTime.now().millisecondsSinceEpoch;
      await box.put(productId, freshItem);

      await _persistTaobaoCache(productId, detail);

      // 记录价格历史
      await _priceHistoryService.recordPriceHistory(
        productId: productId,
        price: latestPrice,
        finalPrice: latestPrice,
        originalPrice: detail.reservePrice ?? detail.zkFinalPrice, // Use reservePrice or zkFinalPrice as original
      );

      if (priceDropped && dropAmount >= _minDropAmountForNotification) {
        // 检查通知开关设置 — use pre-opened settings box from HiveConfig
        final settingsBox = await HiveConfig.getBox(HiveConfig.settingsBox);
        final notificationEnabled = settingsBox.get(
          HiveConfig.priceNotificationEnabledKey,
          defaultValue: true,
        ) as bool;
        
        if (notificationEnabled) {
          await _notificationService.showPriceDropNotification(
            title: (freshItem['title'] ?? '商品').toString(),
            dropAmount: dropAmount,
            latestPrice: latestPrice,
          );
        }
      } else if (lastKnownPrice == null || (latestPrice - lastKnownPrice).abs() >= _priceComparisonEpsilon) {
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
      // Use HiveConfig constant + safe open instead of raw Hive calls.
      final cacheBox = await HiveConfig.getBox(HiveConfig.taobaoItemCacheBox);
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



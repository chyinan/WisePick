import 'dart:async';
import 'dart:developer';

import 'package:hive/hive.dart';
import 'package:wisepick_dart_version/features/price_history/price_history_service.dart';

import '../features/cart/cart_service.dart';
import '../features/products/taobao_item_detail_service.dart';
import 'notification_service.dart';
import '../core/storage/hive_config.dart';
import 'jd_scraper_client.dart';

class PriceRefreshService {
  PriceRefreshService({
    CartService? cartService,
    TaobaoItemDetailService? taobaoService,
    NotificationService? notificationService,
    PriceHistoryService? priceHistoryService,
    JdScraperClient? jdScraperClient,
  })  : _cartService = cartService ?? CartService(),
        _taobaoService = taobaoService ?? TaobaoItemDetailService(),
        _notificationService =
            notificationService ?? NotificationService.instance,
        _priceHistoryService = priceHistoryService ?? PriceHistoryService(),
        _jdScraperClient = jdScraperClient ?? JdScraperClient();

  // ignore: unused_field
  final CartService _cartService;
  final TaobaoItemDetailService _taobaoService;
  final NotificationService _notificationService;
  final PriceHistoryService _priceHistoryService;
  final JdScraperClient _jdScraperClient;

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
        } else if (platform == 'jd') {
          await _handleJdItem(box, key.toString(), item);
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

      // 记录价格历史
      await _priceHistoryService.recordPriceHistory(
        productId: productId,
        price: latestPrice,
        finalPrice: latestPrice,
        originalPrice: detail.reservePrice ?? detail.zkFinalPrice, // Use reservePrice or zkFinalPrice as original
      );

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

  /// 处理京东商品价格刷新（使用新的双源爬取 API）
  Future<void> _handleJdItem(
    Box box,
    String productId,
    Map<String, dynamic> item,
  ) async {
    try {
      // 使用新的双源爬取 API
      final result = await _jdScraperClient.getProductEnhanced(productId);
      
      if (!result.isSuccess || result.data == null) {
        log('获取京东商品 $productId 价格失败: ${result.errorMessage ?? 'Unknown error'}');
        return;
      }

      final info = result.data!;
      final latestPrice = info.price;
      
      if (latestPrice <= 0 || info.isOffShelf) {
        log('京东商品 $productId 价格无效或已下架');
        return;
      }

      final double initialPrice = _extractInitialPrice(item) ?? latestPrice;
      final double? lastKnownPrice = _extractCurrentPrice(item);
      final bool priceDropped = latestPrice < initialPrice - 0.009;
      final double dropAmount = priceDropped ? (initialPrice - latestPrice) : 0.0;

      // 更新购物车数据
      item['initial_price'] ??= initialPrice;
      item['current_price'] = latestPrice;
      item['price'] = latestPrice;
      item['final_price'] = latestPrice;
      item['last_price_refresh'] = DateTime.now().millisecondsSinceEpoch;
      
      // 如果返回了店铺名和图片，也更新到购物车
      if (info.shopName != null && info.shopName!.isNotEmpty) {
        item['shop_title'] = info.shopName;
      }
      if (info.imageUrl != null && info.imageUrl!.isNotEmpty) {
        item['image'] = info.imageUrl;
      }
      
      await box.put(productId, item);

      // 更新 jdPriceCache Hive box（供 jdPriceCacheProvider 使用）
      await _persistJdPriceCache(productId, latestPrice);

      // 记录价格历史
      await _priceHistoryService.recordPriceHistory(
        productId: productId,
        price: latestPrice,
        finalPrice: latestPrice,
        originalPrice: info.originalPrice,
      );

      if (priceDropped && dropAmount >= 0.01) {
        // 检查通知开关设置
        final settingsBox = await Hive.openBox(HiveConfig.settingsBox);
        final notificationEnabled = settingsBox.get(
          HiveConfig.priceNotificationEnabledKey,
          defaultValue: true,
        ) as bool;
        
        if (notificationEnabled) {
          await _notificationService.showPriceDropNotification(
            title: (item['title'] ?? info.title).toString(),
            dropAmount: dropAmount,
            latestPrice: latestPrice,
          );
        }
      } else if (lastKnownPrice == null || (latestPrice - lastKnownPrice).abs() >= 0.01) {
        log('更新京东商品 $productId 价格: $lastKnownPrice -> $latestPrice');
      }
    } catch (e) {
      log('刷新京东商品 $productId 价格失败: $e');
    }
  }

  /// 持久化京东价格到缓存（供 jdPriceCacheProvider 读取）
  Future<void> _persistJdPriceCache(String productId, double price) async {
    try {
      const boxName = 'jdPriceCache';
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox<double>(boxName);
      }
      final cacheBox = Hive.box<double>(boxName);
      await cacheBox.put(productId, price);
    } catch (e) {
      log('写入京东价格缓存失败: $e');
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



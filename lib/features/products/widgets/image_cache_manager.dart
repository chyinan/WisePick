import 'dart:developer' as dev;

import 'package:wisepick_dart_version/core/storage/hive_config.dart';

/// 商品图片和价格的内存+持久化缓存管理（淘宝、拼多多）
class ImageCacheManager {
  static final Map<String, List<String>> _taobaoImageMemoryCache = {};
  static final Map<String, double> _taobaoPriceMemoryCache = {};
  static final Map<String, List<String>> _pddImageMemoryCache = {};
  static final Map<String, double> _pddPriceMemoryCache = {};

  static String normalizeImageUrl(String? url) {
    if (url == null) return '';
    var normalized = url.trim();
    if (normalized.isEmpty) return '';
    if (normalized.startsWith('//')) {
      normalized = 'https:$normalized';
    }
    return normalized;
  }

  // ── 淘宝 ──────────────────────────────────────────────

  static Future<List<String>?> loadCachedTaobaoImages(String productId) async {
    final memory = _taobaoImageMemoryCache[productId];
    if (memory != null && memory.isNotEmpty) return List<String>.from(memory);
    try {
      final box = await HiveConfig.getBox(HiveConfig.taobaoItemCacheBox);
      final stored = box.get('${productId}_images');
      if (stored is List) {
        final list = stored
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList();
        if (list.isNotEmpty) {
          _taobaoImageMemoryCache[productId] = list;
          return list;
        }
      }
    } catch (e, st) {
      dev.log('Failed to load cached taobao images: $e',
          name: 'ImageCacheManager', error: e, stackTrace: st);
    }
    return null;
  }

  static Future<void> persistTaobaoImages(
      String productId, List<String> images) async {
    final sanitized = images
        .map(normalizeImageUrl)
        .where((url) => url.isNotEmpty)
        .toList();
    if (sanitized.isEmpty) return;
    _taobaoImageMemoryCache[productId] = sanitized;
    try {
      final box = await HiveConfig.getBox(HiveConfig.taobaoItemCacheBox);
      await box.put('${productId}_images', sanitized);
    } catch (e, st) {
      dev.log('Failed to persist taobao images: $e',
          name: 'ImageCacheManager', error: e, stackTrace: st);
    }
  }

  static Future<double?> loadCachedTaobaoPrice(String productId) async {
    final memory = _taobaoPriceMemoryCache[productId];
    if (memory != null) return memory;
    try {
      final box = await HiveConfig.getBox(HiveConfig.taobaoItemCacheBox);
      final cached = box.get('${productId}_price');
      final value = _parseDouble(cached);
      if (value != null) {
        _taobaoPriceMemoryCache[productId] = value;
        return value;
      }
    } catch (e, st) {
      dev.log('Failed to load cached taobao price: $e',
          name: 'ImageCacheManager', error: e, stackTrace: st);
    }
    return null;
  }

  static Future<void> persistTaobaoPrice(
      String productId, double price) async {
    _taobaoPriceMemoryCache[productId] = price;
    try {
      final box = await HiveConfig.getBox(HiveConfig.taobaoItemCacheBox);
      await box.put('${productId}_price', price);
      await box.put('${productId}_price_updated_at',
          DateTime.now().millisecondsSinceEpoch);
    } catch (e, st) {
      dev.log('Error persisting taobao price: $e',
          name: 'ImageCacheManager', error: e, stackTrace: st);
    }
  }

  // ── 拼多多 ────────────────────────────────────────────

  static Future<List<String>?> loadCachedPddImages(String productId) async {
    final memory = _pddImageMemoryCache[productId];
    if (memory != null && memory.isNotEmpty) return List<String>.from(memory);
    try {
      final box = await HiveConfig.getBox(HiveConfig.pddItemCacheBox);
      final stored = box.get('${productId}_images');
      if (stored is List) {
        final list = stored
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList();
        if (list.isNotEmpty) {
          _pddImageMemoryCache[productId] = list;
          return list;
        }
      }
    } catch (e, st) {
      dev.log('Error loading cached PDD images: $e',
          name: 'ImageCacheManager', error: e, stackTrace: st);
    }
    return null;
  }

  static Future<void> persistPddImages(
      String productId, List<String> images) async {
    final sanitized = images
        .map(normalizeImageUrl)
        .where((url) => url.isNotEmpty)
        .toList();
    if (sanitized.isEmpty) return;
    _pddImageMemoryCache[productId] = sanitized;
    try {
      final box = await HiveConfig.getBox(HiveConfig.pddItemCacheBox);
      await box.put('${productId}_images', sanitized);
    } catch (e, st) {
      dev.log('Error persisting PDD images: $e',
          name: 'ImageCacheManager', error: e, stackTrace: st);
    }
  }

  static Future<double?> loadCachedPddPrice(String productId) async {
    final memory = _pddPriceMemoryCache[productId];
    if (memory != null) return memory;
    try {
      final box = await HiveConfig.getBox(HiveConfig.pddItemCacheBox);
      final cached = box.get('${productId}_price');
      final value = _parseDouble(cached);
      if (value != null) {
        _pddPriceMemoryCache[productId] = value;
        return value;
      }
    } catch (e, st) {
      dev.log('Error loading cached PDD price: $e',
          name: 'ImageCacheManager', error: e, stackTrace: st);
    }
    return null;
  }

  static Future<void> persistPddPrice(String productId, double price) async {
    _pddPriceMemoryCache[productId] = price;
    try {
      final box = await HiveConfig.getBox(HiveConfig.pddItemCacheBox);
      await box.put('${productId}_price', price);
      await box.put('${productId}_price_updated_at',
          DateTime.now().millisecondsSinceEpoch);
    } catch (e, st) {
      dev.log('Error persisting PDD price: $e',
          name: 'ImageCacheManager', error: e, stackTrace: st);
    }
  }

  // ── 工具 ──────────────────────────────────────────────

  static double? _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

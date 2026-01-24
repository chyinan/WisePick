import 'dart:math';
import 'package:hive_flutter/hive_flutter.dart';
import 'price_history_model.dart';
import '../products/product_model.dart';

/// 价格历史服务
/// 
/// 负责价格历史数据管理、趋势分析、购买时机推荐等业务逻辑
/// 使用 Hive 本地存储持久化数据
class PriceHistoryService {
  // 单例模式
  static final PriceHistoryService _instance = PriceHistoryService._internal();
  factory PriceHistoryService() => _instance;
  PriceHistoryService._internal();

  static const String _boxName = 'price_history_records';

  Future<Box> _getBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  /// 清除指定商品的价格历史数据
  Future<void> clearPriceHistory(String productId) async {
    final box = await _getBox();
    await box.delete(productId);
  }

  /// 清除所有价格历史数据（用于清除旧的 Mock 数据）
  Future<void> clearAllPriceHistory() async {
    final box = await _getBox();
    await box.clear();
  }

  /// 从 ProductModel 记录价格历史
  /// 
  /// 当商品加入购物车时调用，记录初始价格
  Future<void> recordFromProduct(ProductModel product) async {
    final effectivePrice = product.finalPrice > 0 
        ? product.finalPrice 
        : (product.price > 0 ? product.price : product.originalPrice);
    
    if (effectivePrice <= 0) return; // 无效价格不记录
    
    await recordPriceHistory(
      productId: product.id,
      price: product.price > 0 ? product.price : effectivePrice,
      originalPrice: product.originalPrice > 0 ? product.originalPrice : null,
      couponAmount: product.coupon > 0 ? product.coupon : null,
      finalPrice: effectivePrice,
    );
  }

  /// 记录价格历史
  /// 
  /// 与价格监控服务集成，当检测到价格变化时调用
  Future<void> recordPriceHistory({
    required String productId,
    required double price,
    double? originalPrice,
    double? couponAmount,
    required double finalPrice,
  }) async {
    final record = PriceHistoryRecord(
      productId: productId,
      recordedAt: DateTime.now(),
      price: price,
      originalPrice: originalPrice,
      couponAmount: couponAmount,
      finalPrice: finalPrice,
    );

    final box = await _getBox();
    final List<dynamic> rawList = box.get(productId, defaultValue: []);
    final List<Map<String, dynamic>> historyList = rawList
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    
    // Check if the last record is essentially the same price to avoid duplicate consecutive entries
    // unless it's been a long time (e.g. > 1 day)
    bool shouldAdd = true;
    if (historyList.isNotEmpty) {
      final lastRecord = PriceHistoryRecord.fromMap(historyList.last);
      final isSamePrice = (lastRecord.finalPrice - finalPrice).abs() < 0.01;
      final isRecent = DateTime.now().difference(lastRecord.recordedAt).inHours < 24;
      
      if (isSamePrice && isRecent) {
        shouldAdd = false;
      }
    }

    if (shouldAdd) {
      historyList.add(record.toMap());
      await box.put(productId, historyList);
    }
  }

  /// 获取商品价格历史
  /// 
  /// 返回真实记录的价格历史数据，如果没有数据则返回空列表
  Future<List<PriceHistoryRecord>> getPriceHistory({
    required String productId,
    PriceHistoryTimeRange timeRange = PriceHistoryTimeRange.month,
  }) async {
    final box = await _getBox();
    
    List<PriceHistoryRecord> records = [];
    final dynamic data = box.get(productId);

    if (data != null && data is List) {
      records = data.map((e) => PriceHistoryRecord.fromMap(Map<String, dynamic>.from(e))).toList();
    }
    // 不再生成 Mock 数据，返回真实记录的价格历史
    // 如果没有数据，返回空列表，UI 层会显示"暂无数据"提示

    return _filterByTimeRange(records, timeRange);
  }

  /// 获取价格趋势分析
  Future<PriceTrendAnalysis> analyzePriceTrend({
    required String productId,
    required String productTitle,
    String? productImage,
    PriceHistoryTimeRange timeRange = PriceHistoryTimeRange.month,
  }) async {
    final history = await getPriceHistory(
      productId: productId,
      timeRange: timeRange,
    );

    if (history.isEmpty) {
      return PriceTrendAnalysis(
        productId: productId,
        productTitle: productTitle,
        productImage: productImage,
        priceHistory: [],
        currentPrice: 0,
        highestPrice: 0,
        lowestPrice: 0,
        averagePrice: 0,
        trend: PriceTrend.stable,
        volatility: 0,
        startDate: DateTime.now().subtract(timeRange.duration),
        endDate: DateTime.now(),
      );
    }

    // 计算统计数据
    final prices = history.map((r) => r.finalPrice).toList();
    final currentPrice = prices.last;
    final highestPrice = prices.reduce((a, b) => a > b ? a : b);
    final lowestPrice = prices.reduce((a, b) => a < b ? a : b);
    final averagePrice = prices.reduce((a, b) => a + b) / prices.length;

    // 计算波动率
    final variance = prices.map((p) => pow(p - averagePrice, 2)).reduce((a, b) => a + b) / prices.length;
    final stdDev = sqrt(variance.toDouble());
    final volatility = averagePrice > 0 ? stdDev / averagePrice : 0.0;

    // 判断趋势
    final trend = _calculateTrend(history);

    return PriceTrendAnalysis(
      productId: productId,
      productTitle: productTitle,
      productImage: productImage,
      priceHistory: history,
      currentPrice: currentPrice,
      highestPrice: highestPrice,
      lowestPrice: lowestPrice,
      averagePrice: averagePrice,
      trend: trend,
      volatility: volatility,
      startDate: history.first.recordedAt,
      endDate: history.last.recordedAt,
    );
  }

  /// 获取最佳购买时机建议
  Future<BuyingTimeSuggestion> getBestBuyTime({
    required String productId,
    PriceHistoryTimeRange timeRange = PriceHistoryTimeRange.month,
  }) async {
    final history = await getPriceHistory(
      productId: productId,
      timeRange: timeRange,
    );

    if (history.isEmpty) {
      return const BuyingTimeSuggestion(
        type: BuyingSuggestionType.observe,
        reason: '暂无历史价格数据，无法给出建议',
        confidence: 0,
      );
    }

    final prices = history.map((r) => r.finalPrice).toList();
    final currentPrice = prices.last;
    final averagePrice = prices.reduce((a, b) => a + b) / prices.length;
    final lowestPrice = prices.reduce((a, b) => a < b ? a : b);

    // 判断购买时机
    if (currentPrice <= lowestPrice * 1.05) {
      // 当前价格接近历史最低
      return BuyingTimeSuggestion(
        type: BuyingSuggestionType.buyNow,
        reason: '当前价格¥${currentPrice.toStringAsFixed(2)}接近历史最低价¥${lowestPrice.toStringAsFixed(2)}，建议立即购买',
        confidence: 0.9,
      );
    } else if (currentPrice < averagePrice * 0.9) {
      // 当前价格低于平均价
      return BuyingTimeSuggestion(
        type: BuyingSuggestionType.buyNow,
        reason: '当前价格低于历史平均价，是较好的购买时机',
        confidence: 0.75,
      );
    } else if (currentPrice > averagePrice * 1.1) {
      // 当前价格高于平均价
      return BuyingTimeSuggestion(
        type: BuyingSuggestionType.wait,
        reason: '当前价格高于历史平均价，建议等待价格回落',
        confidence: 0.7,
        predictedPrice: averagePrice,
      );
    } else {
      return BuyingTimeSuggestion(
        type: BuyingSuggestionType.observe,
        reason: '当前价格处于正常区间，可根据需求决定是否购买',
        confidence: 0.5,
      );
    }
  }

  /// 多商品价格对比
  Future<List<PriceComparisonItem>> comparePrices({
    required List<Map<String, String>> products, // [{id, title, platform, image?}]
    PriceHistoryTimeRange timeRange = PriceHistoryTimeRange.month,
  }) async {
    final results = <PriceComparisonItem>[];

    for (final product in products) {
      final history = await getPriceHistory(
        productId: product['id']!,
        timeRange: timeRange,
      );

      final currentPrice = history.isNotEmpty ? history.last.finalPrice : 0.0;
      final trend = history.isNotEmpty ? _calculateTrend(history) : PriceTrend.stable;

      results.add(PriceComparisonItem(
        productId: product['id']!,
        productTitle: product['title']!,
        productImage: product['image'],
        platform: product['platform']!,
        priceHistory: history,
        currentPrice: currentPrice,
        trend: trend,
      ));
    }

    return results;
  }

  // ========== 私有方法 ==========

  List<PriceHistoryRecord> _filterByTimeRange(
    List<PriceHistoryRecord> records,
    PriceHistoryTimeRange timeRange,
  ) {
    final startDate = timeRange.startDate;
    return records.where((r) => r.recordedAt.isAfter(startDate)).toList();
  }

  PriceTrend _calculateTrend(List<PriceHistoryRecord> history) {
    if (history.length < 3) return PriceTrend.stable;

    final recentPrices = history.sublist(history.length - 5 > 0 ? history.length - 5 : 0);
    
    int rises = 0;
    int falls = 0;
    
    for (int i = 1; i < recentPrices.length; i++) {
      final diff = recentPrices[i].finalPrice - recentPrices[i - 1].finalPrice;
      if (diff > 0) rises++;
      if (diff < 0) falls++;
    }

    if (rises > falls * 2) return PriceTrend.rising;
    if (falls > rises * 2) return PriceTrend.falling;
    if (rises > 0 && falls > 0) return PriceTrend.volatile;
    return PriceTrend.stable;
  }

}

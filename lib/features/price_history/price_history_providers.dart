import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'price_history_model.dart';
import 'price_history_service.dart';

/// 价格历史服务 Provider
final priceHistoryServiceProvider = Provider<PriceHistoryService>((ref) {
  return PriceHistoryService();
});

/// 当前选择的时间范围 Provider
final priceHistoryTimeRangeProvider = StateProvider<PriceHistoryTimeRange>((ref) {
  return PriceHistoryTimeRange.month;
});

/// 当前选中的商品ID Provider
final selectedProductIdProvider = StateProvider<String?>((ref) {
  return null;
});

/// 价格趋势分析 Provider (需要商品信息)
final priceTrendAnalysisProvider = FutureProvider.autoDispose.family<PriceTrendAnalysis, ProductInfo>((ref, productInfo) async {
  final service = ref.watch(priceHistoryServiceProvider);
  final timeRange = ref.watch(priceHistoryTimeRangeProvider);
  
  return service.analyzePriceTrend(
    productId: productInfo.id,
    productTitle: productInfo.title,
    productImage: productInfo.image,
    timeRange: timeRange,
  );
});

/// 购买时机建议 Provider
final buyingTimeSuggestionProvider = FutureProvider.autoDispose.family<BuyingTimeSuggestion, String>((ref, productId) async {
  final service = ref.watch(priceHistoryServiceProvider);
  final timeRange = ref.watch(priceHistoryTimeRangeProvider);
  
  return service.getBestBuyTime(
    productId: productId,
    timeRange: timeRange,
  );
});

/// 多商品价格对比 Provider
final priceComparisonProvider = FutureProvider.autoDispose.family<List<PriceComparisonItem>, List<Map<String, String>>>((ref, products) async {
  final service = ref.watch(priceHistoryServiceProvider);
  final timeRange = ref.watch(priceHistoryTimeRangeProvider);
  
  return service.comparePrices(
    products: products,
    timeRange: timeRange,
  );
});

/// 用于对比的商品列表 Provider
final comparisonProductsProvider = StateProvider<List<Map<String, String>>>((ref) {
  return [];
});

/// 添加商品到对比列表
void addToComparison(WidgetRef ref, Map<String, String> product) {
  final current = ref.read(comparisonProductsProvider);
  if (current.length < 5 && !current.any((p) => p['id'] == product['id'])) {
    ref.read(comparisonProductsProvider.notifier).state = [...current, product];
  }
}

/// 从对比列表移除商品
void removeFromComparison(WidgetRef ref, String productId) {
  final current = ref.read(comparisonProductsProvider);
  ref.read(comparisonProductsProvider.notifier).state = 
      current.where((p) => p['id'] != productId).toList();
}

/// 清空对比列表
void clearComparison(WidgetRef ref) {
  ref.read(comparisonProductsProvider.notifier).state = [];
}

/// 商品信息（用于Provider参数）
class ProductInfo {
  final String id;
  final String title;
  final String? image;

  const ProductInfo({
    required this.id,
    required this.title,
    this.image,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProductInfo && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

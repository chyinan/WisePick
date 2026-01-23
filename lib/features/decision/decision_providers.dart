import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'decision_models.dart';
import 'decision_service.dart';

/// 决策服务 Provider
final decisionServiceProvider = Provider<DecisionService>((ref) {
  return DecisionService();
});

/// 对比商品列表 Provider
final comparisonListProvider = StateProvider<List<Map<String, dynamic>>>((ref) {
  return [];
});

/// 商品对比结果 Provider
final productComparisonProvider = FutureProvider.autoDispose<ProductComparison?>((ref) async {
  final products = ref.watch(comparisonListProvider);
  if (products.isEmpty) return null;

  final service = ref.watch(decisionServiceProvider);
  return service.compareProducts(products);
});

/// 单个商品评分 Provider
final productScoreProvider = FutureProvider.autoDispose.family<PurchaseDecisionScore, Map<String, dynamic>>((ref, product) async {
  final service = ref.watch(decisionServiceProvider);
  
  return service.calculateScore(
    price: (product['price'] as num?)?.toDouble() ?? 0,
    originalPrice: (product['originalPrice'] as num?)?.toDouble(),
    rating: (product['rating'] as num?)?.toDouble() ?? 0,
    sales: (product['sales'] as num?)?.toInt() ?? 0,
    platform: product['platform'] as String? ?? '',
  );
});

/// 替代商品推荐 Provider
final alternativesProvider = FutureProvider.autoDispose.family<List<AlternativeProduct>, AlternativeRequest>((ref, request) async {
  final service = ref.watch(decisionServiceProvider);
  
  return service.getAlternatives(
    productId: request.productId,
    category: request.category,
    priceRange: request.priceRange,
    limit: request.limit,
  );
});

/// 替代商品请求参数
class AlternativeRequest {
  final String productId;
  final String category;
  final double priceRange;
  final int limit;

  const AlternativeRequest({
    required this.productId,
    required this.category,
    required this.priceRange,
    this.limit = 3,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AlternativeRequest &&
        other.productId == productId &&
        other.category == category &&
        other.priceRange == priceRange &&
        other.limit == limit;
  }

  @override
  int get hashCode => productId.hashCode ^ category.hashCode ^ priceRange.hashCode ^ limit.hashCode;
}

/// 添加商品到对比列表
void addToComparisonList(WidgetRef ref, Map<String, dynamic> product) {
  final current = ref.read(comparisonListProvider);
  if (current.length < 5 && !current.any((p) => p['id'] == product['id'])) {
    ref.read(comparisonListProvider.notifier).state = [...current, product];
  }
}

/// 从对比列表移除商品
void removeFromComparisonList(WidgetRef ref, String productId) {
  final current = ref.read(comparisonListProvider);
  ref.read(comparisonListProvider.notifier).state = 
      current.where((p) => p['id'] != productId).toList();
}

/// 清空对比列表
void clearComparisonList(WidgetRef ref) {
  ref.read(comparisonListProvider.notifier).state = [];
}

/// 对比列表商品数量
int getComparisonCount(WidgetRef ref) {
  return ref.watch(comparisonListProvider).length;
}

/// 检查商品是否在对比列表中
bool isInComparisonList(WidgetRef ref, String productId) {
  final list = ref.watch(comparisonListProvider);
  return list.any((p) => p['id'] == productId);
}

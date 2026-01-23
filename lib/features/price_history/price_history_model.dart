/// 价格历史模块 - 数据模型定义
/// 
/// 基于 PRD v2.0 和 frontend-architecture.md 设计

/// 价格历史记录
class PriceHistoryRecord {
  /// 商品ID
  final String productId;
  
  /// 记录时间
  final DateTime recordedAt;
  
  /// 价格
  final double price;
  
  /// 原价
  final double? originalPrice;
  
  /// 优惠券金额
  final double? couponAmount;
  
  /// 最终价格（扣除优惠券后）
  final double finalPrice;

  const PriceHistoryRecord({
    required this.productId,
    required this.recordedAt,
    required this.price,
    this.originalPrice,
    this.couponAmount,
    required this.finalPrice,
  });

  factory PriceHistoryRecord.fromMap(Map<String, dynamic> map) {
    return PriceHistoryRecord(
      productId: map['product_id'] as String,
      recordedAt: DateTime.parse(map['recorded_at'] as String),
      price: (map['price'] as num).toDouble(),
      originalPrice: (map['original_price'] as num?)?.toDouble(),
      couponAmount: (map['coupon_amount'] as num?)?.toDouble(),
      finalPrice: (map['final_price'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
    'product_id': productId,
    'recorded_at': recordedAt.toIso8601String(),
    'price': price,
    'original_price': originalPrice,
    'coupon_amount': couponAmount,
    'final_price': finalPrice,
  };
}

/// 价格趋势分析结果
class PriceTrendAnalysis {
  /// 商品ID
  final String productId;
  
  /// 商品标题
  final String productTitle;
  
  /// 商品图片
  final String? productImage;
  
  /// 价格历史记录列表
  final List<PriceHistoryRecord> priceHistory;
  
  /// 当前价格
  final double currentPrice;
  
  /// 历史最高价
  final double highestPrice;
  
  /// 历史最低价
  final double lowestPrice;
  
  /// 平均价格
  final double averagePrice;
  
  /// 价格趋势
  final PriceTrend trend;
  
  /// 波动率（标准差/平均价格）
  final double volatility;
  
  /// 分析时间范围
  final DateTime startDate;
  final DateTime endDate;

  const PriceTrendAnalysis({
    required this.productId,
    required this.productTitle,
    this.productImage,
    required this.priceHistory,
    required this.currentPrice,
    required this.highestPrice,
    required this.lowestPrice,
    required this.averagePrice,
    required this.trend,
    required this.volatility,
    required this.startDate,
    required this.endDate,
  });

  /// 当前价格是否处于历史低位（低于平均价的80%）
  bool get isAtLow => currentPrice < averagePrice * 0.8;

  /// 当前价格是否处于历史高位（高于平均价的120%）
  bool get isAtHigh => currentPrice > averagePrice * 1.2;

  /// 获取价格变化百分比（相对于第一条记录）
  double get priceChangePercent {
    if (priceHistory.isEmpty) return 0;
    final firstPrice = priceHistory.first.finalPrice;
    if (firstPrice == 0) return 0;
    return ((currentPrice - firstPrice) / firstPrice) * 100;
  }
}

/// 价格趋势类型
enum PriceTrend {
  /// 上涨
  rising,
  /// 下跌
  falling,
  /// 平稳
  stable,
  /// 波动
  volatile,
}

extension PriceTrendExtension on PriceTrend {
  String get displayName {
    switch (this) {
      case PriceTrend.rising:
        return '上涨';
      case PriceTrend.falling:
        return '下跌';
      case PriceTrend.stable:
        return '平稳';
      case PriceTrend.volatile:
        return '波动';
    }
  }

  String get icon {
    switch (this) {
      case PriceTrend.rising:
        return '📈';
      case PriceTrend.falling:
        return '📉';
      case PriceTrend.stable:
        return '➡️';
      case PriceTrend.volatile:
        return '📊';
    }
  }
}

/// 购买时机建议
class BuyingTimeSuggestion {
  /// 建议类型
  final BuyingSuggestionType type;
  
  /// 建议理由
  final String reason;
  
  /// 置信度 (0-1)
  final double confidence;
  
  /// 预测最佳购买时间（如果有）
  final DateTime? suggestedDate;
  
  /// 预测价格（如果有）
  final double? predictedPrice;

  const BuyingTimeSuggestion({
    required this.type,
    required this.reason,
    required this.confidence,
    this.suggestedDate,
    this.predictedPrice,
  });
}

/// 购买建议类型
enum BuyingSuggestionType {
  /// 立即购买
  buyNow,
  /// 建议等待
  wait,
  /// 建议观望
  observe,
}

extension BuyingSuggestionTypeExtension on BuyingSuggestionType {
  String get displayName {
    switch (this) {
      case BuyingSuggestionType.buyNow:
        return '立即购买';
      case BuyingSuggestionType.wait:
        return '建议等待';
      case BuyingSuggestionType.observe:
        return '建议观望';
    }
  }

  String get description {
    switch (this) {
      case BuyingSuggestionType.buyNow:
        return '当前价格处于历史低位，建议立即购买';
      case BuyingSuggestionType.wait:
        return '价格可能还会下降，建议等待更好的时机';
      case BuyingSuggestionType.observe:
        return '价格波动较大，建议持续观察';
    }
  }
}

/// 价格对比项
class PriceComparisonItem {
  final String productId;
  final String productTitle;
  final String? productImage;
  final String platform;
  final List<PriceHistoryRecord> priceHistory;
  final double currentPrice;
  final PriceTrend trend;

  const PriceComparisonItem({
    required this.productId,
    required this.productTitle,
    this.productImage,
    required this.platform,
    required this.priceHistory,
    required this.currentPrice,
    required this.trend,
  });
}

/// 价格历史时间范围选项
enum PriceHistoryTimeRange {
  week,
  month,
  threeMonths,
  sixMonths,
  year,
  all,
}

extension PriceHistoryTimeRangeExtension on PriceHistoryTimeRange {
  String get displayName {
    switch (this) {
      case PriceHistoryTimeRange.week:
        return '近一周';
      case PriceHistoryTimeRange.month:
        return '近一个月';
      case PriceHistoryTimeRange.threeMonths:
        return '近三个月';
      case PriceHistoryTimeRange.sixMonths:
        return '近六个月';
      case PriceHistoryTimeRange.year:
        return '近一年';
      case PriceHistoryTimeRange.all:
        return '全部';
    }
  }

  Duration get duration {
    switch (this) {
      case PriceHistoryTimeRange.week:
        return const Duration(days: 7);
      case PriceHistoryTimeRange.month:
        return const Duration(days: 30);
      case PriceHistoryTimeRange.threeMonths:
        return const Duration(days: 90);
      case PriceHistoryTimeRange.sixMonths:
        return const Duration(days: 180);
      case PriceHistoryTimeRange.year:
        return const Duration(days: 365);
      case PriceHistoryTimeRange.all:
        return const Duration(days: 3650); // 10 years as max
    }
  }

  DateTime get startDate => DateTime.now().subtract(duration);
}

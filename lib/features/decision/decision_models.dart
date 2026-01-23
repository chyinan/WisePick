/// 购物决策模块 - 数据模型定义
/// 
/// 基于 PRD v2.0 设计，包含多商品对比、购买建议评分、替代商品推荐等

/// 商品对比数据
class ProductComparison {
  /// 对比的商品列表
  final List<ComparisonProduct> products;
  
  /// 对比维度列表
  final List<ComparisonDimension> dimensions;

  const ProductComparison({
    required this.products,
    required this.dimensions,
  });

  /// 获取推荐商品（综合评分最高的）
  ComparisonProduct? get recommendedProduct {
    if (products.isEmpty) return null;
    return products.reduce((a, b) => 
        a.decisionScore.totalScore > b.decisionScore.totalScore ? a : b);
  }
}

/// 对比中的商品
class ComparisonProduct {
  final String id;
  final String title;
  final String? imageUrl;
  final String platform;
  final double price;
  final double? originalPrice;
  final double rating;
  final int sales;
  final String? shopTitle;
  final Map<String, String> specifications;
  final PurchaseDecisionScore decisionScore;

  const ComparisonProduct({
    required this.id,
    required this.title,
    this.imageUrl,
    required this.platform,
    required this.price,
    this.originalPrice,
    required this.rating,
    required this.sales,
    this.shopTitle,
    required this.specifications,
    required this.decisionScore,
  });

  /// 折扣率
  double get discountRate {
    if (originalPrice == null || originalPrice! <= 0) return 0;
    return ((originalPrice! - price) / originalPrice! * 100);
  }
}

/// 对比维度
class ComparisonDimension {
  final String name;
  final String key;
  final DimensionType type;
  final bool highlightBest;
  final bool highlightWorst;

  const ComparisonDimension({
    required this.name,
    required this.key,
    this.type = DimensionType.text,
    this.highlightBest = true,
    this.highlightWorst = false,
  });
}

enum DimensionType {
  text,
  price,
  number,
  rating,
  percentage,
}

/// 购买决策评分
class PurchaseDecisionScore {
  /// 价格评分 (0-25)
  final double priceScore;
  
  /// 评价评分 (0-25)
  final double ratingScore;
  
  /// 销量评分 (0-20)
  final double salesScore;
  
  /// 趋势评分 (0-15)
  final double trendScore;
  
  /// 平台评分 (0-15)
  final double platformScore;
  
  /// 决策理由
  final String reasoning;
  
  /// 详细分析
  final List<ScoreDetail> details;

  const PurchaseDecisionScore({
    required this.priceScore,
    required this.ratingScore,
    required this.salesScore,
    required this.trendScore,
    required this.platformScore,
    required this.reasoning,
    this.details = const [],
  });

  /// 综合评分 (0-100)
  double get totalScore => 
      priceScore + ratingScore + salesScore + trendScore + platformScore;

  /// 评分等级
  ScoreLevel get level {
    if (totalScore >= 85) return ScoreLevel.excellent;
    if (totalScore >= 70) return ScoreLevel.good;
    if (totalScore >= 55) return ScoreLevel.average;
    if (totalScore >= 40) return ScoreLevel.belowAverage;
    return ScoreLevel.poor;
  }

  factory PurchaseDecisionScore.empty() => const PurchaseDecisionScore(
    priceScore: 0,
    ratingScore: 0,
    salesScore: 0,
    trendScore: 0,
    platformScore: 0,
    reasoning: '',
  );
}

/// 评分详情
class ScoreDetail {
  final String dimension;
  final double score;
  final double maxScore;
  final String description;

  const ScoreDetail({
    required this.dimension,
    required this.score,
    required this.maxScore,
    required this.description,
  });

  double get percentage => maxScore > 0 ? score / maxScore : 0;
}

/// 评分等级
enum ScoreLevel {
  excellent,
  good,
  average,
  belowAverage,
  poor,
}

extension ScoreLevelExtension on ScoreLevel {
  String get displayName {
    switch (this) {
      case ScoreLevel.excellent:
        return '极力推荐';
      case ScoreLevel.good:
        return '值得购买';
      case ScoreLevel.average:
        return '中规中矩';
      case ScoreLevel.belowAverage:
        return '谨慎购买';
      case ScoreLevel.poor:
        return '不推荐';
    }
  }

  String get description {
    switch (this) {
      case ScoreLevel.excellent:
        return '综合表现优秀，性价比很高';
      case ScoreLevel.good:
        return '各方面表现良好，值得考虑';
      case ScoreLevel.average:
        return '表现一般，可根据需求决定';
      case ScoreLevel.belowAverage:
        return '存在一些不足，建议再考虑';
      case ScoreLevel.poor:
        return '综合表现较差，不建议购买';
    }
  }
}

/// 替代商品推荐
class AlternativeProduct {
  final String id;
  final String title;
  final String? imageUrl;
  final String platform;
  final double price;
  final double rating;
  final int sales;
  final double similarityScore;
  final String recommendReason;

  const AlternativeProduct({
    required this.id,
    required this.title,
    this.imageUrl,
    required this.platform,
    required this.price,
    required this.rating,
    required this.sales,
    required this.similarityScore,
    required this.recommendReason,
  });
}

/// 对比请求
class ComparisonRequest {
  final List<String> productIds;
  final bool includeAlternatives;
  final bool includeDecisionScore;

  const ComparisonRequest({
    required this.productIds,
    this.includeAlternatives = false,
    this.includeDecisionScore = true,
  });
}

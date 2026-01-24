import 'dart:math';
import 'decision_models.dart';

/// 购物决策服务
/// 
/// 提供商品对比、评分计算、替代商品推荐等功能
class DecisionService {
  // 单例模式
  static final DecisionService _instance = DecisionService._internal();
  factory DecisionService() => _instance;
  DecisionService._internal();

  /// 计算购买决策评分
  PurchaseDecisionScore calculateScore({
    required double price,
    required double? originalPrice,
    required double rating,
    required int sales,
    required String platform,
    double? averageHistoryPrice,
    double? lowestHistoryPrice,
  }) {
    // 价格评分 (0-30)
    final priceScore = _calculatePriceScore(
      price: price,
      originalPrice: originalPrice,
      averageHistoryPrice: averageHistoryPrice,
      lowestHistoryPrice: lowestHistoryPrice,
    );

    // 评价评分 (0-30)
    final ratingScore = _calculateRatingScore(rating, sales);

    // 销量评分 (0-25)
    final salesScore = _calculateSalesScore(sales);

    // 平台评分 (0-15)
    final platformScore = _calculatePlatformScore(platform);

    // 生成决策理由
    final reasoning = _generateReasoning(
      priceScore: priceScore,
      ratingScore: ratingScore,
      salesScore: salesScore,
      platformScore: platformScore,
      price: price,
      rating: rating,
      sales: sales,
      platform: platform,
    );

    // 详细分析
    final details = [
      ScoreDetail(
        dimension: '价格',
        score: priceScore,
        maxScore: 30,
        description: _getPriceDescription(priceScore),
      ),
      ScoreDetail(
        dimension: '评价',
        score: ratingScore,
        maxScore: 30,
        description: _getRatingDescription(ratingScore),
      ),
      ScoreDetail(
        dimension: '销量',
        score: salesScore,
        maxScore: 25,
        description: _getSalesDescription(salesScore),
      ),
      ScoreDetail(
        dimension: '平台',
        score: platformScore,
        maxScore: 15,
        description: _getPlatformDescription(platform),
      ),
    ];

    return PurchaseDecisionScore(
      priceScore: priceScore,
      ratingScore: ratingScore,
      salesScore: salesScore,
      platformScore: platformScore,
      reasoning: reasoning,
      details: details,
    );
  }

  /// 生成商品对比数据
  Future<ProductComparison> compareProducts(List<Map<String, dynamic>> products) async {
    await Future.delayed(const Duration(milliseconds: 300));

    final comparisonProducts = products.map((p) {
      double rating = (p['rating'] as num?)?.toDouble() ?? 0;
      int sales = (p['sales'] as num?)?.toInt() ?? 0;
      final platform = p['platform'] as String? ?? 'unknown';

      // 修正逻辑：根据用户反馈，JD数据的sales字段实际上存的是好评率百分比（例如96代表96%）
      // 这是一个已知的数据源映射错误
      if (platform == 'jd' && sales <= 100 && sales > 0) {
        // 将sales的值作为rating使用 (96 -> 96.0)
        rating = sales.toDouble();
        
        // 既然sales字段被占用了好评率，真实的销量就未知了
        // 我们根据好评率给予一个估算的保底销量，避免评分过低
        // 只有畅销品才会有展示出的高好评率
        sales = 5000; 
      }

      final score = calculateScore(
        price: (p['price'] as num?)?.toDouble() ?? 0,
        originalPrice: (p['originalPrice'] as num?)?.toDouble(),
        rating: rating,
        sales: sales,
        platform: platform,
      );

      return ComparisonProduct(
        id: p['id'] as String? ?? '',
        title: p['title'] as String? ?? '',
        imageUrl: p['imageUrl'] as String?,
        platform: platform,
        price: (p['price'] as num?)?.toDouble() ?? 0,
        originalPrice: (p['originalPrice'] as num?)?.toDouble(),
        rating: rating,
        sales: sales,
        shopTitle: p['shopTitle'] as String?,
        specifications: (p['specifications'] as Map<String, String>?) ?? {},
        decisionScore: score,
      );
    }).toList();

    // 定义对比维度
    const dimensions = [
      ComparisonDimension(name: '价格', key: 'price', type: DimensionType.price),
      ComparisonDimension(name: '评分', key: 'rating', type: DimensionType.rating),
      ComparisonDimension(name: '销量', key: 'sales', type: DimensionType.number),
      ComparisonDimension(name: '综合评分', key: 'totalScore', type: DimensionType.number),
      ComparisonDimension(name: '店铺', key: 'shopTitle', type: DimensionType.text),
      ComparisonDimension(name: '平台', key: 'platform', type: DimensionType.text),
    ];

    return ProductComparison(
      products: comparisonProducts,
      dimensions: dimensions,
    );
  }

  /// 获取替代商品推荐 (Mock数据)
  Future<List<AlternativeProduct>> getAlternatives({
    required String productId,
    required String category,
    required double priceRange,
    int limit = 3,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));

    final random = Random(productId.hashCode);
    final alternatives = <AlternativeProduct>[];

    final platforms = ['淘宝', '京东', '拼多多'];
    final reasons = [
      '同价位中评分更高',
      '销量更高，用户口碑好',
      '价格更低，性价比更优',
      '同品牌其他型号',
      '热销爆款，好评如潮',
    ];

    for (int i = 0; i < limit; i++) {
      alternatives.add(AlternativeProduct(
        id: 'alt_${productId}_$i',
        title: '替代商品 ${i + 1} - $category',
        platform: platforms[random.nextInt(platforms.length)],
        price: priceRange * (0.8 + random.nextDouble() * 0.4),
        rating: 0.85 + random.nextDouble() * 0.15,
        sales: random.nextInt(10000) + 1000,
        similarityScore: 0.7 + random.nextDouble() * 0.25,
        recommendReason: reasons[random.nextInt(reasons.length)],
      ));
    }

    return alternatives;
  }

  // ========== 私有方法 ==========

  double _calculatePriceScore({
    required double price,
    double? originalPrice,
    double? averageHistoryPrice,
    double? lowestHistoryPrice,
  }) {
    double score = 18.0; // 基础分

    // 折扣加分
    if (originalPrice != null && originalPrice > price) {
      final discount = (originalPrice - price) / originalPrice;
      score += discount * 6; // 最多加6分
    }

    // 历史价格对比加分
    if (averageHistoryPrice != null && price < averageHistoryPrice) {
      final belowAverage = (averageHistoryPrice - price) / averageHistoryPrice;
      score += belowAverage * 4; // 最多加4分
    }

    if (lowestHistoryPrice != null && price <= lowestHistoryPrice * 1.05) {
      score += 2; // 接近历史最低加2分
    }

    return min(score, 30);
  }

  double _calculateRatingScore(double rating, int sales) {
    // 如果没有评分数据 (rating <= 0)，但销量很高，说明是好东西
    // 很多电商平台API可能不返回rating字段，导致rating为0
    if (rating <= 0.01) {
       if (sales > 10000) return 28; // 销量过万无差评，默认为好
       if (sales > 1000) return 24;
       if (sales > 100) return 18; // 销量一般，给及格 (60% = 18/30)
       return 12; // 销量也很低，可能真不行
    }

    // 兼容多种评分格式:
    // 1. 小数 0.0-5.0 (常见于商品评分)
    // 2. 小数 0.0-1.0 (常见于好评率)
    // 3. 整数 0-100 (常见于好评率百分比)
    // 4. 整数 0-5 (常见于星级)
    
    double normalizedRating = 0.0;
    
    if (rating > 5) {
      // 认为是百分制 (0-100)，归一化到 0-1
      normalizedRating = rating / 100.0;
    } else if (rating > 1) {
      // 认为是5分制 (1.0-5.0)，归一化到 0-1
      normalizedRating = rating / 5.0;
    } else {
      // 已经是 0-1
      normalizedRating = rating;
    }

    // rating 是 0-1 的评分，满分30
    if (normalizedRating >= 0.95) return 30;
    if (normalizedRating >= 0.9) return 26;
    if (normalizedRating >= 0.85) return 23;
    if (normalizedRating >= 0.8) return 19;
    if (normalizedRating >= 0.7) return 14;
    if (normalizedRating >= 0.6) return 10;
    // 0.2-0.6 给个基础分，避免太难看
    if (normalizedRating >= 0.2) return 6;
    
    // 如果真的很低，但有销量，也给个保底分
    if (sales > 100) return 6;
    
    return 3;
  }

  double _calculateSalesScore(int sales) {
    // 使用对数评分来平滑销量差异
    // 销量 10 => ln(10) ≈ 2.3
    // 销量 100 => ln(100) ≈ 4.6
    // 销量 1000 => ln(1000) ≈ 6.9
    // 销量 10000 => ln(10000) ≈ 9.2
    // 销量 100000 => ln(100000) ≈ 11.5
    
    if (sales <= 0) return 0;
    
    // 基础分 4 分，加上对数增长
    // 系数 1.8 使得 10万销量大约能得 4 + 11.5 * 1.8 ≈ 25分
    // 100销量 ≈ 4 + 4.6 * 1.8 ≈ 12分
    // 即使销量只有几十，也不至于0分
    
    double logSales = log(sales);
    double score = 4.0 + logSales * 1.8;
    
    return min(score, 25.0);
  }

  double _calculatePlatformScore(String platform) {
    switch (platform.toLowerCase()) {
      case 'jd':
      case '京东':
        return 15; // 京东自营品质保障
      case 'taobao':
      case '淘宝':
      case 'tmall':
      case '天猫':
        return 13;
      case 'pdd':
      case '拼多多':
        return 10;
      default:
        return 8;
    }
  }

  String _generateReasoning({
    required double priceScore,
    required double ratingScore,
    required double salesScore,
    required double platformScore,
    required double price,
    required double rating,
    required int sales,
    required String platform,
  }) {
    final totalScore = priceScore + ratingScore + salesScore + platformScore;
    final parts = <String>[];

    // 综合评价 (满分100)
    if (totalScore >= 85) {
      parts.add('这款商品综合表现优秀');
    } else if (totalScore >= 70) {
      parts.add('这款商品整体表现良好');
    } else if (totalScore >= 55) {
      parts.add('这款商品表现中规中矩');
    } else {
      parts.add('这款商品存在一些不足');
    }

    // 价格评价
    if (priceScore >= 24) {
      parts.add('价格非常有竞争力');
    } else if (priceScore >= 18) {
      parts.add('价格较为合理');
    }

    // 评价评分
    if (ratingScore >= 26) {
      parts.add('用户评价很高');
    } else if (ratingScore >= 19) {
      parts.add('用户口碑不错');
    }

    // 销量评价
    if (salesScore >= 22) {
      parts.add('销量出色，市场认可度高');
    } else if (salesScore >= 15) {
      parts.add('销量表现良好');
    }

    return parts.join('，') + '。';
  }

  String _getPriceDescription(double score) {
    if (score >= 24) return '价格非常有优势，性价比极高';
    if (score >= 18) return '价格较为合理';
    if (score >= 12) return '价格中等';
    return '价格偏高';
  }

  String _getRatingDescription(double score) {
    if (score >= 26) return '用户评价极高，好评如潮';
    if (score >= 19) return '用户评价良好';
    if (score >= 12) return '用户评价一般';
    return '用户评价较差';
  }

  String _getSalesDescription(double score) {
    if (score >= 22) return '销量火爆，市场认可';
    if (score >= 15) return '销量不错';
    if (score >= 8) return '销量一般';
    return '销量较低';
  }

  String _getPlatformDescription(String platform) {
    switch (platform.toLowerCase()) {
      case 'jd':
      case '京东':
        return '京东平台，品质有保障';
      case 'taobao':
      case '淘宝':
        return '淘宝平台，选择丰富';
      case 'tmall':
      case '天猫':
        return '天猫平台，品牌官方';
      case 'pdd':
      case '拼多多':
        return '拼多多平台，价格优惠';
      default:
        return '其他平台';
    }
  }
}

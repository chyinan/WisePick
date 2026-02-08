import 'dart:convert';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// 后端决策服务 - 提供商品评分和对比的真实逻辑
class DecisionService {
  // CORS headers
  static const _corsHeaders = {
    'content-type': 'application/json',
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, POST, OPTIONS',
    'access-control-allow-headers':
        'Origin, Content-Type, Accept, Authorization',
  };

  Router get router {
    final router = Router();
    router.post('/compare', _handleCompare);
    router.post('/score', _handleScore);
    return router;
  }

  /// 商品对比 - 对多个商品进行评分和对比
  Future<Response> _handleCompare(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body);

      if (data is! Map || !data.containsKey('products')) {
        return Response(400,
            body: jsonEncode(
                {'error': '请求体必须包含 products 数组'}),
            headers: _corsHeaders);
      }

      final products = (data['products'] as List?) ?? [];
      if (products.isEmpty) {
        return Response(400,
            body: jsonEncode({'error': '至少需要一个商品进行对比'}),
            headers: _corsHeaders);
      }

      final comparedProducts = products.map((p) {
        final product = p as Map<String, dynamic>;
        double rating = (product['rating'] as num?)?.toDouble() ?? 0;
        int sales = (product['sales'] as num?)?.toInt() ?? 0;
        final platform = product['platform'] as String? ?? 'unknown';

        // 修正 JD 数据映射问题：sales 字段存的是好评率百分比
        if (platform == 'jd' && sales <= 100 && sales > 0) {
          rating = sales.toDouble();
          sales = 5000; // 有好评率展示的商品默认有一定销量
        }

        final price = (product['price'] as num?)?.toDouble() ?? 0;
        final originalPrice =
            (product['originalPrice'] as num?)?.toDouble();

        final score = _calculateScore(
          price: price,
          originalPrice: originalPrice,
          rating: rating,
          sales: sales,
          platform: platform,
        );

        return {
          'id': product['id'] ?? '',
          'title': product['title'] ?? '',
          'platform': platform,
          'price': price,
          'originalPrice': originalPrice,
          'rating': rating,
          'sales': sales,
          'score': score,
        };
      }).toList();

      // 按总分排序
      comparedProducts.sort((a, b) {
        final scoreA = a['score'] as Map<String, dynamic>;
        final scoreB = b['score'] as Map<String, dynamic>;
        return (scoreB['totalScore'] as num)
            .compareTo(scoreA['totalScore'] as num);
      });

      return Response.ok(
          jsonEncode({
            'status': 'ok',
            'products': comparedProducts,
            'recommendation': comparedProducts.isNotEmpty
                ? '推荐 "${comparedProducts.first['title']}"，综合评分最高。'
                : '无法提供推荐',
          }),
          headers: _corsHeaders);
    } catch (e) {
      print('[DecisionService] Error in compare: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  /// 单商品评分
  Future<Response> _handleScore(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final price = (data['price'] as num?)?.toDouble() ?? 0;
      final originalPrice =
          (data['originalPrice'] as num?)?.toDouble();
      double rating = (data['rating'] as num?)?.toDouble() ?? 0;
      int sales = (data['sales'] as num?)?.toInt() ?? 0;
      final platform = data['platform'] as String? ?? 'unknown';

      // JD 数据修正
      if (platform == 'jd' && sales <= 100 && sales > 0) {
        rating = sales.toDouble();
        sales = 5000;
      }

      final score = _calculateScore(
        price: price,
        originalPrice: originalPrice,
        rating: rating,
        sales: sales,
        platform: platform,
      );

      return Response.ok(jsonEncode(score), headers: _corsHeaders);
    } catch (e) {
      print('[DecisionService] Error in score: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  // ========== 评分核心逻辑 ==========

  /// 计算综合评分 (总分100)
  Map<String, dynamic> _calculateScore({
    required double price,
    double? originalPrice,
    required double rating,
    required int sales,
    required String platform,
  }) {
    final priceScore = _calculatePriceScore(
      price: price,
      originalPrice: originalPrice,
    );
    final ratingScore = _calculateRatingScore(rating, sales);
    final salesScore = _calculateSalesScore(sales);
    final platformScore = _calculatePlatformScore(platform);
    final totalScore = priceScore + ratingScore + salesScore + platformScore;

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

    return {
      'totalScore': double.parse(totalScore.toStringAsFixed(1)),
      'breakdown': {
        'price': {'score': double.parse(priceScore.toStringAsFixed(1)), 'maxScore': 30, 'description': _getPriceDescription(priceScore)},
        'rating': {'score': double.parse(ratingScore.toStringAsFixed(1)), 'maxScore': 30, 'description': _getRatingDescription(ratingScore)},
        'sales': {'score': double.parse(salesScore.toStringAsFixed(1)), 'maxScore': 25, 'description': _getSalesDescription(salesScore)},
        'platform': {'score': double.parse(platformScore.toStringAsFixed(1)), 'maxScore': 15, 'description': _getPlatformDescription(platform)},
      },
      'reasoning': reasoning,
    };
  }

  /// 价格评分 (0-30)
  double _calculatePriceScore({
    required double price,
    double? originalPrice,
  }) {
    double score = 18.0;

    if (originalPrice != null && originalPrice > price) {
      final discount = (originalPrice - price) / originalPrice;
      score += discount * 6;
    }

    return min(score, 30);
  }

  /// 评价评分 (0-30)
  double _calculateRatingScore(double rating, int sales) {
    if (rating <= 0.01) {
      if (sales > 10000) return 28;
      if (sales > 1000) return 24;
      if (sales > 100) return 18;
      return 12;
    }

    double normalizedRating;
    if (rating > 5) {
      normalizedRating = rating / 100.0;
    } else if (rating > 1) {
      normalizedRating = rating / 5.0;
    } else {
      normalizedRating = rating;
    }

    if (normalizedRating >= 0.95) return 30;
    if (normalizedRating >= 0.9) return 26;
    if (normalizedRating >= 0.85) return 23;
    if (normalizedRating >= 0.8) return 19;
    if (normalizedRating >= 0.7) return 14;
    if (normalizedRating >= 0.6) return 10;
    if (normalizedRating >= 0.2) return 6;
    if (sales > 100) return 6;
    return 3;
  }

  /// 销量评分 (0-25)
  double _calculateSalesScore(int sales) {
    if (sales <= 0) return 0;
    double logSales = log(sales);
    double score = 4.0 + logSales * 1.8;
    return min(score, 25.0);
  }

  /// 平台评分 (0-15)
  double _calculatePlatformScore(String platform) {
    switch (platform.toLowerCase()) {
      case 'jd':
      case '京东':
        return 15;
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

  /// 生成决策理由
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

    if (totalScore >= 85) {
      parts.add('这款商品综合表现优秀');
    } else if (totalScore >= 70) {
      parts.add('这款商品整体表现良好');
    } else if (totalScore >= 55) {
      parts.add('这款商品表现中规中矩');
    } else {
      parts.add('这款商品存在一些不足');
    }

    if (priceScore >= 24) {
      parts.add('价格非常有竞争力');
    } else if (priceScore >= 18) {
      parts.add('价格较为合理');
    }

    if (ratingScore >= 26) {
      parts.add('用户评价很高');
    } else if (ratingScore >= 19) {
      parts.add('用户口碑不错');
    }

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

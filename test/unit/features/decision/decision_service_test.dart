import 'package:test/test.dart';
import 'package:wisepick_dart_version/features/decision/decision_service.dart';
import 'package:wisepick_dart_version/features/decision/decision_models.dart';

void main() {
  // DecisionService 是单例，直接使用
  final svc = DecisionService();

  // ─── calculateScore ──────────────────────────────────────────────────────

  group('calculateScore', () {
    test('京东高评分高销量 → totalScore >= 85，level = excellent', () {
      final score = svc.calculateScore(
        price: 199,
        originalPrice: 299,
        rating: 4.8,
        sales: 50000,
        platform: 'jd',
      );
      expect(score.totalScore, greaterThanOrEqualTo(85));
      expect(score.level, ScoreLevel.excellent);
    });

    test('无评分低销量 → totalScore < 55', () {
      final score = svc.calculateScore(
        price: 199,
        originalPrice: null,
        rating: 0,
        sales: 10,
        platform: 'unknown',
      );
      expect(score.totalScore, lessThan(55));
    });

    test('有折扣且低于历史均价 → priceScore > 18', () {
      final score = svc.calculateScore(
        price: 80,
        originalPrice: 100,
        rating: 4.5,
        sales: 1000,
        platform: 'taobao',
        averageHistoryPrice: 95,
      );
      expect(score.priceScore, greaterThan(18));
    });
  });

  // ─── _calculateRatingScore（通过 calculateScore 间接测试）────────────────

  group('_calculateRatingScore（间接）', () {
    test('rating=4.8（5分制）→ ratingScore = 30', () {
      final score = svc.calculateScore(
        price: 100, originalPrice: null,
        rating: 4.8, sales: 1000, platform: 'jd',
      );
      expect(score.ratingScore, equals(30));
    });

    test('rating=96（百分制）→ ratingScore = 30', () {
      final score = svc.calculateScore(
        price: 100, originalPrice: null,
        rating: 96, sales: 1000, platform: 'jd',
      );
      expect(score.ratingScore, equals(30));
    });

    test('rating=0, sales=50000 → ratingScore = 28', () {
      final score = svc.calculateScore(
        price: 100, originalPrice: null,
        rating: 0, sales: 50000, platform: 'jd',
      );
      expect(score.ratingScore, equals(28));
    });
  });

  // ─── _calculateSalesScore ────────────────────────────────────────────────

  group('_calculateSalesScore（间接）', () {
    test('sales=0 → salesScore = 0', () {
      final score = svc.calculateScore(
        price: 100, originalPrice: null,
        rating: 4.5, sales: 0, platform: 'jd',
      );
      expect(score.salesScore, equals(0));
    });

    test('sales=100000 → salesScore 接近上限 25', () {
      final score = svc.calculateScore(
        price: 100, originalPrice: null,
        rating: 4.5, sales: 100000, platform: 'jd',
      );
      expect(score.salesScore, greaterThan(24));
      expect(score.salesScore, lessThanOrEqualTo(25));
    });
  });

  // ─── _calculatePlatformScore ─────────────────────────────────────────────

  group('_calculatePlatformScore（间接）', () {
    test('jd → platformScore = 15', () {
      final score = svc.calculateScore(
        price: 100, originalPrice: null,
        rating: 4.5, sales: 1000, platform: 'jd',
      );
      expect(score.platformScore, equals(15));
    });

    test('taobao → platformScore = 13', () {
      final score = svc.calculateScore(
        price: 100, originalPrice: null,
        rating: 4.5, sales: 1000, platform: 'taobao',
      );
      expect(score.platformScore, equals(13));
    });

    test('pdd → platformScore = 10', () {
      final score = svc.calculateScore(
        price: 100, originalPrice: null,
        rating: 4.5, sales: 1000, platform: 'pdd',
      );
      expect(score.platformScore, equals(10));
    });

    test('unknown → platformScore = 8', () {
      final score = svc.calculateScore(
        price: 100, originalPrice: null,
        rating: 4.5, sales: 1000, platform: 'unknown',
      );
      expect(score.platformScore, equals(8));
    });
  });

  // ─── ScoreLevel ──────────────────────────────────────────────────────────

  group('ScoreLevel', () {
    PurchaseDecisionScore scoreWith(double total) {
      // 分配到各维度，使 totalScore == total
      return PurchaseDecisionScore(
        priceScore: total * 0.3,
        ratingScore: total * 0.3,
        salesScore: total * 0.25,
        platformScore: total * 0.15,
        reasoning: '',
      );
    }

    test('totalScore=90 → excellent，displayName=极力推荐', () {
      final s = scoreWith(90);
      expect(s.level, ScoreLevel.excellent);
      expect(s.level.displayName, '极力推荐');
    });

    test('totalScore=72 → good', () {
      expect(scoreWith(72).level, ScoreLevel.good);
    });

    test('totalScore=57 → average', () {
      expect(scoreWith(57).level, ScoreLevel.average);
    });

    test('totalScore=42 → belowAverage', () {
      expect(scoreWith(42).level, ScoreLevel.belowAverage);
    });

    test('totalScore=30 → poor', () {
      expect(scoreWith(30).level, ScoreLevel.poor);
    });
  });

  // ─── ComparisonProduct.discountRate ──────────────────────────────────────

  group('ComparisonProduct.discountRate', () {
    PurchaseDecisionScore emptyScore() => PurchaseDecisionScore.empty();

    test('originalPrice=100, price=80 → discountRate = 20.0', () {
      final p = ComparisonProduct(
        id: '1', title: 'T', platform: 'jd',
        price: 80, originalPrice: 100,
        rating: 4.5, sales: 1000,
        specifications: {}, decisionScore: emptyScore(),
      );
      expect(p.discountRate, closeTo(20.0, 0.01));
    });

    test('originalPrice=null → discountRate = 0', () {
      final p = ComparisonProduct(
        id: '1', title: 'T', platform: 'jd',
        price: 80, originalPrice: null,
        rating: 4.5, sales: 1000,
        specifications: {}, decisionScore: emptyScore(),
      );
      expect(p.discountRate, equals(0));
    });
  });

  // ─── compareProducts JD 数据修正 ─────────────────────────────────────────

  group('compareProducts — JD 数据修正', () {
    test('platform=jd, sales=96 → rating 被修正为 96.0，sales 被修正为 5000', () async {
      final comparison = await svc.compareProducts([
        {
          'id': 'jd-1',
          'title': '测试商品',
          'platform': 'jd',
          'price': 199.0,
          'sales': 96,
          'rating': 0.0,
        }
      ]);
      final product = comparison.products.first;
      expect(product.rating, equals(96.0));
      expect(product.sales, equals(5000));
    });
  });

  // ─── 淘宝销量缺失时的评分算法 ──────────────────────────────────────────────

  group('淘宝销量缺失时的评分算法', () {
    test('淘宝商品 sales=0 时，salesAvailable=false，salesScore=12.5', () {
      final score = svc.calculateScore(
        price: 100,
        originalPrice: null,
        rating: 0,
        sales: 0,
        platform: 'taobao',
        salesAvailable: false,
      );
      expect(score.salesScore, equals(12.5));
    });

    test('淘宝商品 sales=0, rating=0 时，ratingScore=15（中性分）', () {
      final score = svc.calculateScore(
        price: 100,
        originalPrice: null,
        rating: 0,
        sales: 0,
        platform: 'taobao',
        salesAvailable: false,
      );
      expect(score.ratingScore, equals(15));
    });

    test('淘宝商品无销量数据时，totalScore ≈ 58.5（中规中矩）', () {
      final score = svc.calculateScore(
        price: 100,
        originalPrice: null,
        rating: 0,
        sales: 0,
        platform: 'taobao',
        salesAvailable: false,
      );
      // 价格18 + 评价15 + 销量12.5 + 平台13 = 58.5
      expect(score.totalScore, closeTo(58.5, 0.1));
      expect(score.level, ScoreLevel.average);
    });

    test('淘宝商品无销量数据时，reasoning 包含"销量数据暂无"说明', () {
      final score = svc.calculateScore(
        price: 100,
        originalPrice: null,
        rating: 0,
        sales: 0,
        platform: 'taobao',
        salesAvailable: false,
      );
      expect(score.reasoning, contains('销量数据暂无'));
    });

    test('淘宝商品无销量数据时，销量维度描述为"销量数据暂无"', () {
      final score = svc.calculateScore(
        price: 100,
        originalPrice: null,
        rating: 0,
        sales: 0,
        platform: 'taobao',
        salesAvailable: false,
      );
      final salesDetail = score.details.firstWhere((d) => d.dimension == '销量');
      expect(salesDetail.description, equals('销量数据暂无'));
    });

    test('compareProducts 自动检测淘宝 sales=0 为数据不可用', () async {
      final comparison = await svc.compareProducts([
        {
          'id': 'taobao-1',
          'title': '淘宝商品',
          'platform': 'taobao',
          'price': 100.0,
          'sales': 0,
          'rating': 0.0,
        }
      ]);
      final product = comparison.products.first;
      // 验证评分是否为中规中矩
      expect(product.decisionScore.totalScore, closeTo(58.5, 0.1));
      expect(product.decisionScore.level, ScoreLevel.average);
    });

    test('淘宝商品有销量时，salesAvailable=true，正常计算', () {
      final score = svc.calculateScore(
        price: 100,
        originalPrice: null,
        rating: 0,
        sales: 1000,
        platform: 'taobao',
        salesAvailable: true,
      );
      // sales=1000 时 salesScore ≈ 4 + ln(1000)*1.8 ≈ 4 + 6.9*1.8 ≈ 16.4
      expect(score.salesScore, greaterThan(12.5));
      expect(score.reasoning, isNot(contains('销量数据暂无')));
    });

    test('京东商品 sales=0 时，salesAvailable=true（京东数据不同），正常计算', () {
      final score = svc.calculateScore(
        price: 100,
        originalPrice: null,
        rating: 0,
        sales: 0,
        platform: 'jd',
        salesAvailable: true,
      );
      // 京东 sales=0 时不视为数据不可用
      expect(score.salesScore, equals(0));
      expect(score.reasoning, isNot(contains('销量数据暂无')));
    });
  });
}

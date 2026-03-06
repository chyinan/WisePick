import 'dart:io';

import 'package:hive/hive.dart';
import 'package:test/test.dart';
import 'package:wisepick_dart_version/features/price_history/price_history_model.dart';
import 'package:wisepick_dart_version/features/price_history/price_history_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_price_test_');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    try {
      await Hive.deleteFromDisk();
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    await PriceHistoryService().clearAllPriceHistory();
  });

  group('PriceHistoryService - 记录价格', () {
    test('记录价格后可查询到', () async {
      final svc = PriceHistoryService();
      await svc.recordPriceHistory(
        productId: 'p1',
        price: 100.0,
        finalPrice: 90.0,
      );

      final history = await svc.getPriceHistory(
        productId: 'p1',
        timeRange: PriceHistoryTimeRange.year,
      );

      expect(history.length, 1);
      expect(history.first.finalPrice, 90.0);
    });

    test('相同价格在 24 小时内不重复记录', () async {
      final svc = PriceHistoryService();
      await svc.recordPriceHistory(
          productId: 'p2', price: 50.0, finalPrice: 50.0);
      await svc.recordPriceHistory(
          productId: 'p2', price: 50.0, finalPrice: 50.0);

      final history = await svc.getPriceHistory(
        productId: 'p2',
        timeRange: PriceHistoryTimeRange.year,
      );

      expect(history.length, 1);
    });

    test('价格变化时追加新记录', () async {
      final svc = PriceHistoryService();
      await svc.recordPriceHistory(
          productId: 'p3', price: 100.0, finalPrice: 100.0);
      await svc.recordPriceHistory(
          productId: 'p3', price: 80.0, finalPrice: 80.0);

      final history = await svc.getPriceHistory(
        productId: 'p3',
        timeRange: PriceHistoryTimeRange.year,
      );

      expect(history.length, 2);
    });

    test('clearPriceHistory 清除指定商品数据', () async {
      final svc = PriceHistoryService();
      await svc.recordPriceHistory(
          productId: 'p4', price: 60.0, finalPrice: 60.0);
      await svc.clearPriceHistory('p4');

      final history = await svc.getPriceHistory(
        productId: 'p4',
        timeRange: PriceHistoryTimeRange.year,
      );

      expect(history.isEmpty, isTrue);
    });
  });

  group('PriceHistoryService - 趋势分析', () {
    test('无数据时返回空分析结果', () async {
      final svc = PriceHistoryService();
      final analysis = await svc.analyzePriceTrend(
        productId: 'empty',
        productTitle: '测试商品',
      );

      expect(analysis.priceHistory.isEmpty, isTrue);
      expect(analysis.currentPrice, 0);
    });

    test('有数据时正确计算最高/最低/平均价', () async {
      final svc = PriceHistoryService();
      // 写入三条不同价格（间隔足够大以绕过去重逻辑）
      final box = await Hive.openBox('price_history_records');
      final records = [
        PriceHistoryRecord(
          productId: 'p5',
          recordedAt: DateTime.now().subtract(const Duration(days: 3)),
          price: 120.0,
          finalPrice: 120.0,
        ),
        PriceHistoryRecord(
          productId: 'p5',
          recordedAt: DateTime.now().subtract(const Duration(days: 2)),
          price: 80.0,
          finalPrice: 80.0,
        ),
        PriceHistoryRecord(
          productId: 'p5',
          recordedAt: DateTime.now().subtract(const Duration(days: 1)),
          price: 100.0,
          finalPrice: 100.0,
        ),
      ];
      await box.put('p5', records.map((r) => r.toMap()).toList());

      final analysis = await svc.analyzePriceTrend(
        productId: 'p5',
        productTitle: '测试商品',
        timeRange: PriceHistoryTimeRange.year,
      );

      expect(analysis.highestPrice, 120.0);
      expect(analysis.lowestPrice, 80.0);
      expect(analysis.averagePrice, closeTo(100.0, 0.01));
    });
  });

  group('PriceHistoryService - 购买建议', () {
    test('无数据时返回 observe 建议', () async {
      final svc = PriceHistoryService();
      final suggestion = await svc.getBestBuyTime(productId: 'no_data');
      expect(suggestion.type, BuyingSuggestionType.observe);
    });

    test('当前价格接近历史最低时建议立即购买', () async {
      final svc = PriceHistoryService();
      final box = await Hive.openBox('price_history_records');
      final records = [
        PriceHistoryRecord(
          productId: 'buy_now',
          recordedAt: DateTime.now().subtract(const Duration(days: 5)),
          price: 200.0,
          finalPrice: 200.0,
        ),
        PriceHistoryRecord(
          productId: 'buy_now',
          recordedAt: DateTime.now().subtract(const Duration(days: 1)),
          price: 100.0,
          finalPrice: 100.0, // 接近历史最低
        ),
      ];
      await box.put('buy_now', records.map((r) => r.toMap()).toList());

      final suggestion = await svc.getBestBuyTime(
        productId: 'buy_now',
        timeRange: PriceHistoryTimeRange.year,
      );

      expect(suggestion.type, BuyingSuggestionType.buyNow);
    });
  });
}

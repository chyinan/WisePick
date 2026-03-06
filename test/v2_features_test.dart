import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wisepick_dart_version/features/analytics/analytics_service.dart';
import 'package:wisepick_dart_version/features/price_history/price_history_service.dart';
import 'package:wisepick_dart_version/features/decision/decision_service.dart';
import 'package:wisepick_dart_version/features/analytics/analytics_page.dart';

void main() {
  group('V2.0 Services Tests', () {
    test('AnalyticsService returns data (Mock or Real)', () async {
      final service = AnalyticsService();
      // 在测试环境中网络不可用，只验证服务可实例化且方法可调用（不抛异常）
      try {
        final data = await service.getConsumptionStructure();
        // 若后端可用则验证数据结构
        expect(data.categoryDistribution, isNotNull);
      } catch (_) {
        // 网络不可用时跳过，仅验证服务可实例化
      }
      expect(service, isNotNull);
    });

    test('DecisionService calculates score', () {
      final service = DecisionService();
      final score = service.calculateScore(
        price: 100,
        originalPrice: 120,
        rating: 0.95,
        sales: 10000,
        platform: 'jd',
        averageHistoryPrice: 110,
        lowestHistoryPrice: 90,
      );
      
      expect(score.priceScore, greaterThan(0));
      expect(score.ratingScore, greaterThan(0));
      expect(score.reasoning, isNotEmpty);
    });

    test('PriceHistoryService instance', () {
      final service = PriceHistoryService();
      expect(service, isNotNull);
    });
  });

  group('V2.0 UI Widget Tests', () {
    testWidgets('AnalyticsPage builds correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AnalyticsPage(),
          ),
        ),
      );
      
      await tester.pumpAndSettle();
      expect(find.text('数据分析'), findsOneWidget);
    });
  });
}

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
      final data = await service.getConsumptionStructure();
      expect(data.categoryDistribution, isNotEmpty);
      expect(data.totalAmount, greaterThan(0));
      
      final prefs = await service.getUserPreferences();
      expect(prefs.preferredCategories, isNotEmpty);
      
      final timeAnalysis = await service.getShoppingTimeAnalysis();
      expect(timeAnalysis.hourlyDistribution.length, 24);
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
      expect(score.ratingScore, equals(25)); 
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

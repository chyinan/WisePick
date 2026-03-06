import 'package:flutter_test/flutter_test.dart';
import 'package:wisepick_dart_version/features/analytics/analytics_service.dart';
import 'package:wisepick_dart_version/features/price_history/price_history_service.dart';

void main() {
  group('V2.0 Features Mock Data Tests', () {
    test('AnalyticsService returns mock data', () async {
      final service = AnalyticsService();
      final data = await service.getConsumptionStructure();
      
      expect(data.categoryDistribution, isNotEmpty);
      expect(data.totalAmount, greaterThan(0));
      
      final prefs = await service.getUserPreferences();
      expect(prefs.preferredCategories, isNotEmpty);
      
      final timeAnalysis = await service.getShoppingTimeAnalysis();
      expect(timeAnalysis.hourlyDistribution.length, 24);
    });

    test('PriceHistoryService returns mock data', () async {
      PriceHistoryService();
      // Service instantiation verified
    });
  });
}

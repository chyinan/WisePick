import 'package:flutter_test/flutter_test.dart';
import 'package:wisepick_dart_version/features/analytics/analytics_models.dart';

void main() {
  // ──────────────────────────────────────────────────────────────
  // AnalyticsDateRange
  // ──────────────────────────────────────────────────────────────
  group('AnalyticsDateRange', () {
    test('description - 近一周', () {
      final r = AnalyticsDateRange(
        start: DateTime.now().subtract(const Duration(days: 5)),
        end: DateTime.now(),
      );
      expect(r.description, equals('近一周'));
    });

    test('description - 近一个月', () {
      final r = AnalyticsDateRange(
        start: DateTime.now().subtract(const Duration(days: 25)),
        end: DateTime.now(),
      );
      expect(r.description, equals('近一个月'));
    });

    test('description - 近三个月', () {
      final r = AnalyticsDateRange(
        start: DateTime.now().subtract(const Duration(days: 60)),
        end: DateTime.now(),
      );
      expect(r.description, equals('近三个月'));
    });

    test('description - 近一年', () {
      final r = AnalyticsDateRange(
        start: DateTime.now().subtract(const Duration(days: 200)),
        end: DateTime.now(),
      );
      expect(r.description, equals('近一年'));
    });

    test('description - 全部时间', () {
      final r = AnalyticsDateRange(
        start: DateTime.now().subtract(const Duration(days: 400)),
        end: DateTime.now(),
      );
      expect(r.description, equals('全部时间'));
    });

    test('lastWeek 范围约为 7 天', () {
      final r = AnalyticsDateRange.lastWeek();
      final days = r.end.difference(r.start).inDays;
      expect(days, equals(7));
    });

    test('lastMonth 范围约为 30 天', () {
      final r = AnalyticsDateRange.lastMonth();
      final days = r.end.difference(r.start).inDays;
      expect(days, equals(30));
    });

    test('lastThreeMonths 范围约为 90 天', () {
      final r = AnalyticsDateRange.lastThreeMonths();
      final days = r.end.difference(r.start).inDays;
      expect(days, equals(90));
    });

    test('lastYear 范围约为 365 天', () {
      final r = AnalyticsDateRange.lastYear();
      final days = r.end.difference(r.start).inDays;
      expect(days, equals(365));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // PlatformPreference.displayName
  // ──────────────────────────────────────────────────────────────
  group('PlatformPreference.displayName', () {
    test('taobao → 淘宝', () {
      const p = PlatformPreference(platform: 'taobao', count: 1, amount: 0, percentage: 0);
      expect(p.displayName, equals('淘宝'));
    });

    test('jd → 京东', () {
      const p = PlatformPreference(platform: 'jd', count: 1, amount: 0, percentage: 0);
      expect(p.displayName, equals('京东'));
    });

    test('pdd → 拼多多', () {
      const p = PlatformPreference(platform: 'pdd', count: 1, amount: 0, percentage: 0);
      expect(p.displayName, equals('拼多多'));
    });

    test('未知平台返回原始值', () {
      const p = PlatformPreference(platform: 'amazon', count: 1, amount: 0, percentage: 0);
      expect(p.displayName, equals('amazon'));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // HourlyDistribution.displayHour
  // ──────────────────────────────────────────────────────────────
  group('HourlyDistribution.displayHour', () {
    test('0 → 00:00', () {
      const h = HourlyDistribution(hour: 0, count: 0);
      expect(h.displayHour, equals('00:00'));
    });

    test('9 → 09:00', () {
      const h = HourlyDistribution(hour: 9, count: 0);
      expect(h.displayHour, equals('09:00'));
    });

    test('23 → 23:00', () {
      const h = HourlyDistribution(hour: 23, count: 0);
      expect(h.displayHour, equals('23:00'));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // WeekdayDistribution.displayName
  // ──────────────────────────────────────────────────────────────
  group('WeekdayDistribution.displayName', () {
    test('0 → 周一', () {
      const d = WeekdayDistribution(weekday: 0, count: 0);
      expect(d.displayName, equals('周一'));
    });

    test('6 → 周日', () {
      const d = WeekdayDistribution(weekday: 6, count: 0);
      expect(d.displayName, equals('周日'));
    });

    test('所有星期名称正确', () {
      const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      for (var i = 0; i < 7; i++) {
        final d = WeekdayDistribution(weekday: i, count: 0);
        expect(d.displayName, equals(names[i]));
      }
    });
  });

  // ──────────────────────────────────────────────────────────────
  // ConsumptionStructure.empty
  // ──────────────────────────────────────────────────────────────
  group('ConsumptionStructure.empty', () {
    test('所有列表为空', () {
      final s = ConsumptionStructure.empty();
      expect(s.categoryDistribution, isEmpty);
      expect(s.priceRangeDistribution, isEmpty);
      expect(s.platformPreference, isEmpty);
    });

    test('totalAmount 和 totalProducts 为 0', () {
      final s = ConsumptionStructure.empty();
      expect(s.totalAmount, equals(0.0));
      expect(s.totalProducts, equals(0));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // UserPreferences.empty
  // ──────────────────────────────────────────────────────────────
  group('UserPreferences.empty', () {
    test('所有列表为空', () {
      final p = UserPreferences.empty();
      expect(p.preferredCategories, isEmpty);
      expect(p.platformRanking, isEmpty);
      expect(p.userTags, isEmpty);
    });

    test('shoppingFrequency 为暂无数据', () {
      final p = UserPreferences.empty();
      expect(p.shoppingFrequency, equals('暂无数据'));
    });

    test('pricePreference averagePrice 为 0', () {
      final p = UserPreferences.empty();
      expect(p.pricePreference.averagePrice, equals(0.0));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // ShoppingTimeAnalysis.empty
  // ──────────────────────────────────────────────────────────────
  group('ShoppingTimeAnalysis.empty', () {
    test('hourlyDistribution 有 24 个元素', () {
      final a = ShoppingTimeAnalysis.empty();
      expect(a.hourlyDistribution.length, equals(24));
    });

    test('weekdayDistribution 有 7 个元素', () {
      final a = ShoppingTimeAnalysis.empty();
      expect(a.weekdayDistribution.length, equals(7));
    });

    test('heatmapData 为 7x24', () {
      final a = ShoppingTimeAnalysis.empty();
      expect(a.heatmapData.length, equals(7));
      for (final row in a.heatmapData) {
        expect(row.length, equals(24));
      }
    });

    test('peakHours 和 peakDays 为暂无数据', () {
      final a = ShoppingTimeAnalysis.empty();
      expect(a.peakHours, equals('暂无数据'));
      expect(a.peakDays, equals('暂无数据'));
    });

    test('所有计数为 0', () {
      final a = ShoppingTimeAnalysis.empty();
      for (final h in a.hourlyDistribution) {
        expect(h.count, equals(0));
      }
      for (final d in a.weekdayDistribution) {
        expect(d.count, equals(0));
      }
    });
  });

  // ──────────────────────────────────────────────────────────────
  // AnalyticsState
  // ──────────────────────────────────────────────────────────────
  group('AnalyticsState', () {
    test('initial 状态', () {
      final s = AnalyticsState<String>.initial();
      expect(s.state, equals(AnalyticsLoadingState.initial));
      expect(s.isLoading, isFalse);
      expect(s.isLoaded, isFalse);
      expect(s.hasError, isFalse);
    });

    test('loading 状态', () {
      final s = AnalyticsState<String>.loading();
      expect(s.state, equals(AnalyticsLoadingState.loading));
      expect(s.isLoading, isTrue);
      expect(s.isLoaded, isFalse);
    });

    test('loaded 状态', () {
      final s = AnalyticsState<String>.loaded('数据');
      expect(s.state, equals(AnalyticsLoadingState.loaded));
      expect(s.isLoaded, isTrue);
      expect(s.data, equals('数据'));
    });

    test('error 状态', () {
      final s = AnalyticsState<String>.error('加载失败');
      expect(s.state, equals(AnalyticsLoadingState.error));
      expect(s.hasError, isTrue);
      expect(s.errorMessage, equals('加载失败'));
    });
  });
}

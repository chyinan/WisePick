/// 数据分析模块 - 数据模型定义
/// 
/// 基于 PRD v2.0 和 frontend-architecture.md 设计

/// 消费结构分析数据
class ConsumptionStructure {
  /// 品类分布
  final List<CategoryDistribution> categoryDistribution;
  
  /// 价格区间分布
  final List<PriceRangeDistribution> priceRangeDistribution;
  
  /// 平台偏好分布
  final List<PlatformPreference> platformPreference;
  
  /// 总消费金额
  final double totalAmount;
  
  /// 商品总数
  final int totalProducts;
  
  /// 分析时间范围
  final AnalyticsDateRange timeRange;

  const ConsumptionStructure({
    required this.categoryDistribution,
    required this.priceRangeDistribution,
    required this.platformPreference,
    required this.totalAmount,
    required this.totalProducts,
    required this.timeRange,
  });

  factory ConsumptionStructure.empty() => ConsumptionStructure(
    categoryDistribution: [],
    priceRangeDistribution: [],
    platformPreference: [],
    totalAmount: 0,
    totalProducts: 0,
    timeRange: AnalyticsDateRange(
      start: DateTime.now().subtract(const Duration(days: 30)),
      end: DateTime.now(),
    ),
  );
}

/// 品类分布数据
class CategoryDistribution {
  final String category;
  final int count;
  final double amount;
  final double percentage;

  const CategoryDistribution({
    required this.category,
    required this.count,
    required this.amount,
    required this.percentage,
  });
}

/// 价格区间分布数据
class PriceRangeDistribution {
  final String range; // e.g., "0-50", "50-100", "100-500"
  final double minPrice;
  final double maxPrice;
  final int count;
  final double percentage;

  const PriceRangeDistribution({
    required this.range,
    required this.minPrice,
    required this.maxPrice,
    required this.count,
    required this.percentage,
  });
}

/// 平台偏好数据
class PlatformPreference {
  final String platform; // 'taobao', 'jd', 'pdd'
  final int count;
  final double amount;
  final double percentage;

  const PlatformPreference({
    required this.platform,
    required this.count,
    required this.amount,
    required this.percentage,
  });

  /// 获取平台显示名称
  String get displayName {
    switch (platform) {
      case 'taobao':
        return '淘宝';
      case 'jd':
        return '京东';
      case 'pdd':
        return '拼多多';
      default:
        return platform;
    }
  }
}

/// 用户偏好分析数据
class UserPreferences {
  /// 偏好品类列表
  final List<String> preferredCategories;
  
  /// 价格偏好区间
  final PricePreference pricePreference;
  
  /// 平台偏好排序
  final List<String> platformRanking;
  
  /// 购物频率描述
  final String shoppingFrequency;
  
  /// 用户购物画像标签
  final List<String> userTags;

  const UserPreferences({
    required this.preferredCategories,
    required this.pricePreference,
    required this.platformRanking,
    required this.shoppingFrequency,
    required this.userTags,
  });

  factory UserPreferences.empty() => const UserPreferences(
    preferredCategories: [],
    pricePreference: PricePreference(
      minPrice: 0,
      maxPrice: 0,
      averagePrice: 0,
      description: '暂无数据',
    ),
    platformRanking: [],
    shoppingFrequency: '暂无数据',
    userTags: [],
  );
}

/// 价格偏好数据
class PricePreference {
  final double minPrice;
  final double maxPrice;
  final double averagePrice;
  final String description; // e.g., "偏好中等价位商品"

  const PricePreference({
    required this.minPrice,
    required this.maxPrice,
    required this.averagePrice,
    required this.description,
  });
}

/// 购物时间分析数据
class ShoppingTimeAnalysis {
  /// 24小时分布（0-23小时，每小时的对话/购物次数）
  final List<HourlyDistribution> hourlyDistribution;
  
  /// 星期分布（周一到周日）
  final List<WeekdayDistribution> weekdayDistribution;
  
  /// 热力图数据（7天 x 24小时）
  final List<List<int>> heatmapData;
  
  /// 最活跃时段
  final String peakHours;
  
  /// 最活跃日期
  final String peakDays;

  const ShoppingTimeAnalysis({
    required this.hourlyDistribution,
    required this.weekdayDistribution,
    required this.heatmapData,
    required this.peakHours,
    required this.peakDays,
  });

  factory ShoppingTimeAnalysis.empty() => ShoppingTimeAnalysis(
    hourlyDistribution: List.generate(24, (i) => HourlyDistribution(hour: i, count: 0)),
    weekdayDistribution: List.generate(7, (i) => WeekdayDistribution(weekday: i, count: 0)),
    heatmapData: List.generate(7, (_) => List.generate(24, (_) => 0)),
    peakHours: '暂无数据',
    peakDays: '暂无数据',
  );
}

/// 小时分布数据
class HourlyDistribution {
  final int hour; // 0-23
  final int count;

  const HourlyDistribution({
    required this.hour,
    required this.count,
  });

  String get displayHour => '${hour.toString().padLeft(2, '0')}:00';
}

/// 星期分布数据
class WeekdayDistribution {
  final int weekday; // 0=周一, 6=周日
  final int count;

  const WeekdayDistribution({
    required this.weekday,
    required this.count,
  });

  String get displayName {
    const names = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return names[weekday];
  }
}

/// 购物报告数据
class ShoppingReport {
  final DateTime generatedAt;
  final AnalyticsDateRange timeRange;
  final ConsumptionStructure consumptionStructure;
  final UserPreferences userPreferences;
  final ShoppingTimeAnalysis shoppingTimeAnalysis;
  final ReportSummary summary;

  const ShoppingReport({
    required this.generatedAt,
    required this.timeRange,
    required this.consumptionStructure,
    required this.userPreferences,
    required this.shoppingTimeAnalysis,
    required this.summary,
  });
}

/// 报告摘要
class ReportSummary {
  final String title; // e.g., "2026年1月购物报告"
  final String totalSpending; // 格式化的消费金额
  final String topCategory; // 最常购买的品类
  final String favoritesPlatform; // 最常使用的平台
  final String shoppingStyle; // 购物风格描述
  final List<String> insights; // 洞察要点

  const ReportSummary({
    required this.title,
    required this.totalSpending,
    required this.topCategory,
    required this.favoritesPlatform,
    required this.shoppingStyle,
    required this.insights,
  });
}

/// 分析时间范围
class AnalyticsDateRange {
  final DateTime start;
  final DateTime end;

  const AnalyticsDateRange({
    required this.start,
    required this.end,
  });

  /// 获取时间范围描述
  String get description {
    final days = end.difference(start).inDays;
    if (days <= 7) return '近一周';
    if (days <= 30) return '近一个月';
    if (days <= 90) return '近三个月';
    if (days <= 365) return '近一年';
    return '全部时间';
  }

  /// 预设时间范围
  static AnalyticsDateRange lastWeek() => AnalyticsDateRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );

  static AnalyticsDateRange lastMonth() => AnalyticsDateRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );

  static AnalyticsDateRange lastThreeMonths() => AnalyticsDateRange(
    start: DateTime.now().subtract(const Duration(days: 90)),
    end: DateTime.now(),
  );

  static AnalyticsDateRange lastYear() => AnalyticsDateRange(
    start: DateTime.now().subtract(const Duration(days: 365)),
    end: DateTime.now(),
  );
}

/// 分析数据加载状态
enum AnalyticsLoadingState {
  initial,
  loading,
  loaded,
  error,
}

/// 分析数据状态包装
class AnalyticsState<T> {
  final AnalyticsLoadingState state;
  final T? data;
  final String? errorMessage;

  const AnalyticsState({
    required this.state,
    this.data,
    this.errorMessage,
  });

  factory AnalyticsState.initial() => const AnalyticsState(
    state: AnalyticsLoadingState.initial,
  );

  factory AnalyticsState.loading() => const AnalyticsState(
    state: AnalyticsLoadingState.loading,
  );

  factory AnalyticsState.loaded(T data) => AnalyticsState(
    state: AnalyticsLoadingState.loaded,
    data: data,
  );

  factory AnalyticsState.error(String message) => AnalyticsState(
    state: AnalyticsLoadingState.error,
    errorMessage: message,
  );

  bool get isLoading => state == AnalyticsLoadingState.loading;
  bool get isLoaded => state == AnalyticsLoadingState.loaded;
  bool get hasError => state == AnalyticsLoadingState.error;
}

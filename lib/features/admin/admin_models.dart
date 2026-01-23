/// 管理员后台模块 - 数据模型定义
/// 
/// 基于 PRD v2.0 设计，包含用户统计、系统监控、搜索热词统计等

/// 用户统计数据
class UserStatistics {
  /// 总用户数
  final int totalUsers;
  
  /// 活跃用户数
  final ActiveUserStats activeUsers;
  
  /// 用户留存率
  final RetentionStats retentionRate;
  
  /// 新增用户趋势
  final List<DailyCount> newUserTrend;
  
  /// 统计时间范围
  final DateTime startDate;
  final DateTime endDate;

  const UserStatistics({
    required this.totalUsers,
    required this.activeUsers,
    required this.retentionRate,
    required this.newUserTrend,
    required this.startDate,
    required this.endDate,
  });

  factory UserStatistics.empty() => UserStatistics(
    totalUsers: 0,
    activeUsers: ActiveUserStats.empty(),
    retentionRate: RetentionStats.empty(),
    newUserTrend: [],
    startDate: DateTime.now(),
    endDate: DateTime.now(),
  );
}

/// 活跃用户统计
class ActiveUserStats {
  final int daily;
  final int weekly;
  final int monthly;

  const ActiveUserStats({
    required this.daily,
    required this.weekly,
    required this.monthly,
  });

  factory ActiveUserStats.empty() => const ActiveUserStats(
    daily: 0,
    weekly: 0,
    monthly: 0,
  );
}

/// 留存率统计
class RetentionStats {
  final double day1;
  final double day7;
  final double day30;

  const RetentionStats({
    required this.day1,
    required this.day7,
    required this.day30,
  });

  factory RetentionStats.empty() => const RetentionStats(
    day1: 0,
    day7: 0,
    day30: 0,
  );
}

/// 每日计数
class DailyCount {
  final DateTime date;
  final int count;

  const DailyCount({
    required this.date,
    required this.count,
  });
}

/// 系统统计数据
class SystemStatistics {
  /// API调用统计
  final ApiCallStats apiCalls;
  
  /// 搜索统计
  final SearchStats searchStats;
  
  /// 错误统计
  final ErrorStats errorStats;
  
  /// 响应时间分布
  final List<ResponseTimeDistribution> responseTimeDistribution;
  
  /// 统计时间范围
  final DateTime startDate;
  final DateTime endDate;

  const SystemStatistics({
    required this.apiCalls,
    required this.searchStats,
    required this.errorStats,
    required this.responseTimeDistribution,
    required this.startDate,
    required this.endDate,
  });

  factory SystemStatistics.empty() => SystemStatistics(
    apiCalls: ApiCallStats.empty(),
    searchStats: SearchStats.empty(),
    errorStats: ErrorStats.empty(),
    responseTimeDistribution: [],
    startDate: DateTime.now(),
    endDate: DateTime.now(),
  );
}

/// API调用统计
class ApiCallStats {
  final int total;
  final int success;
  final int failed;
  final double avgResponseTime;

  const ApiCallStats({
    required this.total,
    required this.success,
    required this.failed,
    required this.avgResponseTime,
  });

  factory ApiCallStats.empty() => const ApiCallStats(
    total: 0,
    success: 0,
    failed: 0,
    avgResponseTime: 0,
  );

  double get successRate => total > 0 ? success / total : 0;
}

/// 搜索统计
class SearchStats {
  final int totalSearches;
  final int successfulSearches;
  final double successRate;
  final List<KeywordCount> topKeywords;

  const SearchStats({
    required this.totalSearches,
    required this.successfulSearches,
    required this.successRate,
    required this.topKeywords,
  });

  factory SearchStats.empty() => const SearchStats(
    totalSearches: 0,
    successfulSearches: 0,
    successRate: 0,
    topKeywords: [],
  );
}

/// 关键词计数
class KeywordCount {
  final String keyword;
  final int count;
  final double percentage;

  const KeywordCount({
    required this.keyword,
    required this.count,
    this.percentage = 0,
  });
}

/// 错误统计
class ErrorStats {
  final int totalErrors;
  final List<ErrorTypeCount> errorTypes;
  final double errorRate;

  const ErrorStats({
    required this.totalErrors,
    required this.errorTypes,
    required this.errorRate,
  });

  factory ErrorStats.empty() => const ErrorStats(
    totalErrors: 0,
    errorTypes: [],
    errorRate: 0,
  );
}

/// 错误类型计数
class ErrorTypeCount {
  final String type;
  final int count;
  final String description;

  const ErrorTypeCount({
    required this.type,
    required this.count,
    required this.description,
  });
}

/// 响应时间分布
class ResponseTimeDistribution {
  final String range;
  final int count;
  final double percentage;

  const ResponseTimeDistribution({
    required this.range,
    required this.count,
    required this.percentage,
  });
}

/// 搜索热词数据
class SearchKeywordStats {
  final List<KeywordCount> topKeywords;
  final List<DailyKeywordTrend> trends;
  final List<KeywordCount> failedKeywords;
  final DateTime startDate;
  final DateTime endDate;

  const SearchKeywordStats({
    required this.topKeywords,
    required this.trends,
    required this.failedKeywords,
    required this.startDate,
    required this.endDate,
  });

  factory SearchKeywordStats.empty() => SearchKeywordStats(
    topKeywords: [],
    trends: [],
    failedKeywords: [],
    startDate: DateTime.now(),
    endDate: DateTime.now(),
  );
}

/// 每日关键词趋势
class DailyKeywordTrend {
  final DateTime date;
  final int searchCount;
  final List<KeywordCount> topKeywords;

  const DailyKeywordTrend({
    required this.date,
    required this.searchCount,
    required this.topKeywords,
  });
}

/// 统计时间范围选项
enum AdminStatsTimeRange {
  today,
  yesterday,
  lastWeek,
  lastMonth,
  lastThreeMonths,
}

extension AdminStatsTimeRangeExtension on AdminStatsTimeRange {
  String get displayName {
    switch (this) {
      case AdminStatsTimeRange.today:
        return '今天';
      case AdminStatsTimeRange.yesterday:
        return '昨天';
      case AdminStatsTimeRange.lastWeek:
        return '近7天';
      case AdminStatsTimeRange.lastMonth:
        return '近30天';
      case AdminStatsTimeRange.lastThreeMonths:
        return '近90天';
    }
  }

  DateTime get startDate {
    final now = DateTime.now();
    switch (this) {
      case AdminStatsTimeRange.today:
        return DateTime(now.year, now.month, now.day);
      case AdminStatsTimeRange.yesterday:
        return DateTime(now.year, now.month, now.day - 1);
      case AdminStatsTimeRange.lastWeek:
        return now.subtract(const Duration(days: 7));
      case AdminStatsTimeRange.lastMonth:
        return now.subtract(const Duration(days: 30));
      case AdminStatsTimeRange.lastThreeMonths:
        return now.subtract(const Duration(days: 90));
    }
  }

  DateTime get endDate {
    final now = DateTime.now();
    if (this == AdminStatsTimeRange.yesterday) {
      return DateTime(now.year, now.month, now.day - 1, 23, 59, 59);
    }
    return now;
  }
}

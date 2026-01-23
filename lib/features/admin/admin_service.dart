import 'dart:math';
import 'admin_models.dart';

/// 管理员后台服务
/// 
/// 提供用户统计、系统监控、搜索热词统计等功能
/// 当前使用Mock数据，后续可接入后端API
class AdminService {
  // 单例模式
  static final AdminService _instance = AdminService._internal();
  factory AdminService() => _instance;
  AdminService._internal();

  /// 获取用户统计数据
  Future<UserStatistics> getUserStatistics({
    AdminStatsTimeRange timeRange = AdminStatsTimeRange.lastWeek,
  }) async {
    await Future.delayed(const Duration(milliseconds: 800));
    
    final random = Random();
    final days = timeRange == AdminStatsTimeRange.today ? 1 
        : timeRange == AdminStatsTimeRange.yesterday ? 1
        : timeRange == AdminStatsTimeRange.lastWeek ? 7
        : timeRange == AdminStatsTimeRange.lastMonth ? 30
        : 90;

    // 生成新增用户趋势
    final newUserTrend = <DailyCount>[];
    for (int i = days - 1; i >= 0; i--) {
      newUserTrend.add(DailyCount(
        date: DateTime.now().subtract(Duration(days: i)),
        count: 50 + random.nextInt(150),
      ));
    }

    return UserStatistics(
      totalUsers: 15000 + random.nextInt(5000),
      activeUsers: ActiveUserStats(
        daily: 800 + random.nextInt(400),
        weekly: 3500 + random.nextInt(1500),
        monthly: 8000 + random.nextInt(4000),
      ),
      retentionRate: RetentionStats(
        day1: 0.35 + random.nextDouble() * 0.2,
        day7: 0.25 + random.nextDouble() * 0.15,
        day30: 0.15 + random.nextDouble() * 0.1,
      ),
      newUserTrend: newUserTrend,
      startDate: timeRange.startDate,
      endDate: timeRange.endDate,
    );
  }

  /// 获取系统统计数据
  Future<SystemStatistics> getSystemStatistics({
    AdminStatsTimeRange timeRange = AdminStatsTimeRange.lastWeek,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));
    
    final random = Random();
    final totalCalls = 50000 + random.nextInt(30000);
    final successCalls = (totalCalls * (0.92 + random.nextDouble() * 0.06)).toInt();

    // 生成热门关键词
    final keywords = ['手机', '耳机', '笔记本电脑', '平板', '充电器', '键盘', '鼠标', '显示器', '路由器', '音响'];
    final topKeywords = keywords.take(10).map((k) => KeywordCount(
      keyword: k,
      count: 1000 + random.nextInt(5000),
    )).toList()..sort((a, b) => b.count.compareTo(a.count));

    // 计算百分比
    final totalKeywordCount = topKeywords.fold<int>(0, (sum, k) => sum + k.count);
    final keywordsWithPercentage = topKeywords.map((k) => KeywordCount(
      keyword: k.keyword,
      count: k.count,
      percentage: k.count / totalKeywordCount * 100,
    )).toList();

    // 错误类型
    final errorTypes = [
      ErrorTypeCount(type: 'NetworkError', count: 120 + random.nextInt(100), description: '网络连接错误'),
      ErrorTypeCount(type: 'APIError', count: 80 + random.nextInt(60), description: 'API调用错误'),
      ErrorTypeCount(type: 'TimeoutError', count: 50 + random.nextInt(40), description: '请求超时'),
      ErrorTypeCount(type: 'ParseError', count: 30 + random.nextInt(20), description: '数据解析错误'),
    ];

    // 响应时间分布
    final responseDistribution = [
      ResponseTimeDistribution(range: '<100ms', count: 15000, percentage: 30),
      ResponseTimeDistribution(range: '100-500ms', count: 25000, percentage: 50),
      ResponseTimeDistribution(range: '500-1000ms', count: 7500, percentage: 15),
      ResponseTimeDistribution(range: '>1000ms', count: 2500, percentage: 5),
    ];

    return SystemStatistics(
      apiCalls: ApiCallStats(
        total: totalCalls,
        success: successCalls,
        failed: totalCalls - successCalls,
        avgResponseTime: 200 + random.nextDouble() * 150,
      ),
      searchStats: SearchStats(
        totalSearches: 30000 + random.nextInt(20000),
        successfulSearches: 28000 + random.nextInt(18000),
        successRate: 0.9 + random.nextDouble() * 0.08,
        topKeywords: keywordsWithPercentage,
      ),
      errorStats: ErrorStats(
        totalErrors: errorTypes.fold<int>(0, (sum, e) => sum + e.count),
        errorTypes: errorTypes,
        errorRate: (totalCalls - successCalls) / totalCalls,
      ),
      responseTimeDistribution: responseDistribution,
      startDate: timeRange.startDate,
      endDate: timeRange.endDate,
    );
  }

  /// 获取搜索热词统计
  Future<SearchKeywordStats> getSearchKeywordStats({
    AdminStatsTimeRange timeRange = AdminStatsTimeRange.lastWeek,
    int limit = 20,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    
    final random = Random();
    
    // 热门关键词
    final keywords = [
      '手机', '耳机', '笔记本电脑', '平板电脑', '充电器', 
      '蓝牙键盘', '无线鼠标', '4K显示器', 'WiFi路由器', '智能音响',
      '机械键盘', '游戏耳机', '移动电源', '手机壳', '数据线',
      '智能手表', '运动手环', '蓝牙音箱', '投影仪', '摄像头',
    ];

    final topKeywords = keywords.take(limit).map((k) => KeywordCount(
      keyword: k,
      count: 500 + random.nextInt(5000),
    )).toList()..sort((a, b) => b.count.compareTo(a.count));

    // 每日趋势
    final days = timeRange == AdminStatsTimeRange.lastWeek ? 7
        : timeRange == AdminStatsTimeRange.lastMonth ? 30
        : 7;
    
    final trends = <DailyKeywordTrend>[];
    for (int i = days - 1; i >= 0; i--) {
      final dailyKeywords = keywords.take(5).map((k) => KeywordCount(
        keyword: k,
        count: 100 + random.nextInt(500),
      )).toList();

      trends.add(DailyKeywordTrend(
        date: DateTime.now().subtract(Duration(days: i)),
        searchCount: 3000 + random.nextInt(2000),
        topKeywords: dailyKeywords,
      ));
    }

    // 搜索失败的关键词
    final failedKeywords = [
      KeywordCount(keyword: '特殊商品A', count: 50 + random.nextInt(50)),
      KeywordCount(keyword: '未知品牌B', count: 30 + random.nextInt(30)),
      KeywordCount(keyword: '错误拼写C', count: 20 + random.nextInt(20)),
    ];

    return SearchKeywordStats(
      topKeywords: topKeywords,
      trends: trends,
      failedKeywords: failedKeywords,
      startDate: timeRange.startDate,
      endDate: timeRange.endDate,
    );
  }

  /// 导出统计数据
  Future<String> exportData({
    required String dataType,
    required AdminStatsTimeRange timeRange,
    required String format,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    
    // 模拟导出，返回文件路径
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '/exports/${dataType}_${timeRange.name}_$timestamp.$format';
  }
}

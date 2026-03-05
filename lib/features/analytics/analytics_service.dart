import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/api_client.dart';
import '../../core/backend_config.dart';
import 'analytics_models.dart';

/// 数据分析服务
///
/// 负责消费结构分析、用户偏好分析、购物时间分析等业务逻辑
/// 调用后端 /api/v1/analytics/* 接口获取真实数据
class AnalyticsService {
  // 单例模式
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  final ApiClient _apiClient = ApiClient();

  /// 动态解析后端基础 URL
  String get _baseUrl => '${BackendConfig.resolveSync()}/api/v1/analytics';

  /// 获取消费结构分析数据
  ///
  /// [timeRange] 分析的时间范围
  Future<ConsumptionStructure> getConsumptionStructure({
    AnalyticsDateRange? timeRange,
  }) async {
    final range = timeRange ?? AnalyticsDateRange.lastMonth();
    try {
      final response = await _apiClient.get('$_baseUrl/consumption-structure');
      if (response.statusCode == 200) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data as Map<String, dynamic>;

        final totalAmount =
            (data['totalAmount'] as num?)?.toDouble() ?? 0.0;
        final totalProducts =
            (data['totalProducts'] as num?)?.toInt() ?? 0;

        // 解析品类分布
        final categoryList = data['categoryDistribution'] as List? ?? [];
        final categoryDistribution = categoryList.map((item) {
          final m = item as Map<String, dynamic>;
          return CategoryDistribution(
            category: _translateCategory(m['category'] as String? ?? 'Other'),
            count: (m['count'] as num?)?.toInt() ?? 0,
            amount: (m['amount'] as num?)?.toDouble() ?? 0.0,
            percentage: (m['percentage'] as num?)?.toDouble() ?? 0.0,
          );
        }).toList();

        // 解析平台偏好
        final platformList = data['platformPreference'] as List? ?? [];
        final platformPreference = platformList.map((item) {
          final m = item as Map<String, dynamic>;
          return PlatformPreference(
            platform: m['platform'] as String? ?? 'unknown',
            count: (m['count'] as num?)?.toInt() ?? 0,
            amount: (m['amount'] as num?)?.toDouble() ?? 0.0,
            percentage: (m['percentage'] as num?)?.toDouble() ?? 0.0,
          );
        }).toList();

        // 解析后端返回的价格区间分布
        final priceRangeList = data['priceRangeDistribution'] as List? ?? [];
        final priceRangeDistribution = priceRangeList.map((item) {
          final m = item as Map<String, dynamic>;
          return PriceRangeDistribution(
            range: m['range'] as String? ?? '',
            minPrice: (m['minPrice'] as num?)?.toDouble() ?? 0.0,
            maxPrice: (m['maxPrice'] as num?)?.toDouble() ?? 0.0,
            count: (m['count'] as num?)?.toInt() ?? 0,
            percentage: (m['percentage'] as num?)?.toDouble() ?? 0.0,
          );
        }).toList();

        return ConsumptionStructure(
          categoryDistribution: categoryDistribution,
          priceRangeDistribution: priceRangeDistribution,
          platformPreference: platformPreference,
          totalAmount: totalAmount,
          totalProducts: totalProducts,
          timeRange: range,
        );
      }
    } catch (e) {
      dev.log('Error fetching consumption structure: $e', name: 'AnalyticsService');
    }

    return ConsumptionStructure.empty();
  }

  /// 获取用户偏好分析数据
  Future<UserPreferences> getUserPreferences() async {
    try {
      final response = await _apiClient.get('$_baseUrl/preferences');
      if (response.statusCode == 200) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data as Map<String, dynamic>;

        final preferredCategories = (data['preferredCategories'] as List?)
                ?.map((e) => _translateCategory(e as String))
                .toList() ??
            [];

        // 后端字段名为 pricePreference
        final pricePref =
            data['pricePreference'] as Map<String, dynamic>? ?? {};
        final minPrice =
            (pricePref['minPrice'] as num?)?.toDouble() ?? 0.0;
        final maxPrice =
            (pricePref['maxPrice'] as num?)?.toDouble() ?? 0.0;
        final avgPrice =
            (pricePref['averagePrice'] as num?)?.toDouble() ?? 0.0;

        final platformRanking = (data['platformRanking'] as List?)
                ?.map((e) => e as String)
                .toList() ??
            [];

        // 后端已返回 shoppingFrequency 和 userTags
        final backendFrequency = data['shoppingFrequency'] as String?;
        final backendTags = (data['userTags'] as List?)
                ?.map((e) => e as String)
                .toList();

        // 根据价格范围确定描述
        String priceDesc;
        if (avgPrice < 50) {
          priceDesc = '偏好低价位商品';
        } else if (avgPrice < 200) {
          priceDesc = '偏好中低价位商品';
        } else if (avgPrice < 500) {
          priceDesc = '偏好中等价位商品';
        } else if (avgPrice < 1000) {
          priceDesc = '偏好中高价位商品';
        } else {
          priceDesc = '偏好高价位商品';
        }

        // 根据偏好生成用户标签
        final userTags = <String>[];
        if (preferredCategories.contains('数码电子')) userTags.add('数码控');
        if (preferredCategories.contains('美妆护肤')) userTags.add('颜值党');
        if (avgPrice < 200) userTags.add('性价比优先');
        if (avgPrice >= 200 && avgPrice < 500) userTags.add('理性消费');
        if (avgPrice >= 500) userTags.add('品质优先');
        if (userTags.isEmpty) userTags.add('综合消费');

        return UserPreferences(
          preferredCategories: preferredCategories,
          pricePreference: PricePreference(
            minPrice: minPrice,
            maxPrice: maxPrice,
            averagePrice: avgPrice,
            description: pricePref['description'] as String? ?? priceDesc,
          ),
          platformRanking: platformRanking,
          shoppingFrequency: backendFrequency ?? '基于购物车数据分析',
          userTags: backendTags ?? userTags,
        );
      }
    } catch (e) {
      dev.log('Error fetching user preferences: $e', name: 'AnalyticsService');
    }

    return UserPreferences.empty();
  }

  /// 获取购物时间分析数据
  Future<ShoppingTimeAnalysis> getShoppingTimeAnalysis({
    AnalyticsDateRange? timeRange,
  }) async {
    try {
      final response = await _apiClient.get('$_baseUrl/shopping-time');
      if (response.statusCode == 200) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data as Map<String, dynamic>;

        // 解析小时分布
        final hourlyList = data['hourlyDistribution'] as List? ?? [];
        final hourlyDistribution = List.generate(24, (hour) {
          final item = hourlyList.firstWhere(
            (e) => (e as Map<String, dynamic>)['hour'] == hour,
            orElse: () => {'hour': hour, 'count': 0},
          ) as Map<String, dynamic>;
          return HourlyDistribution(
            hour: hour,
            count: (item['count'] as num?)?.toInt() ?? 0,
          );
        });

        // 解析星期分布
        final weekdayList = data['weekdayDistribution'] as List? ?? [];
        final weekdayDistribution = List.generate(7, (day) {
          final item = weekdayList.firstWhere(
            (e) => (e as Map<String, dynamic>)['weekday'] == day,
            orElse: () => {'weekday': day, 'count': 0},
          ) as Map<String, dynamic>;
          return WeekdayDistribution(
            weekday: day,
            count: (item['count'] as num?)?.toInt() ?? 0,
          );
        });

        // 生成热力图数据 (7天 x 24小时)
        // 基于hourly和weekday分布交叉估算
        final heatmapData = List.generate(7, (day) {
          final dayCount = weekdayDistribution[day].count;
          return List.generate(24, (hour) {
            final hourCount = hourlyDistribution[hour].count;
            final totalHours = hourlyDistribution.fold(0, (s, h) => s + h.count);
            if (totalHours == 0) return 0;
            return (dayCount * hourCount / totalHours).round();
          });
        });

        // 计算高峰时段
        final sortedHours = List.of(hourlyDistribution)
          ..sort((a, b) => b.count.compareTo(a.count));
        final peakHours = sortedHours.take(3).map((h) => '${h.hour}:00').join('、');

        final sortedDays = List.of(weekdayDistribution)
          ..sort((a, b) => b.count.compareTo(a.count));
        final peakDays = sortedDays.take(2).map((d) => d.displayName).join('、');

        return ShoppingTimeAnalysis(
          hourlyDistribution: hourlyDistribution,
          weekdayDistribution: weekdayDistribution,
          heatmapData: heatmapData,
          peakHours: peakHours.isNotEmpty ? peakHours : '暂无数据',
          peakDays: peakDays.isNotEmpty ? peakDays : '暂无数据',
        );
      }
    } catch (e) {
      dev.log('Error fetching shopping time analysis: $e', name: 'AnalyticsService');
    }

    return ShoppingTimeAnalysis.empty();
  }

  /// 生成购物报告
  ///
  /// [timeRange] 报告的时间范围
  /// 返回完整的购物报告数据，可用于PDF导出
  Future<ShoppingReport> generateReport({
    required AnalyticsDateRange timeRange,
  }) async {
    // 并行获取所有分析数据
    final results = await Future.wait([
      getConsumptionStructure(timeRange: timeRange),
      getUserPreferences(),
      getShoppingTimeAnalysis(timeRange: timeRange),
    ]);

    final consumption = results[0] as ConsumptionStructure;
    final preferences = results[1] as UserPreferences;
    final timeAnalysis = results[2] as ShoppingTimeAnalysis;

    // 生成报告摘要
    final summary = _generateReportSummary(
      timeRange: timeRange,
      consumption: consumption,
      preferences: preferences,
    );

    return ShoppingReport(
      generatedAt: DateTime.now(),
      timeRange: timeRange,
      consumptionStructure: consumption,
      userPreferences: preferences,
      shoppingTimeAnalysis: timeAnalysis,
      summary: summary,
    );
  }

  /// 导出报告为PDF
  ///
  /// 使用 pdf 包生成真实 PDF 文件并保存到应用文档目录
  /// 返回生成的 PDF 文件路径
  Future<String> exportReportToPdf(ShoppingReport report) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              report.summary.title,
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            '生成时间: ${report.generatedAt.toLocal().toString().substring(0, 19)}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 16),

          // 报告摘要
          pw.Header(level: 1, text: '报告摘要'),
          pw.Bullet(text: '总消费: ${report.summary.totalSpending}'),
          pw.Bullet(text: '最常购买品类: ${report.summary.topCategory}'),
          pw.Bullet(text: '最常用平台: ${report.summary.favoritesPlatform}'),
          pw.Bullet(text: '购物风格: ${report.summary.shoppingStyle}'),
          pw.SizedBox(height: 8),
          ...report.summary.insights.map((i) => pw.Bullet(text: i)),
          pw.SizedBox(height: 16),

          // 消费结构
          pw.Header(level: 1, text: '消费结构'),
          pw.Text('商品总数: ${report.consumptionStructure.totalProducts}'),
          pw.Text('消费总额: ¥${report.consumptionStructure.totalAmount.toStringAsFixed(2)}'),
          pw.SizedBox(height: 8),
          if (report.consumptionStructure.categoryDistribution.isNotEmpty) ...[
            pw.Text('品类分布:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.TableHelper.fromTextArray(
              headers: ['品类', '数量', '金额', '占比'],
              data: report.consumptionStructure.categoryDistribution.map((c) => [
                c.category,
                c.count.toString(),
                '¥${c.amount.toStringAsFixed(2)}',
                '${c.percentage.toStringAsFixed(1)}%',
              ]).toList(),
            ),
            pw.SizedBox(height: 8),
          ],
          if (report.consumptionStructure.priceRangeDistribution.isNotEmpty) ...[
            pw.Text('价格区间分布:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.TableHelper.fromTextArray(
              headers: ['价格区间', '数量', '占比'],
              data: report.consumptionStructure.priceRangeDistribution.map((p) => [
                p.range,
                p.count.toString(),
                '${p.percentage.toStringAsFixed(1)}%',
              ]).toList(),
            ),
            pw.SizedBox(height: 8),
          ],
          if (report.consumptionStructure.platformPreference.isNotEmpty) ...[
            pw.Text('平台分布:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.TableHelper.fromTextArray(
              headers: ['平台', '数量', '金额', '占比'],
              data: report.consumptionStructure.platformPreference.map((p) => [
                p.displayName,
                p.count.toString(),
                '¥${p.amount.toStringAsFixed(2)}',
                '${p.percentage.toStringAsFixed(1)}%',
              ]).toList(),
            ),
            pw.SizedBox(height: 16),
          ],

          // 用户偏好
          pw.Header(level: 1, text: '用户偏好'),
          pw.Text('偏好品类: ${report.userPreferences.preferredCategories.join("、")}'),
          pw.Text('价格偏好: ${report.userPreferences.pricePreference.description}'),
          pw.Text('平均消费: ¥${report.userPreferences.pricePreference.averagePrice.toStringAsFixed(2)}'),
          pw.Text('购物频率: ${report.userPreferences.shoppingFrequency}'),
          pw.Text('用户标签: ${report.userPreferences.userTags.join("、")}'),
          pw.SizedBox(height: 16),

          // 购物时间分析
          pw.Header(level: 1, text: '购物时间分析'),
          pw.Text('高峰时段: ${report.shoppingTimeAnalysis.peakHours}'),
          pw.Text('高峰日期: ${report.shoppingTimeAnalysis.peakDays}'),
        ],
      ),
    );

    // 保存 PDF 文件到应用文档目录
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = '${dir.path}/shopping_report_$timestamp.pdf';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());

    return filePath;
  }

  // ========== 辅助方法 ==========

  /// 将英文品类名翻译为中文
  String _translateCategory(String category) {
    switch (category) {
      case 'Electronics':
        return '数码电子';
      case 'Clothing':
        return '服装鞋包';
      case 'Home':
        return '家居日用';
      case 'Other':
        return '其他';
      default:
        return category;
    }
  }

  /// 将平台标识翻译为中文
  String _translatePlatform(String platform) {
    switch (platform.toLowerCase()) {
      case 'jd':
        return '京东';
      case 'taobao':
        return '淘宝';
      case 'pdd':
        return '拼多多';
      default:
        return platform;
    }
  }

  ReportSummary _generateReportSummary({
    required AnalyticsDateRange timeRange,
    required ConsumptionStructure consumption,
    required UserPreferences preferences,
  }) {
    final now = DateTime.now();
    final title = '${now.year}年${now.month}月购物报告';

    // 获取消费最多的品类
    String topCategory = '暂无';
    if (consumption.categoryDistribution.isNotEmpty) {
      final sorted = List.of(consumption.categoryDistribution)
        ..sort((a, b) => b.amount.compareTo(a.amount));
      topCategory = sorted.first.category;
    }

    // 获取最常用的平台
    String favoritePlatform = '暂无';
    if (consumption.platformPreference.isNotEmpty) {
      final sorted = List.of(consumption.platformPreference)
        ..sort((a, b) => b.count.compareTo(a.count));
      favoritePlatform = sorted.first.displayName;
    }

    return ReportSummary(
      title: title,
      totalSpending: '¥${consumption.totalAmount.toStringAsFixed(2)}',
      topCategory: topCategory,
      favoritesPlatform: favoritePlatform,
      shoppingStyle: _getShoppingStyle(preferences),
      insights: [
        if (topCategory != '暂无') '您在${topCategory}品类消费最多',
        if (favoritePlatform != '暂无') '您最常在${favoritePlatform}平台购物',
        if (preferences.pricePreference.averagePrice > 0)
          '您的平均消费金额为¥${preferences.pricePreference.averagePrice.toStringAsFixed(0)}',
        '建议关注价格波动，把握最佳购买时机',
      ],
    );
  }

  String _getShoppingStyle(UserPreferences preferences) {
    if (preferences.userTags.contains('品质优先')) {
      return '品质型消费者 - 注重商品质量和品牌';
    } else if (preferences.userTags.contains('理性消费')) {
      return '理性型消费者 - 注重性价比和实用性';
    } else if (preferences.userTags.contains('性价比优先')) {
      return '精打细算型 - 追求高性价比';
    } else {
      return '综合型消费者 - 兼顾品质和价格';
    }
  }
}

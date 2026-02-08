import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/database.dart';

/// 后端分析服务 - 基于 cart_items 表的真实数据分析
class AnalyticsService {
  final Database db;

  // CORS headers for all responses
  static const _corsHeaders = {
    'content-type': 'application/json',
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, POST, OPTIONS',
    'access-control-allow-headers':
        'Origin, Content-Type, Accept, Authorization',
  };

  AnalyticsService(this.db);

  Router get router {
    final router = Router();
    router.get('/consumption-structure', _handleConsumptionStructure);
    router.get('/preferences', _handlePreferences);
    router.get('/shopping-time', _handleShoppingTime);
    return router;
  }

  /// 消费结构分析 - 基于 cart_items 表真实数据
  Future<Response> _handleConsumptionStructure(Request request) async {
    try {
      // 解析时间范围参数
      final startDate = request.url.queryParameters['start_date'];
      final endDate = request.url.queryParameters['end_date'];

      var dateFilter = '';
      final params = <String, dynamic>{};
      if (startDate != null && endDate != null) {
        dateFilter =
            ' AND c.created_at >= @startDate AND c.created_at <= @endDate';
        params['startDate'] = DateTime.parse(startDate);
        params['endDate'] = DateTime.parse(endDate);
      }

      // 1. 平台分布 (作为"品类"维度 - 因为 cart_items 没有 category 字段，用 platform 作为主要分组)
      final platformDist = await db.queryAll('''
        SELECT 
          c.platform,
          COUNT(*) as count,
          SUM(COALESCE(c.final_price, c.price) * c.quantity) as amount
        FROM cart_items c
        WHERE c.deleted_at IS NULL $dateFilter
        GROUP BY c.platform
        ORDER BY amount DESC
      ''', parameters: params.isEmpty ? null : params);

      // 计算总金额
      double totalAmount = 0;
      int totalProducts = 0;
      for (final row in platformDist) {
        final amount = _toDouble(row['amount']);
        final count = (row['count'] as int?) ?? 0;
        totalAmount += amount;
        totalProducts += count;
      }

      // 构建品类(平台)分布
      final categoryDistribution = platformDist.map((row) {
        final amount = _toDouble(row['amount']);
        final count = (row['count'] as int?) ?? 0;
        final percentage =
            totalAmount > 0 ? (amount / totalAmount * 100) : 0.0;
        return {
          'category': _platformDisplayName(row['platform'] as String? ?? ''),
          'count': count,
          'amount': double.parse(amount.toStringAsFixed(2)),
          'percentage': double.parse(percentage.toStringAsFixed(1)),
        };
      }).toList();

      // 2. 价格区间分布
      final priceRanges = await db.queryAll('''
        SELECT 
          CASE 
            WHEN COALESCE(c.final_price, c.price) < 50 THEN '0-50'
            WHEN COALESCE(c.final_price, c.price) < 100 THEN '50-100'
            WHEN COALESCE(c.final_price, c.price) < 500 THEN '100-500'
            WHEN COALESCE(c.final_price, c.price) < 1000 THEN '500-1000'
            ELSE '1000+'
          END as price_range,
          COUNT(*) as count
        FROM cart_items c
        WHERE c.deleted_at IS NULL $dateFilter
        GROUP BY price_range
        ORDER BY 
          CASE price_range
            WHEN '0-50' THEN 1
            WHEN '50-100' THEN 2
            WHEN '100-500' THEN 3
            WHEN '500-1000' THEN 4
            ELSE 5
          END
      ''', parameters: params.isEmpty ? null : params);

      final totalForRange = priceRanges.fold<int>(
          0, (sum, r) => sum + ((r['count'] as int?) ?? 0));

      final priceRangeDistribution = priceRanges.map((row) {
        final count = (row['count'] as int?) ?? 0;
        final range = row['price_range'] as String;
        final percentage =
            totalForRange > 0 ? (count / totalForRange * 100) : 0.0;

        double minPrice = 0, maxPrice = 10000;
        switch (range) {
          case '0-50':
            minPrice = 0;
            maxPrice = 50;
            break;
          case '50-100':
            minPrice = 50;
            maxPrice = 100;
            break;
          case '100-500':
            minPrice = 100;
            maxPrice = 500;
            break;
          case '500-1000':
            minPrice = 500;
            maxPrice = 1000;
            break;
          case '1000+':
            minPrice = 1000;
            maxPrice = 10000;
            break;
        }

        return {
          'range': range,
          'minPrice': minPrice,
          'maxPrice': maxPrice,
          'count': count,
          'percentage': double.parse(percentage.toStringAsFixed(1)),
        };
      }).toList();

      // 3. 平台偏好（与品类分布类似但结构不同）
      final platformPreference = platformDist.map((row) {
        final amount = _toDouble(row['amount']);
        final count = (row['count'] as int?) ?? 0;
        final percentage =
            totalAmount > 0 ? (amount / totalAmount * 100) : 0.0;
        return {
          'platform': row['platform'],
          'count': count,
          'amount': double.parse(amount.toStringAsFixed(2)),
          'percentage': double.parse(percentage.toStringAsFixed(1)),
        };
      }).toList();

      final result = {
        'categoryDistribution': categoryDistribution,
        'priceRangeDistribution': priceRangeDistribution,
        'platformPreference': platformPreference,
        'totalAmount': double.parse(totalAmount.toStringAsFixed(2)),
        'totalProducts': totalProducts,
      };

      return Response.ok(jsonEncode(result), headers: _corsHeaders);
    } catch (e) {
      print('[AnalyticsService] Error in consumption-structure: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  /// 用户偏好分析 - 基于 cart_items 表真实数据
  Future<Response> _handlePreferences(Request request) async {
    try {
      // 1. 最常购买的平台排名
      final platformRanking = await db.queryAll('''
        SELECT c.platform, COUNT(*) as count
        FROM cart_items c
        WHERE c.deleted_at IS NULL
        GROUP BY c.platform
        ORDER BY count DESC
      ''');

      // 2. 价格偏好
      final priceStats = await db.queryOne('''
        SELECT 
          MIN(COALESCE(c.final_price, c.price)) as min_price,
          MAX(COALESCE(c.final_price, c.price)) as max_price,
          AVG(COALESCE(c.final_price, c.price)) as avg_price
        FROM cart_items c
        WHERE c.deleted_at IS NULL
          AND COALESCE(c.final_price, c.price) > 0
      ''');

      final minPrice = _toDouble(priceStats?['min_price']);
      final maxPrice = _toDouble(priceStats?['max_price']);
      final avgPrice = _toDouble(priceStats?['avg_price']);

      // 3. 确定价格偏好描述
      String priceDescription;
      if (avgPrice < 100) {
        priceDescription = '偏好经济实惠商品';
      } else if (avgPrice < 300) {
        priceDescription = '偏好中等价位商品';
      } else if (avgPrice < 800) {
        priceDescription = '偏好中高端商品';
      } else {
        priceDescription = '偏好高端品质商品';
      }

      // 4. 购物频率（基于最近30天的购物记录）
      final frequencyResult = await db.queryOne('''
        SELECT COUNT(*) as count
        FROM cart_items c
        WHERE c.deleted_at IS NULL
          AND c.created_at >= CURRENT_DATE - INTERVAL '30 days'
      ''');
      final recentCount = (frequencyResult?['count'] as int?) ?? 0;
      String shoppingFrequency;
      if (recentCount == 0) {
        shoppingFrequency = '近30天无购物记录';
      } else if (recentCount <= 5) {
        shoppingFrequency = '每月约${recentCount}次';
      } else if (recentCount <= 15) {
        shoppingFrequency = '每周约${(recentCount / 4).ceil()}次';
      } else {
        shoppingFrequency = '每周约${(recentCount / 4).ceil()}次，购物活跃';
      }

      // 5. 生成用户标签
      final userTags = <String>[];
      if (avgPrice > 500) userTags.add('品质优先');
      if (avgPrice < 200) userTags.add('性价比优先');
      if (recentCount > 10) userTags.add('活跃买家');
      if (platformRanking.isNotEmpty) {
        final topPlatform = platformRanking.first['platform'] as String?;
        if (topPlatform == 'jd') userTags.add('京东达人');
        if (topPlatform == 'taobao') userTags.add('淘宝达人');
        if (topPlatform == 'pdd') userTags.add('拼多多达人');
      }
      if (userTags.isEmpty) userTags.add('理性消费');

      // 6. 提取偏好品类（从 title 关键词中提取常见品类）
      final preferredCategories = await _extractCategoriesFromTitles();

      final result = {
        'preferredCategories': preferredCategories,
        'pricePreference': {
          'minPrice': double.parse(minPrice.toStringAsFixed(2)),
          'maxPrice': double.parse(maxPrice.toStringAsFixed(2)),
          'averagePrice': double.parse(avgPrice.toStringAsFixed(2)),
          'description': priceDescription,
        },
        'platformRanking': platformRanking
            .map((r) =>
                _platformDisplayName(r['platform'] as String? ?? ''))
            .toList(),
        'shoppingFrequency': shoppingFrequency,
        'userTags': userTags,
      };

      return Response.ok(jsonEncode(result), headers: _corsHeaders);
    } catch (e) {
      print('[AnalyticsService] Error in preferences: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  /// 购物时间分析 - 基于 cart_items 表真实数据
  Future<Response> _handleShoppingTime(Request request) async {
    try {
      // 1. 24小时分布
      final hourlyDist = await db.queryAll('''
        SELECT 
          EXTRACT(HOUR FROM c.created_at) as hour,
          COUNT(*) as count
        FROM cart_items c
        WHERE c.deleted_at IS NULL
        GROUP BY EXTRACT(HOUR FROM c.created_at)
        ORDER BY hour
      ''');

      // 填充完整的24小时
      final hourlyMap = <int, int>{};
      for (final row in hourlyDist) {
        final hour = (row['hour'] as num?)?.toInt() ?? 0;
        final count = (row['count'] as int?) ?? 0;
        hourlyMap[hour] = count;
      }
      final hourlyDistribution = List.generate(24, (hour) {
        return {'hour': hour, 'count': hourlyMap[hour] ?? 0};
      });

      // 2. 星期分布
      final weekdayDist = await db.queryAll('''
        SELECT 
          EXTRACT(DOW FROM c.created_at) as weekday,
          COUNT(*) as count
        FROM cart_items c
        WHERE c.deleted_at IS NULL
        GROUP BY EXTRACT(DOW FROM c.created_at)
        ORDER BY weekday
      ''');

      final weekdayMap = <int, int>{};
      for (final row in weekdayDist) {
        final day = (row['weekday'] as num?)?.toInt() ?? 0;
        final count = (row['count'] as int?) ?? 0;
        weekdayMap[day] = count;
      }
      final weekdayDistribution = List.generate(7, (day) {
        return {'weekday': day, 'count': weekdayMap[day] ?? 0};
      });

      // 3. 热力图数据 (7天 x 24小时)
      final heatmapQuery = await db.queryAll('''
        SELECT 
          EXTRACT(DOW FROM c.created_at) as weekday,
          EXTRACT(HOUR FROM c.created_at) as hour,
          COUNT(*) as count
        FROM cart_items c
        WHERE c.deleted_at IS NULL
        GROUP BY EXTRACT(DOW FROM c.created_at), EXTRACT(HOUR FROM c.created_at)
      ''');

      final heatmapData = List.generate(7, (_) => List.filled(24, 0));
      for (final row in heatmapQuery) {
        final day = (row['weekday'] as num?)?.toInt() ?? 0;
        final hour = (row['hour'] as num?)?.toInt() ?? 0;
        final count = (row['count'] as int?) ?? 0;
        if (day >= 0 && day < 7 && hour >= 0 && hour < 24) {
          heatmapData[day][hour] = count;
        }
      }

      // 4. 计算高峰时段
      int peakHourStart = 0;
      int peakHourCount = 0;
      for (int i = 0; i < 24; i++) {
        final count = hourlyMap[i] ?? 0;
        if (count > peakHourCount) {
          peakHourCount = count;
          peakHourStart = i;
        }
      }
      final peakHourEnd = (peakHourStart + 2) % 24;
      final peakHours =
          '${peakHourStart.toString().padLeft(2, '0')}:00 - ${peakHourEnd.toString().padLeft(2, '0')}:00';

      // 5. 计算高峰日
      final weekdayNames = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
      final sortedDays = weekdayDistribution.toList()
        ..sort((a, b) =>
            (b['count'] as int).compareTo(a['count'] as int));
      final topDays = sortedDays
          .take(2)
          .map((d) => weekdayNames[d['weekday'] as int])
          .join('、');

      final result = {
        'hourlyDistribution': hourlyDistribution,
        'weekdayDistribution': weekdayDistribution,
        'heatmapData': heatmapData,
        'peakHours': peakHours,
        'peakDays': topDays.isNotEmpty ? topDays : '暂无数据',
      };

      return Response.ok(jsonEncode(result), headers: _corsHeaders);
    } catch (e) {
      print('[AnalyticsService] Error in shopping-time: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  // ========== Helper Methods ==========

  /// 从购物车商品标题中提取品类关键词
  Future<List<String>> _extractCategoriesFromTitles() async {
    try {
      final titles = await db.queryAll('''
        SELECT DISTINCT c.title
        FROM cart_items c
        WHERE c.deleted_at IS NULL
        ORDER BY c.created_at DESC
        LIMIT 100
      ''');

      // 常见品类关键词映射
      const categoryKeywords = {
        '数码电子': ['手机', '耳机', '电脑', '笔记本', '平板', '键盘', '鼠标', '显示器', 'DAC', '音响', '充电'],
        '服装鞋包': ['衣服', '裤子', '鞋', '包', '外套', '上衣', '连衣裙', '运动'],
        '家居日用': ['家居', '日用', '收纳', '清洁', '厨房', '卫浴', '灯'],
        '美妆护肤': ['面膜', '护肤', '化妆', '口红', '粉底', '洗面奶', '精华'],
        '食品生鲜': ['零食', '水果', '牛奶', '茶', '咖啡', '酒', '坚果'],
      };

      final categoryCounts = <String, int>{};

      for (final row in titles) {
        final title = (row['title'] as String? ?? '').toLowerCase();
        for (final entry in categoryKeywords.entries) {
          for (final keyword in entry.value) {
            if (title.contains(keyword)) {
              categoryCounts[entry.key] =
                  (categoryCounts[entry.key] ?? 0) + 1;
              break; // 每个标题每个品类只计一次
            }
          }
        }
      }

      // 按出现次数排序，返回前3
      final sorted = categoryCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      if (sorted.isEmpty) {
        return ['暂无足够数据分析'];
      }

      return sorted.take(3).map((e) => e.key).toList();
    } catch (e) {
      print('[AnalyticsService] Error extracting categories: $e');
      return ['暂无足够数据分析'];
    }
  }

  /// 安全地将数据库值转换为 double
  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  /// 平台标识转显示名称
  String _platformDisplayName(String platform) {
    switch (platform.toLowerCase()) {
      case 'jd':
        return '京东';
      case 'taobao':
        return '淘宝';
      case 'pdd':
        return '拼多多';
      case 'tmall':
        return '天猫';
      default:
        return platform;
    }
  }
}

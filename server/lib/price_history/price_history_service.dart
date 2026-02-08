import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/database.dart';

/// 后端价格历史服务 - 基于 price_history 表的真实数据
class PriceHistoryService {
  final Database db;

  // CORS headers
  static const _corsHeaders = {
    'content-type': 'application/json',
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, POST, OPTIONS',
    'access-control-allow-headers':
        'Origin, Content-Type, Accept, Authorization',
  };

  PriceHistoryService(this.db);

  Router get router {
    final router = Router();
    router.get('/<productId>', _handleGetHistory);
    router.post('/batch', _handleBatchHistory);
    router.post('/record', _handleRecordPrice);
    return router;
  }

  /// 获取单个商品的价格历史
  Future<Response> _handleGetHistory(
      Request request, String productId) async {
    try {
      final limit =
          int.tryParse(request.url.queryParameters['limit'] ?? '90') ?? 90;
      final platform = request.url.queryParameters['platform'];

      var whereClause = 'WHERE product_id = @productId';
      final params = <String, dynamic>{
        'productId': productId,
        'limit': limit,
      };

      if (platform != null && platform.isNotEmpty) {
        whereClause += ' AND platform = @platform';
        params['platform'] = platform;
      }

      final history = await db.queryAll('''
        SELECT 
          product_id, platform, price, original_price, 
          coupon, final_price, title, source, recorded_at
        FROM price_history
        $whereClause
        ORDER BY recorded_at DESC
        LIMIT @limit
      ''', parameters: params);

      final result = history.map((row) {
        return {
          'productId': row['product_id'],
          'platform': row['platform'],
          'price': _toDouble(row['price']),
          'originalPrice': _toDouble(row['original_price']),
          'coupon': _toDouble(row['coupon']),
          'finalPrice': _toDouble(row['final_price']),
          'title': row['title'],
          'source': row['source'],
          'timestamp': (row['recorded_at'] as DateTime?)?.toIso8601String(),
        };
      }).toList();

      // 如果没有历史记录，尝试从 cart_items 中获取初始价格
      if (result.isEmpty) {
        final cartItem = await db.queryOne('''
          SELECT product_id, platform, price, original_price, 
                 coupon, final_price, title, created_at
          FROM cart_items
          WHERE product_id = @productId AND deleted_at IS NULL
          LIMIT 1
        ''', parameters: {'productId': productId});

        if (cartItem != null) {
          result.add({
            'productId': cartItem['product_id'],
            'platform': cartItem['platform'],
            'price': _toDouble(cartItem['price']),
            'originalPrice': _toDouble(cartItem['original_price']),
            'coupon': _toDouble(cartItem['coupon']),
            'finalPrice': _toDouble(cartItem['final_price']),
            'title': cartItem['title'],
            'source': 'cart',
            'timestamp':
                (cartItem['created_at'] as DateTime?)?.toIso8601String(),
          });
        }
      }

      return Response.ok(jsonEncode(result), headers: _corsHeaders);
    } catch (e) {
      print('[PriceHistoryService] Error getting history: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  /// 批量获取多个商品的价格历史
  Future<Response> _handleBatchHistory(Request request) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final ids = (json['productIds'] as List?)?.cast<String>() ?? [];

      if (ids.isEmpty) {
        return Response(400,
            body: jsonEncode({'error': '缺少 productIds 参数'}),
            headers: _corsHeaders);
      }

      final resultMap = <String, List<Map<String, dynamic>>>{};

      for (final id in ids) {
        final history = await db.queryAll('''
          SELECT 
            product_id, platform, price, original_price, 
            final_price, recorded_at
          FROM price_history
          WHERE product_id = @productId
          ORDER BY recorded_at DESC
          LIMIT 30
        ''', parameters: {'productId': id});

        resultMap[id] = history.map((row) {
          return {
            'price': _toDouble(row['price']),
            'originalPrice': _toDouble(row['original_price']),
            'finalPrice': _toDouble(row['final_price']),
            'timestamp':
                (row['recorded_at'] as DateTime?)?.toIso8601String(),
          };
        }).toList();
      }

      return Response.ok(jsonEncode(resultMap), headers: _corsHeaders);
    } catch (e) {
      print('[PriceHistoryService] Error in batch history: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  /// 记录新的价格数据点
  Future<Response> _handleRecordPrice(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final productId = data['productId'] as String?;
      final platform = data['platform'] as String?;
      final price = (data['price'] as num?)?.toDouble();

      if (productId == null || platform == null || price == null) {
        return Response(400,
            body: jsonEncode(
                {'error': '缺少必要参数: productId, platform, price'}),
            headers: _corsHeaders);
      }

      await db.execute('''
        INSERT INTO price_history (
          product_id, platform, price, original_price, 
          coupon, final_price, title, source
        ) VALUES (
          @productId, @platform, @price, @originalPrice, 
          @coupon, @finalPrice, @title, @source
        )
      ''', parameters: {
        'productId': productId,
        'platform': platform,
        'price': price,
        'originalPrice': (data['originalPrice'] as num?)?.toDouble(),
        'coupon': (data['coupon'] as num?)?.toDouble() ?? 0,
        'finalPrice': (data['finalPrice'] as num?)?.toDouble() ?? price,
        'title': data['title'] as String?,
        'source': data['source'] as String? ?? 'api',
      });

      return Response.ok(
          jsonEncode({'success': true, 'message': '价格记录已保存'}),
          headers: _corsHeaders);
    } catch (e) {
      print('[PriceHistoryService] Error recording price: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  /// 安全地将数据库值转换为 double
  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }
}

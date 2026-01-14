import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'jd_scraper_service.dart';
import 'cookie_manager.dart';
import 'models/models.dart';

/// 京东爬虫服务路由
///
/// 提供以下 API 端点：
/// - GET  /api/jd/scraper/product/:skuId - 获取单个商品信息
/// - POST /api/jd/scraper/products/batch - 批量获取商品信息
/// - GET  /api/jd/scraper/status - 获取服务状态
/// - GET  /api/jd/cookie/status - 获取 Cookie 状态
/// - POST /api/jd/cookie/update - 更新 Cookie
/// - GET  /api/jd/errors - 获取错误日志
class JdScraperRoutes {
  /// 爬虫服务实例
  final JdScraperService _service;

  /// 是否已初始化
  bool _initialized = false;

  JdScraperRoutes({JdScraperService? service})
      : _service = service ?? JdScraperService(
          config: JdScraperConfig.production(),
        );

  /// 获取路由处理器
  Router get router {
    final router = Router();

    // 商品信息获取
    router.get('/api/jd/scraper/product/<skuId>', _getProduct);
    router.post('/api/jd/scraper/products/batch', _getBatchProducts);

    // 服务状态
    router.get('/api/jd/scraper/status', _getStatus);

    // Cookie 管理
    router.get('/api/jd/cookie/status', _getCookieStatus);
    router.post('/api/jd/cookie/update', _updateCookie);

    // 错误日志
    router.get('/api/jd/errors', _getErrors);

    // 缓存管理
    router.post('/api/jd/cache/clear', _clearCache);

    return router;
  }

  /// 确保服务已初始化
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await _service.initialize();
      _initialized = true;
    }
  }

  /// 获取单个商品信息
  Future<Response> _getProduct(Request request, String skuId) async {
    try {
      await _ensureInitialized();

      final forceRefresh =
          request.url.queryParameters['forceRefresh'] == 'true';

      final info = await _service.getProductInfo(
        skuId,
        forceRefresh: forceRefresh,
      );

      return _jsonResponse({
        'success': true,
        'data': info.toJson(),
      });
    } on ScraperException catch (e) {
      return _errorResponse(e.type.name, e.message, statusCode: _getStatusCode(e.type));
    } catch (e) {
      return _errorResponse('unknown', e.toString());
    }
  }

  /// 批量获取商品信息
  Future<Response> _getBatchProducts(Request request) async {
    try {
      await _ensureInitialized();

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final skuIds = (data['skuIds'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList();

      if (skuIds == null || skuIds.isEmpty) {
        return _errorResponse('badRequest', 'Missing skuIds parameter',
            statusCode: 400);
      }

      final maxConcurrency = data['maxConcurrency'] as int? ?? 2;

      final results = await _service.getBatchProductInfo(
        skuIds,
        maxConcurrency: maxConcurrency,
      );

      return _jsonResponse({
        'success': true,
        'data': results.map((info) => info.toJson()).toList(),
        'total': skuIds.length,
        'success_count': results.length,
      });
    } on ScraperException catch (e) {
      return _errorResponse(e.type.name, e.message, statusCode: _getStatusCode(e.type));
    } catch (e) {
      return _errorResponse('unknown', e.toString());
    }
  }

  /// 获取服务状态
  Future<Response> _getStatus(Request request) async {
    try {
      await _ensureInitialized();
      final status = await _service.getStatus();
      return _jsonResponse({
        'success': true,
        'data': status,
      });
    } catch (e) {
      return _errorResponse('unknown', e.toString());
    }
  }

  /// 获取 Cookie 状态
  Future<Response> _getCookieStatus(Request request) async {
    try {
      final status = await _service.cookieManager.getStatus();
      return _jsonResponse({
        'success': true,
        'data': status,
      });
    } catch (e) {
      return _errorResponse('unknown', e.toString());
    }
  }

  /// 更新 Cookie
  Future<Response> _updateCookie(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final cookie = data['cookie'] as String?;

      if (cookie == null || cookie.isEmpty) {
        return _errorResponse('badRequest', 'Missing cookie parameter',
            statusCode: 400);
      }

      await _service.cookieManager.saveCookie(cookie);

      return _jsonResponse({
        'success': true,
        'message': 'Cookie updated successfully',
      });
    } catch (e) {
      return _errorResponse('unknown', e.toString());
    }
  }

  /// 获取错误日志
  Future<Response> _getErrors(Request request) async {
    try {
      final limitStr = request.url.queryParameters['limit'];
      final typeStr = request.url.queryParameters['type'];

      final limit = limitStr != null ? int.tryParse(limitStr) : 50;
      ScraperErrorType? type;
      if (typeStr != null) {
        try {
          type = ScraperErrorType.values.firstWhere(
            (t) => t.name == typeStr,
          );
        } catch (_) {}
      }

      final errors = _service.getErrorHistory(type: type, limit: limit);

      return _jsonResponse({
        'success': true,
        'data': errors.map((e) => e.toJson()).toList(),
        'total': errors.length,
      });
    } catch (e) {
      return _errorResponse('unknown', e.toString());
    }
  }

  /// 清除缓存
  Future<Response> _clearCache(Request request) async {
    try {
      _service.clearCache();
      return _jsonResponse({
        'success': true,
        'message': 'Cache cleared successfully',
      });
    } catch (e) {
      return _errorResponse('unknown', e.toString());
    }
  }

  /// 关闭服务
  Future<void> close() async {
    await _service.close();
  }

  // ==================== 工具方法 ====================

  /// JSON 响应
  Response _jsonResponse(Map<String, dynamic> data, {int statusCode = 200}) {
    return Response(
      statusCode,
      body: jsonEncode(data),
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    );
  }

  /// 错误响应
  Response _errorResponse(String errorType, String message,
      {int statusCode = 500}) {
    return Response(
      statusCode,
      body: jsonEncode({
        'success': false,
        'error': errorType,
        'message': message,
      }),
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    );
  }

  /// 根据错误类型获取 HTTP 状态码
  int _getStatusCode(ScraperErrorType type) {
    switch (type) {
      case ScraperErrorType.cookieExpired:
      case ScraperErrorType.loginRequired:
        return 401;
      case ScraperErrorType.antiBotDetected:
        return 403;
      case ScraperErrorType.productNotFound:
        return 404;
      case ScraperErrorType.timeout:
        return 504;
      case ScraperErrorType.networkError:
        return 503;
      default:
        return 500;
    }
  }
}

/// 创建爬虫服务路由的快捷方法
Router createJdScraperRouter({JdScraperService? service}) {
  return JdScraperRoutes(service: service).router;
}











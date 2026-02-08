import 'dart:developer' as developer;
import '../../core/api_client.dart';

/// 购物车数据服务
class CartService {
  final ApiClient _apiClient;

  /// 允许的平台值
  static const Set<String> _validPlatforms = {'jd', 'taobao', 'pdd'};

  CartService(this._apiClient);

  /// 获取购物车商品列表
  /// 
  /// [page] 页码
  /// [pageSize] 每页数量
  /// [platform] 平台筛选（jd/taobao/pdd）
  /// [userId] 用户 ID 筛选
  Future<Map<String, dynamic>> getCartItems({
    int page = 1,
    int pageSize = 20,
    String? platform,
    String? userId,
  }) async {
    // 参数边界检查
    final safePage = page.clamp(1, 10000);
    final safePageSize = pageSize.clamp(1, 100);

    try {
      // 构建 URL 参数
      final params = <String, String>{
        'page': safePage.toString(),
        'pageSize': safePageSize.toString(),
      };

      // 验证并添加平台参数
      if (platform != null && platform.isNotEmpty) {
        final safePlatform = platform.toLowerCase().trim();
        if (_validPlatforms.contains(safePlatform)) {
          params['platform'] = safePlatform;
        }
      }

      // 添加用户 ID 参数
      if (userId != null && userId.trim().isNotEmpty) {
        params['userId'] = Uri.encodeComponent(userId.trim());
      }

      final queryString = params.entries
          .map((e) => '${e.key}=${e.value}')
          .join('&');

      final response = await _apiClient.get('/api/v1/admin/cart-items?$queryString');
      final data = _safeParseMap(response.data);

      if (data == null) {
        return _emptyResult(safePage);
      }

      return {
        'items': _safeParseList(data['items']),
        'total': _safeParseInt(data['total'], 0),
        'page': _safeParseInt(data['page'], safePage),
        'totalPages': _safeParseInt(data['totalPages'], 1),
      };
    } catch (e) {
      _log('获取购物车列表失败: $e', isError: true);
      rethrow;
    }
  }

  /// 获取购物车统计
  Future<Map<String, dynamic>> getCartStats() async {
    try {
      final response = await _apiClient.get('/api/v1/admin/cart-items/stats');
      return _safeParseMap(response.data) ?? _defaultStats();
    } catch (e) {
      _log('获取购物车统计失败: $e', isError: true);
      rethrow;
    }
  }

  /// 删除购物车商品
  Future<void> deleteCartItem(String id) async {
    if (id.trim().isEmpty) {
      throw ArgumentError('商品 ID 不能为空');
    }

    try {
      await _apiClient.delete('/api/v1/admin/cart-items/${Uri.encodeComponent(id)}');
      _log('商品删除成功: $id');
    } catch (e) {
      _log('删除商品失败: $e', isError: true);
      rethrow;
    }
  }

  Map<String, dynamic> _emptyResult(int page) => {
        'items': <Map<String, dynamic>>[],
        'total': 0,
        'page': page,
        'totalPages': 1,
      };

  Map<String, dynamic> _defaultStats() => {
        'total': 0,
        'todayNew': 0,
        'weekNew': 0,
        'totalValue': '0.00',
        'byPlatform': <Map<String, dynamic>>[],
      };

  Map<String, dynamic>? _safeParseMap(dynamic data) {
    if (data == null) return null;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  List<Map<String, dynamic>> _safeParseList(dynamic data) {
    if (data == null) return [];
    if (data is! List) return [];

    return data
        .map((item) => _safeParseMap(item))
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  int _safeParseInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  void _log(String message, {bool isError = false}) {
    final prefix = isError ? '❌ Cart' : '🛒 Cart';
    developer.log('$prefix: $message', name: 'CartService');
  }
}

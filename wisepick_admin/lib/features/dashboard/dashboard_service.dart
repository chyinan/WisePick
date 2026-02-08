import 'dart:developer' as developer;
import '../../core/api_client.dart';

/// Dashboard 数据服务
class DashboardService {
  final ApiClient _apiClient;

  DashboardService(this._apiClient);

  /// 获取用户统计数据
  Future<Map<String, dynamic>> getUserStats() async {
    try {
      final response = await _apiClient.get('/api/v1/admin/users/stats');
      return _safeParseMap(response.data) ?? _defaultUserStats();
    } catch (e) {
      _log('获取用户统计失败: $e', isError: true);
      rethrow;
    }
  }

  /// 获取系统统计数据
  Future<Map<String, dynamic>> getSystemStats() async {
    try {
      final response = await _apiClient.get('/api/v1/admin/system/stats');
      return _safeParseMap(response.data) ?? _defaultSystemStats();
    } catch (e) {
      _log('获取系统统计失败: $e', isError: true);
      rethrow;
    }
  }

  /// 获取最近注册用户
  Future<List<Map<String, dynamic>>> getRecentUsers() async {
    try {
      final response = await _apiClient.get('/api/v1/admin/recent-users');
      final data = _safeParseMap(response.data);
      if (data == null) return [];

      return _safeParseList(data['users']);
    } catch (e) {
      _log('获取最近用户失败: $e', isError: true);
      rethrow;
    }
  }

  /// 获取活动图表数据
  Future<List<Map<String, dynamic>>> getActivityChart() async {
    try {
      final response = await _apiClient.get('/api/v1/admin/activity-chart');
      final data = _safeParseMap(response.data);
      if (data == null) return [];

      return _safeParseList(data['data']);
    } catch (e) {
      _log('获取活动图表失败: $e', isError: true);
      rethrow;
    }
  }

  /// 安全解析 Map 数据
  Map<String, dynamic>? _safeParseMap(dynamic data) {
    if (data == null) return null;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  /// 安全解析 List<Map> 数据
  List<Map<String, dynamic>> _safeParseList(dynamic data) {
    if (data == null) return [];
    if (data is! List) return [];

    return data
        .map((item) => _safeParseMap(item))
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// 默认用户统计数据
  Map<String, dynamic> _defaultUserStats() => {
        'totalUsers': 0,
        'todayNewUsers': 0,
        'weekNewUsers': 0,
        'monthNewUsers': 0,
        'verifiedUsers': 0,
        'verificationRate': 0,
        'activeUsers': {'daily': 0, 'weekly': 0, 'monthly': 0},
      };

  /// 默认系统统计数据
  Map<String, dynamic> _defaultSystemStats() => {
        'cartItems': {'total': 0, 'today': 0, 'byPlatform': {}},
        'conversations': {'total': 0, 'today': 0},
        'messages': {'total': 0},
        'devices': {'active': 0},
      };

  void _log(String message, {bool isError = false}) {
    final prefix = isError ? '❌ Dashboard' : '📊 Dashboard';
    developer.log('$prefix: $message', name: 'DashboardService');
  }
}

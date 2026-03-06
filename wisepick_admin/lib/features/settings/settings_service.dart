import 'dart:developer' as developer;
import '../../core/api_client.dart';

/// 系统设置服务
class SettingsService {
  final ApiClient _apiClient;

  SettingsService(this._apiClient);

  /// 获取系统设置
  Future<Map<String, dynamic>> getSettings() async {
    try {
      final response = await _apiClient.get('/api/v1/admin/settings');
      return _safeParseMap(response.data) ?? _defaultSettings();
    } catch (e) {
      _log('获取设置失败: $e', isError: true);
      rethrow;
    }
  }

  /// 更新系统设置
  Future<void> updateSettings(Map<String, dynamic> settings) async {
    if (settings.isEmpty) {
      throw ArgumentError('设置数据不能为空');
    }

    try {
      await _apiClient.put('/api/v1/admin/settings', data: settings);
      _log('设置更新成功');
    } catch (e) {
      _log('更新设置失败: $e', isError: true);
      rethrow;
    }
  }

  /// 获取设备会话列表
  Future<Map<String, dynamic>> getSessions({
    int page = 1,
    int pageSize = 20,
    bool activeOnly = false,
  }) async {
    final safePage = page.clamp(1, 10000);
    final safePageSize = pageSize.clamp(1, 100);

    try {
      final response = await _apiClient.get(
        '/api/v1/admin/sessions?page=$safePage&pageSize=$safePageSize&activeOnly=$activeOnly',
      );

      final data = _safeParseMap(response.data);
      if (data == null) {
        return _emptySessionsResult(safePage);
      }

      return {
        'sessions': _safeParseList(data['sessions']),
        'total': _safeParseInt(data['total'], 0),
        'page': _safeParseInt(data['page'], safePage),
        'totalPages': _safeParseInt(data['totalPages'], 1),
      };
    } catch (e) {
      _log('获取会话列表失败: $e', isError: true);
      rethrow;
    }
  }

  /// 修改管理员密码
  Future<void> changeAdminPassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    if (oldPassword.isEmpty) throw ArgumentError('原密码不能为空');
    if (newPassword.isEmpty) throw ArgumentError('新密码不能为空');
    if (newPassword.length < 8) throw ArgumentError('新密码长度不能少于8位');

    try {
      final response = await _apiClient.post(
        '/admin/change-password',
        data: {'old_password': oldPassword, 'new_password': newPassword},
      );
      final data = response.data;
      if (data is Map && data['success'] != true) {
        throw Exception(data['message']?.toString() ?? '修改失败');
      }
      _log('管理员密码修改成功');
    } catch (e) {
      _log('修改密码失败: $e', isError: true);
      rethrow;
    }
  }

  /// 删除设备会话（强制下线）
  Future<void> deleteSession(String id) async {
    if (id.trim().isEmpty) {
      throw ArgumentError('会话 ID 不能为空');
    }

    try {
      await _apiClient.delete('/api/v1/admin/sessions/${Uri.encodeComponent(id)}');
      _log('会话删除成功（强制下线）: $id');
    } catch (e) {
      _log('删除会话失败: $e', isError: true);
      rethrow;
    }
  }

  Map<String, dynamic> _defaultSettings() => {
        'server': {'host': '-', 'port': '-'},
        'database': {'host': '-', 'port': '-', 'name': '-', 'status': 'unknown'},
        'ai': {'provider': '-', 'model': '-', 'baseUrl': '-', 'hasApiKey': false},
        'jd': {'hasCookie': false, 'cookieSource': '-'},
        'features': {'emailVerification': false, 'rateLimit': false},
      };

  Map<String, dynamic> _emptySessionsResult(int page) => {
        'sessions': <Map<String, dynamic>>[],
        'total': 0,
        'page': page,
        'totalPages': 1,
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
    final prefix = isError ? '❌ Settings' : '⚙️ Settings';
    developer.log('$prefix: $message', name: 'SettingsService');
  }
}

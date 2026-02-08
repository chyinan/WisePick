import 'dart:developer' as developer;
import '../../core/api_client.dart';

/// 用户管理服务
class UsersService {
  final ApiClient _apiClient;

  UsersService(this._apiClient);

  /// 获取用户列表
  /// 
  /// [page] 页码，从1开始
  /// [pageSize] 每页数量，默认20
  Future<Map<String, dynamic>> getUsers({int page = 1, int pageSize = 20}) async {
    // 参数边界检查
    final safePage = page.clamp(1, 10000);
    final safePageSize = pageSize.clamp(1, 100);

    try {
      final response = await _apiClient.get(
        '/api/v1/admin/users?page=$safePage&pageSize=$safePageSize',
      );
      final data = _safeParseMap(response.data);

      if (data == null) {
        return _emptyResult(safePage);
      }

      return {
        'users': _safeParseList(data['users']),
        'total': _safeParseInt(data['total'], 0),
        'page': _safeParseInt(data['page'], safePage),
        'totalPages': _safeParseInt(data['totalPages'], 1),
      };
    } catch (e) {
      _log('获取用户列表失败: $e', isError: true);
      rethrow;
    }
  }

  /// 删除用户
  /// 
  /// [id] 用户 ID，不能为空
  Future<void> deleteUser(String id) async {
    if (id.trim().isEmpty) {
      throw ArgumentError('用户 ID 不能为空');
    }

    try {
      await _apiClient.delete('/api/v1/admin/users/${Uri.encodeComponent(id)}');
      _log('用户删除成功: $id');
    } catch (e) {
      _log('删除用户失败: $e', isError: true);
      rethrow;
    }
  }

  /// 更新用户信息
  /// 
  /// [id] 用户 ID
  /// [data] 更新数据，会过滤空值
  Future<void> updateUser(String id, Map<String, dynamic> data) async {
    if (id.trim().isEmpty) {
      throw ArgumentError('用户 ID 不能为空');
    }

    // 过滤空值，只发送有效数据
    final filteredData = Map<String, dynamic>.from(data)
      ..removeWhere((key, value) => value == null || (value is String && value.isEmpty));

    if (filteredData.isEmpty) {
      throw ArgumentError('没有有效的更新数据');
    }

    try {
      await _apiClient.put(
        '/api/v1/admin/users/${Uri.encodeComponent(id)}',
        data: filteredData,
      );
      _log('用户更新成功: $id');
    } catch (e) {
      _log('更新用户失败: $e', isError: true);
      rethrow;
    }
  }

  /// 空结果
  Map<String, dynamic> _emptyResult(int page) => {
        'users': <Map<String, dynamic>>[],
        'total': 0,
        'page': page,
        'totalPages': 1,
      };

  /// 安全解析 Map
  Map<String, dynamic>? _safeParseMap(dynamic data) {
    if (data == null) return null;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  /// 安全解析 List<Map>
  List<Map<String, dynamic>> _safeParseList(dynamic data) {
    if (data == null) return [];
    if (data is! List) return [];

    return data
        .map((item) => _safeParseMap(item))
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// 安全解析 int
  int _safeParseInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  void _log(String message, {bool isError = false}) {
    final prefix = isError ? '❌ Users' : '👥 Users';
    developer.log('$prefix: $message', name: 'UsersService');
  }
}

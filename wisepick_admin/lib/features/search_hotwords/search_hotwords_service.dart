import 'dart:developer' as developer;
import '../../core/api_client.dart';

/// 搜索热词服务
class SearchHotwordsService {
  final ApiClient _apiClient;

  SearchHotwordsService(this._apiClient);

  /// 获取搜索热词聚合数据
  Future<Map<String, dynamic>> getHotwords({
    int limit = 20,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final params = <String, String>{'limit': limit.clamp(1, 100).toString()};
      if (startDate != null) params['start_date'] = startDate;
      if (endDate != null) params['end_date'] = endDate;

      final queryString = params.entries.map((e) => '${e.key}=${e.value}').join('&');
      final response = await _apiClient.get('/api/v1/admin/search-hotwords?$queryString');
      final data = _safeMap(response.data);
      if (data == null) return _empty();

      return {
        'hotwords': _safeList(data['hotwords']),
        'totalSearches': _safeInt(data['totalSearches'], 0),
        'uniqueKeywords': _safeInt(data['uniqueKeywords'], 0),
        'trend': _safeList(data['trend']),
      };
    } catch (e) {
      _log('获取搜索热词失败: $e', isError: true);
      rethrow;
    }
  }

  Map<String, dynamic> _empty() => {
        'hotwords': <Map<String, dynamic>>[],
        'totalSearches': 0,
        'uniqueKeywords': 0,
        'trend': <Map<String, dynamic>>[],
      };

  Map<String, dynamic>? _safeMap(dynamic data) {
    if (data == null) return null;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.map((k, v) => MapEntry(k.toString(), v));
    return null;
  }

  List<Map<String, dynamic>> _safeList(dynamic data) {
    if (data == null) return [];
    if (data is! List) return [];
    return data.map((e) => _safeMap(e)).whereType<Map<String, dynamic>>().toList();
  }

  int _safeInt(dynamic value, int def) {
    if (value == null) return def;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? def;
    return def;
  }

  void _log(String message, {bool isError = false}) {
    developer.log(
      '${isError ? '❌' : '🔍'} Hotwords: $message',
      name: 'SearchHotwordsService',
    );
  }
}

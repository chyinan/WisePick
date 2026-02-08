import 'dart:developer' as developer;
import '../../core/api_client.dart';

/// 会话记录服务
class ConversationsService {
  final ApiClient _apiClient;

  ConversationsService(this._apiClient);

  /// 获取会话列表
  Future<Map<String, dynamic>> getConversations({
    int page = 1,
    int pageSize = 20,
    String? userId,
  }) async {
    final safePage = page.clamp(1, 10000);
    final safePageSize = pageSize.clamp(1, 100);

    try {
      final params = <String, String>{
        'page': safePage.toString(),
        'pageSize': safePageSize.toString(),
      };

      if (userId != null && userId.trim().isNotEmpty) {
        params['userId'] = Uri.encodeComponent(userId.trim());
      }

      final queryString = params.entries
          .map((e) => '${e.key}=${e.value}')
          .join('&');

      final response = await _apiClient.get('/api/v1/admin/conversations?$queryString');
      final data = _safeParseMap(response.data);

      if (data == null) {
        return _emptyConversationsResult(safePage);
      }

      return {
        'conversations': _safeParseList(data['conversations']),
        'total': _safeParseInt(data['total'], 0),
        'page': _safeParseInt(data['page'], safePage),
        'totalPages': _safeParseInt(data['totalPages'], 1),
      };
    } catch (e) {
      _log('获取会话列表失败: $e', isError: true);
      rethrow;
    }
  }

  /// 获取会话消息
  Future<Map<String, dynamic>> getMessages(
    String conversationId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    if (conversationId.trim().isEmpty) {
      throw ArgumentError('会话 ID 不能为空');
    }

    final safePage = page.clamp(1, 10000);
    final safePageSize = pageSize.clamp(1, 200);

    try {
      final encodedId = Uri.encodeComponent(conversationId.trim());
      final response = await _apiClient.get(
        '/api/v1/admin/conversations/$encodedId/messages?page=$safePage&pageSize=$safePageSize',
      );

      final data = _safeParseMap(response.data);
      if (data == null) {
        return _emptyMessagesResult();
      }

      return {
        'messages': _safeParseList(data['messages']),
        'total': _safeParseInt(data['total'], 0),
        'page': _safeParseInt(data['page'], safePage),
        'totalPages': _safeParseInt(data['totalPages'], 1),
      };
    } catch (e) {
      _log('获取消息列表失败: $e', isError: true);
      rethrow;
    }
  }

  /// 删除会话
  Future<void> deleteConversation(String id) async {
    if (id.trim().isEmpty) {
      throw ArgumentError('会话 ID 不能为空');
    }

    try {
      await _apiClient.delete('/api/v1/admin/conversations/${Uri.encodeComponent(id)}');
      _log('会话删除成功: $id');
    } catch (e) {
      _log('删除会话失败: $e', isError: true);
      rethrow;
    }
  }

  Map<String, dynamic> _emptyConversationsResult(int page) => {
        'conversations': <Map<String, dynamic>>[],
        'total': 0,
        'page': page,
        'totalPages': 1,
      };

  Map<String, dynamic> _emptyMessagesResult() => {
        'messages': <Map<String, dynamic>>[],
        'total': 0,
        'page': 1,
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
    final prefix = isError ? '❌ Conversations' : '💬 Conversations';
    developer.log('$prefix: $message', name: 'ConversationsService');
  }
}

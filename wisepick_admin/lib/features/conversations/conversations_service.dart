import '../../core/api_client.dart';

class ConversationsService {
  final ApiClient _apiClient;

  ConversationsService(this._apiClient);

  Future<Map<String, dynamic>> getConversations({
    int page = 1,
    int pageSize = 20,
    String? userId,
  }) async {
    var url = '/api/v1/admin/conversations?page=$page&pageSize=$pageSize';
    if (userId != null && userId.isNotEmpty) {
      url += '&userId=$userId';
    }
    final response = await _apiClient.get(url);
    final data = response.data as Map<String, dynamic>;
    return {
      'conversations': List<Map<String, dynamic>>.from(data['conversations'] ?? []),
      'total': data['total'] ?? 0,
      'page': data['page'] ?? 1,
      'totalPages': data['totalPages'] ?? 1,
    };
  }

  Future<Map<String, dynamic>> getMessages(String conversationId, {int page = 1, int pageSize = 50}) async {
    final response = await _apiClient.get(
      '/api/v1/admin/conversations/$conversationId/messages?page=$page&pageSize=$pageSize'
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> deleteConversation(String id) async {
    await _apiClient.delete('/api/v1/admin/conversations/$id');
  }
}

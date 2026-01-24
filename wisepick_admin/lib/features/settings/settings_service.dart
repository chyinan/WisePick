import '../../core/api_client.dart';

class SettingsService {
  final ApiClient _apiClient;

  SettingsService(this._apiClient);

  Future<Map<String, dynamic>> getSettings() async {
    final response = await _apiClient.get('/api/v1/admin/settings');
    return response.data as Map<String, dynamic>;
  }

  Future<void> updateSettings(Map<String, dynamic> settings) async {
    await _apiClient.put('/api/v1/admin/settings', data: settings);
  }

  Future<Map<String, dynamic>> getSessions({
    int page = 1,
    int pageSize = 20,
    bool activeOnly = false,
  }) async {
    final response = await _apiClient.get(
      '/api/v1/admin/sessions?page=$page&pageSize=$pageSize&activeOnly=$activeOnly'
    );
    final data = response.data as Map<String, dynamic>;
    return {
      'sessions': List<Map<String, dynamic>>.from(data['sessions'] ?? []),
      'total': data['total'] ?? 0,
      'page': data['page'] ?? 1,
      'totalPages': data['totalPages'] ?? 1,
    };
  }

  Future<void> deleteSession(String id) async {
    await _apiClient.delete('/api/v1/admin/sessions/$id');
  }
}

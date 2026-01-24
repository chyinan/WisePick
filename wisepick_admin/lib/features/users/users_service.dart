import '../../core/api_client.dart';

class UsersService {
  final ApiClient _apiClient;

  UsersService(this._apiClient);

  Future<Map<String, dynamic>> getUsers({int page = 1, int pageSize = 20}) async {
    final response = await _apiClient.get('/api/v1/admin/users?page=$page&pageSize=$pageSize');
    final data = response.data as Map<String, dynamic>;
    return {
      'users': List<Map<String, dynamic>>.from(data['users'] ?? []),
      'total': data['total'] ?? 0,
      'page': data['page'] ?? 1,
      'totalPages': data['totalPages'] ?? 1,
    };
  }

  Future<void> deleteUser(String id) async {
    await _apiClient.delete('/api/v1/admin/users/$id');
  }

  Future<void> updateUser(String id, Map<String, dynamic> data) async {
    await _apiClient.put('/api/v1/admin/users/$id', data: data);
  }
}

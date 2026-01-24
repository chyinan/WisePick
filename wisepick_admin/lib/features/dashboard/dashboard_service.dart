import '../../core/api_client.dart';

class DashboardService {
  final ApiClient _apiClient;

  DashboardService(this._apiClient);

  Future<Map<String, dynamic>> getUserStats() async {
    final response = await _apiClient.get('/api/v1/admin/users/stats');
    return response.data;
  }

  Future<Map<String, dynamic>> getSystemStats() async {
    final response = await _apiClient.get('/api/v1/admin/system/stats');
    return response.data;
  }

  Future<List<Map<String, dynamic>>> getRecentUsers() async {
    final response = await _apiClient.get('/api/v1/admin/recent-users');
    final data = response.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['users'] ?? []);
  }

  Future<List<Map<String, dynamic>>> getActivityChart() async {
    final response = await _apiClient.get('/api/v1/admin/activity-chart');
    final data = response.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['data'] ?? []);
  }
}

import 'package:dio/dio.dart';
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
}

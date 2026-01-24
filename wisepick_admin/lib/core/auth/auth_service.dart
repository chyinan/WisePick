import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api_client.dart';

class AuthService {
  final ApiClient _apiClient;
  final FlutterSecureStorage _storage;

  AuthService(this._apiClient) : _storage = const FlutterSecureStorage();

  Future<bool> login(String password) async {
    try {
      final response = await _apiClient.post('/admin/login', data: {'password': password});
      if (response.statusCode == 200) {
        final data = response.data;
        if (data['success'] == true) {
          // Token might be returned if implemented, otherwise just password success
          await _storage.write(key: 'auth_token', value: 'admin_logged_in'); 
          return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: 'auth_token');
  }

  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: 'auth_token');
    return token != null;
  }
}

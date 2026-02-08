import 'dart:developer' as developer;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api_client.dart';

/// 认证结果类，包含登录状态和错误信息
class AuthResult {
  final bool success;
  final String? errorMessage;

  const AuthResult({required this.success, this.errorMessage});

  factory AuthResult.success() => const AuthResult(success: true);

  factory AuthResult.failure(String message) => AuthResult(
        success: false,
        errorMessage: message,
      );
}

/// 认证服务，处理登录、登出和会话状态
class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _loginTimestampKey = 'login_timestamp';

  final ApiClient _apiClient;
  final FlutterSecureStorage _storage;

  /// 使用共享的安全存储配置，确保与 ApiClient 一致
  AuthService(this._apiClient) : _storage = sharedSecureStorage;

  /// 执行登录
  /// 
  /// 返回 [AuthResult] 包含成功状态和可能的错误信息
  Future<AuthResult> login(String password) async {
    // 输入验证
    if (password.isEmpty) {
      return AuthResult.failure('密码不能为空');
    }

    if (password.length < 3) {
      return AuthResult.failure('密码格式不正确');
    }

    try {
      final response = await _apiClient.post(
        '/admin/login',
        data: {'password': password},
      );

      // 安全地解析响应数据
      final data = _safeParseMap(response.data);
      if (data == null) {
        _log('登录响应数据格式错误', isError: true);
        return AuthResult.failure('服务器响应格式错误');
      }

      if (data['success'] == true) {
        // 提取 token，如果没有返回则使用标记
        final token = data['token']?.toString() ?? 'admin_logged_in';

        try {
          await _storage.write(key: _tokenKey, value: token);
          await _storage.write(
            key: _loginTimestampKey,
            value: DateTime.now().toIso8601String(),
          );
          _log('登录成功');
          return AuthResult.success();
        } catch (storageError) {
          _log('保存认证信息失败: $storageError', isError: true);
          return AuthResult.failure('保存登录状态失败，请重试');
        }
      }

      // 提取服务器返回的错误信息
      final errorMsg = data['error']?.toString() ??
          data['message']?.toString() ??
          '登录失败';
      return AuthResult.failure(errorMsg);
    } on ApiException catch (e) {
      _log('登录 API 错误: ${e.message}', isError: true);

      if (e.isConnectionError) {
        return AuthResult.failure('无法连接服务器，请检查网络');
      }
      if (e.isTimeoutError) {
        return AuthResult.failure('连接超时，请重试');
      }
      if (e.statusCode == 401 || e.statusCode == 403) {
        return AuthResult.failure('密码错误');
      }

      return AuthResult.failure(e.message);
    } catch (e) {
      _log('登录未知错误: $e', isError: true);
      return AuthResult.failure('登录失败，请稍后重试');
    }
  }

  /// 执行登出
  Future<void> logout() async {
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _loginTimestampKey);
      _log('登出成功');
    } catch (e) {
      _log('清除认证信息失败: $e', isError: true);
      // 尝试删除所有数据作为后备方案
      try {
        await _storage.deleteAll();
      } catch (_) {}
    }
  }

  /// 检查是否已登录
  Future<bool> isLoggedIn() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      return token != null && token.isNotEmpty;
    } catch (e) {
      _log('读取登录状态失败: $e', isError: true);
      return false;
    }
  }

  /// 获取当前认证令牌
  Future<String?> getToken() async {
    try {
      return await _storage.read(key: _tokenKey);
    } catch (e) {
      _log('读取令牌失败: $e', isError: true);
      return null;
    }
  }

  /// 安全解析 Map 数据
  Map<String, dynamic>? _safeParseMap(dynamic data) {
    if (data == null) return null;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  /// 记录日志
  void _log(String message, {bool isError = false}) {
    final prefix = isError ? '❌ Auth' : '🔐 Auth';
    developer.log('$prefix: $message', name: 'AuthService');
  }
}

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'user_model.dart';
import 'token_manager.dart';

/// 认证结果
class AuthResult {
  final bool success;
  final String? message;
  final User? user;
  final String? accessToken;
  final String? refreshToken;

  AuthResult({
    required this.success,
    this.message,
    this.user,
    this.accessToken,
    this.refreshToken,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String?,
      user: json['user'] != null 
          ? User.fromJson(json['user'] as Map<String, dynamic>) 
          : null,
      accessToken: json['access_token'] as String?,
      refreshToken: json['refresh_token'] as String?,
    );
  }

  factory AuthResult.error(String message) {
    return AuthResult(success: false, message: message);
  }
}

/// 前端认证服务 - 与后端 API 通信
class AuthService {
  final Dio _dio;
  final TokenManager _tokenManager;
  
  // API 基础 URL
  String get _baseUrl {
    try {
      if (Hive.isBoxOpen('settings')) {
        final box = Hive.box('settings');
        final proxyUrl = box.get('proxy_url') as String?;
        if (proxyUrl != null && proxyUrl.isNotEmpty) {
          return proxyUrl;
        }
      }
    } catch (_) {}
    return 'http://localhost:9527';
  }

  String get _authBaseUrl => '$_baseUrl/api/v1/auth';

  AuthService({Dio? dio, TokenManager? tokenManager})
      : _dio = dio ?? Dio(),
        _tokenManager = tokenManager ?? TokenManager.instance {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    
    // 添加拦截器处理 Token 刷新
    _dio.interceptors.add(_AuthInterceptor(this));
  }

  /// 获取请求头
  Map<String, String> _getHeaders({bool includeAuth = false}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-Device-Id': _tokenManager.deviceId,
      'X-Device-Name': _tokenManager.deviceName,
      'X-Device-Type': _tokenManager.deviceType,
    };

    if (includeAuth && _tokenManager.accessToken != null) {
      headers['Authorization'] = 'Bearer ${_tokenManager.accessToken}';
    }

    return headers;
  }

  /// 用户注册
  Future<AuthResult> register({
    required String email,
    required String password,
    String? nickname,
  }) async {
    try {
      final response = await _dio.post(
        '$_authBaseUrl/register',
        data: jsonEncode({
          'email': email,
          'password': password,
          if (nickname != null) 'nickname': nickname,
        }),
        options: Options(headers: _getHeaders()),
      );

      final result = AuthResult.fromJson(response.data as Map<String, dynamic>);
      
      if (result.success && result.accessToken != null && result.refreshToken != null) {
        await _tokenManager.saveTokens(
          accessToken: result.accessToken!,
          refreshToken: result.refreshToken!,
        );
        if (result.user != null) {
          await _tokenManager.saveUserData(result.user!.toJson());
        }
      }

      return result;
    } on DioException catch (e) {
      return _handleDioError(e);
    } catch (e) {
      return AuthResult.error('注册失败: ${e.toString()}');
    }
  }

  /// 用户登录
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '$_authBaseUrl/login',
        data: jsonEncode({
          'email': email,
          'password': password,
        }),
        options: Options(headers: _getHeaders()),
      );

      final result = AuthResult.fromJson(response.data as Map<String, dynamic>);
      
      if (result.success && result.accessToken != null && result.refreshToken != null) {
        await _tokenManager.saveTokens(
          accessToken: result.accessToken!,
          refreshToken: result.refreshToken!,
        );
        if (result.user != null) {
          await _tokenManager.saveUserData(result.user!.toJson());
        }
      }

      return result;
    } on DioException catch (e) {
      return _handleDioError(e);
    } catch (e) {
      return AuthResult.error('登录失败: ${e.toString()}');
    }
  }

  /// 刷新 Token
  /// 
  /// 只有在服务器明确返回 401（refresh token 无效）时才清除登录状态
  /// 网络错误等其他情况不会清除本地的登录凭证
  Future<AuthResult> refreshToken() async {
    final currentRefreshToken = _tokenManager.refreshToken;
    if (currentRefreshToken == null) {
      return AuthResult.error('未登录');
    }

    try {
      final response = await _dio.post(
        '$_authBaseUrl/refresh',
        data: jsonEncode({
          'refresh_token': currentRefreshToken,
        }),
        options: Options(headers: _getHeaders()),
      );

      final result = AuthResult.fromJson(response.data as Map<String, dynamic>);
      
      if (result.success && result.accessToken != null) {
        await _tokenManager.updateAccessToken(result.accessToken!);
        if (result.refreshToken != null) {
          await _tokenManager.saveTokens(
            accessToken: result.accessToken!,
            refreshToken: result.refreshToken!,
          );
        }
        if (result.user != null) {
          await _tokenManager.saveUserData(result.user!.toJson());
        }
      }

      return result;
    } on DioException catch (e) {
      // 只有在服务器明确返回 401 时才清除登录状态
      // 这表示 refresh token 已失效或被撤销
      if (e.response?.statusCode == 401) {
        await _tokenManager.clearAll();
        return AuthResult.error('登录已过期，请重新登录');
      }
      // 其他错误（如网络问题）不清除登录状态
      return _handleDioError(e);
    } catch (e) {
      // 非网络错误也不清除登录状态
      return AuthResult.error('刷新令牌失败: ${e.toString()}');
    }
  }

  /// 登出
  Future<AuthResult> logout() async {
    try {
      await _dio.post(
        '$_authBaseUrl/logout',
        options: Options(headers: _getHeaders(includeAuth: true)),
      );
    } catch (_) {
      // 即使 API 调用失败也清除本地 tokens
    }

    await _tokenManager.clearAll();
    return AuthResult(success: true, message: '已登出');
  }

  /// 登出所有设备
  Future<AuthResult> logoutAll() async {
    try {
      await _dio.post(
        '$_authBaseUrl/logout-all',
        options: Options(headers: _getHeaders(includeAuth: true)),
      );
    } catch (_) {
      // 即使 API 调用失败也清除本地 tokens
    }

    await _tokenManager.clearAll();
    return AuthResult(success: true, message: '已从所有设备登出');
  }

  /// 获取当前用户信息
  Future<User?> getCurrentUser() async {
    if (!_tokenManager.isLoggedIn) {
      return null;
    }

    try {
      final response = await _dio.get(
        '$_authBaseUrl/me',
        options: Options(headers: _getHeaders(includeAuth: true)),
      );

      final data = response.data as Map<String, dynamic>;
      if (data['success'] == true && data['user'] != null) {
        final user = User.fromJson(data['user'] as Map<String, dynamic>);
        await _tokenManager.saveUserData(user.toJson());
        return user;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        // Token 无效，尝试刷新
        final refreshResult = await refreshToken();
        if (refreshResult.success) {
          return getCurrentUser(); // 重试
        }
      }
    } catch (_) {}

    // 返回缓存的用户数据
    final cached = await _tokenManager.getCachedUserData();
    if (cached != null) {
      return User.fromJson(cached);
    }
    return null;
  }

  /// 获取用户会话列表
  Future<List<UserSession>> getUserSessions() async {
    try {
      final response = await _dio.get(
        '$_authBaseUrl/sessions',
        options: Options(headers: _getHeaders(includeAuth: true)),
      );

      final data = response.data as Map<String, dynamic>;
      if (data['success'] == true && data['sessions'] is List) {
        final currentDeviceId = data['current_device_id'] as String?;
        return (data['sessions'] as List)
            .map((s) => UserSession.fromJson(
                s as Map<String, dynamic>,
                currentDeviceId: currentDeviceId,
              ))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// 修改密码
  Future<AuthResult> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      final response = await _dio.post(
        '$_authBaseUrl/change-password',
        data: jsonEncode({
          'old_password': oldPassword,
          'new_password': newPassword,
        }),
        options: Options(headers: _getHeaders(includeAuth: true)),
      );

      return AuthResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      return _handleDioError(e);
    } catch (e) {
      return AuthResult.error('修改密码失败: ${e.toString()}');
    }
  }

  /// 更新用户资料
  Future<AuthResult> updateProfile({
    String? nickname,
    String? avatarUrl,
  }) async {
    try {
      final response = await _dio.patch(
        '$_authBaseUrl/profile',
        data: jsonEncode({
          if (nickname != null) 'nickname': nickname,
          if (avatarUrl != null) 'avatar_url': avatarUrl,
        }),
        options: Options(headers: _getHeaders(includeAuth: true)),
      );

      final result = AuthResult.fromJson(response.data as Map<String, dynamic>);
      if (result.success && result.user != null) {
        await _tokenManager.saveUserData(result.user!.toJson());
      }
      return result;
    } on DioException catch (e) {
      return _handleDioError(e);
    } catch (e) {
      return AuthResult.error('更新资料失败: ${e.toString()}');
    }
  }

  /// 处理 Dio 错误
  AuthResult _handleDioError(DioException e) {
    if (e.response != null) {
      try {
        final data = e.response!.data;
        if (data is Map<String, dynamic>) {
          return AuthResult.fromJson(data);
        }
      } catch (_) {}
      
      switch (e.response!.statusCode) {
        case 400:
          return AuthResult.error('请求参数错误');
        case 401:
          return AuthResult.error('认证失败，请重新登录');
        case 403:
          return AuthResult.error('没有权限');
        case 404:
          return AuthResult.error('服务不可用');
        case 429:
          return AuthResult.error('请求过于频繁，请稍后再试');
        case 500:
          return AuthResult.error('服务器错误');
        default:
          return AuthResult.error('请求失败 (${e.response!.statusCode})');
      }
    }

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return AuthResult.error('连接超时，请检查网络');
    }

    if (e.type == DioExceptionType.connectionError) {
      return AuthResult.error('无法连接服务器');
    }

    return AuthResult.error('网络错误: ${e.message}');
  }

  // ============================================================
  // 安全问题和密码重置相关方法
  // ============================================================

  /// 设置安全问题
  Future<AuthResult> setSecurityQuestion({
    required String question,
    required String answer,
    int order = 1,
  }) async {
    try {
      final response = await _dio.post(
        '$_authBaseUrl/security-question',
        data: jsonEncode({
          'question': question,
          'answer': answer,
          'order': order,
        }),
        options: Options(headers: _getHeaders(includeAuth: true)),
      );

      return AuthResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      return _handleDioError(e);
    } catch (e) {
      return AuthResult.error('设置安全问题失败: ${e.toString()}');
    }
  }

  /// 获取当前用户的安全问题
  Future<SecurityQuestionResult> getSecurityQuestion() async {
    try {
      final response = await _dio.get(
        '$_authBaseUrl/security-question',
        options: Options(headers: _getHeaders(includeAuth: true)),
      );

      final data = response.data as Map<String, dynamic>;
      return SecurityQuestionResult.fromJson(data);
    } on DioException catch (e) {
      return SecurityQuestionResult(
        success: false,
        message: _handleDioError(e).message,
      );
    } catch (e) {
      return SecurityQuestionResult(
        success: false,
        message: '获取安全问题失败: ${e.toString()}',
      );
    }
  }

  /// 根据邮箱获取安全问题（忘记密码第一步）
  Future<SecurityQuestionResult> getSecurityQuestionByEmail(String email) async {
    try {
      final response = await _dio.post(
        '$_authBaseUrl/forgot-password/question',
        data: jsonEncode({'email': email}),
        options: Options(headers: _getHeaders()),
      );

      final data = response.data as Map<String, dynamic>;
      return SecurityQuestionResult.fromJson(data);
    } on DioException catch (e) {
      final error = _handleDioError(e);
      return SecurityQuestionResult(
        success: false,
        message: error.message,
      );
    } catch (e) {
      return SecurityQuestionResult(
        success: false,
        message: '获取安全问题失败: ${e.toString()}',
      );
    }
  }

  /// 验证安全问题答案（忘记密码第二步）
  Future<PasswordResetResult> verifySecurityQuestion({
    required String email,
    required String answer,
    int order = 1,
  }) async {
    try {
      final response = await _dio.post(
        '$_authBaseUrl/forgot-password/verify',
        data: jsonEncode({
          'email': email,
          'answer': answer,
          'order': order,
        }),
        options: Options(headers: _getHeaders()),
      );

      final data = response.data as Map<String, dynamic>;
      return PasswordResetResult.fromJson(data);
    } on DioException catch (e) {
      final error = _handleDioError(e);
      return PasswordResetResult(
        success: false,
        message: error.message,
      );
    } catch (e) {
      return PasswordResetResult(
        success: false,
        message: '验证失败: ${e.toString()}',
      );
    }
  }

  /// 使用重置令牌重置密码（忘记密码第三步）
  Future<AuthResult> resetPassword({
    required String resetToken,
    required String newPassword,
  }) async {
    try {
      final response = await _dio.post(
        '$_authBaseUrl/forgot-password/reset',
        data: jsonEncode({
          'reset_token': resetToken,
          'new_password': newPassword,
        }),
        options: Options(headers: _getHeaders()),
      );

      return AuthResult.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      return _handleDioError(e);
    } catch (e) {
      return AuthResult.error('密码重置失败: ${e.toString()}');
    }
  }
}

/// 安全问题查询结果
class SecurityQuestionResult {
  final bool success;
  final String? message;
  final bool hasSecurityQuestion;
  final List<Map<String, dynamic>> questions;

  SecurityQuestionResult({
    required this.success,
    this.message,
    this.hasSecurityQuestion = false,
    this.questions = const [],
  });

  factory SecurityQuestionResult.fromJson(Map<String, dynamic> json) {
    final questionsList = json['questions'] as List?;
    return SecurityQuestionResult(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String?,
      hasSecurityQuestion: json['has_security_question'] as bool? ?? 
          (questionsList != null && questionsList.isNotEmpty),
      questions: questionsList
              ?.map((q) => {
                    'question': q['question'] as String? ?? '',
                    'order': q['order'] as int? ?? 1,
                  })
              .toList() ??
          [],
    );
  }
}

/// 密码重置结果
class PasswordResetResult {
  final bool success;
  final String? message;
  final String? resetToken;

  PasswordResetResult({
    required this.success,
    this.message,
    this.resetToken,
  });

  factory PasswordResetResult.fromJson(Map<String, dynamic> json) {
    return PasswordResetResult(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String?,
      resetToken: json['reset_token'] as String?,
    );
  }
}

/// 认证拦截器 - 自动刷新 Token
class _AuthInterceptor extends Interceptor {
  final AuthService _authService;
  bool _isRefreshing = false;

  _AuthInterceptor(this._authService);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final refreshResult = await _authService.refreshToken();
        if (refreshResult.success) {
          // Token 刷新成功，重试原请求
          final opts = err.requestOptions;
          opts.headers['Authorization'] = 
              'Bearer ${TokenManager.instance.accessToken}';
          
          final response = await Dio().fetch(opts);
          _isRefreshing = false;
          return handler.resolve(response);
        }
      } catch (_) {}
      _isRefreshing = false;
    }
    handler.next(err);
  }
}

import 'dart:async';

import 'package:dio/dio.dart';

import 'api_client.dart';
import 'config.dart';

/// JdToken 表示从京东换取到的 token 结构
class JdToken {
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;

  JdToken({required this.accessToken, this.refreshToken, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.toIso8601String(),
      };

  static JdToken fromJson(Map<String, dynamic> json) => JdToken(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String?,
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}

/// Token 存储接口：实际实现应使用数据库或 Vault。
abstract class TokenStore {
  Future<void> saveTokens(String userId, JdToken token);
  Future<JdToken?> getTokens(String userId);
  Future<void> deleteTokens(String userId);
}

/// 简单的内存实现，仅用于开发与测试（生产请使用加密 DB/Redis/Vault）
class InMemoryTokenStore implements TokenStore {
  final Map<String, Map<String, dynamic>> _storage = {};

  @override
  Future<void> saveTokens(String userId, JdToken token) async {
    _storage[userId] = token.toJson();
  }

  @override
  Future<JdToken?> getTokens(String userId) async {
    final data = _storage[userId];
    if (data == null) return null;
    return JdToken.fromJson(data);
  }

  @override
  Future<void> deleteTokens(String userId) async {
    _storage.remove(userId);
  }
}

/// JdOAuthService 负责：构建授权 URL、处理回调、交换 token、刷新 token、提供给 ApiClient 获取 token 的方法。
class JdOAuthService {
  final ApiClient apiClient;
  final TokenStore tokenStore;
  final Dio _httpClient;

  // 单-flight 刷新锁：防止多个请求并发触发多次刷新（示意，单实例可用）
  final Map<String, Completer<JdToken?>> _refreshInProgress = {};

  JdOAuthService({required this.apiClient, required this.tokenStore}) : _httpClient = Dio();

  /// 根据官方文档构造授权 URL（authorization endpoint）
  String buildAuthorizeUrl({required String redirectUri, required String state, String? scope}) {
    final appKey = Config.jdAppKey.trim();
    // 使用京东开放文档指定的 open-oauth 授权入口和参数名（app_key、response_type、redirect_uri、state、scope）
    final params = <String, String>{
      'app_key': appKey,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'state': state,
      'scope': scope ?? 'snsapi_base',
    };
    final uri = Uri.parse('https://open-oauth.jd.com/oauth2/to_login').replace(queryParameters: params);
    return uri.toString();
  }

  /// 处理回调：接收 code 并用它换取 token，保存到 tokenStore
  Future<void> handleAuthorizationCallback({required String userId, required String code, required String redirectUri}) async {
    final token = await exchangeCodeForToken(code: code, redirectUri: redirectUri);
    if (token != null) {
      await tokenStore.saveTokens(userId, token);
    } else {
      throw StateError('Token exchange failed for code');
    }
  }

  /// 使用授权码与京东 token 端点交换 token
  Future<JdToken?> exchangeCodeForToken({required String code, required String redirectUri}) async {
    // 使用 open-oauth access_token 端点，部分环境需要 GET 查询参数形式
    final params = {
      'app_key': Config.jdAppKey,
      'app_secret': Config.jdAppSecret,
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
    };
    try {
      final resp = await _httpClient.get('https://open-oauth.jd.com/oauth2/access_token', queryParameters: params);
      if (resp.statusCode != null && resp.statusCode! >= 400) {
        // log for debugging
        print('[ERROR] access_token endpoint returned status ${resp.statusCode}');
        print('[ERROR] body: ${resp.data}');
        return null;
      }
      final data = resp.data as Map<String, dynamic>;
      if (data.containsKey('code') && data['code'] != 0) {
        print('[ERROR] access_token response error: ${data}');
        return null;
      }
      final accessToken = data['access_token'] as String;
      final refreshToken = data['refresh_token'] as String?;
      final expiresIn = (data['expires_in'] is int) ? data['expires_in'] as int : int.tryParse('${data['expires_in']}') ?? 3600;
      final expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
      return JdToken(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt);
    } on DioException catch (dioErr) {
      print('[DIO ERROR] ${dioErr.message}');
      if (dioErr.response != null) {
        print('[DIO RESPONSE] status: ${dioErr.response?.statusCode}, data: ${dioErr.response?.data}');
      }
      return null;
    } catch (e) {
      print('[ERROR] exchangeCodeForToken exception: $e');
      return null;
    }
  }

  /// 从存储读取 token（如果快过期会尝试刷新），返回可用 access token
  Future<String?> getAccessTokenForUser(String userId) async {
    final token = await tokenStore.getTokens(userId);
    if (token == null) return null;

    // 如果 access token 即将过期（例如剩余时间 < 60s），尝试刷新
    final timeLeft = token.expiresAt.difference(DateTime.now());
    if (timeLeft.inSeconds < 60 && token.refreshToken != null) {
      final refreshed = await _refreshTokenSingleFlight(userId, token.refreshToken!);
      return refreshed?.accessToken;
    }
    if (token.isExpired && token.refreshToken != null) {
      final refreshed = await _refreshTokenSingleFlight(userId, token.refreshToken!);
      return refreshed?.accessToken;
    }
    return token.accessToken;
  }

  /// 使用 refresh_token 刷新 access_token（包含单-flight 控制）
  Future<JdToken?> _refreshTokenSingleFlight(String userId, String refreshToken) async {
    // 如果已有刷新在进行中，等待它完成
    if (_refreshInProgress.containsKey(userId)) {
      return _refreshInProgress[userId]!.future;
    }

    final completer = Completer<JdToken?>();
    _refreshInProgress[userId] = completer;

    try {
      final newToken = await refreshAccessToken(refreshToken: refreshToken);
      if (newToken != null) {
        await tokenStore.saveTokens(userId, newToken);
      }
      completer.complete(newToken);
      return newToken;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _refreshInProgress.remove(userId);
    }
  }

  /// 实际调用京东 token refresh 端点
  Future<JdToken?> refreshAccessToken({required String refreshToken}) async {
    final params = {
      'app_key': Config.jdAppKey,
      'app_secret': Config.jdAppSecret,
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
    };
    try {
      final resp = await _httpClient.get('https://open-oauth.jd.com/oauth2/refresh_token', queryParameters: params);
      if (resp.statusCode != null && resp.statusCode! >= 400) {
        print('[ERROR] refresh_token endpoint status ${resp.statusCode}');
        print('[ERROR] body: ${resp.data}');
        return null;
      }
      final data = resp.data as Map<String, dynamic>;
      if (data.containsKey('code') && data['code'] != 0) {
        print('[ERROR] refresh_token response error: ${data}');
        return null;
      }
      final accessToken = data['access_token'] as String;
      final newRefreshToken = data['refresh_token'] as String? ?? refreshToken;
      final expiresIn = (data['expires_in'] is int) ? data['expires_in'] as int : int.tryParse('${data['expires_in']}') ?? 3600;
      final expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
      return JdToken(accessToken: accessToken, refreshToken: newRefreshToken, expiresAt: expiresAt);
    } on DioException catch (dioErr) {
      print('[DIO ERROR] ${dioErr.message}');
      if (dioErr.response != null) {
        print('[DIO RESPONSE] status: ${dioErr.response?.statusCode}, data: ${dioErr.response?.data}');
      }
      return null;
    } catch (e) {
      print('[ERROR] refreshAccessToken exception: $e');
      return null;
    }
  }

  /// 撤销 token（可选）
  Future<bool> revokeToken({required String token}) async {
    try {
      final resp = await _httpClient.post('https://jos.jd.com/oauth/revoke', data: {'token': token});
      return resp.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 给 ApiClient 使用的辅助函数：在遇到 401 时尝试刷新并返回是否重试成功
  Future<bool> refreshIfNeededForRequest(RequestOptions requestOptions) async {
    // 期望请求上下文在 options.extra 中带上 userId
    final userId = requestOptions.extra['userId'] as String?;
    if (userId == null) return false;

    final token = await tokenStore.getTokens(userId);
    if (token == null || token.refreshToken == null) return false;

    final refreshed = await _refreshTokenSingleFlight(userId, token.refreshToken!);
    return refreshed != null;
  }
}
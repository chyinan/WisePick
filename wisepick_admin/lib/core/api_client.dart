import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 统一的安全存储配置
/// 
/// 在 ApiClient 和 AuthService 之间共享，确保配置一致性。
/// 注意：修改此配置会影响所有使用安全存储的组件。
const FlutterSecureStorage sharedSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

/// API 客户端异常，封装网络和业务错误
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic originalError;

  ApiException({
    required this.message,
    this.statusCode,
    this.originalError,
  });

  @override
  String toString() => 'ApiException: $message (code: $statusCode)';

  /// 是否为网络连接错误
  bool get isConnectionError =>
      originalError is DioException &&
      (originalError as DioException).type == DioExceptionType.connectionError;

  /// 是否为超时错误
  bool get isTimeoutError =>
      originalError is DioException &&
      ((originalError as DioException).type == DioExceptionType.connectionTimeout ||
          (originalError as DioException).type == DioExceptionType.receiveTimeout ||
          (originalError as DioException).type == DioExceptionType.sendTimeout);

  /// 是否为认证错误
  bool get isAuthError => statusCode == 401 || statusCode == 403;
}

/// 统一 API 客户端，负责所有网络请求
/// 
/// 使用单例模式确保整个应用共享同一个实例，
/// 避免重复创建 Dio 实例和拦截器导致的资源浪费和状态不一致
class ApiClient {
  static const String _defaultBaseUrl = 'http://localhost:9527';
  static const Duration _defaultConnectTimeout = Duration(seconds: 15);
  static const Duration _defaultReceiveTimeout = Duration(seconds: 30);
  static const int _maxRetries = 2;

  /// 单例实例
  static ApiClient? _instance;
  
  /// 获取单例实例
  /// 
  /// 首次调用时会创建实例，后续调用返回同一实例。
  /// 注意：如果单例已存在，后续调用的参数将被忽略。
  factory ApiClient({
    String baseUrl = _defaultBaseUrl,
    Duration connectTimeout = _defaultConnectTimeout,
    Duration receiveTimeout = _defaultReceiveTimeout,
  }) {
    // 如果已有实例，检查参数一致性并返回
    if (_instance != null) {
      // 在开发阶段，如果传入了不同的配置参数，记录警告日志
      // 这有助于发现配置不一致的问题
      if (baseUrl != _defaultBaseUrl && baseUrl != _instance!._baseUrl) {
        developer.log(
          '⚠️ API: ApiClient 单例已存在，忽略传入的 baseUrl: $baseUrl (当前: ${_instance!._baseUrl})',
          name: 'ApiClient',
        );
      }
      return _instance!;
    }
    
    _instance = ApiClient._internal(
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
    );
    return _instance!;
  }

  final Dio _dio;
  final FlutterSecureStorage _storage;
  final String _baseUrl;

  /// 401 错误回调，用于全局登出处理
  void Function()? onUnauthorized;

  ApiClient._internal({
    required String baseUrl,
    required Duration connectTimeout,
    required Duration receiveTimeout,
  })  : _baseUrl = baseUrl,
        _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: connectTimeout,
          receiveTimeout: receiveTimeout,
          validateStatus: (status) => status != null && status < 500,
        )),
        _storage = sharedSecureStorage {
    _setupInterceptors();
  }
  
  /// 重置单例（仅用于测试）
  static void resetForTesting() {
    _instance = null;
  }

  void _setupInterceptors() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onResponse: _onResponse,
      onError: _onError,
    ));
  }

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final token = await _storage.read(key: 'auth_token');
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    } catch (e) {
      _log('读取认证令牌失败: $e', isError: true);
      // 继续请求，不阻塞
    }

    _log('请求: ${options.method} ${options.path}');
    return handler.next(options);
  }

  void _onResponse(Response response, ResponseInterceptorHandler handler) {
    _log('响应: ${response.statusCode} ${response.requestOptions.path}');
    return handler.next(response);
  }

  Future<void> _onError(
    DioException e,
    ErrorInterceptorHandler handler,
  ) async {
    _log(
      '请求错误: ${e.type} ${e.requestOptions.path} - ${e.message}',
      isError: true,
    );

    if (e.response?.statusCode == 401) {
      _log('认证失败，触发登出回调', isError: true);
      onUnauthorized?.call();
    }

    return handler.next(e);
  }

  /// 执行 GET 请求
  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) async {
    return _executeWithRetry(
      () => _dio.get(path, queryParameters: queryParameters),
      path: path,
      method: 'GET',
    );
  }

  /// 执行 POST 请求
  Future<Response> post(String path, {dynamic data}) async {
    return _executeWithRetry(
      () => _dio.post(path, data: data),
      path: path,
      method: 'POST',
    );
  }

  /// 执行 PUT 请求
  Future<Response> put(String path, {dynamic data}) async {
    return _executeWithRetry(
      () => _dio.put(path, data: data),
      path: path,
      method: 'PUT',
    );
  }

  /// 执行 DELETE 请求
  Future<Response> delete(String path) async {
    return _executeWithRetry(
      () => _dio.delete(path),
      path: path,
      method: 'DELETE',
    );
  }

  /// 带重试的请求执行
  Future<Response> _executeWithRetry(
    Future<Response> Function() request, {
    required String path,
    required String method,
    int retryCount = 0,
  }) async {
    try {
      final response = await request();

      // 检查业务层面的错误响应
      if (response.statusCode != null && response.statusCode! >= 400) {
        throw ApiException(
          message: _extractErrorMessage(response),
          statusCode: response.statusCode,
        );
      }

      return response;
    } on DioException catch (e) {
      // 仅对可重试的错误进行重试（连接错误、超时等）
      if (_shouldRetry(e) && retryCount < _maxRetries) {
        _log('请求失败，第 ${retryCount + 1} 次重试: $path');
        await Future.delayed(Duration(milliseconds: 500 * (retryCount + 1)));
        return _executeWithRetry(
          request,
          path: path,
          method: method,
          retryCount: retryCount + 1,
        );
      }

      throw _convertException(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        message: '请求失败: ${e.toString()}',
        originalError: e,
      );
    }
  }

  /// 判断是否应该重试
  bool _shouldRetry(DioException e) {
    // 连接错误和超时错误可以重试
    return e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError;
  }

  /// 转换 Dio 异常为 ApiException
  ApiException _convertException(DioException e) {
    String message;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        message = '连接超时，请检查网络';
        break;
      case DioExceptionType.sendTimeout:
        message = '发送超时，请重试';
        break;
      case DioExceptionType.receiveTimeout:
        message = '接收超时，服务器响应慢';
        break;
      case DioExceptionType.connectionError:
        message = '网络连接失败，请检查网络设置';
        break;
      case DioExceptionType.cancel:
        message = '请求已取消';
        break;
      case DioExceptionType.badResponse:
        message = _extractErrorMessage(e.response);
        break;
      default:
        message = e.message ?? '网络请求失败';
    }

    return ApiException(
      message: message,
      statusCode: e.response?.statusCode,
      originalError: e,
    );
  }

  /// 从响应中提取错误消息
  String _extractErrorMessage(Response? response) {
    if (response == null) return '未知错误';

    try {
      final data = response.data;
      if (data is Map<String, dynamic>) {
        // 尝试多种常见的错误字段
        return data['error']?.toString() ??
            data['message']?.toString() ??
            data['msg']?.toString() ??
            '请求失败 (${response.statusCode})';
      }
    } catch (_) {}

    return '请求失败 (${response.statusCode})';
  }

  /// 记录日志
  void _log(String message, {bool isError = false}) {
    final prefix = isError ? '❌ API' : '📡 API';
    developer.log('$prefix: $message', name: 'ApiClient');
  }

  /// 获取基础 URL
  String get baseUrl => _baseUrl;
}

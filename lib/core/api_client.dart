import 'dart:async';
import 'package:dio/dio.dart';

import 'resilience/retry_policy.dart';
import 'resilience/circuit_breaker.dart';
import 'resilience/result.dart';
import 'logging/app_logger.dart';

/// API Client Configuration
class ApiClientConfig {
  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Duration sendTimeout;
  final String? baseUrl;
  final RetryConfig retryConfig;
  final bool enableCircuitBreaker;
  final CircuitBreakerConfig circuitBreakerConfig;
  final bool logRequests;
  final bool logResponseBody;
  final Map<String, String> defaultHeaders;

  const ApiClientConfig({
    this.connectTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(minutes: 5),
    this.sendTimeout = const Duration(seconds: 30),
    this.baseUrl,
    this.retryConfig = const RetryConfig(),
    this.enableCircuitBreaker = true,
    this.circuitBreakerConfig = const CircuitBreakerConfig(),
    this.logRequests = true,
    this.logResponseBody = false,
    this.defaultHeaders = const {},
  });

  factory ApiClientConfig.development() {
    return ApiClientConfig(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 2),
      retryConfig: RetryConfig.conservative,
      logRequests: true,
      logResponseBody: true,
    );
  }

  factory ApiClientConfig.production() {
    return const ApiClientConfig(
      connectTimeout: Duration(seconds: 30),
      receiveTimeout: Duration(minutes: 5),
      retryConfig: RetryConfig.defaultConfig,
      enableCircuitBreaker: true,
      logRequests: true,
      logResponseBody: false,
    );
  }

  factory ApiClientConfig.aiService() {
    return ApiClientConfig(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 10),
      sendTimeout: const Duration(minutes: 2),
      retryConfig: RetryConfig.aiService,
      circuitBreakerConfig: CircuitBreakerConfig.aiService,
    );
  }
}

typedef RequestInterceptor = Future<RequestOptions> Function(RequestOptions options);
typedef ResponseInterceptor = Future<Response> Function(Response response);
typedef ErrorInterceptor = Future<DioException> Function(DioException error);

/// Enhanced API Client with retry, circuit breaker, and logging
class ApiClient {
  final Dio dio;
  final ApiClientConfig config;
  final ModuleLogger _logger;
  final RetryExecutor _retryExecutor;
  CircuitBreaker? _circuitBreaker;

  final List<RequestInterceptor> _requestInterceptors = [];
  final List<ResponseInterceptor> _responseInterceptors = [];
  final List<ErrorInterceptor> _errorInterceptors = [];
  int _requestCount = 0;

  ApiClient({
    Dio? dio,
    ApiClientConfig? config,
  })  : config = config ?? const ApiClientConfig(),
        dio = dio ?? Dio(),
        _logger = AppLogger.instance.module('ApiClient'),
        _retryExecutor = RetryExecutor(config: config?.retryConfig) {
    _configureDio();
    _setupCircuitBreaker();
  }

  void _configureDio() {
    dio.options.connectTimeout = config.connectTimeout;
    dio.options.receiveTimeout = config.receiveTimeout;
    dio.options.sendTimeout = config.sendTimeout;
    if (config.baseUrl != null) dio.options.baseUrl = config.baseUrl!;
    if (config.defaultHeaders.isNotEmpty) {
      dio.options.headers.addAll(config.defaultHeaders);
    }
    if (config.logRequests) dio.interceptors.add(_createLoggingInterceptor());
  }

  void _setupCircuitBreaker() {
    if (config.enableCircuitBreaker) {
      _circuitBreaker = CircuitBreaker(
        name: 'ApiClient',
        config: config.circuitBreakerConfig,
      );
    }
  }

  Interceptor _createLoggingInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) {
        final requestId = _generateRequestId();
        options.extra['requestId'] = requestId;
        options.extra['startTime'] = DateTime.now();
        _logger.debug('-> ${options.method} ${options.uri}',
            context: {'requestId': requestId});
        handler.next(options);
      },
      onResponse: (response, handler) {
        final requestId = response.requestOptions.extra['requestId'];
        final startTime = response.requestOptions.extra['startTime'] as DateTime?;
        final duration = startTime != null
            ? DateTime.now().difference(startTime).inMilliseconds
            : 0;
        _logger.debug('<- ${response.statusCode} ${response.requestOptions.uri}',
            context: {'requestId': requestId, 'duration': '${duration}ms'});
        handler.next(response);
      },
      onError: (error, handler) {
        final requestId = error.requestOptions.extra['requestId'];
        _logger.warning('x ${error.type.name} ${error.requestOptions.uri}',
            context: {'requestId': requestId}, error: error.message);
        handler.next(error);
      },
    );
  }

  String _generateRequestId() =>
      'req_${DateTime.now().millisecondsSinceEpoch}_${++_requestCount}';

  void addRequestInterceptor(RequestInterceptor interceptor) =>
      _requestInterceptors.add(interceptor);
  void addResponseInterceptor(ResponseInterceptor interceptor) =>
      _responseInterceptors.add(interceptor);
  void addErrorInterceptor(ErrorInterceptor interceptor) =>
      _errorInterceptors.add(interceptor);

  Future<Response> get(String path, {
    Map<String, dynamic>? params,
    Map<String, dynamic>? headers,
    Duration? timeout,
    bool retry = true,
  }) async {
    return _executeRequest(
      () async {
        final options = Options(headers: headers);
        if (timeout != null) options.receiveTimeout = timeout;
        return await dio.get(path, queryParameters: params, options: options);
      },
      operationName: 'GET $path',
      retry: retry,
    );
  }

  Future<Response> post(String path, {
    dynamic data,
    Map<String, dynamic>? headers,
    ResponseType? responseType,
    Duration? timeout,
    bool retry = true,
  }) async {
    return _executeRequest(
      () async {
        final options = Options(headers: headers, responseType: responseType);
        if (timeout != null) options.receiveTimeout = timeout;
        return await dio.post(path, data: data, options: options);
      },
      operationName: 'POST $path',
      retry: retry,
    );
  }

  Future<Response> put(String path, {
    dynamic data,
    Map<String, dynamic>? headers,
    Duration? timeout,
    bool retry = true,
  }) async {
    return _executeRequest(
      () async {
        final options = Options(headers: headers);
        if (timeout != null) options.receiveTimeout = timeout;
        return await dio.put(path, data: data, options: options);
      },
      operationName: 'PUT $path',
      retry: retry,
    );
  }

  Future<Response> delete(String path, {
    dynamic data,
    Map<String, dynamic>? headers,
    Duration? timeout,
    bool retry = true,
  }) async {
    return _executeRequest(
      () async {
        final options = Options(headers: headers);
        if (timeout != null) options.receiveTimeout = timeout;
        return await dio.delete(path, data: data, options: options);
      },
      operationName: 'DELETE $path',
      retry: retry,
    );
  }

  Future<Response> patch(String path, {
    dynamic data,
    Map<String, dynamic>? headers,
    Duration? timeout,
    bool retry = true,
  }) async {
    return _executeRequest(
      () async {
        final options = Options(headers: headers);
        if (timeout != null) options.receiveTimeout = timeout;
        return await dio.patch(path, data: data, options: options);
      },
      operationName: 'PATCH $path',
      retry: retry,
    );
  }

  Future<Response> _executeRequest(
    Future<Response> Function() request, {
    required String operationName,
    bool retry = true,
  }) async {
    if (_circuitBreaker != null && !_circuitBreaker!.allowRequest()) {
      _logger.warning('Circuit breaker open: $operationName');
      throw DioException(
        requestOptions: RequestOptions(path: operationName),
        type: DioExceptionType.unknown,
        error: CircuitBreakerException(
          message: 'Circuit breaker is open',
          state: _circuitBreaker!.state,
          remainingTimeout: null,
        ),
      );
    }

    try {
      Response response;
      if (retry) {
        final result = await _retryExecutor.execute(
          request,
          operationName: operationName,
          retryIf: _shouldRetryDioError,
        );
        response = result.getOrThrow();
      } else {
        response = await request();
      }
      _circuitBreaker?.recordSuccess();
      return response;
    } on DioException catch (e) {
      _circuitBreaker?.recordFailure();
      throw _enhanceDioException(e);
    } catch (e) {
      // Non-DioException errors (e.g. parsing, type errors) must still
      // be counted as failures by the circuit breaker so its failure
      // rate stays accurate.
      _circuitBreaker?.recordFailure();
      rethrow;
    }
  }

  bool _shouldRetryDioError(Object error) {
    if (error is! DioException) return false;
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        return statusCode != null && (statusCode >= 500 || statusCode == 429);
      default:
        return false;
    }
  }

  DioException _enhanceDioException(DioException e) {
    String msg;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        msg = 'Connection timeout';
        break;
      case DioExceptionType.sendTimeout:
        msg = 'Send timeout';
        break;
      case DioExceptionType.receiveTimeout:
        msg = 'Receive timeout';
        break;
      case DioExceptionType.connectionError:
        msg = 'Network connection failed';
        break;
      case DioExceptionType.badResponse:
        msg = _getStatusCodeMessage(e.response?.statusCode);
        break;
      case DioExceptionType.cancel:
        msg = 'Request cancelled';
        break;
      default:
        msg = e.message ?? 'Unknown error';
    }
    return DioException(
      requestOptions: e.requestOptions,
      response: e.response,
      type: e.type,
      error: e.error,
      message: msg,
    );
  }

  String _getStatusCodeMessage(int? code) {
    switch (code) {
      case 400: return 'Bad request';
      case 401: return 'Unauthorized';
      case 403: return 'Forbidden';
      case 404: return 'Not found';
      case 429: return 'Too many requests';
      case 500: return 'Server error';
      case 502: return 'Bad gateway';
      case 503: return 'Service unavailable';
      case 504: return 'Gateway timeout';
      default: return 'Server error ($code)';
    }
  }

  Map<String, dynamic>? getCircuitBreakerStatus() => _circuitBreaker?.getStatus();
  void resetCircuitBreaker() => _circuitBreaker?.reset();

  Future<Result<Response>> getAsResult(String path, {
    Map<String, dynamic>? params,
    Map<String, dynamic>? headers,
    Duration? timeout,
    bool retry = true,
  }) async {
    return Result.fromAsync(() => get(path, params: params, headers: headers,
        timeout: timeout, retry: retry));
  }

  Future<Result<Response>> postAsResult(String path, {
    dynamic data,
    Map<String, dynamic>? headers,
    ResponseType? responseType,
    Duration? timeout,
    bool retry = true,
  }) async {
    return Result.fromAsync(() => post(path, data: data, headers: headers,
        responseType: responseType, timeout: timeout, retry: retry));
  }

  void close() => dio.close();
}

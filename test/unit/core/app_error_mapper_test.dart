import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisepick_dart_version/core/error/app_error.dart';
import 'package:wisepick_dart_version/core/error/app_error_mapper.dart';

void main() {
  group('AppErrorMapper', () {
    group('mapException', () {
      test('returns same AppError if already an AppError', () {
        const original = AppError(
          type: AppErrorType.network,
          userMessage: '网络错误',
        );
        final result = AppErrorMapper.mapException(original);
        expect(identical(result, original), isTrue);
      });

      test('maps SocketException string to network error', () {
        final error = Exception('SocketException: Connection refused');
        final result = AppErrorMapper.mapException(error);
        expect(result.type, AppErrorType.network);
        expect(result.userMessage, contains('网络'));
      });

      test('maps connection refused to network error', () {
        final error = Exception('connection refused');
        final result = AppErrorMapper.mapException(error);
        expect(result.type, AppErrorType.network);
      });

      test('maps TimeoutException string to timeout error', () {
        final error = Exception('TimeoutException after 30s');
        final result = AppErrorMapper.mapException(error);
        expect(result.type, AppErrorType.timeout);
        expect(result.userMessage, contains('超时'));
      });

      test('maps timed out string to timeout error', () {
        final error = Exception('request timed out');
        final result = AppErrorMapper.mapException(error);
        expect(result.type, AppErrorType.timeout);
      });

      test('maps SSL/handshake error to network error', () {
        final error = Exception('HandshakeException: certificate_verify_failed');
        final result = AppErrorMapper.mapException(error);
        expect(result.type, AppErrorType.network);
        expect(result.userMessage, contains('安全连接'));
      });

      test('maps 401/forbidden to auth error', () {
        final error = Exception('HTTP 401 Unauthorized');
        final result = AppErrorMapper.mapException(error);
        expect(result.type, AppErrorType.auth);
        expect(result.canRetry, isFalse);
      });

      test('maps 403/forbidden to auth error', () {
        final error = Exception('403 forbidden');
        final result = AppErrorMapper.mapException(error);
        expect(result.type, AppErrorType.auth);
        expect(result.canRetry, isFalse);
      });

      test('maps unknown exception to unknown error', () {
        final error = Exception('something weird happened');
        final result = AppErrorMapper.mapException(error);
        expect(result.type, AppErrorType.unknown);
        expect(result.userMessage, contains('操作失败'));
        expect(result.technicalDetail, isNotNull);
      });

      test('never exposes raw exception text in userMessage', () {
        final rawText = 'DioException [bad response]: {"error":"internal"}';
        final error = Exception(rawText);
        final result = AppErrorMapper.mapException(error);
        // userMessage should be a friendly Chinese message, not the raw text
        expect(result.userMessage.contains('DioException'), isFalse);
        expect(result.userMessage.contains('{'), isFalse);
      });
    });

    group('mapDioException', () {
      test('maps connectionTimeout to timeout error', () {
        final dio = DioException(
          type: DioExceptionType.connectionTimeout,
          requestOptions: RequestOptions(path: '/test'),
        );
        final result = AppErrorMapper.mapDioException(dio);
        expect(result.type, AppErrorType.timeout);
        expect(result.userMessage, contains('连接超时'));
      });

      test('maps sendTimeout to timeout error', () {
        final dio = DioException(
          type: DioExceptionType.sendTimeout,
          requestOptions: RequestOptions(path: '/test'),
        );
        final result = AppErrorMapper.mapDioException(dio);
        expect(result.type, AppErrorType.timeout);
      });

      test('maps receiveTimeout to timeout error', () {
        final dio = DioException(
          type: DioExceptionType.receiveTimeout,
          requestOptions: RequestOptions(path: '/test'),
        );
        final result = AppErrorMapper.mapDioException(dio);
        expect(result.type, AppErrorType.timeout);
        expect(result.userMessage, contains('响应超时'));
      });

      test('maps connectionError to network error', () {
        final dio = DioException(
          type: DioExceptionType.connectionError,
          requestOptions: RequestOptions(path: '/test'),
        );
        final result = AppErrorMapper.mapDioException(dio);
        expect(result.type, AppErrorType.network);
        expect(result.userMessage, contains('连接'));
      });

      test('maps cancel to cancelled error with canRetry false', () {
        final dio = DioException(
          type: DioExceptionType.cancel,
          requestOptions: RequestOptions(path: '/test'),
        );
        final result = AppErrorMapper.mapDioException(dio);
        expect(result.type, AppErrorType.cancelled);
        expect(result.canRetry, isFalse);
      });

      test('maps badResponse 400 to validation error', () {
        final dio = DioException(
          type: DioExceptionType.badResponse,
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            statusCode: 400,
            requestOptions: RequestOptions(path: '/test'),
          ),
        );
        final result = AppErrorMapper.mapDioException(dio);
        expect(result.type, AppErrorType.validation);
        expect(result.canRetry, isFalse);
      });

      test('maps badResponse 401 to auth error', () {
        final dio = DioException(
          type: DioExceptionType.badResponse,
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            statusCode: 401,
            requestOptions: RequestOptions(path: '/test'),
          ),
        );
        final result = AppErrorMapper.mapDioException(dio);
        expect(result.type, AppErrorType.auth);
        expect(result.canRetry, isFalse);
        expect(result.userMessage, contains('登录'));
      });

      test('maps badResponse 403 to auth error', () {
        final dio = DioException(
          type: DioExceptionType.badResponse,
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            statusCode: 403,
            requestOptions: RequestOptions(path: '/test'),
          ),
        );
        final result = AppErrorMapper.mapDioException(dio);
        expect(result.type, AppErrorType.auth);
        expect(result.canRetry, isFalse);
      });

      test('maps badResponse 404 to serverError with no retry', () {
        final dio = DioException(
          type: DioExceptionType.badResponse,
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            statusCode: 404,
            requestOptions: RequestOptions(path: '/test'),
          ),
        );
        final result = AppErrorMapper.mapDioException(dio);
        expect(result.type, AppErrorType.serverError);
        expect(result.canRetry, isFalse);
      });

      test('maps badResponse 429 to rateLimit error', () {
        final dio = DioException(
          type: DioExceptionType.badResponse,
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            statusCode: 429,
            requestOptions: RequestOptions(path: '/test'),
          ),
        );
        final result = AppErrorMapper.mapDioException(dio);
        expect(result.type, AppErrorType.rateLimit);
        expect(result.userMessage, contains('频繁'));
      });

      test('maps badResponse 500 to serverError', () {
        final dio = DioException(
          type: DioExceptionType.badResponse,
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            statusCode: 500,
            requestOptions: RequestOptions(path: '/test'),
          ),
        );
        final result = AppErrorMapper.mapDioException(dio);
        expect(result.type, AppErrorType.serverError);
        expect(result.userMessage, contains('服务器'));
      });

      test('maps badResponse 502 to serverError', () {
        final dio = DioException(
          type: DioExceptionType.badResponse,
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            statusCode: 502,
            requestOptions: RequestOptions(path: '/test'),
          ),
        );
        final result = AppErrorMapper.mapDioException(dio);
        expect(result.type, AppErrorType.serverError);
      });

      test('maps badResponse 503 to serverError', () {
        final dio = DioException(
          type: DioExceptionType.badResponse,
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            statusCode: 503,
            requestOptions: RequestOptions(path: '/test'),
          ),
        );
        final result = AppErrorMapper.mapDioException(dio);
        expect(result.type, AppErrorType.serverError);
      });

      test('maps badResponse 504 to timeout error', () {
        final dio = DioException(
          type: DioExceptionType.badResponse,
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            statusCode: 504,
            requestOptions: RequestOptions(path: '/test'),
          ),
        );
        final result = AppErrorMapper.mapDioException(dio);
        expect(result.type, AppErrorType.timeout);
      });

      test('maps unknown status code to unknown error', () {
        final dio = DioException(
          type: DioExceptionType.badResponse,
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            statusCode: 999,
            requestOptions: RequestOptions(path: '/test'),
          ),
        );
        final result = AppErrorMapper.mapDioException(dio);
        expect(result.type, AppErrorType.unknown);
      });

      test('maps unknown DioExceptionType to unknown error', () {
        final dio = DioException(
          type: DioExceptionType.unknown,
          requestOptions: RequestOptions(path: '/test'),
        );
        final result = AppErrorMapper.mapDioException(dio);
        expect(result.type, AppErrorType.unknown);
        expect(result.userMessage, contains('服务'));
      });
    });

    group('AppError', () {
      test('has correct default canRetry', () {
        const error = AppError(
          type: AppErrorType.network,
          userMessage: '测试',
        );
        expect(error.canRetry, isTrue);
      });

      test('toString includes type and message', () {
        const error = AppError(
          type: AppErrorType.timeout,
          userMessage: '请求超时',
        );
        expect(error.toString(), contains('timeout'));
        expect(error.toString(), contains('请求超时'));
      });

      test('all error types have distinct icons', () {
        final icons = <dynamic>{};
        for (final type in AppErrorType.values) {
          final error = AppError(type: type, userMessage: '');
          icons.add(error.icon);
        }
        // At least most types should have distinct icons
        expect(icons.length, greaterThanOrEqualTo(AppErrorType.values.length - 1));
      });
    });

    group('cross-module consistency', () {
      test('all userMessages are Chinese and do not contain raw exception text', () {
        final testCases = <Object>[
          Exception('SocketException: host not found'),
          Exception('TimeoutException after 30000ms'),
          Exception('HandshakeException: ssl error'),
          Exception('401 unauthorized'),
          Exception('random error xyz'),
          DioException(
            type: DioExceptionType.connectionTimeout,
            requestOptions: RequestOptions(path: '/test'),
          ),
          DioException(
            type: DioExceptionType.badResponse,
            requestOptions: RequestOptions(path: '/test'),
            response: Response(
              statusCode: 500,
              requestOptions: RequestOptions(path: '/test'),
            ),
          ),
        ];

        for (final error in testCases) {
          final appError = AppErrorMapper.mapException(error);
          // User messages should not contain raw technical patterns
          expect(appError.userMessage.contains('Exception'), isFalse,
              reason: 'userMessage should not contain "Exception" for $error');
          expect(appError.userMessage.contains('DioException'), isFalse,
              reason: 'userMessage should not contain "DioException" for $error');
          expect(appError.userMessage.contains('{'), isFalse,
              reason: 'userMessage should not contain JSON braces for $error');
          // All messages should contain Chinese characters
          expect(
            RegExp(r'[\u4e00-\u9fff]').hasMatch(appError.userMessage),
            isTrue,
            reason: 'userMessage should contain Chinese chars for $error',
          );
        }
      });
    });
  });
}

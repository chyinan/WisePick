import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisepick_dart_version/features/chat/chat_error_mapper.dart';

// 构造一个最小的 DioException
DioException _makeDioException(
  DioExceptionType type, {
  int? statusCode,
  String? message,
}) {
  final requestOptions = RequestOptions(path: '/test');
  return DioException(
    requestOptions: requestOptions,
    type: type,
    message: message,
    response: statusCode != null
        ? Response(requestOptions: requestOptions, statusCode: statusCode)
        : null,
  );
}

void main() {
  // ──────────────────────────────────────────────────────────────
  // ChatError
  // ──────────────────────────────────────────────────────────────
  group('ChatError', () {
    test('toString 包含类型和消息', () {
      const e = ChatError(type: ChatErrorType.network, userMessage: '网络错误');
      expect(e.toString(), contains('network'));
      expect(e.toString(), contains('网络错误'));
    });

    test('canRetry 默认为 true', () {
      const e = ChatError(type: ChatErrorType.unknown, userMessage: '未知错误');
      expect(e.canRetry, isTrue);
    });

    test('canRetry 可设为 false', () {
      const e = ChatError(
        type: ChatErrorType.auth,
        userMessage: '认证失败',
        canRetry: false,
      );
      expect(e.canRetry, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // ChatErrorMapper.mapException — 普通异常
  // ──────────────────────────────────────────────────────────────
  group('ChatErrorMapper.mapException', () {
    test('ChatError 直接透传', () {
      const original = ChatError(
        type: ChatErrorType.rateLimit,
        userMessage: '限流',
      );
      final result = ChatErrorMapper.mapException(original);
      expect(result, same(original));
    });

    test('SocketException → network 类型', () {
      final e = Exception('SocketException: connection refused');
      final result = ChatErrorMapper.mapException(e);
      expect(result.type, ChatErrorType.network);
      expect(result.canRetry, isTrue);
    });

    test('connection refused → network 类型', () {
      final e = Exception('connection refused');
      final result = ChatErrorMapper.mapException(e);
      expect(result.type, ChatErrorType.network);
    });

    test('network is unreachable → network 类型', () {
      final e = Exception('network is unreachable');
      final result = ChatErrorMapper.mapException(e);
      expect(result.type, ChatErrorType.network);
    });

    test('TimeoutException → timeout 类型', () {
      final e = Exception('TimeoutException: timed out');
      final result = ChatErrorMapper.mapException(e);
      expect(result.type, ChatErrorType.timeout);
    });

    test('timed out → timeout 类型', () {
      final e = Exception('request timed out');
      final result = ChatErrorMapper.mapException(e);
      expect(result.type, ChatErrorType.timeout);
    });

    test('HandshakeException → network 类型', () {
      final e = Exception('HandshakeException: ssl error');
      final result = ChatErrorMapper.mapException(e);
      expect(result.type, ChatErrorType.network);
    });

    test('certificate_verify_failed → network 类型', () {
      final e = Exception('certificate_verify_failed');
      final result = ChatErrorMapper.mapException(e);
      expect(result.type, ChatErrorType.network);
    });

    test('ssl → network 类型', () {
      final e = Exception('ssl handshake failed');
      final result = ChatErrorMapper.mapException(e);
      expect(result.type, ChatErrorType.network);
    });

    test('forbidden → auth 类型，canRetry=false', () {
      final e = Exception('forbidden access');
      final result = ChatErrorMapper.mapException(e);
      expect(result.type, ChatErrorType.auth);
      expect(result.canRetry, isFalse);
    });

    test('401 字符串 → auth 类型', () {
      final e = Exception('error 401 unauthorized');
      final result = ChatErrorMapper.mapException(e);
      expect(result.type, ChatErrorType.auth);
    });

    test('403 字符串 → auth 类型', () {
      final e = Exception('error 403 forbidden');
      final result = ChatErrorMapper.mapException(e);
      expect(result.type, ChatErrorType.auth);
    });

    test('未知异常 → unknown 类型', () {
      final e = Exception('some random error');
      final result = ChatErrorMapper.mapException(e);
      expect(result.type, ChatErrorType.unknown);
    });

    test('DioException 委托给 mapDioException', () {
      final e = _makeDioException(DioExceptionType.cancel);
      final result = ChatErrorMapper.mapException(e);
      expect(result.type, ChatErrorType.cancelled);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // ChatErrorMapper.mapDioException
  // ──────────────────────────────────────────────────────────────
  group('ChatErrorMapper.mapDioException', () {
    test('connectionTimeout → timeout', () {
      final e = _makeDioException(DioExceptionType.connectionTimeout);
      final result = ChatErrorMapper.mapDioException(e);
      expect(result.type, ChatErrorType.timeout);
      expect(result.canRetry, isTrue);
    });

    test('sendTimeout → timeout', () {
      final e = _makeDioException(DioExceptionType.sendTimeout);
      final result = ChatErrorMapper.mapDioException(e);
      expect(result.type, ChatErrorType.timeout);
    });

    test('receiveTimeout → timeout（AI 响应超时）', () {
      final e = _makeDioException(DioExceptionType.receiveTimeout);
      final result = ChatErrorMapper.mapDioException(e);
      expect(result.type, ChatErrorType.timeout);
      expect(result.userMessage, contains('AI'));
    });

    test('connectionError → network', () {
      final e = _makeDioException(DioExceptionType.connectionError);
      final result = ChatErrorMapper.mapDioException(e);
      expect(result.type, ChatErrorType.network);
    });

    test('cancel → cancelled，canRetry=false', () {
      final e = _makeDioException(DioExceptionType.cancel);
      final result = ChatErrorMapper.mapDioException(e);
      expect(result.type, ChatErrorType.cancelled);
      expect(result.canRetry, isFalse);
    });

    test('badResponse 400 → unknown', () {
      final e = _makeDioException(DioExceptionType.badResponse, statusCode: 400);
      final result = ChatErrorMapper.mapDioException(e);
      expect(result.type, ChatErrorType.unknown);
    });

    test('badResponse 401 → auth，canRetry=false', () {
      final e = _makeDioException(DioExceptionType.badResponse, statusCode: 401);
      final result = ChatErrorMapper.mapDioException(e);
      expect(result.type, ChatErrorType.auth);
      expect(result.canRetry, isFalse);
    });

    test('badResponse 403 → auth，canRetry=false', () {
      final e = _makeDioException(DioExceptionType.badResponse, statusCode: 403);
      final result = ChatErrorMapper.mapDioException(e);
      expect(result.type, ChatErrorType.auth);
      expect(result.canRetry, isFalse);
    });

    test('badResponse 404 → serverError，canRetry=false', () {
      final e = _makeDioException(DioExceptionType.badResponse, statusCode: 404);
      final result = ChatErrorMapper.mapDioException(e);
      expect(result.type, ChatErrorType.serverError);
      expect(result.canRetry, isFalse);
    });

    test('badResponse 429 → rateLimit', () {
      final e = _makeDioException(DioExceptionType.badResponse, statusCode: 429);
      final result = ChatErrorMapper.mapDioException(e);
      expect(result.type, ChatErrorType.rateLimit);
    });

    test('badResponse 500 → serverError', () {
      final e = _makeDioException(DioExceptionType.badResponse, statusCode: 500);
      final result = ChatErrorMapper.mapDioException(e);
      expect(result.type, ChatErrorType.serverError);
    });

    test('badResponse 502 → serverError', () {
      final e = _makeDioException(DioExceptionType.badResponse, statusCode: 502);
      final result = ChatErrorMapper.mapDioException(e);
      expect(result.type, ChatErrorType.serverError);
    });

    test('badResponse 503 → serverError', () {
      final e = _makeDioException(DioExceptionType.badResponse, statusCode: 503);
      final result = ChatErrorMapper.mapDioException(e);
      expect(result.type, ChatErrorType.serverError);
    });

    test('badResponse 504 → timeout', () {
      final e = _makeDioException(DioExceptionType.badResponse, statusCode: 504);
      final result = ChatErrorMapper.mapDioException(e);
      expect(result.type, ChatErrorType.timeout);
    });

    test('badResponse 未知状态码 → unknown', () {
      final e = _makeDioException(DioExceptionType.badResponse, statusCode: 418);
      final result = ChatErrorMapper.mapDioException(e);
      expect(result.type, ChatErrorType.unknown);
      expect(result.userMessage, contains('418'));
    });

    test('unknown DioExceptionType → unknown', () {
      final e = _makeDioException(DioExceptionType.unknown);
      final result = ChatErrorMapper.mapDioException(e);
      expect(result.type, ChatErrorType.unknown);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // ChatErrorMapper.iconForType
  // ──────────────────────────────────────────────────────────────
  group('ChatErrorMapper.iconForType', () {
    test('每种类型都返回非空字符串', () {
      for (final type in ChatErrorType.values) {
        final icon = ChatErrorMapper.iconForType(type);
        expect(icon, isNotEmpty, reason: 'type=$type 应有图标');
      }
    });

    test('network → 🌐', () {
      expect(ChatErrorMapper.iconForType(ChatErrorType.network), equals('🌐'));
    });

    test('timeout → ⏱️', () {
      expect(ChatErrorMapper.iconForType(ChatErrorType.timeout), equals('⏱️'));
    });

    test('auth → 🔑', () {
      expect(ChatErrorMapper.iconForType(ChatErrorType.auth), equals('🔑'));
    });

    test('rateLimit → ⏳', () {
      expect(ChatErrorMapper.iconForType(ChatErrorType.rateLimit), equals('⏳'));
    });

    test('serverError → 🔧', () {
      expect(ChatErrorMapper.iconForType(ChatErrorType.serverError), equals('🔧'));
    });

    test('cancelled → ✋', () {
      expect(ChatErrorMapper.iconForType(ChatErrorType.cancelled), equals('✋'));
    });

    test('unknown → ⚠️', () {
      expect(ChatErrorMapper.iconForType(ChatErrorType.unknown), equals('⚠️'));
    });
  });
}

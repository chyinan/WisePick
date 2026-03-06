import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisepick_dart_version/features/auth/auth_service.dart';
import 'package:wisepick_dart_version/features/auth/token_manager.dart';

// ─── FakeAdapter ─────────────────────────────────────────────────────────────

class _FakeAdapter implements HttpClientAdapter {
  Object? _next; // Response data map or DioException

  void respondWith(Map<String, dynamic> body, {int statusCode = 200}) {
    _next = ResponseBody.fromString(jsonEncode(body), statusCode,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }

  void throwWith(int statusCode) {
    _next = statusCode;
  }

  void throwTimeout() {
    _next = DioExceptionType.connectionTimeout;
  }

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    final n = _next;
    if (n is ResponseBody) return n;
    if (n is int) {
      // 返回非 map 的 body，确保 _handleDioError 走到 switch 分支
      throw DioException(
        requestOptions: options,
        response: Response(
          statusCode: n,
          data: 'error',
          requestOptions: options,
        ),
        type: DioExceptionType.badResponse,
      );
    }
    if (n is DioExceptionType) {
      throw DioException(requestOptions: options, type: n);
    }
    throw StateError('_FakeAdapter: no response configured');
  }

  @override
  void close({bool force = false}) {}
}

// ─── FakeTokenManager ────────────────────────────────────────────────────────

class _FakeTokenManager extends TokenManager {
  String? savedAccess;
  String? savedRefresh;
  bool cleared = false;

  _FakeTokenManager() : super.forTesting();

  @override
  String? get accessToken => savedAccess;

  @override
  String? get refreshToken => savedRefresh;

  @override
  bool get isLoggedIn => savedAccess != null;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    Duration accessTokenExpiry = const Duration(minutes: 15),
    Duration? refreshTokenExpiry,
  }) async {
    savedAccess = accessToken;
    savedRefresh = refreshToken;
  }

  @override
  Future<void> updateAccessToken(
    String token, {
    Duration expiry = const Duration(minutes: 15),
    bool extendSession = false,
  }) async => savedAccess = token;

  @override
  Future<void> saveUserData(Map<String, dynamic> data) async {}

  @override
  Future<Map<String, dynamic>?> getCachedUserData() async => null;

  @override
  Future<void> clearAll() async {
    cleared = true;
    savedAccess = null;
    savedRefresh = null;
  }
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  late _FakeAdapter adapter;
  late _FakeTokenManager fakeTokenManager;
  late AuthService sut;

  setUp(() {
    adapter = _FakeAdapter();
    fakeTokenManager = _FakeTokenManager();
    final dio = Dio();
    dio.httpClientAdapter = adapter;
    sut = AuthService(dio: dio, tokenManager: fakeTokenManager);
  });

  group('_handleDioError — HTTP 状态码映射', () {
    test('400 → success=false，含"参数"提示', () async {
      adapter.throwWith(400);
      final result = await sut.login(email: 'a@b.com', password: 'pw');
      expect(result.success, isFalse);
      expect(result.message, contains('参数'));
    });

    test('401 → success=false，含"认证"提示', () async {
      adapter.throwWith(401);
      final result = await sut.login(email: 'a@b.com', password: 'pw');
      expect(result.success, isFalse);
      expect(result.message, contains('认证'));
    });

    test('403 → success=false，含"权限"提示', () async {
      adapter.throwWith(403);
      final result = await sut.login(email: 'a@b.com', password: 'pw');
      expect(result.success, isFalse);
      expect(result.message, contains('权限'));
    });

    test('404 → success=false，含"服务"提示', () async {
      adapter.throwWith(404);
      final result = await sut.login(email: 'a@b.com', password: 'pw');
      expect(result.success, isFalse);
      expect(result.message, contains('服务'));
    });

    test('429 → success=false，含"频繁"提示', () async {
      adapter.throwWith(429);
      final result = await sut.login(email: 'a@b.com', password: 'pw');
      expect(result.success, isFalse);
      expect(result.message, contains('频繁'));
    });

    test('500 → success=false，含"服务器"提示', () async {
      adapter.throwWith(500);
      final result = await sut.login(email: 'a@b.com', password: 'pw');
      expect(result.success, isFalse);
      expect(result.message, contains('服务器'));
    });

    test('连接超时 → success=false，含"超时"提示', () async {
      adapter.throwTimeout();
      final result = await sut.login(email: 'a@b.com', password: 'pw');
      expect(result.success, isFalse);
      expect(result.message, contains('超时'));
    });
  });

  group('login', () {
    test('成功时 accessToken 和 refreshToken 不为 null', () async {
      adapter.respondWith({
        'success': true,
        'access_token': 'acc-123',
        'refresh_token': 'ref-456',
        'user': {'id': '1', 'email': 'a@b.com', 'nickname': 'Test'},
      });
      final result = await sut.login(email: 'a@b.com', password: 'pw');
      expect(result.success, isTrue);
      expect(result.accessToken, isNotNull);
      expect(result.refreshToken, isNotNull);
    });
  });

  group('refreshToken', () {
    test('收到 401 时返回 success=false', () async {
      fakeTokenManager.savedRefresh = 'old-refresh';
      adapter.throwWith(401);
      final result = await sut.refreshToken();
      expect(result.success, isFalse);
    });
  });

  group('logout', () {
    test('即使 API 失败也返回 success=true', () async {
      adapter.throwWith(500);
      final result = await sut.logout();
      expect(result.success, isTrue);
      expect(fakeTokenManager.cleared, isTrue);
    });
  });
}

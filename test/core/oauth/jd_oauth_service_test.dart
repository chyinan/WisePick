import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisepick_dart_version/core/api_client.dart';
import 'package:wisepick_dart_version/core/jd_oauth_service.dart';

void main() {
  // ──────────────────────────────────────────────────────────────
  // JdToken
  // ──────────────────────────────────────────────────────────────
  group('JdToken', () {
    test('isExpired - 未过期时为 false', () {
      final token = JdToken(
        accessToken: 'at',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(token.isExpired, isFalse);
    });

    test('isExpired - 已过期时为 true', () {
      final token = JdToken(
        accessToken: 'at',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(token.isExpired, isTrue);
    });

    test('toJson 序列化所有字段', () {
      final expiry = DateTime(2026, 1, 1, 12, 0, 0);
      final token = JdToken(
        accessToken: 'access-123',
        refreshToken: 'refresh-456',
        expiresAt: expiry,
      );
      final json = token.toJson();
      expect(json['access_token'], equals('access-123'));
      expect(json['refresh_token'], equals('refresh-456'));
      expect(json['expires_at'], equals(expiry.toIso8601String()));
    });

    test('toJson refreshToken 为 null 时序列化为 null', () {
      final token = JdToken(
        accessToken: 'access-123',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final json = token.toJson();
      expect(json['refresh_token'], isNull);
    });

    test('fromJson 正确反序列化', () {
      final expiry = DateTime(2026, 6, 1, 0, 0, 0).toUtc();
      final json = {
        'access_token': 'at-abc',
        'refresh_token': 'rt-xyz',
        'expires_at': expiry.toIso8601String(),
      };
      final token = JdToken.fromJson(json);
      expect(token.accessToken, equals('at-abc'));
      expect(token.refreshToken, equals('rt-xyz'));
      expect(token.expiresAt, equals(expiry));
    });

    test('fromJson refreshToken 为 null 时正确处理', () {
      final json = {
        'access_token': 'at-abc',
        'refresh_token': null,
        'expires_at': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      };
      final token = JdToken.fromJson(json);
      expect(token.refreshToken, isNull);
    });

    test('toJson → fromJson 往返一致', () {
      final original = JdToken(
        accessToken: 'at-round-trip',
        refreshToken: 'rt-round-trip',
        expiresAt: DateTime(2026, 3, 1, 10, 30, 0),
      );
      final restored = JdToken.fromJson(original.toJson());
      expect(restored.accessToken, equals(original.accessToken));
      expect(restored.refreshToken, equals(original.refreshToken));
      expect(restored.expiresAt.toIso8601String(), equals(original.expiresAt.toIso8601String()));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // InMemoryTokenStore
  // ──────────────────────────────────────────────────────────────
  group('InMemoryTokenStore', () {
    late InMemoryTokenStore store;

    setUp(() {
      store = InMemoryTokenStore();
    });

    test('getTokens 初始返回 null', () async {
      expect(await store.getTokens('user1'), isNull);
    });

    test('saveTokens 后 getTokens 返回正确 token', () async {
      final token = JdToken(
        accessToken: 'at-1',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await store.saveTokens('user1', token);
      final retrieved = await store.getTokens('user1');
      expect(retrieved, isNotNull);
      expect(retrieved!.accessToken, equals('at-1'));
    });

    test('saveTokens 覆盖同一用户的旧 token', () async {
      final old = JdToken(accessToken: 'old', expiresAt: DateTime.now().add(const Duration(hours: 1)));
      final fresh = JdToken(accessToken: 'fresh', expiresAt: DateTime.now().add(const Duration(hours: 2)));
      await store.saveTokens('user1', old);
      await store.saveTokens('user1', fresh);
      final retrieved = await store.getTokens('user1');
      expect(retrieved!.accessToken, equals('fresh'));
    });

    test('deleteTokens 后 getTokens 返回 null', () async {
      final token = JdToken(accessToken: 'at', expiresAt: DateTime.now().add(const Duration(hours: 1)));
      await store.saveTokens('user1', token);
      await store.deleteTokens('user1');
      expect(await store.getTokens('user1'), isNull);
    });

    test('deleteTokens 不存在的用户不抛出异常', () async {
      await expectLater(store.deleteTokens('nonexistent'), completes);
    });

    test('不同用户的 token 互不干扰', () async {
      final t1 = JdToken(accessToken: 'at-user1', expiresAt: DateTime.now().add(const Duration(hours: 1)));
      final t2 = JdToken(accessToken: 'at-user2', expiresAt: DateTime.now().add(const Duration(hours: 1)));
      await store.saveTokens('user1', t1);
      await store.saveTokens('user2', t2);
      expect((await store.getTokens('user1'))!.accessToken, equals('at-user1'));
      expect((await store.getTokens('user2'))!.accessToken, equals('at-user2'));
    });

    test('删除一个用户不影响另一个', () async {
      final t1 = JdToken(accessToken: 'at-1', expiresAt: DateTime.now().add(const Duration(hours: 1)));
      final t2 = JdToken(accessToken: 'at-2', expiresAt: DateTime.now().add(const Duration(hours: 1)));
      await store.saveTokens('user1', t1);
      await store.saveTokens('user2', t2);
      await store.deleteTokens('user1');
      expect(await store.getTokens('user1'), isNull);
      expect((await store.getTokens('user2'))!.accessToken, equals('at-2'));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // JdOAuthService.buildAuthorizeUrl
  // ──────────────────────────────────────────────────────────────
  group('JdOAuthService.buildAuthorizeUrl', () {
    late JdOAuthService service;

    setUp(() {
      service = JdOAuthService(
        apiClient: _FakeApiClient(),
        tokenStore: InMemoryTokenStore(),
      );
    });

    test('返回京东授权端点 URL', () {
      final url = service.buildAuthorizeUrl(
        redirectUri: 'https://example.com/callback',
        state: 'test-state',
      );
      expect(url, contains('open-oauth.jd.com'));
      expect(url, contains('oauth2/to_login'));
    });

    test('包含 response_type=code', () {
      final url = service.buildAuthorizeUrl(
        redirectUri: 'https://example.com/callback',
        state: 'test-state',
      );
      expect(url, contains('response_type=code'));
    });

    test('包含 state 参数', () {
      final url = service.buildAuthorizeUrl(
        redirectUri: 'https://example.com/callback',
        state: 'my-state-123',
      );
      expect(url, contains('my-state-123'));
    });

    test('包含 redirect_uri 参数', () {
      final url = service.buildAuthorizeUrl(
        redirectUri: 'https://example.com/callback',
        state: 'test-state',
      );
      expect(url, contains(Uri.encodeComponent('https://example.com/callback')));
    });

    test('scope 默认为 snsapi_base', () {
      final url = service.buildAuthorizeUrl(
        redirectUri: 'https://example.com/callback',
        state: 'test-state',
      );
      expect(url, contains('snsapi_base'));
    });

    test('自定义 scope 正确传入', () {
      final url = service.buildAuthorizeUrl(
        redirectUri: 'https://example.com/callback',
        state: 'test-state',
        scope: 'snsapi_userinfo',
      );
      expect(url, contains('snsapi_userinfo'));
    });

    test('返回合法 URI', () {
      final url = service.buildAuthorizeUrl(
        redirectUri: 'https://example.com/callback',
        state: 'test-state',
      );
      expect(() => Uri.parse(url), returnsNormally);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // JdOAuthService.getAccessTokenForUser
  // ──────────────────────────────────────────────────────────────
  group('JdOAuthService.getAccessTokenForUser', () {
    test('用户无 token 时返回 null', () async {
      final service = JdOAuthService(
        apiClient: _FakeApiClient(),
        tokenStore: InMemoryTokenStore(),
      );
      expect(await service.getAccessTokenForUser('user1'), isNull);
    });

    test('有效 token 直接返回 accessToken', () async {
      final store = InMemoryTokenStore();
      final token = JdToken(
        accessToken: 'valid-at',
        expiresAt: DateTime.now().add(const Duration(hours: 2)),
      );
      await store.saveTokens('user1', token);
      final service = JdOAuthService(apiClient: _FakeApiClient(), tokenStore: store);
      expect(await service.getAccessTokenForUser('user1'), equals('valid-at'));
    });

    test('已过期且无 refreshToken 时返回过期 token（不刷新）', () async {
      final store = InMemoryTokenStore();
      final token = JdToken(
        accessToken: 'expired-at',
        refreshToken: null,
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      await store.saveTokens('user1', token);
      final service = JdOAuthService(apiClient: _FakeApiClient(), tokenStore: store);
      // 无 refreshToken，直接返回过期 token
      expect(await service.getAccessTokenForUser('user1'), equals('expired-at'));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // JdOAuthService.refreshIfNeededForRequest
  // ──────────────────────────────────────────────────────────────
  group('JdOAuthService.refreshIfNeededForRequest', () {
    test('extra 中无 userId 时返回 false', () async {
      final service = JdOAuthService(
        apiClient: _FakeApiClient(),
        tokenStore: InMemoryTokenStore(),
      );
      final options = _fakeRequestOptions(extra: {});
      expect(await service.refreshIfNeededForRequest(options), isFalse);
    });

    test('用户无 token 时返回 false', () async {
      final service = JdOAuthService(
        apiClient: _FakeApiClient(),
        tokenStore: InMemoryTokenStore(),
      );
      final options = _fakeRequestOptions(extra: {'userId': 'user1'});
      expect(await service.refreshIfNeededForRequest(options), isFalse);
    });

    test('token 无 refreshToken 时返回 false', () async {
      final store = InMemoryTokenStore();
      await store.saveTokens('user1', JdToken(
        accessToken: 'at',
        refreshToken: null,
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      ));
      final service = JdOAuthService(apiClient: _FakeApiClient(), tokenStore: store);
      final options = _fakeRequestOptions(extra: {'userId': 'user1'});
      expect(await service.refreshIfNeededForRequest(options), isFalse);
    });
  });
}

// ── 辅助类 ──────────────────────────────────────────────────────

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(dio: Dio());
}

RequestOptions _fakeRequestOptions({Map<String, dynamic> extra = const {}}) {
  return RequestOptions(path: '/test', extra: extra);
}

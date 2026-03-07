import 'package:flutter_test/flutter_test.dart';
import 'package:wisepick_dart_version/core/jd_oauth_service.dart';
import 'package:wisepick_dart_version/core/oauth_controller.dart';
import 'package:wisepick_dart_version/core/oauth_state_store.dart';
import 'package:wisepick_dart_version/core/api_client.dart';
import 'package:dio/dio.dart';

void main() {
  late OAuthStateStore stateStore;
  late JdOAuthService jdService;
  late OAuthController controller;

  setUp(() {
    stateStore = OAuthStateStore();
    jdService = JdOAuthService(
      apiClient: ApiClient(dio: Dio()),
      tokenStore: InMemoryTokenStore(),
    );
    controller = OAuthController(jdOAuthService: jdService, stateStore: stateStore);
  });

  // ──────────────────────────────────────────────────────────────
  // authorize
  // ──────────────────────────────────────────────────────────────
  group('OAuthController.authorize', () {
    test('返回 authorize_url 和 state', () {
      final result = controller.authorize(redirectUri: 'https://example.com/callback');
      expect(result.containsKey('authorize_url'), isTrue);
      expect(result.containsKey('state'), isTrue);
    });

    test('authorize_url 是合法 URI', () {
      final result = controller.authorize(redirectUri: 'https://example.com/callback');
      final url = result['authorize_url'] as String;
      expect(() => Uri.parse(url), returnsNormally);
    });

    test('authorize_url 包含京东授权端点', () {
      final result = controller.authorize(redirectUri: 'https://example.com/callback');
      final url = result['authorize_url'] as String;
      expect(url, contains('open-oauth.jd.com'));
    });

    test('state 是非空字符串', () {
      final result = controller.authorize(redirectUri: 'https://example.com/callback');
      final state = result['state'] as String;
      expect(state, isNotEmpty);
    });

    test('state 是 UUID 格式', () {
      final result = controller.authorize(redirectUri: 'https://example.com/callback');
      final state = result['state'] as String;
      // UUID v4 格式：8-4-4-4-12
      final uuidRegex = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      expect(uuidRegex.hasMatch(state), isTrue);
    });

    test('每次调用生成不同的 state', () {
      final r1 = controller.authorize(redirectUri: 'https://example.com/callback');
      final r2 = controller.authorize(redirectUri: 'https://example.com/callback');
      expect(r1['state'], isNot(equals(r2['state'])));
    });

    test('生成的 state 被保存到 stateStore 中（可消费）', () {
      final result = controller.authorize(redirectUri: 'https://example.com/callback');
      final state = result['state'] as String;
      expect(stateStore.consume(state), isTrue);
    });

    test('authorize_url 包含 redirect_uri', () {
      const redirectUri = 'https://example.com/callback';
      final result = controller.authorize(redirectUri: redirectUri);
      final url = result['authorize_url'] as String;
      expect(url, contains(Uri.encodeComponent(redirectUri)));
    });

    test('传入 scope 时 authorize_url 包含该 scope', () {
      final result = controller.authorize(
        redirectUri: 'https://example.com/callback',
        scope: 'snsapi_userinfo',
      );
      final url = result['authorize_url'] as String;
      expect(url, contains('snsapi_userinfo'));
    });

    test('不传 scope 时使用默认 scope', () {
      final result = controller.authorize(redirectUri: 'https://example.com/callback');
      final url = result['authorize_url'] as String;
      expect(url, contains('snsapi_base'));
    });

    test('authorize_url 中的 state 与返回的 state 一致', () {
      final result = controller.authorize(redirectUri: 'https://example.com/callback');
      final state = result['state'] as String;
      final url = result['authorize_url'] as String;
      expect(url, contains(state));
    });

    test('多次调用各自的 state 都可以独立消费', () {
      final r1 = controller.authorize(redirectUri: 'https://example.com/cb');
      final r2 = controller.authorize(redirectUri: 'https://example.com/cb');
      final r3 = controller.authorize(redirectUri: 'https://example.com/cb');
      expect(stateStore.consume(r1['state'] as String), isTrue);
      expect(stateStore.consume(r2['state'] as String), isTrue);
      expect(stateStore.consume(r3['state'] as String), isTrue);
    });
  });
}

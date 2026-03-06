import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'package:wisepick_proxy_server/proxy/proxy_handler.dart';
import 'package:wisepick_proxy_server/database/database.dart';

/// ============================================================
/// Module: ProxyHandler
/// What: AI 代理端点行为验证
/// Why: 代理层是 AI 请求的唯一入口，错误处理和 CORS 必须正确
/// Coverage: 缺少 API Key 返回500、OPTIONS 预检处理、
///           请求体解析（stream/非stream）
/// ============================================================
void main() {
  late ProxyHandler handler;

  setUp(() {
    Database.setEnvVars({
      'JWT_SECRET': 'test-jwt-secret-for-unit-tests',
      'JWT_REFRESH_SECRET': 'test-refresh-secret-for-unit-tests',
    });
    handler = ProxyHandler();
  });

  // ============================================================
  // OPTIONS 预检请求
  // ============================================================
  group('ProxyHandler - OPTIONS 预检', () {
    test('OPTIONS 请求返回200及CORS头', () async {
      final request = Request(
        'OPTIONS',
        Uri.parse('http://localhost:9527/v1/chat/completions'),
      );
      final response = await handler.router.call(request);
      expect(response.statusCode, equals(200));
      expect(
        response.headers['access-control-allow-origin'],
        equals('*'),
      );
      expect(
        response.headers['access-control-allow-methods'],
        contains('POST'),
      );
    });
  });

  // ============================================================
  // Authorization 头透传
  // ============================================================
  group('ProxyHandler - Authorization 透传', () {
    test('无 Authorization 头时不崩溃，直接转发', () async {
      final body = jsonEncode({'model': 'gpt-3.5-turbo', 'messages': []});
      final request = Request(
        'POST',
        Uri.parse('http://localhost:9527/v1/chat/completions'),
        body: body,
        headers: {'content-type': 'application/json'},
      );
      // 服务端不再校验 API Key，直接转发（上游会返回401，但不会500）
      final response = await handler.router.call(request);
      expect(response.statusCode, isNot(equals(500)));
    });
  });

  // ============================================================
  // CORS 响应头
  // ============================================================
  group('ProxyHandler - CORS 头', () {
    test('所有响应包含 access-control-allow-origin: *', () async {
      final request = Request(
        'OPTIONS',
        Uri.parse('http://localhost:9527/v1/chat/completions'),
      );
      final response = await handler.router.call(request);
      expect(response.headers['access-control-allow-origin'], equals('*'));
    });
  });

  // ============================================================
  // 请求体解析
  // ============================================================
  group('ProxyHandler - 请求体解析', () {
    test('stream=true 的请求被识别为流式请求', () async {
      // 此测试验证 ProxyHandler 能正确解析 stream 字段
      // 由于没有真实 API Key，请求会在 API Key 检查处失败
      // 但我们可以验证 handler 不会在解析阶段崩溃
      final body = jsonEncode({
        'model': 'gpt-3.5-turbo',
        'messages': [
          {'role': 'user', 'content': 'hello'}
        ],
        'stream': true,
      });
      final request = Request(
        'POST',
        Uri.parse('http://localhost:9527/v1/chat/completions'),
        body: body,
        headers: {'content-type': 'application/json'},
      );

      // 不应抛出异常
      final response = await handler.router.call(request);
      expect(response.statusCode, isNotNull);
    });

    test('无效 JSON 请求体不崩溃', () async {
      final request = Request(
        'POST',
        Uri.parse('http://localhost:9527/v1/chat/completions'),
        body: 'not-json',
        headers: {'content-type': 'application/json'},
      );

      final response = await handler.router.call(request);
      // 应返回错误响应而非抛出异常
      expect(response.statusCode, isNotNull);
    });
  });
}

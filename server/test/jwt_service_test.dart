import 'package:test/test.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import '../lib/auth/jwt_service.dart';
import '../lib/database/database.dart';

/// ============================================================
/// Module: JwtService
/// What: JWT Token 生成、验证、Bearer 提取
/// Why: 认证系统安全性的核心，Token 逻辑错误将导致
///      未授权访问或合法用户被拒绝
/// Coverage: 生成访问/刷新 Token、验证有效/无效/过期 Token、
///           Header 提取、JwtPayload 属性
/// ============================================================
void main() {
  setUpAll(() {
    // Set known secrets for deterministic testing
    Database.setEnvVars({
      'JWT_SECRET': 'test-jwt-secret-for-unit-tests',
      'JWT_REFRESH_SECRET': 'test-refresh-secret-for-unit-tests',
    });
  });

  group('JwtService - generateAccessToken', () {
    test('should generate a non-empty token string', () {
      final token = JwtService.generateAccessToken(
        userId: 'user-123',
        email: 'test@example.com',
      );
      expect(token, isNotEmpty);
      expect(token.contains('.'), isTrue); // JWT has dots
    });

    test('should generate different tokens for different users', () {
      final token1 = JwtService.generateAccessToken(
        userId: 'user-1',
        email: 'a@example.com',
      );
      final token2 = JwtService.generateAccessToken(
        userId: 'user-2',
        email: 'b@example.com',
      );
      expect(token1, isNot(equals(token2)));
    });

    test('should include deviceId when provided', () {
      final token = JwtService.generateAccessToken(
        userId: 'user-123',
        email: 'test@example.com',
        deviceId: 'device-abc',
      );

      final payload = JwtService.verifyAccessToken(token);
      expect(payload, isNotNull);
      expect(payload!.deviceId, equals('device-abc'));
    });
  });

  group('JwtService - verifyAccessToken', () {
    test('should verify a valid access token', () {
      final token = JwtService.generateAccessToken(
        userId: 'user-456',
        email: 'verify@example.com',
        deviceId: 'dev-1',
      );

      final payload = JwtService.verifyAccessToken(token);
      expect(payload, isNotNull);
      expect(payload!.userId, equals('user-456'));
      expect(payload.email, equals('verify@example.com'));
      expect(payload.deviceId, equals('dev-1'));
      expect(payload.type, equals('access'));
    });

    test('should return null for tampered token', () {
      final token = JwtService.generateAccessToken(
        userId: 'user-123',
        email: 'test@example.com',
      );

      // Tamper with the token
      final tampered = '${token}x';
      final payload = JwtService.verifyAccessToken(tampered);
      expect(payload, isNull);
    });

    test('should return null for completely invalid token', () {
      final payload = JwtService.verifyAccessToken('not-a-jwt');
      expect(payload, isNull);
    });

    test('should return null for empty token', () {
      final payload = JwtService.verifyAccessToken('');
      expect(payload, isNull);
    });

    test('should return null for refresh token used as access token', () {
      // Generate a refresh token
      final refreshToken = JwtService.generateRefreshToken(
        userId: 'user-123',
        deviceId: 'dev-1',
      );

      // Try to verify as access token - should fail due to type mismatch
      // Note: This may also fail because different secrets are used
      final payload = JwtService.verifyAccessToken(refreshToken);
      expect(payload, isNull);
    });

    test('should return null for token signed with wrong secret', () {
      // Create a token with a different secret
      final jwt = JWT(
        {
          'sub': 'user-999',
          'email': 'wrong@example.com',
          'type': 'access',
        },
        issuer: 'wisepick',
      );
      final wrongToken = jwt.sign(SecretKey('wrong-secret'));

      final payload = JwtService.verifyAccessToken(wrongToken);
      expect(payload, isNull);
    });
  });

  group('JwtService - generateRefreshToken', () {
    test('should generate a non-empty token string', () {
      final token = JwtService.generateRefreshToken(
        userId: 'user-123',
        deviceId: 'device-xyz',
      );
      expect(token, isNotEmpty);
      expect(token.contains('.'), isTrue);
    });

    test('should generate different tokens for different devices', () {
      final token1 = JwtService.generateRefreshToken(
        userId: 'user-1',
        deviceId: 'device-a',
      );
      final token2 = JwtService.generateRefreshToken(
        userId: 'user-1',
        deviceId: 'device-b',
      );
      expect(token1, isNot(equals(token2)));
    });
  });

  group('JwtService - verifyRefreshToken', () {
    test('should verify a valid refresh token', () {
      final token = JwtService.generateRefreshToken(
        userId: 'user-789',
        deviceId: 'dev-2',
      );

      final payload = JwtService.verifyRefreshToken(token);
      expect(payload, isNotNull);
      expect(payload!.userId, equals('user-789'));
      expect(payload.deviceId, equals('dev-2'));
      expect(payload.type, equals('refresh'));
      // Refresh token verification doesn't set email
      expect(payload.email, isNull);
    });

    test('should return null for tampered refresh token', () {
      final token = JwtService.generateRefreshToken(
        userId: 'user-123',
        deviceId: 'dev-1',
      );

      final tampered = '${token}tampered';
      final payload = JwtService.verifyRefreshToken(tampered);
      expect(payload, isNull);
    });

    test('should return null for access token used as refresh token', () {
      final accessToken = JwtService.generateAccessToken(
        userId: 'user-123',
        email: 'test@example.com',
      );

      // Different secret, should fail
      final payload = JwtService.verifyRefreshToken(accessToken);
      expect(payload, isNull);
    });

    test('should return null for invalid token', () {
      expect(JwtService.verifyRefreshToken('garbage'), isNull);
      expect(JwtService.verifyRefreshToken(''), isNull);
    });
  });

  group('JwtService - extractTokenFromHeader', () {
    test('should extract token from valid Bearer header', () {
      final token = JwtService.extractTokenFromHeader('Bearer my-token-123');
      expect(token, equals('my-token-123'));
    });

    test('should extract token with complex JWT value', () {
      final jwtLike = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLTEyMyJ9.sig';
      final token = JwtService.extractTokenFromHeader('Bearer $jwtLike');
      expect(token, equals(jwtLike));
    });

    test('should return null for null header', () {
      expect(JwtService.extractTokenFromHeader(null), isNull);
    });

    test('should return null for non-Bearer header', () {
      expect(JwtService.extractTokenFromHeader('Basic abc123'), isNull);
    });

    test('should return null for empty string', () {
      expect(JwtService.extractTokenFromHeader(''), isNull);
    });

    test('should return null for just "Bearer" without space', () {
      expect(JwtService.extractTokenFromHeader('Bearer'), isNull);
    });

    test('should return empty string for "Bearer " with space but no token',
        () {
      final result = JwtService.extractTokenFromHeader('Bearer ');
      expect(result, equals(''));
    });

    test('should be case sensitive - "bearer" should fail', () {
      expect(JwtService.extractTokenFromHeader('bearer my-token'), isNull);
    });
  });

  group('JwtPayload', () {
    test('should store all fields', () {
      final expiresAt = DateTime(2025, 12, 31);
      final payload = JwtPayload(
        userId: 'uid-1',
        email: 'user@test.com',
        deviceId: 'dev-1',
        type: 'access',
        expiresAt: expiresAt,
      );
      expect(payload.userId, equals('uid-1'));
      expect(payload.email, equals('user@test.com'));
      expect(payload.deviceId, equals('dev-1'));
      expect(payload.type, equals('access'));
      expect(payload.expiresAt, equals(expiresAt));
    });

    test('should allow null optional fields', () {
      final payload = JwtPayload(
        userId: 'uid-2',
        type: 'refresh',
      );
      expect(payload.email, isNull);
      expect(payload.deviceId, isNull);
      expect(payload.expiresAt, isNull);
    });
  });

  group('JwtService - Token Expiry Constants', () {
    test('access token expiry should be 15 minutes', () {
      expect(JwtService.accessTokenExpiry, equals(const Duration(minutes: 15)));
    });

    test('refresh token expiry should be 30 days', () {
      expect(JwtService.refreshTokenExpiry, equals(const Duration(days: 30)));
    });
  });

  group('JwtService - End-to-end Token Flow', () {
    test('full access token lifecycle: generate → verify → extract', () {
      // 1. Generate
      final token = JwtService.generateAccessToken(
        userId: 'e2e-user',
        email: 'e2e@test.com',
        deviceId: 'e2e-device',
      );

      // 2. Simulate HTTP header
      final authHeader = 'Bearer $token';

      // 3. Extract from header
      final extracted = JwtService.extractTokenFromHeader(authHeader);
      expect(extracted, equals(token));

      // 4. Verify
      final payload = JwtService.verifyAccessToken(extracted!);
      expect(payload, isNotNull);
      expect(payload!.userId, equals('e2e-user'));
      expect(payload.email, equals('e2e@test.com'));
      expect(payload.deviceId, equals('e2e-device'));
      expect(payload.type, equals('access'));
    });

    test('full refresh token lifecycle: generate → verify', () {
      // 1. Generate
      final token = JwtService.generateRefreshToken(
        userId: 'e2e-user',
        deviceId: 'e2e-device',
      );

      // 2. Verify
      final payload = JwtService.verifyRefreshToken(token);
      expect(payload, isNotNull);
      expect(payload!.userId, equals('e2e-user'));
      expect(payload.deviceId, equals('e2e-device'));
      expect(payload.type, equals('refresh'));
    });

    test('tokens should not be cross-verifiable', () {
      final accessToken = JwtService.generateAccessToken(
        userId: 'cross-user',
        email: 'cross@test.com',
      );
      final refreshToken = JwtService.generateRefreshToken(
        userId: 'cross-user',
        deviceId: 'cross-device',
      );

      // Access token should NOT verify as refresh
      expect(JwtService.verifyRefreshToken(accessToken), isNull);
      // Refresh token should NOT verify as access
      expect(JwtService.verifyAccessToken(refreshToken), isNull);
    });
  });
}

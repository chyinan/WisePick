import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import '../database/database.dart';

/// JWT Token 管理服务
class JwtService {
  // Token 有效期配置
  static const Duration accessTokenExpiry = Duration(minutes: 15);
  static const Duration refreshTokenExpiry = Duration(days: 30);

  // 从环境变量获取密钥
  static String get _jwtSecret {
    return Database.getEnv('JWT_SECRET', 'wisepick-jwt-secret-key-change-in-production');
  }

  static String get _refreshSecret =>
      Database.getEnv('JWT_REFRESH_SECRET', 'wisepick-refresh-secret-key-change-in-production');

  /// 生成 Access Token
  static String generateAccessToken({
    required String userId,
    required String email,
    String? deviceId,
  }) {
    final jwt = JWT(
      {
        'sub': userId,
        'email': email,
        'device_id': deviceId,
        'type': 'access',
      },
      issuer: 'wisepick',
      subject: userId,
    );

    return jwt.sign(
      SecretKey(_jwtSecret),
      expiresIn: accessTokenExpiry,
    );
  }

  /// 生成 Refresh Token
  static String generateRefreshToken({
    required String userId,
    required String deviceId,
  }) {
    final jwt = JWT(
      {
        'sub': userId,
        'device_id': deviceId,
        'type': 'refresh',
      },
      issuer: 'wisepick',
      subject: userId,
    );

    return jwt.sign(
      SecretKey(_refreshSecret),
      expiresIn: refreshTokenExpiry,
    );
  }

  /// 验证 Access Token
  static JwtPayload? verifyAccessToken(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(_jwtSecret));
      final payload = jwt.payload as Map<String, dynamic>;

      // 验证 token 类型
      if (payload['type'] != 'access') {
        return null;
      }

      return JwtPayload(
        userId: payload['sub'] as String,
        email: payload['email'] as String?,
        deviceId: payload['device_id'] as String?,
        type: 'access',
        expiresAt: jwt.payload is Map && jwt.payload['exp'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (jwt.payload['exp'] as int) * 1000)
            : null,
      );
    } on JWTExpiredException {
      return null;
    } on JWTException catch (e) {
      return null;
    }
  }

  /// 验证 Refresh Token
  static JwtPayload? verifyRefreshToken(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(_refreshSecret));
      final payload = jwt.payload as Map<String, dynamic>;

      // 验证 token 类型
      if (payload['type'] != 'refresh') {
        return null;
      }

      return JwtPayload(
        userId: payload['sub'] as String,
        email: null,
        deviceId: payload['device_id'] as String?,
        type: 'refresh',
        expiresAt: null,
      );
    } on JWTExpiredException {
      return null;
    } on JWTException catch (e) {
      return null;
    }
  }

  /// 从请求头提取 token
  static String? extractTokenFromHeader(String? authHeader) {
    if (authHeader == null || !authHeader.startsWith('Bearer ')) {
      return null;
    }
    return authHeader.substring(7);
  }
}

/// JWT 载荷
class JwtPayload {
  final String userId;
  final String? email;
  final String? deviceId;
  final String type;
  final DateTime? expiresAt;

  JwtPayload({
    required this.userId,
    this.email,
    this.deviceId,
    required this.type,
    this.expiresAt,
  });
}

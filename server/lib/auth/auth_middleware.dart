import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'jwt_service.dart';

/// 认证中间件 - 用于保护需要登录的路由
class AuthMiddleware {
  /// 创建一个需要认证的中间件
  /// 如果验证失败，返回 401 响应
  static Middleware requireAuth() {
    return (Handler innerHandler) {
      return (Request request) async {
        final authHeader = request.headers['authorization'];
        final token = JwtService.extractTokenFromHeader(authHeader);

        if (token == null) {
          return Response(401, 
            body: jsonEncode({
              'success': false,
              'message': '未提供认证令牌',
              'code': 'MISSING_TOKEN',
            }),
            headers: _corsHeaders,
          );
        }

        final payload = JwtService.verifyAccessToken(token);
        if (payload == null) {
          return Response(401, 
            body: jsonEncode({
              'success': false,
              'message': '无效或过期的认证令牌',
              'code': 'INVALID_TOKEN',
            }),
            headers: _corsHeaders,
          );
        }

        // 将用户信息添加到请求上下文中
        final updatedRequest = request.change(context: {
          ...request.context,
          'userId': payload.userId,
          'email': payload.email,
          'deviceId': payload.deviceId,
          'authPayload': payload,
        });

        return innerHandler(updatedRequest);
      };
    };
  }

  /// 创建一个可选认证的中间件
  /// 如果提供了 token 且有效，则添加用户信息到上下文
  /// 如果没有 token 或 token 无效，仍然继续处理请求
  static Middleware optionalAuth() {
    return (Handler innerHandler) {
      return (Request request) async {
        final authHeader = request.headers['authorization'];
        final token = JwtService.extractTokenFromHeader(authHeader);

        if (token != null) {
          final payload = JwtService.verifyAccessToken(token);
          if (payload != null) {
            final updatedRequest = request.change(context: {
              ...request.context,
              'userId': payload.userId,
              'email': payload.email,
              'deviceId': payload.deviceId,
              'authPayload': payload,
              'isAuthenticated': true,
            });
            return innerHandler(updatedRequest);
          }
        }

        // 没有认证或认证无效，继续处理但不添加用户信息
        final updatedRequest = request.change(context: {
          ...request.context,
          'isAuthenticated': false,
        });
        return innerHandler(updatedRequest);
      };
    };
  }

  /// 通用响应头
  static const _corsHeaders = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization, X-Device-Id, X-Device-Name, X-Device-Type',
  };
}

/// 从请求上下文中获取用户 ID
extension AuthRequestExtension on Request {
  /// 获取用户 ID（如果已认证）
  String? get userId => context['userId'] as String?;

  /// 获取用户邮箱（如果已认证）
  String? get userEmail => context['email'] as String?;

  /// 获取设备 ID（如果已认证）
  String? get deviceId => context['deviceId'] as String?;

  /// 获取完整的认证载荷（如果已认证）
  JwtPayload? get authPayload => context['authPayload'] as JwtPayload?;

  /// 是否已认证
  bool get isAuthenticated => context['isAuthenticated'] as bool? ?? userId != null;
}

/// 便捷函数：创建需要认证的中间件
Middleware requireAuth() => AuthMiddleware.requireAuth();

/// 便捷函数：创建可选认证的中间件
Middleware optionalAuth() => AuthMiddleware.optionalAuth();

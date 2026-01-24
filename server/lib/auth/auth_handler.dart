import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'auth_service.dart';
import 'jwt_service.dart';
import '../database/database.dart';

/// 认证 API 路由处理器
class AuthHandler {
  final AuthService _authService;

  AuthHandler(Database db) : _authService = AuthService(db);

  /// 获取路由
  Router get router {
    final router = Router();

    // 用户注册
    router.post('/register', _handleRegister);

    // 用户登录
    router.post('/login', _handleLogin);

    // 刷新 Token
    router.post('/refresh', _handleRefresh);

    // 登出（需要认证）
    router.post('/logout', _handleLogout);

    // 登出所有设备（需要认证）
    router.post('/logout-all', _handleLogoutAll);

    // 获取当前用户信息（需要认证）
    router.get('/me', _handleGetMe);

    // 获取用户会话列表（需要认证）
    router.get('/sessions', _handleGetSessions);

    // 修改密码（需要认证）
    router.post('/change-password', _handleChangePassword);

    // 更新用户资料（需要认证）
    router.put('/profile', _handleUpdateProfile);
    router.patch('/profile', _handleUpdateProfile);

    // ============================================================
    // 安全问题和密码重置相关路由
    // ============================================================
    
    // 设置安全问题（需要认证）
    router.post('/security-question', _handleSetSecurityQuestion);

    // 获取当前用户的安全问题（需要认证）
    router.get('/security-question', _handleGetSecurityQuestion);

    // 根据邮箱获取安全问题（忘记密码流程）
    router.post('/forgot-password/question', _handleGetQuestionByEmail);

    // 验证安全问题答案（忘记密码流程）
    router.post('/forgot-password/verify', _handleVerifySecurityQuestion);

    // 重置密码（使用重置令牌）
    router.post('/forgot-password/reset', _handleResetPassword);

    return router;
  }

  /// 通用响应头
  static const _corsHeaders = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization, X-Device-Id, X-Device-Name, X-Device-Type',
  };

  /// 从请求中提取客户端信息
  Map<String, String?> _extractClientInfo(Request request) {
    return {
      'ipAddress': request.headers['x-forwarded-for']?.split(',').first.trim() 
          ?? request.headers['x-real-ip'],
      'userAgent': request.headers['user-agent'],
      'deviceId': request.headers['x-device-id'],
      'deviceName': request.headers['x-device-name'],
      'deviceType': request.headers['x-device-type'],
    };
  }

  /// 从请求中验证并提取用户信息
  JwtPayload? _extractAuthPayload(Request request) {
    final authHeader = request.headers['authorization'];
    final token = JwtService.extractTokenFromHeader(authHeader);
    if (token == null) return null;
    return JwtService.verifyAccessToken(token);
  }

  /// 处理注册请求
  Future<Response> _handleRegister(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final email = data['email']?.toString();
      final password = data['password']?.toString();
      final nickname = data['nickname']?.toString();

      if (email == null || email.isEmpty) {
        return Response(400, body: jsonEncode({
          'success': false,
          'message': '邮箱不能为空',
        }), headers: _corsHeaders);
      }

      if (password == null || password.isEmpty) {
        return Response(400, body: jsonEncode({
          'success': false,
          'message': '密码不能为空',
        }), headers: _corsHeaders);
      }

      final clientInfo = _extractClientInfo(request);

      final result = await _authService.register(
        email: email,
        password: password,
        nickname: nickname,
        deviceId: clientInfo['deviceId'],
        deviceName: clientInfo['deviceName'],
        deviceType: clientInfo['deviceType'],
        ipAddress: clientInfo['ipAddress'],
        userAgent: clientInfo['userAgent'],
      );

      final statusCode = result.success ? 201 : 400;
      return Response(statusCode, 
        body: jsonEncode(result.toJson()), 
        headers: _corsHeaders,
      );
    } catch (e) {
      print('[AuthHandler] Register error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'message': '服务器错误'}),
        headers: _corsHeaders,
      );
    }
  }

  /// 处理登录请求
  Future<Response> _handleLogin(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final email = data['email']?.toString();
      final password = data['password']?.toString();

      if (email == null || email.isEmpty) {
        return Response(400, body: jsonEncode({
          'success': false,
          'message': '邮箱不能为空',
        }), headers: _corsHeaders);
      }

      if (password == null || password.isEmpty) {
        return Response(400, body: jsonEncode({
          'success': false,
          'message': '密码不能为空',
        }), headers: _corsHeaders);
      }

      final clientInfo = _extractClientInfo(request);

      final result = await _authService.login(
        email: email,
        password: password,
        deviceId: clientInfo['deviceId'],
        deviceName: clientInfo['deviceName'],
        deviceType: clientInfo['deviceType'],
        ipAddress: clientInfo['ipAddress'],
        userAgent: clientInfo['userAgent'],
      );

      final statusCode = result.success ? 200 : 401;
      return Response(statusCode, 
        body: jsonEncode(result.toJson()), 
        headers: _corsHeaders,
      );
    } catch (e) {
      print('[AuthHandler] Login error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'message': '服务器错误'}),
        headers: _corsHeaders,
      );
    }
  }

  /// 处理刷新 Token 请求
  Future<Response> _handleRefresh(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final refreshToken = data['refresh_token']?.toString();

      if (refreshToken == null || refreshToken.isEmpty) {
        return Response(400, body: jsonEncode({
          'success': false,
          'message': '刷新令牌不能为空',
        }), headers: _corsHeaders);
      }

      final clientInfo = _extractClientInfo(request);

      final result = await _authService.refreshToken(
        refreshToken: refreshToken,
        ipAddress: clientInfo['ipAddress'],
        userAgent: clientInfo['userAgent'],
      );

      final statusCode = result.success ? 200 : 401;
      return Response(statusCode, 
        body: jsonEncode(result.toJson()), 
        headers: _corsHeaders,
      );
    } catch (e) {
      print('[AuthHandler] Refresh error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'message': '服务器错误'}),
        headers: _corsHeaders,
      );
    }
  }

  /// 处理登出请求
  Future<Response> _handleLogout(Request request) async {
    try {
      final payload = _extractAuthPayload(request);
      if (payload == null) {
        return Response(401, body: jsonEncode({
          'success': false,
          'message': '未授权',
        }), headers: _corsHeaders);
      }

      final clientInfo = _extractClientInfo(request);
      final deviceId = clientInfo['deviceId'] ?? payload.deviceId;

      if (deviceId == null) {
        return Response(400, body: jsonEncode({
          'success': false,
          'message': '设备ID不能为空',
        }), headers: _corsHeaders);
      }

      final result = await _authService.logout(
        userId: payload.userId,
        deviceId: deviceId,
      );

      return Response.ok(
        jsonEncode(result.toJson()), 
        headers: _corsHeaders,
      );
    } catch (e) {
      print('[AuthHandler] Logout error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'message': '服务器错误'}),
        headers: _corsHeaders,
      );
    }
  }

  /// 处理登出所有设备请求
  Future<Response> _handleLogoutAll(Request request) async {
    try {
      final payload = _extractAuthPayload(request);
      if (payload == null) {
        return Response(401, body: jsonEncode({
          'success': false,
          'message': '未授权',
        }), headers: _corsHeaders);
      }

      final result = await _authService.logoutAll(userId: payload.userId);

      return Response.ok(
        jsonEncode(result.toJson()), 
        headers: _corsHeaders,
      );
    } catch (e) {
      print('[AuthHandler] Logout all error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'message': '服务器错误'}),
        headers: _corsHeaders,
      );
    }
  }

  /// 处理获取当前用户信息请求
  Future<Response> _handleGetMe(Request request) async {
    try {
      final payload = _extractAuthPayload(request);
      if (payload == null) {
        return Response(401, body: jsonEncode({
          'success': false,
          'message': '未授权',
        }), headers: _corsHeaders);
      }

      final user = await _authService.getUserById(payload.userId);
      if (user == null) {
        return Response(404, body: jsonEncode({
          'success': false,
          'message': '用户不存在',
        }), headers: _corsHeaders);
      }

      return Response.ok(jsonEncode({
        'success': true,
        'user': user.toJson(),
      }), headers: _corsHeaders);
    } catch (e) {
      print('[AuthHandler] Get me error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'message': '服务器错误'}),
        headers: _corsHeaders,
      );
    }
  }

  /// 处理获取用户会话列表请求
  Future<Response> _handleGetSessions(Request request) async {
    try {
      final payload = _extractAuthPayload(request);
      if (payload == null) {
        return Response(401, body: jsonEncode({
          'success': false,
          'message': '未授权',
        }), headers: _corsHeaders);
      }

      final sessions = await _authService.getUserSessions(payload.userId);

      return Response.ok(jsonEncode({
        'success': true,
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'current_device_id': payload.deviceId,
      }), headers: _corsHeaders);
    } catch (e) {
      print('[AuthHandler] Get sessions error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'message': '服务器错误'}),
        headers: _corsHeaders,
      );
    }
  }

  /// 处理修改密码请求
  Future<Response> _handleChangePassword(Request request) async {
    try {
      final payload = _extractAuthPayload(request);
      if (payload == null) {
        return Response(401, body: jsonEncode({
          'success': false,
          'message': '未授权',
        }), headers: _corsHeaders);
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final oldPassword = data['old_password']?.toString();
      final newPassword = data['new_password']?.toString();

      if (oldPassword == null || oldPassword.isEmpty) {
        return Response(400, body: jsonEncode({
          'success': false,
          'message': '原密码不能为空',
        }), headers: _corsHeaders);
      }

      if (newPassword == null || newPassword.isEmpty) {
        return Response(400, body: jsonEncode({
          'success': false,
          'message': '新密码不能为空',
        }), headers: _corsHeaders);
      }

      final result = await _authService.changePassword(
        userId: payload.userId,
        oldPassword: oldPassword,
        newPassword: newPassword,
      );

      final statusCode = result.success ? 200 : 400;
      return Response(statusCode, 
        body: jsonEncode(result.toJson()), 
        headers: _corsHeaders,
      );
    } catch (e) {
      print('[AuthHandler] Change password error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'message': '服务器错误'}),
        headers: _corsHeaders,
      );
    }
  }

  /// 处理更新用户资料请求
  Future<Response> _handleUpdateProfile(Request request) async {
    try {
      final payload = _extractAuthPayload(request);
      if (payload == null) {
        return Response(401, body: jsonEncode({
          'success': false,
          'message': '未授权',
        }), headers: _corsHeaders);
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final nickname = data['nickname']?.toString();
      final avatarUrl = data['avatar_url']?.toString();

      final result = await _authService.updateProfile(
        userId: payload.userId,
        nickname: nickname,
        avatarUrl: avatarUrl,
      );

      final statusCode = result.success ? 200 : 400;
      return Response(statusCode, 
        body: jsonEncode(result.toJson()), 
        headers: _corsHeaders,
      );
    } catch (e) {
      print('[AuthHandler] Update profile error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'message': '服务器错误'}),
        headers: _corsHeaders,
      );
    }
  }

  // ============================================================
  // 安全问题和密码重置相关处理函数
  // ============================================================

  /// 处理设置安全问题请求
  Future<Response> _handleSetSecurityQuestion(Request request) async {
    try {
      final payload = _extractAuthPayload(request);
      if (payload == null) {
        return Response(401, body: jsonEncode({
          'success': false,
          'message': '未授权',
        }), headers: _corsHeaders);
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final question = data['question']?.toString();
      final answer = data['answer']?.toString();
      final order = data['order'] as int? ?? 1;

      if (question == null || question.isEmpty) {
        return Response(400, body: jsonEncode({
          'success': false,
          'message': '安全问题不能为空',
        }), headers: _corsHeaders);
      }

      if (answer == null || answer.isEmpty) {
        return Response(400, body: jsonEncode({
          'success': false,
          'message': '安全问题答案不能为空',
        }), headers: _corsHeaders);
      }

      final result = await _authService.setSecurityQuestion(
        userId: payload.userId,
        question: question,
        answer: answer,
        questionOrder: order,
      );

      final statusCode = result.success ? 200 : 400;
      return Response(statusCode, 
        body: jsonEncode(result.toJson()), 
        headers: _corsHeaders,
      );
    } catch (e) {
      print('[AuthHandler] Set security question error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'message': '服务器错误'}),
        headers: _corsHeaders,
      );
    }
  }

  /// 处理获取当前用户安全问题请求
  Future<Response> _handleGetSecurityQuestion(Request request) async {
    try {
      final payload = _extractAuthPayload(request);
      if (payload == null) {
        return Response(401, body: jsonEncode({
          'success': false,
          'message': '未授权',
        }), headers: _corsHeaders);
      }

      final questions = await _authService.getSecurityQuestions(payload.userId);
      final hasQuestion = questions.isNotEmpty;

      return Response.ok(jsonEncode({
        'success': true,
        'has_security_question': hasQuestion,
        'questions': questions,
      }), headers: _corsHeaders);
    } catch (e) {
      print('[AuthHandler] Get security question error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'message': '服务器错误'}),
        headers: _corsHeaders,
      );
    }
  }

  /// 处理根据邮箱获取安全问题请求（忘记密码第一步）
  Future<Response> _handleGetQuestionByEmail(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final email = data['email']?.toString();

      if (email == null || email.isEmpty) {
        return Response(400, body: jsonEncode({
          'success': false,
          'message': '邮箱不能为空',
        }), headers: _corsHeaders);
      }

      final result = await _authService.getSecurityQuestionByEmail(email);

      if (result == null) {
        // 为了安全，不透露用户是否存在或是否设置了安全问题
        return Response(400, body: jsonEncode({
          'success': false,
          'message': '该邮箱未注册或未设置安全问题',
        }), headers: _corsHeaders);
      }

      return Response.ok(jsonEncode({
        'success': true,
        'questions': result['questions'],
      }), headers: _corsHeaders);
    } catch (e) {
      print('[AuthHandler] Get question by email error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'message': '服务器错误'}),
        headers: _corsHeaders,
      );
    }
  }

  /// 处理验证安全问题答案请求（忘记密码第二步）
  Future<Response> _handleVerifySecurityQuestion(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final email = data['email']?.toString();
      final answer = data['answer']?.toString();
      final order = data['order'] as int? ?? 1;

      if (email == null || email.isEmpty) {
        return Response(400, body: jsonEncode({
          'success': false,
          'message': '邮箱不能为空',
        }), headers: _corsHeaders);
      }

      if (answer == null || answer.isEmpty) {
        return Response(400, body: jsonEncode({
          'success': false,
          'message': '答案不能为空',
        }), headers: _corsHeaders);
      }

      final result = await _authService.verifySecurityQuestionAndCreateResetToken(
        email: email,
        answer: answer,
        questionOrder: order,
      );

      if (!result.success) {
        return Response(400, body: jsonEncode({
          'success': false,
          'message': result.message ?? '验证失败',
        }), headers: _corsHeaders);
      }

      return Response.ok(jsonEncode({
        'success': true,
        'message': '验证成功',
        'reset_token': result.accessToken, // 临时使用 accessToken 字段
      }), headers: _corsHeaders);
    } catch (e) {
      print('[AuthHandler] Verify security question error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'message': '服务器错误'}),
        headers: _corsHeaders,
      );
    }
  }

  /// 处理重置密码请求（忘记密码第三步）
  Future<Response> _handleResetPassword(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final resetToken = data['reset_token']?.toString();
      final newPassword = data['new_password']?.toString();

      if (resetToken == null || resetToken.isEmpty) {
        return Response(400, body: jsonEncode({
          'success': false,
          'message': '重置令牌不能为空',
        }), headers: _corsHeaders);
      }

      if (newPassword == null || newPassword.isEmpty) {
        return Response(400, body: jsonEncode({
          'success': false,
          'message': '新密码不能为空',
        }), headers: _corsHeaders);
      }

      final result = await _authService.resetPasswordWithToken(
        resetToken: resetToken,
        newPassword: newPassword,
      );

      final statusCode = result.success ? 200 : 400;
      return Response(statusCode, 
        body: jsonEncode(result.toJson()), 
        headers: _corsHeaders,
      );
    } catch (e) {
      print('[AuthHandler] Reset password error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'message': '服务器错误'}),
        headers: _corsHeaders,
      );
    }
  }
}

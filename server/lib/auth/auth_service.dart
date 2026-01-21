import 'package:dbcrypt/dbcrypt.dart';
import 'package:uuid/uuid.dart';
import '../database/database.dart';
import '../models/user.dart';
import 'jwt_service.dart';

/// 认证结果
class AuthResult {
  final bool success;
  final String? message;
  final User? user;
  final String? accessToken;
  final String? refreshToken;
  final UserSession? session;

  AuthResult({
    required this.success,
    this.message,
    this.user,
    this.accessToken,
    this.refreshToken,
    this.session,
  });

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      if (message != null) 'message': message,
      if (user != null) 'user': user!.toPublicJson(),
      if (accessToken != null) 'access_token': accessToken,
      if (refreshToken != null) 'refresh_token': refreshToken,
      if (session != null) 'session': session!.toJson(),
    };
  }

  factory AuthResult.error(String message) {
    return AuthResult(success: false, message: message);
  }

  factory AuthResult.success({
    User? user,
    String? accessToken,
    String? refreshToken,
    UserSession? session,
    String? message,
  }) {
    return AuthResult(
      success: true,
      user: user,
      accessToken: accessToken,
      refreshToken: refreshToken,
      session: session,
      message: message,
    );
  }
}

/// 认证服务
class AuthService {
  final Database _db;
  final DBCrypt _bcrypt = DBCrypt();
  final Uuid _uuid = Uuid();

  // 登录尝试限制
  static const int maxLoginAttempts = 5;
  static const Duration lockoutDuration = Duration(minutes: 15);

  AuthService(this._db);

  /// 哈希密码
  String _hashPassword(String password) {
    return _bcrypt.hashpw(password, _bcrypt.gensalt());
  }

  /// 验证密码
  bool _verifyPassword(String password, String hash) {
    try {
      return _bcrypt.checkpw(password, hash);
    } catch (e) {
      print('[AuthService] Password verification error: $e');
      return false;
    }
  }

  /// 生成设备ID（如果客户端未提供）
  String generateDeviceId() {
    return _uuid.v4();
  }

  /// 检查登录频率限制
  Future<bool> _checkLoginRateLimit(String email, String? ipAddress) async {
    try {
      final cutoffTime = DateTime.now().subtract(lockoutDuration);
      
      final result = await _db.queryOne('''
        SELECT COUNT(*) as attempts
        FROM login_attempts
        WHERE email = @email
          AND attempted_at > @cutoff
          AND success = false
      ''', parameters: {
        'email': email,
        'cutoff': cutoffTime,
      });

      final attempts = (result?['attempts'] as int?) ?? 0;
      return attempts < maxLoginAttempts;
    } catch (e) {
      print('[AuthService] Rate limit check error: $e');
      return true; // 出错时允许登录尝试
    }
  }

  /// 记录登录尝试
  Future<void> _recordLoginAttempt({
    required String email,
    required bool success,
    String? userId,
    String? ipAddress,
    String? userAgent,
    String? failureReason,
  }) async {
    try {
      await _db.execute('''
        INSERT INTO login_attempts (email, user_id, ip_address, user_agent, success, failure_reason)
        VALUES (@email, @userId, @ipAddress::inet, @userAgent, @success, @failureReason)
      ''', parameters: {
        'email': email,
        'userId': userId,
        'ipAddress': ipAddress,
        'userAgent': userAgent,
        'success': success,
        'failureReason': failureReason,
      });
    } catch (e) {
      print('[AuthService] Record login attempt error: $e');
    }
  }

  /// 用户注册
  Future<AuthResult> register({
    required String email,
    required String password,
    String? nickname,
    String? deviceId,
    String? deviceName,
    String? deviceType,
    String? ipAddress,
    String? userAgent,
  }) async {
    // 验证邮箱格式
    if (!_isValidEmail(email)) {
      return AuthResult.error('邮箱格式不正确');
    }

    // 验证密码强度
    final passwordError = _validatePassword(password);
    if (passwordError != null) {
      return AuthResult.error(passwordError);
    }

    // 检查邮箱是否已存在
    final existingUser = await _db.queryOne(
      'SELECT id FROM users WHERE email = @email',
      parameters: {'email': email.toLowerCase()},
    );
    if (existingUser != null) {
      return AuthResult.error('该邮箱已被注册');
    }

    // 创建用户
    final userId = _uuid.v4();
    final passwordHash = _hashPassword(password);
    final now = DateTime.now();
    final actualDeviceId = deviceId ?? generateDeviceId();

    try {
      await _db.execute('''
        INSERT INTO users (id, email, password_hash, nickname, created_at, updated_at)
        VALUES (@id, @email, @passwordHash, @nickname, @createdAt, @updatedAt)
      ''', parameters: {
        'id': userId,
        'email': email.toLowerCase(),
        'passwordHash': passwordHash,
        'nickname': nickname,
        'createdAt': now,
        'updatedAt': now,
      });

      // 查询创建的用户
      final userRow = await _db.queryOne(
        'SELECT * FROM users WHERE id = @id',
        parameters: {'id': userId},
      );
      if (userRow == null) {
        return AuthResult.error('用户创建失败');
      }
      final user = User.fromRow(userRow);

      // 创建会话
      final sessionResult = await _createSession(
        userId: userId,
        email: email,
        deviceId: actualDeviceId,
        deviceName: deviceName,
        deviceType: deviceType,
        ipAddress: ipAddress,
        userAgent: userAgent,
      );
      if (!sessionResult.success) {
        return sessionResult;
      }

      return AuthResult.success(
        user: user,
        accessToken: sessionResult.accessToken,
        refreshToken: sessionResult.refreshToken,
        session: sessionResult.session,
        message: '注册成功',
      );
    } catch (e) {
      print('[AuthService] Registration error: $e');
      return AuthResult.error('注册失败: ${e.toString()}');
    }
  }

  /// 用户登录
  Future<AuthResult> login({
    required String email,
    required String password,
    String? deviceId,
    String? deviceName,
    String? deviceType,
    String? ipAddress,
    String? userAgent,
  }) async {
    final emailLower = email.toLowerCase();

    // 检查登录频率限制
    final canAttempt = await _checkLoginRateLimit(emailLower, ipAddress);
    if (!canAttempt) {
      return AuthResult.error('登录尝试过于频繁，请稍后再试');
    }

    // 查找用户
    final userRow = await _db.queryOne(
      'SELECT * FROM users WHERE email = @email',
      parameters: {'email': emailLower},
    );

    if (userRow == null) {
      await _recordLoginAttempt(
        email: emailLower,
        success: false,
        ipAddress: ipAddress,
        userAgent: userAgent,
        failureReason: 'user_not_found',
      );
      return AuthResult.error('邮箱或密码错误');
    }

    final user = User.fromRow(userRow);
    final passwordHash = userRow['password_hash'] as String;

    // 检查用户状态
    if (user.status != 'active') {
      await _recordLoginAttempt(
        email: emailLower,
        success: false,
        userId: user.id,
        ipAddress: ipAddress,
        userAgent: userAgent,
        failureReason: 'account_${user.status}',
      );
      return AuthResult.error('账号已被${user.status == 'suspended' ? '暂停' : '禁用'}');
    }

    // 验证密码
    if (!_verifyPassword(password, passwordHash)) {
      await _recordLoginAttempt(
        email: emailLower,
        success: false,
        userId: user.id,
        ipAddress: ipAddress,
        userAgent: userAgent,
        failureReason: 'wrong_password',
      );
      return AuthResult.error('邮箱或密码错误');
    }

    // 记录成功登录
    await _recordLoginAttempt(
      email: emailLower,
      success: true,
      userId: user.id,
      ipAddress: ipAddress,
      userAgent: userAgent,
    );

    // 更新最后登录时间
    await _db.execute('''
      UPDATE users SET last_login_at = @now, updated_at = @now WHERE id = @id
    ''', parameters: {
      'now': DateTime.now(),
      'id': user.id,
    });

    // 创建会话
    final actualDeviceId = deviceId ?? generateDeviceId();
    final sessionResult = await _createSession(
      userId: user.id,
      email: emailLower,
      deviceId: actualDeviceId,
      deviceName: deviceName,
      deviceType: deviceType,
      ipAddress: ipAddress,
      userAgent: userAgent,
    );

    if (!sessionResult.success) {
      return sessionResult;
    }

    return AuthResult.success(
      user: user,
      accessToken: sessionResult.accessToken,
      refreshToken: sessionResult.refreshToken,
      session: sessionResult.session,
      message: '登录成功',
    );
  }

  /// 创建会话
  Future<AuthResult> _createSession({
    required String userId,
    required String email,
    required String deviceId,
    String? deviceName,
    String? deviceType,
    String? ipAddress,
    String? userAgent,
  }) async {
    try {
      // 检查是否已有该设备的会话，如果有则更新
      final existingSession = await _db.queryOne('''
        SELECT id FROM user_sessions
        WHERE user_id = @userId AND device_id = @deviceId AND is_active = true
      ''', parameters: {
        'userId': userId,
        'deviceId': deviceId,
      });

      final sessionId = existingSession?['id'] as String? ?? _uuid.v4();
      final accessToken = JwtService.generateAccessToken(
        userId: userId,
        email: email,
        deviceId: deviceId,
      );
      final refreshToken = JwtService.generateRefreshToken(
        userId: userId,
        deviceId: deviceId,
      );
      final now = DateTime.now();

      if (existingSession != null) {
        // 更新现有会话
        await _db.execute('''
          UPDATE user_sessions
          SET refresh_token = @refreshToken,
              last_active_at = @now,
              ip_address = @ipAddress::inet,
              user_agent = @userAgent
          WHERE id = @id
        ''', parameters: {
          'id': sessionId,
          'refreshToken': refreshToken,
          'now': now,
          'ipAddress': ipAddress,
          'userAgent': userAgent,
        });
      } else {
        // 创建新会话
        await _db.execute('''
          INSERT INTO user_sessions (id, user_id, device_id, device_name, device_type, refresh_token, ip_address, user_agent, last_active_at, created_at)
          VALUES (@id, @userId, @deviceId, @deviceName, @deviceType, @refreshToken, @ipAddress::inet, @userAgent, @now, @now)
        ''', parameters: {
          'id': sessionId,
          'userId': userId,
          'deviceId': deviceId,
          'deviceName': deviceName,
          'deviceType': deviceType,
          'refreshToken': refreshToken,
          'ipAddress': ipAddress,
          'userAgent': userAgent,
          'now': now,
        });
      }

      // 查询会话
      final sessionRow = await _db.queryOne(
        'SELECT * FROM user_sessions WHERE id = @id',
        parameters: {'id': sessionId},
      );

      return AuthResult.success(
        accessToken: accessToken,
        refreshToken: refreshToken,
        session: sessionRow != null ? UserSession.fromRow(sessionRow) : null,
      );
    } catch (e) {
      print('[AuthService] Create session error: $e');
      return AuthResult.error('创建会话失败');
    }
  }

  /// 刷新 Token
  Future<AuthResult> refreshToken({
    required String refreshToken,
    String? ipAddress,
    String? userAgent,
  }) async {
    // 验证 refresh token
    final payload = JwtService.verifyRefreshToken(refreshToken);
    if (payload == null) {
      return AuthResult.error('无效或过期的刷新令牌');
    }

    // 查找会话
    final sessionRow = await _db.queryOne('''
      SELECT * FROM user_sessions
      WHERE user_id = @userId
        AND device_id = @deviceId
        AND refresh_token = @refreshToken
        AND is_active = true
    ''', parameters: {
      'userId': payload.userId,
      'deviceId': payload.deviceId,
      'refreshToken': refreshToken,
    });

    if (sessionRow == null) {
      return AuthResult.error('会话不存在或已失效');
    }

    // 查找用户
    final userRow = await _db.queryOne(
      'SELECT * FROM users WHERE id = @id AND status = @status',
      parameters: {'id': payload.userId, 'status': 'active'},
    );

    if (userRow == null) {
      return AuthResult.error('用户不存在或已被禁用');
    }

    final user = User.fromRow(userRow);
    final session = UserSession.fromRow(sessionRow);

    // 生成新的 tokens
    final newAccessToken = JwtService.generateAccessToken(
      userId: user.id,
      email: user.email,
      deviceId: session.deviceId,
    );
    final newRefreshToken = JwtService.generateRefreshToken(
      userId: user.id,
      deviceId: session.deviceId,
    );

    // 更新会话
    await _db.execute('''
      UPDATE user_sessions
      SET refresh_token = @newRefreshToken,
          last_active_at = @now,
          ip_address = COALESCE(@ipAddress::inet, ip_address),
          user_agent = COALESCE(@userAgent, user_agent)
      WHERE id = @id
    ''', parameters: {
      'id': session.id,
      'newRefreshToken': newRefreshToken,
      'now': DateTime.now(),
      'ipAddress': ipAddress,
      'userAgent': userAgent,
    });

    return AuthResult.success(
      user: user,
      accessToken: newAccessToken,
      refreshToken: newRefreshToken,
    );
  }

  /// 登出（单设备）
  Future<AuthResult> logout({
    required String userId,
    required String deviceId,
  }) async {
    try {
      await _db.execute('''
        UPDATE user_sessions
        SET is_active = false
        WHERE user_id = @userId AND device_id = @deviceId
      ''', parameters: {
        'userId': userId,
        'deviceId': deviceId,
      });

      return AuthResult.success(message: '已登出');
    } catch (e) {
      print('[AuthService] Logout error: $e');
      return AuthResult.error('登出失败');
    }
  }

  /// 登出所有设备
  Future<AuthResult> logoutAll({required String userId}) async {
    try {
      await _db.execute('''
        UPDATE user_sessions
        SET is_active = false
        WHERE user_id = @userId
      ''', parameters: {'userId': userId});

      return AuthResult.success(message: '已从所有设备登出');
    } catch (e) {
      print('[AuthService] Logout all error: $e');
      return AuthResult.error('登出失败');
    }
  }

  /// 获取用户信息
  Future<User?> getUserById(String userId) async {
    final row = await _db.queryOne(
      'SELECT * FROM users WHERE id = @id',
      parameters: {'id': userId},
    );
    return row != null ? User.fromRow(row) : null;
  }

  /// 获取用户的所有活跃会话
  Future<List<UserSession>> getUserSessions(String userId) async {
    final rows = await _db.queryAll('''
      SELECT * FROM user_sessions
      WHERE user_id = @userId AND is_active = true
      ORDER BY last_active_at DESC
    ''', parameters: {'userId': userId});

    return rows.map((row) => UserSession.fromRow(row)).toList();
  }

  /// 验证邮箱格式
  bool _isValidEmail(String email) {
    final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return regex.hasMatch(email);
  }

  /// 验证密码强度
  String? _validatePassword(String password) {
    if (password.length < 8) {
      return '密码长度至少为8位';
    }
    if (!password.contains(RegExp(r'[a-zA-Z]'))) {
      return '密码必须包含字母';
    }
    if (!password.contains(RegExp(r'[0-9]'))) {
      return '密码必须包含数字';
    }
    return null;
  }

  /// 修改密码
  Future<AuthResult> changePassword({
    required String userId,
    required String oldPassword,
    required String newPassword,
  }) async {
    // 验证新密码强度
    final passwordError = _validatePassword(newPassword);
    if (passwordError != null) {
      return AuthResult.error(passwordError);
    }

    // 获取用户
    final userRow = await _db.queryOne(
      'SELECT * FROM users WHERE id = @id',
      parameters: {'id': userId},
    );
    if (userRow == null) {
      return AuthResult.error('用户不存在');
    }

    // 验证旧密码
    final oldHash = userRow['password_hash'] as String;
    if (!_verifyPassword(oldPassword, oldHash)) {
      return AuthResult.error('原密码错误');
    }

    // 更新密码
    final newHash = _hashPassword(newPassword);
    await _db.execute('''
      UPDATE users
      SET password_hash = @hash, updated_at = @now
      WHERE id = @id
    ''', parameters: {
      'id': userId,
      'hash': newHash,
      'now': DateTime.now(),
    });

    // 登出所有其他设备（安全考虑）
    // 可选：保留当前设备

    return AuthResult.success(message: '密码修改成功');
  }

  /// 更新用户资料
  Future<AuthResult> updateProfile({
    required String userId,
    String? nickname,
    String? avatarUrl,
  }) async {
    try {
      final updates = <String>[];
      final params = <String, dynamic>{'id': userId, 'now': DateTime.now()};

      if (nickname != null) {
        updates.add('nickname = @nickname');
        params['nickname'] = nickname;
      }
      if (avatarUrl != null) {
        updates.add('avatar_url = @avatarUrl');
        params['avatarUrl'] = avatarUrl;
      }

      if (updates.isEmpty) {
        return AuthResult.error('没有要更新的内容');
      }

      updates.add('updated_at = @now');

      await _db.execute('''
        UPDATE users
        SET ${updates.join(', ')}
        WHERE id = @id
      ''', parameters: params);

      final user = await getUserById(userId);
      return AuthResult.success(user: user, message: '资料更新成功');
    } catch (e) {
      print('[AuthService] Update profile error: $e');
      return AuthResult.error('更新失败');
    }
  }
}

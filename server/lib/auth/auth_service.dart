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

    // 检查邮箱是否已存在（排除已删除的用户）
    final existingUser = await _db.queryOne(
      'SELECT id, status FROM users WHERE email = @email',
      parameters: {'email': email.toLowerCase()},
    );
    if (existingUser != null) {
      final status = existingUser['status'] as String?;
      if (status == 'deleted') {
        // 如果用户已被删除，先硬删除旧记录再允许注册
        await _hardDeleteUser(existingUser['id'] as String);
      } else {
        return AuthResult.error('该邮箱已被注册');
      }
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
      // 检查是否已有该设备的会话（包括不活跃的），如果有则更新
      final existingSession = await _db.queryOne('''
        SELECT id FROM user_sessions
        WHERE user_id = @userId AND device_id = @deviceId
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
        // 更新现有会话（重新激活并更新 token）
        await _db.execute('''
          UPDATE user_sessions
          SET refresh_token = @refreshToken,
              last_active_at = @now,
              ip_address = @ipAddress::inet,
              user_agent = @userAgent,
              is_active = true
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
    // 基本格式验证
    final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,10}$');
    if (!regex.hasMatch(email)) {
      return false;
    }

    // 提取域名部分
    final domain = email.split('@').last.toLowerCase();
    
    // 常见有效顶级域名白名单
    const validTLDs = {
      'com', 'cn', 'net', 'org', 'edu', 'gov', 'io', 'co', 'me', 'info',
      'biz', 'cc', 'tv', 'app', 'dev', 'xyz', 'top', 'vip', 'club', 'shop',
      'online', 'site', 'tech', 'store', 'blog', 'live', 'pro', 'cloud',
      // 国家/地区域名
      'uk', 'de', 'fr', 'jp', 'kr', 'ru', 'br', 'in', 'au', 'ca', 'hk', 'tw',
      // 二级域名
      'com.cn', 'net.cn', 'org.cn', 'edu.cn', 'gov.cn', 'ac.cn',
      'co.uk', 'co.jp', 'co.kr', 'com.hk', 'com.tw',
    };

    // 常见拼写错误黑名单
    const invalidDomains = {
      'qq.oom', 'qq.coom', 'qq.comm', 'qq.con', 'qq.cm',
      'gmail.oom', 'gmail.coom', 'gmail.comm', 'gmail.con', 'gmail.cm',
      '163.oom', '163.coom', '163.comm', '163.con', '163.cm',
      '126.oom', '126.coom', '126.comm', '126.con', '126.cm',
      'outlook.oom', 'outlook.coom', 'outlook.comm', 'outlook.con',
      'hotmail.oom', 'hotmail.coom', 'hotmail.comm', 'hotmail.con',
      'yahoo.oom', 'yahoo.coom', 'yahoo.comm', 'yahoo.con',
      'icloud.oom', 'icloud.coom', 'icloud.comm', 'icloud.con',
    };

    // 检查是否在黑名单中
    if (invalidDomains.contains(domain)) {
      return false;
    }

    // 提取顶级域名
    final tld = domain.contains('.') ? domain.split('.').last : domain;
    
    // 检查二级域名（如 com.cn）
    final parts = domain.split('.');
    if (parts.length >= 2) {
      final tld2 = '${parts[parts.length - 2]}.${parts.last}';
      if (validTLDs.contains(tld2)) {
        return true;
      }
    }

    // 检查顶级域名是否有效
    return validTLDs.contains(tld);
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

  // ============================================================
  // 安全问题相关方法
  // ============================================================

  /// 设置安全问题（注册时或之后设置）
  Future<AuthResult> setSecurityQuestion({
    required String userId,
    required String question,
    required String answer,
    int questionOrder = 1,
  }) async {
    if (question.isEmpty) {
      return AuthResult.error('安全问题不能为空');
    }
    if (answer.isEmpty) {
      return AuthResult.error('安全问题答案不能为空');
    }
    if (answer.length < 2) {
      return AuthResult.error('答案至少需要2个字符');
    }

    try {
      // 将答案转为小写后再哈希，以便验证时不区分大小写
      final answerHash = _hashPassword(answer.toLowerCase().trim());

      // 使用 upsert 来创建或更新安全问题
      await _db.execute('''
        INSERT INTO user_security_questions (user_id, question, answer_hash, question_order)
        VALUES (@userId, @question, @answerHash, @order)
        ON CONFLICT (user_id, question_order)
        DO UPDATE SET question = @question, answer_hash = @answerHash, updated_at = NOW()
      ''', parameters: {
        'userId': userId,
        'question': question.trim(),
        'answerHash': answerHash,
        'order': questionOrder,
      });

      return AuthResult.success(message: '安全问题设置成功');
    } catch (e) {
      print('[AuthService] Set security question error: $e');
      return AuthResult.error('设置安全问题失败');
    }
  }

  /// 获取用户的安全问题（不包含答案）
  Future<List<Map<String, dynamic>>> getSecurityQuestions(String userId) async {
    try {
      final rows = await _db.queryAll('''
        SELECT question, question_order
        FROM user_security_questions
        WHERE user_id = @userId
        ORDER BY question_order
      ''', parameters: {'userId': userId});

      return rows.map((row) => {
        'question': row['question'] as String,
        'order': row['question_order'] as int,
      }).toList();
    } catch (e) {
      print('[AuthService] Get security questions error: $e');
      return [];
    }
  }

  /// 根据邮箱获取安全问题（用于忘记密码流程）
  Future<Map<String, dynamic>?> getSecurityQuestionByEmail(String email) async {
    try {
      final user = await _db.queryOne(
        'SELECT id FROM users WHERE email = @email AND status = @status',
        parameters: {'email': email.toLowerCase(), 'status': 'active'},
      );

      if (user == null) {
        return null;
      }

      final userId = user['id'] as String;
      final questions = await getSecurityQuestions(userId);

      if (questions.isEmpty) {
        return null;
      }

      return {
        'user_id': userId,
        'questions': questions,
      };
    } catch (e) {
      print('[AuthService] Get security question by email error: $e');
      return null;
    }
  }

  /// 验证安全问题答案
  Future<bool> verifySecurityAnswer({
    required String userId,
    required String answer,
    int questionOrder = 1,
  }) async {
    try {
      final row = await _db.queryOne('''
        SELECT answer_hash
        FROM user_security_questions
        WHERE user_id = @userId AND question_order = @order
      ''', parameters: {
        'userId': userId,
        'order': questionOrder,
      });

      if (row == null) {
        return false;
      }

      final answerHash = row['answer_hash'] as String;
      // 验证时也转为小写
      return _verifyPassword(answer.toLowerCase().trim(), answerHash);
    } catch (e) {
      print('[AuthService] Verify security answer error: $e');
      return false;
    }
  }

  /// 验证安全问题并创建密码重置令牌
  Future<AuthResult> verifySecurityQuestionAndCreateResetToken({
    required String email,
    required String answer,
    int questionOrder = 1,
  }) async {
    try {
      // 查找用户
      final user = await _db.queryOne(
        'SELECT id FROM users WHERE email = @email AND status = @status',
        parameters: {'email': email.toLowerCase(), 'status': 'active'},
      );

      if (user == null) {
        // 为了安全，不透露用户是否存在
        return AuthResult.error('邮箱或安全问题答案错误');
      }

      final userId = user['id'] as String;

      // 验证安全问题答案
      final isValid = await verifySecurityAnswer(
        userId: userId,
        answer: answer,
        questionOrder: questionOrder,
      );

      if (!isValid) {
        return AuthResult.error('安全问题答案错误');
      }

      // 生成重置令牌
      final resetToken = _uuid.v4();
      final expiresAt = DateTime.now().add(const Duration(minutes: 15));

      // 删除该用户的旧重置令牌
      await _db.execute('''
        DELETE FROM password_reset_tokens WHERE user_id = @userId
      ''', parameters: {'userId': userId});

      // 创建新的重置令牌
      await _db.execute('''
        INSERT INTO password_reset_tokens (user_id, token, verified, expires_at)
        VALUES (@userId, @token, true, @expiresAt)
      ''', parameters: {
        'userId': userId,
        'token': resetToken,
        'expiresAt': expiresAt,
      });

      return AuthResult.success(
        message: '验证成功',
        accessToken: resetToken, // 临时使用 accessToken 字段返回重置令牌
      );
    } catch (e) {
      print('[AuthService] Verify and create reset token error: $e');
      return AuthResult.error('验证失败');
    }
  }

  /// 使用重置令牌重置密码
  Future<AuthResult> resetPasswordWithToken({
    required String resetToken,
    required String newPassword,
  }) async {
    // 验证新密码强度
    final passwordError = _validatePassword(newPassword);
    if (passwordError != null) {
      return AuthResult.error(passwordError);
    }

    try {
      // 查找并验证重置令牌
      final tokenRow = await _db.queryOne('''
        SELECT user_id, verified, expires_at, used_at
        FROM password_reset_tokens
        WHERE token = @token
      ''', parameters: {'token': resetToken});

      if (tokenRow == null) {
        return AuthResult.error('无效的重置令牌');
      }

      final verified = tokenRow['verified'] as bool? ?? false;
      final expiresAt = tokenRow['expires_at'] as DateTime;
      final usedAt = tokenRow['used_at'] as DateTime?;

      if (!verified) {
        return AuthResult.error('重置令牌未验证');
      }

      if (usedAt != null) {
        return AuthResult.error('重置令牌已使用');
      }

      if (DateTime.now().isAfter(expiresAt)) {
        return AuthResult.error('重置令牌已过期');
      }

      final userId = tokenRow['user_id'] as String;

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

      // 标记令牌为已使用
      await _db.execute('''
        UPDATE password_reset_tokens
        SET used_at = @now
        WHERE token = @token
      ''', parameters: {
        'token': resetToken,
        'now': DateTime.now(),
      });

      // 登出所有设备（安全考虑）
      await logoutAll(userId: userId);

      return AuthResult.success(message: '密码重置成功，请重新登录');
    } catch (e) {
      print('[AuthService] Reset password with token error: $e');
      return AuthResult.error('密码重置失败');
    }
  }

  /// 检查用户是否设置了安全问题
  Future<bool> hasSecurityQuestion(String userId) async {
    try {
      final row = await _db.queryOne('''
        SELECT COUNT(*) as count
        FROM user_security_questions
        WHERE user_id = @userId
      ''', parameters: {'userId': userId});

      return (row?['count'] as int? ?? 0) > 0;
    } catch (e) {
      print('[AuthService] Check security question error: $e');
      return false;
    }
  }

  /// 硬删除用户（彻底删除所有相关数据）
  /// 用于清理已软删除的用户，以便邮箱可以重新注册
  Future<void> _hardDeleteUser(String userId) async {
    try {
      print('[AuthService] Hard deleting user: $userId');
      
      // 删除顺序很重要，需要先删除外键依赖的表
      // 1. 删除密码重置令牌
      await _db.execute(
        'DELETE FROM password_reset_tokens WHERE user_id = @userId',
        parameters: {'userId': userId},
      );
      
      // 2. 删除安全问题
      await _db.execute(
        'DELETE FROM user_security_questions WHERE user_id = @userId',
        parameters: {'userId': userId},
      );
      
      // 3. 删除消息（通过会话）
      await _db.execute('''
        DELETE FROM messages WHERE conversation_id IN (
          SELECT id FROM conversations WHERE user_id = @userId
        )
      ''', parameters: {'userId': userId});
      
      // 4. 删除会话记录
      await _db.execute(
        'DELETE FROM conversations WHERE user_id = @userId',
        parameters: {'userId': userId},
      );
      
      // 5. 删除购物车
      await _db.execute(
        'DELETE FROM cart_items WHERE user_id = @userId',
        parameters: {'userId': userId},
      );
      
      // 6. 删除同步版本记录
      await _db.execute(
        'DELETE FROM sync_versions WHERE user_id = @userId',
        parameters: {'userId': userId},
      );
      
      // 7. 删除用户会话
      await _db.execute(
        'DELETE FROM user_sessions WHERE user_id = @userId',
        parameters: {'userId': userId},
      );
      
      // 8. 最后删除用户
      await _db.execute(
        'DELETE FROM users WHERE id = @userId',
        parameters: {'userId': userId},
      );
      
      print('[AuthService] User hard deleted successfully: $userId');
    } catch (e) {
      print('[AuthService] Hard delete user error: $e');
      // 不抛出异常，让注册流程继续
    }
  }
}

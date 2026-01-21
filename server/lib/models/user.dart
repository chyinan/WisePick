/// 用户模型
class User {
  final String id;
  final String email;
  final String? nickname;
  final String? avatarUrl;
  final bool emailVerified;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLoginAt;
  final String status;

  User({
    required this.id,
    required this.email,
    this.nickname,
    this.avatarUrl,
    this.emailVerified = false,
    required this.createdAt,
    required this.updatedAt,
    this.lastLoginAt,
    this.status = 'active',
  });

  /// 从数据库行创建
  factory User.fromRow(Map<String, dynamic> row) {
    return User(
      id: row['id'] as String,
      email: row['email'] as String,
      nickname: row['nickname'] as String?,
      avatarUrl: row['avatar_url'] as String?,
      emailVerified: row['email_verified'] as bool? ?? false,
      createdAt: row['created_at'] as DateTime,
      updatedAt: row['updated_at'] as DateTime,
      lastLoginAt: row['last_login_at'] as DateTime?,
      status: row['status'] as String? ?? 'active',
    );
  }

  /// 转换为 JSON（不包含敏感信息）
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'nickname': nickname,
      'avatar_url': avatarUrl,
      'email_verified': emailVerified,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_login_at': lastLoginAt?.toIso8601String(),
      'status': status,
    };
  }

  /// 转换为简洁 JSON（用于公开 API）
  Map<String, dynamic> toPublicJson() {
    return {
      'id': id,
      'email': email,
      'nickname': nickname,
      'avatar_url': avatarUrl,
      'email_verified': emailVerified,
    };
  }
}

/// 用户会话模型
class UserSession {
  final String id;
  final String userId;
  final String deviceId;
  final String? deviceName;
  final String? deviceType;
  final String refreshToken;
  final String? pushToken;
  final DateTime lastActiveAt;
  final DateTime createdAt;
  final String? ipAddress;
  final String? userAgent;
  final bool isActive;

  UserSession({
    required this.id,
    required this.userId,
    required this.deviceId,
    this.deviceName,
    this.deviceType,
    required this.refreshToken,
    this.pushToken,
    required this.lastActiveAt,
    required this.createdAt,
    this.ipAddress,
    this.userAgent,
    this.isActive = true,
  });

  /// 从数据库行创建
  factory UserSession.fromRow(Map<String, dynamic> row) {
    return UserSession(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      deviceId: row['device_id'] as String,
      deviceName: row['device_name'] as String?,
      deviceType: row['device_type'] as String?,
      refreshToken: row['refresh_token'] as String,
      pushToken: row['push_token'] as String?,
      lastActiveAt: row['last_active_at'] as DateTime,
      createdAt: row['created_at'] as DateTime,
      ipAddress: row['ip_address']?.toString(),
      userAgent: row['user_agent'] as String?,
      isActive: row['is_active'] as bool? ?? true,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'device_id': deviceId,
      'device_name': deviceName,
      'device_type': deviceType,
      'last_active_at': lastActiveAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'is_active': isActive,
    };
  }
}

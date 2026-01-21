/// 用户模型 (前端)
class User {
  final String id;
  final String email;
  final String? nickname;
  final String? avatarUrl;
  final bool emailVerified;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastLoginAt;
  final String status;

  User({
    required this.id,
    required this.email,
    this.nickname,
    this.avatarUrl,
    this.emailVerified = false,
    this.createdAt,
    this.updatedAt,
    this.lastLoginAt,
    this.status = 'active',
  });

  /// 从 JSON 创建
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      nickname: json['nickname'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      emailVerified: json['email_verified'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      lastLoginAt: json['last_login_at'] != null
          ? DateTime.tryParse(json['last_login_at'] as String)
          : null,
      status: json['status'] as String? ?? 'active',
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'nickname': nickname,
      'avatar_url': avatarUrl,
      'email_verified': emailVerified,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'last_login_at': lastLoginAt?.toIso8601String(),
      'status': status,
    };
  }

  /// 复制并修改
  User copyWith({
    String? id,
    String? email,
    String? nickname,
    String? avatarUrl,
    bool? emailVerified,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastLoginAt,
    String? status,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      nickname: nickname ?? this.nickname,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      emailVerified: emailVerified ?? this.emailVerified,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      status: status ?? this.status,
    );
  }

  /// 显示名称（优先昵称，否则邮箱前缀）
  String get displayName {
    if (nickname != null && nickname!.isNotEmpty) {
      return nickname!;
    }
    final atIndex = email.indexOf('@');
    return atIndex > 0 ? email.substring(0, atIndex) : email;
  }

  @override
  String toString() => 'User(id: $id, email: $email, nickname: $nickname)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is User && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// 用户会话模型
class UserSession {
  final String id;
  final String deviceId;
  final String? deviceName;
  final String? deviceType;
  final DateTime lastActiveAt;
  final DateTime createdAt;
  final bool isActive;
  final bool isCurrentDevice;

  UserSession({
    required this.id,
    required this.deviceId,
    this.deviceName,
    this.deviceType,
    required this.lastActiveAt,
    required this.createdAt,
    this.isActive = true,
    this.isCurrentDevice = false,
  });

  factory UserSession.fromJson(Map<String, dynamic> json, {String? currentDeviceId}) {
    final deviceId = json['device_id'] as String;
    return UserSession(
      id: json['id'] as String,
      deviceId: deviceId,
      deviceName: json['device_name'] as String?,
      deviceType: json['device_type'] as String?,
      lastActiveAt: DateTime.parse(json['last_active_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      isActive: json['is_active'] as bool? ?? true,
      isCurrentDevice: currentDeviceId != null && deviceId == currentDeviceId,
    );
  }

  /// 设备类型图标
  String get deviceIcon {
    switch (deviceType?.toLowerCase()) {
      case 'ios':
      case 'iphone':
      case 'ipad':
        return '📱';
      case 'android':
        return '🤖';
      case 'web':
        return '🌐';
      case 'windows':
        return '💻';
      case 'macos':
      case 'mac':
        return '🍎';
      case 'linux':
        return '🐧';
      default:
        return '📱';
    }
  }

  /// 显示名称
  String get displayName {
    if (deviceName != null && deviceName!.isNotEmpty) {
      return deviceName!;
    }
    return deviceType ?? '未知设备';
  }
}

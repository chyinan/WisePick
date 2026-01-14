/// Cookie 数据模型
class CookieData {
  /// Cookie 字符串
  final String cookie;

  /// 保存时间
  final DateTime savedAt;

  /// 预估过期时间
  final DateTime? expiresAt;

  /// 最后验证时间
  final DateTime? lastValidatedAt;

  /// 是否已验证有效
  final bool? isValid;

  CookieData({
    required this.cookie,
    required this.savedAt,
    this.expiresAt,
    this.lastValidatedAt,
    this.isValid,
  });

  /// 从 JSON Map 创建实例
  factory CookieData.fromJson(Map<String, dynamic> json) {
    return CookieData(
      cookie: json['cookie'] as String,
      savedAt: DateTime.parse(json['savedAt'] as String),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      lastValidatedAt: json['lastValidatedAt'] != null
          ? DateTime.parse(json['lastValidatedAt'] as String)
          : null,
      isValid: json['isValid'] as bool?,
    );
  }

  /// 转换为 JSON Map
  Map<String, dynamic> toJson() => {
        'cookie': cookie,
        'savedAt': savedAt.toIso8601String(),
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
        if (lastValidatedAt != null)
          'lastValidatedAt': lastValidatedAt!.toIso8601String(),
        if (isValid != null) 'isValid': isValid,
      };

  /// 检查 Cookie 是否可能已过期（基于预估过期时间）
  bool get isPossiblyExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// 获取 Cookie 的存活天数
  int get ageInDays {
    return DateTime.now().difference(savedAt).inDays;
  }

  /// 创建一个更新了验证状态的副本
  CookieData copyWith({
    String? cookie,
    DateTime? savedAt,
    DateTime? expiresAt,
    DateTime? lastValidatedAt,
    bool? isValid,
  }) {
    return CookieData(
      cookie: cookie ?? this.cookie,
      savedAt: savedAt ?? this.savedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      lastValidatedAt: lastValidatedAt ?? this.lastValidatedAt,
      isValid: isValid ?? this.isValid,
    );
  }

  @override
  String toString() {
    return 'CookieData(savedAt: $savedAt, expiresAt: $expiresAt, ageInDays: $ageInDays)';
  }
}

/// 单个 Cookie 项
class CookieItem {
  final String name;
  final String value;
  final String domain;
  final String path;
  final DateTime? expires;
  final bool httpOnly;
  final bool secure;

  CookieItem({
    required this.name,
    required this.value,
    this.domain = '.jd.com',
    this.path = '/',
    this.expires,
    this.httpOnly = false,
    this.secure = true,
  });

  /// 从 Cookie 字符串的单个部分解析
  factory CookieItem.fromString(String part, {String domain = '.jd.com'}) {
    final trimmed = part.trim();
    if (trimmed.isEmpty || !trimmed.contains('=')) {
      throw FormatException('Invalid cookie format: $part');
    }

    final equalIndex = trimmed.indexOf('=');
    final name = trimmed.substring(0, equalIndex).trim();
    final value = trimmed.substring(equalIndex + 1).trim();

    return CookieItem(
      name: name,
      value: value,
      domain: domain,
    );
  }

  /// 转换为 Map 格式（用于 Puppeteer）
  Map<String, dynamic> toMap() => {
        'name': name,
        'value': value,
        'domain': domain,
        'path': path,
        if (expires != null) 'expires': expires!.millisecondsSinceEpoch ~/ 1000,
        'httpOnly': httpOnly,
        'secure': secure,
      };

  @override
  String toString() => '$name=$value';
}











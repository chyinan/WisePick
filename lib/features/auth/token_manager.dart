import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Token 管理器 - 安全存储和管理认证 Token
class TokenManager {
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _deviceIdKey = 'device_id';
  static const String _userDataKey = 'user_data';
  static const String _tokenExpiryKey = 'token_expiry';

  // 使用 FlutterSecureStorage 存储敏感数据
  final FlutterSecureStorage _secureStorage;
  
  // 缓存的 tokens（减少读取次数）
  String? _cachedAccessToken;
  String? _cachedRefreshToken;
  String? _cachedDeviceId;
  DateTime? _cachedTokenExpiry;

  TokenManager._() : _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static final TokenManager _instance = TokenManager._();
  static TokenManager get instance => _instance;

  /// 初始化 Token 管理器
  Future<void> init() async {
    // 预加载缓存
    _cachedAccessToken = await _secureStorage.read(key: _accessTokenKey);
    _cachedRefreshToken = await _secureStorage.read(key: _refreshTokenKey);
    _cachedDeviceId = await _secureStorage.read(key: _deviceIdKey);
    
    final expiryStr = await _secureStorage.read(key: _tokenExpiryKey);
    if (expiryStr != null) {
      _cachedTokenExpiry = DateTime.tryParse(expiryStr);
    }

    // 确保有设备 ID
    if (_cachedDeviceId == null) {
      _cachedDeviceId = const Uuid().v4();
      await _secureStorage.write(key: _deviceIdKey, value: _cachedDeviceId);
    }
  }

  /// 获取设备 ID
  String get deviceId => _cachedDeviceId ?? const Uuid().v4();

  /// 获取设备名称
  String get deviceName {
    if (kIsWeb) return 'Web Browser';
    try {
      if (Platform.isAndroid) return 'Android Device';
      if (Platform.isIOS) return 'iOS Device';
      if (Platform.isMacOS) return 'macOS';
      if (Platform.isWindows) return 'Windows';
      if (Platform.isLinux) return 'Linux';
    } catch (_) {}
    return 'Unknown Device';
  }

  /// 获取设备类型
  String get deviceType {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
      if (Platform.isMacOS) return 'macos';
      if (Platform.isWindows) return 'windows';
      if (Platform.isLinux) return 'linux';
    } catch (_) {}
    return 'unknown';
  }

  /// 获取 Access Token
  String? get accessToken => _cachedAccessToken;

  /// 获取 Refresh Token
  String? get refreshToken => _cachedRefreshToken;

  /// 是否已登录
  bool get isLoggedIn => _cachedAccessToken != null && _cachedAccessToken!.isNotEmpty;

  /// Access Token 是否过期
  bool get isAccessTokenExpired {
    if (_cachedTokenExpiry == null) return true;
    // 提前 1 分钟认为过期，以便有时间刷新
    return DateTime.now().isAfter(_cachedTokenExpiry!.subtract(const Duration(minutes: 1)));
  }

  /// 保存 Tokens
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    Duration accessTokenExpiry = const Duration(minutes: 15),
  }) async {
    _cachedAccessToken = accessToken;
    _cachedRefreshToken = refreshToken;
    _cachedTokenExpiry = DateTime.now().add(accessTokenExpiry);

    await Future.wait([
      _secureStorage.write(key: _accessTokenKey, value: accessToken),
      _secureStorage.write(key: _refreshTokenKey, value: refreshToken),
      _secureStorage.write(key: _tokenExpiryKey, value: _cachedTokenExpiry!.toIso8601String()),
    ]);
  }

  /// 更新 Access Token（刷新后）
  Future<void> updateAccessToken(String accessToken, {Duration expiry = const Duration(minutes: 15)}) async {
    _cachedAccessToken = accessToken;
    _cachedTokenExpiry = DateTime.now().add(expiry);

    await Future.wait([
      _secureStorage.write(key: _accessTokenKey, value: accessToken),
      _secureStorage.write(key: _tokenExpiryKey, value: _cachedTokenExpiry!.toIso8601String()),
    ]);
  }

  /// 保存用户数据到本地缓存（非敏感数据用 Hive）
  Future<void> saveUserData(Map<String, dynamic> userData) async {
    try {
      final box = await Hive.openBox('auth');
      await box.put(_userDataKey, jsonEncode(userData));
    } catch (_) {
      // 静默处理保存错误
    }
  }

  /// 获取缓存的用户数据
  Future<Map<String, dynamic>?> getCachedUserData() async {
    try {
      final box = await Hive.openBox('auth');
      final data = box.get(_userDataKey);
      if (data != null && data is String) {
        return jsonDecode(data) as Map<String, dynamic>;
      }
    } catch (_) {
      // 静默处理读取错误
    }
    return null;
  }

  /// 清除所有认证数据（登出）
  Future<void> clearAll() async {
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    _cachedTokenExpiry = null;

    await Future.wait([
      _secureStorage.delete(key: _accessTokenKey),
      _secureStorage.delete(key: _refreshTokenKey),
      _secureStorage.delete(key: _tokenExpiryKey),
    ]);

    // 清除用户缓存
    try {
      final box = await Hive.openBox('auth');
      await box.delete(_userDataKey);
    } catch (_) {}
  }

  /// 获取授权头
  Map<String, String> getAuthHeaders() {
    final headers = <String, String>{
      'X-Device-Id': deviceId,
      'X-Device-Name': deviceName,
      'X-Device-Type': deviceType,
    };

    if (_cachedAccessToken != null && _cachedAccessToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_cachedAccessToken';
    }

    return headers;
  }
}

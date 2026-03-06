import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:hive_flutter/hive_flutter.dart';

import 'storage/hive_config.dart';

/// 集中式后端地址解析器
///
/// 所有需要连接后端的客户端服务都应使用此类来获取后端基础 URL，
/// 而非各自硬编码 `http://localhost:9527`。
///
/// 解析优先级：
/// 1. Hive settings box 中的 `backend_base` 键（用户在管理设置中配置）
/// 2. 环境变量 `BACKEND_BASE`
/// 3. 编译期常量 `BACKEND_BASE`（通过 --dart-define 传入）
/// 4. 默认值 `http://localhost:9527`（仅用于本地开发）
class BackendConfig {
  static const String _defaultBase = 'http://localhost:9527';
  static const String _settingsBoxName = 'settings';
  static const String _settingsKey = 'backend_base';

  /// 缓存已解析的 URL，避免每次都读取 Hive
  static String? _cachedBase;
  static DateTime? _cacheTime;
  static const Duration _cacheTtl = Duration(seconds: 30);

  BackendConfig._();

  /// 同步获取后端基础 URL（需确保 Hive 已初始化）
  ///
  /// 适用于已知 Hive 处于 open 状态的场景（如应用启动后）。
  /// 如果 Hive 尚未初始化，将回退到环境变量和默认值。
  static String resolveSync() {
    // 使用短期缓存避免频繁 I/O
    if (_cachedBase != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheTtl) {
        return _cachedBase!;
      }
    }

    String result = _defaultBase;

    // 1. 尝试从 Hive 读取
    try {
      if (Hive.isBoxOpen(_settingsBoxName)) {
        final box = Hive.box(_settingsBoxName);
        final String? b = box.get(_settingsKey) as String?;
        if (b != null && b.trim().isNotEmpty) {
          result = b.trim();
          _updateCache(result);
          return result;
        }
      }
    } catch (e, st) {
      dev.log('Error reading Hive settings for backend base: $e', name: 'BackendConfig', error: e, stackTrace: st);
    }

    // 2. 尝试环境变量
    try {
      final envBase = Platform.environment['BACKEND_BASE'];
      if (envBase != null && envBase.trim().isNotEmpty) {
        result = envBase.trim();
        _updateCache(result);
        return result;
      }
    } catch (e, st) {
      // Platform.environment 在 Web 上不可用，忽略
      dev.log('Platform.environment not available: $e', name: 'BackendConfig', error: e, stackTrace: st);
    }

    // 3. 编译期常量
    const compileTimeBase =
        String.fromEnvironment('BACKEND_BASE', defaultValue: '');
    if (compileTimeBase.isNotEmpty) {
      result = compileTimeBase;
      _updateCache(result);
      return result;
    }

    // 4. 默认值
    _updateCache(result);
    return result;
  }

  /// 异步获取后端基础 URL（会确保 Hive box 已打开）
  ///
  /// 推荐在首次使用时调用，以确保 Hive 已正确初始化。
  static Future<String> resolve() async {
    // 使用短期缓存
    if (_cachedBase != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheTtl) {
        return _cachedBase!;
      }
    }

    // 1. 尝试从 Hive 读取
    try {
      final box = await HiveConfig.getBox(HiveConfig.settingsBox);
      final String? b = box.get(_settingsKey) as String?;
      if (b != null && b.trim().isNotEmpty) {
        final result = b.trim();
        _updateCache(result);
        return result;
      }
    } catch (e, st) {
      dev.log('Error resolving backend base async from Hive: $e', name: 'BackendConfig', error: e, stackTrace: st);
    }

    // 2-4: 同步回退
    return resolveSync();
  }

  /// 使缓存失效（在用户更改设置后调用）
  static void invalidateCache() {
    _cachedBase = null;
    _cacheTime = null;
  }

  static void _updateCache(String value) {
    _cachedBase = value;
    _cacheTime = DateTime.now();
  }

  /// 验证后端URL是否安全（防止SSRF攻击）
  ///
  /// [allowPrivate] 为 true 时允许内网/本地地址（开发模式下使用）。
  /// 返回 null 表示验证通过，返回错误信息字符串表示验证失败。
  static String? validateBackendUrl(String url, {bool allowPrivate = false}) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return 'URL不能为空';

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasAuthority) return 'URL格式无效';

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'URL必须使用 http 或 https 协议';
    }

    final host = uri.host.toLowerCase();
    if (host.isEmpty) return 'URL缺少主机名';

    if (!allowPrivate) {
      if (host == 'localhost' || host == '::1') {
        return '生产环境不允许使用本地地址';
      }
      final ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
      final m = ipv4.firstMatch(host);
      if (m != null) {
        final a = int.parse(m.group(1)!);
        final b = int.parse(m.group(2)!);
        if (a == 127) return '不允许使用回环地址（127.x.x.x）';
        if (a == 10) return '不允许使用内网地址（10.x.x.x）';
        if (a == 172 && b >= 16 && b <= 31) return '不允许使用内网地址（172.16-31.x.x）';
        if (a == 192 && b == 168) return '不允许使用内网地址（192.168.x.x）';
      }
    }

    if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
      return '端口号必须在 1-65535 范围内';
    }

    return null;
  }

  /// 检查当前解析到的后端地址是否仍为开发默认值
  static bool isDefaultDevelopmentUrl() {
    final current = resolveSync();
    return current == _defaultBase ||
        current.contains('localhost') ||
        current.contains('127.0.0.1');
  }

  /// 已经发出过警告的标记，避免重复日志刷屏
  static bool _hasWarnedDefault = false;

  /// 在非 debug 模式下检查后端地址是否仍为默认开发值，
  /// 如果是则发出一次性警告日志。应在应用启动时调用。
  static void warnIfDefaultInProduction() {
    if (_hasWarnedDefault) return;
    if (kDebugMode) return; // debug 模式不警告

    if (isDefaultDevelopmentUrl()) {
      _hasWarnedDefault = true;
      dev.log(
        '⚠️  后端地址仍为开发默认值 ($_defaultBase)。'
        '在生产环境中请通过管理设置、环境变量 BACKEND_BASE 或 --dart-define 配置真实后端地址。',
        name: 'BackendConfig',
      );
    }
  }
}

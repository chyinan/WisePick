import 'dart:convert';
import 'dart:io';

import 'models/cookie_data.dart';
import 'models/scraper_error.dart';

/// 京东联盟 Cookie 管理器
///
/// 负责 Cookie 的存储、读取、解析和有效性管理
class CookieManager {
  /// Cookie 存储路径
  final String cookiePath;

  /// Cookie 备份路径
  final String backupPath;

  /// 预估的 Cookie 有效期（天）
  final int estimatedExpiryDays;

  /// 内存缓存的 Cookie 数据
  CookieData? _cachedCookie;

  /// 上次 Cookie 检查结果
  bool? _lastCheckResult;

  /// 上次检查时间
  DateTime? _lastCheckTime;

  CookieManager({
    String? cookiePath,
    String? backupPath,
    this.estimatedExpiryDays = 14,
  })  : cookiePath = cookiePath ?? 'data/jd_cookies.json',
        backupPath = backupPath ?? 'data/jd_cookies_backup.json';

  /// 加载 Cookie
  ///
  /// 从文件加载 Cookie，如果文件不存在返回 null
  Future<CookieData?> loadCookie() async {
    // 如果有内存缓存，直接返回
    if (_cachedCookie != null) {
      return _cachedCookie;
    }

    try {
      final file = File(cookiePath);
      if (!await file.exists()) {
        _log('Cookie 文件不存在: $cookiePath');
        return null;
      }

      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      _cachedCookie = CookieData.fromJson(data);

      _log('成功加载 Cookie，保存于: ${_cachedCookie!.savedAt}');
      return _cachedCookie;
    } catch (e, stack) {
      _log('加载 Cookie 失败: $e');
      throw ScraperException.unknown(e, stack);
    }
  }

  /// 获取 Cookie 字符串
  ///
  /// 便捷方法，直接返回 Cookie 字符串或 null
  Future<String?> getCookieString() async {
    final data = await loadCookie();
    return data?.cookie;
  }

  /// 保存 Cookie
  ///
  /// 保存新的 Cookie 并自动备份旧的
  Future<void> saveCookie(String cookie) async {
    try {
      // 确保目录存在
      final dir = Directory(_getDirectory(cookiePath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        _log('创建目录: ${dir.path}');
      }

      // 备份旧 Cookie
      final oldFile = File(cookiePath);
      if (await oldFile.exists()) {
        await oldFile.copy(backupPath);
        _log('已备份旧 Cookie 到: $backupPath');
      }

      // 创建新的 Cookie 数据
      final data = CookieData(
        cookie: cookie,
        savedAt: DateTime.now(),
        expiresAt: DateTime.now().add(Duration(days: estimatedExpiryDays)),
      );

      // 保存到文件
      final jsonString = const JsonEncoder.withIndent('  ').convert(data.toJson());
      await File(cookiePath).writeAsString(jsonString, encoding: utf8);

      // 更新内存缓存
      _cachedCookie = data;
      _lastCheckResult = null; // 重置检查状态

      _log('Cookie 保存成功');
    } catch (e, stack) {
      _log('保存 Cookie 失败: $e');
      throw ScraperException.unknown(e, stack);
    }
  }

  /// 解析 Cookie 字符串为 Cookie 项列表
  ///
  /// 将 "name1=value1; name2=value2" 格式的字符串解析为 [CookieItem] 列表
  List<CookieItem> parseCookieString(String cookieString) {
    final cookies = <CookieItem>[];

    for (final part in cookieString.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;

      try {
        final item = CookieItem.fromString(trimmed);
        cookies.add(item);
      } catch (e) {
        // 跳过无效的 Cookie 项
        _log('跳过无效的 Cookie 项: $trimmed');
      }
    }

    _log('解析得到 ${cookies.length} 个 Cookie 项');
    return cookies;
  }

  /// 将 Cookie 项列表转换为 Puppeteer 格式
  ///
  /// 返回可直接用于 page.setCookie 的 Map 列表
  List<Map<String, dynamic>> toPuppeteerFormat(List<CookieItem> cookies) {
    return cookies.map((c) => c.toMap()).toList();
  }

  /// 从字符串直接获取 Puppeteer 格式的 Cookie
  ///
  /// 便捷方法，组合了解析和格式转换
  List<Map<String, dynamic>> parseForPuppeteer(String cookieString) {
    final items = parseCookieString(cookieString);
    return toPuppeteerFormat(items);
  }

  /// 更新 Cookie 验证状态
  ///
  /// 当验证 Cookie 有效性后调用此方法更新状态
  Future<void> updateValidationStatus(bool isValid) async {
    _lastCheckResult = isValid;
    _lastCheckTime = DateTime.now();

    if (_cachedCookie != null) {
      _cachedCookie = _cachedCookie!.copyWith(
        lastValidatedAt: DateTime.now(),
        isValid: isValid,
      );

      // 同步更新到文件
      try {
        final jsonString =
            const JsonEncoder.withIndent('  ').convert(_cachedCookie!.toJson());
        await File(cookiePath).writeAsString(jsonString, encoding: utf8);
      } catch (e) {
        _log('更新验证状态到文件失败: $e');
      }
    }

    if (!isValid) {
      _log('Cookie 验证失败，可能已过期');
    }
  }

  /// 检查是否需要验证 Cookie
  ///
  /// 如果距离上次验证超过指定时间，则需要重新验证
  bool needsValidation({Duration checkInterval = const Duration(hours: 1)}) {
    if (_lastCheckTime == null) return true;
    return DateTime.now().difference(_lastCheckTime!) > checkInterval;
  }

  /// 获取上次验证结果
  bool? get lastValidationResult => _lastCheckResult;

  /// 清除内存缓存
  void clearCache() {
    _cachedCookie = null;
    _lastCheckResult = null;
    _lastCheckTime = null;
    _log('已清除 Cookie 缓存');
  }

  /// 删除 Cookie 文件
  Future<void> deleteCookie() async {
    try {
      final file = File(cookiePath);
      if (await file.exists()) {
        await file.delete();
        _log('已删除 Cookie 文件');
      }
      clearCache();
    } catch (e) {
      _log('删除 Cookie 文件失败: $e');
    }
  }

  /// 获取 Cookie 状态摘要
  Future<Map<String, dynamic>> getStatus() async {
    final data = await loadCookie();
    return {
      'exists': data != null,
      'savedAt': data?.savedAt.toIso8601String(),
      'expiresAt': data?.expiresAt?.toIso8601String(),
      'ageInDays': data?.ageInDays,
      'isPossiblyExpired': data?.isPossiblyExpired ?? true,
      'lastValidatedAt': data?.lastValidatedAt?.toIso8601String(),
      'isValid': data?.isValid,
      'needsValidation': needsValidation(),
    };
  }

  /// 从环境变量或默认值加载 Cookie
  ///
  /// 优先使用文件中的 Cookie，如果不存在则尝试从环境变量加载
  Future<String?> loadCookieWithFallback() async {
    // 首先尝试从文件加载
    var cookieString = await getCookieString();
    if (cookieString != null && cookieString.isNotEmpty) {
      return cookieString;
    }

    // 尝试从环境变量加载
    final envCookie = Platform.environment['JD_COOKIE'];
    if (envCookie != null && envCookie.isNotEmpty) {
      _log('从环境变量加载 Cookie');
      await saveCookie(envCookie);
      return envCookie;
    }

    _log('未找到可用的 Cookie');
    return null;
  }

  // ==================== 私有方法 ====================

  /// 获取路径的目录部分
  String _getDirectory(String path) {
    final lastSep = path.lastIndexOf(Platform.pathSeparator);
    if (lastSep == -1) {
      final lastSlash = path.lastIndexOf('/');
      if (lastSlash == -1) return '.';
      return path.substring(0, lastSlash);
    }
    return path.substring(0, lastSep);
  }

  /// 日志输出
  void _log(String message) {
    print('[CookieManager] $message');
  }
}











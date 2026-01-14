import 'dart:convert';
import 'dart:io';

import 'models/scraper_error.dart';

/// 日志级别
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// 错误日志条目
class ErrorEntry {
  final String id;
  final ScraperErrorType type;
  final String message;
  final String? skuId;
  final DateTime timestamp;
  final Map<String, dynamic> details;

  ErrorEntry({
    required this.id,
    required this.type,
    required this.message,
    this.skuId,
    required this.timestamp,
    this.details = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'message': message,
        if (skuId != null) 'skuId': skuId,
        'timestamp': timestamp.toIso8601String(),
        'details': details,
      };
}

/// 爬虫日志记录器
///
/// 提供日志记录和错误追踪功能
class ScraperLogger {
  /// 日志目录
  final String logDir;

  /// 最小日志级别
  final LogLevel minLevel;

  /// 是否输出到控制台
  final bool consoleOutput;

  /// 是否写入文件
  final bool fileOutput;

  /// 当前日志文件
  File? _currentLogFile;

  /// 当前日志日期
  String? _currentLogDate;

  ScraperLogger({
    String? logDir,
    this.minLevel = LogLevel.info,
    this.consoleOutput = true,
    this.fileOutput = true,
  }) : logDir = logDir ?? 'data/scraper_logs' {
    if (fileOutput) {
      _ensureLogDirectory();
    }
  }

  /// 确保日志目录存在
  void _ensureLogDirectory() {
    final dir = Directory(logDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  /// 记录日志
  void log(
    LogLevel level,
    String message, {
    Map<String, dynamic>? context,
    String? module,
  }) {
    if (level.index < minLevel.index) return;

    final timestamp = DateTime.now();
    final logEntry = {
      'timestamp': timestamp.toIso8601String(),
      'level': level.name.toUpperCase(),
      'message': message,
      if (module != null) 'module': module,
      if (context != null) 'context': context,
    };

    // 控制台输出
    if (consoleOutput) {
      final prefix = module != null ? '[$module]' : '';
      final levelStr = '[${level.name.toUpperCase()}]';
      print('$levelStr $prefix $message');
    }

    // 文件输出
    if (fileOutput) {
      _writeToFile(logEntry, timestamp);
    }
  }

  /// 写入日志文件
  void _writeToFile(Map<String, dynamic> logEntry, DateTime timestamp) {
    try {
      final dateStr = timestamp.toIso8601String().split('T')[0];

      // 如果日期变化，创建新文件
      if (_currentLogDate != dateStr) {
        _currentLogDate = dateStr;
        _currentLogFile = File('$logDir/scraper_$dateStr.log');
      }

      _currentLogFile?.writeAsStringSync(
        '${jsonEncode(logEntry)}\n',
        mode: FileMode.append,
      );
    } catch (e) {
      // 忽略日志写入错误
    }
  }

  // 便捷方法
  void debug(String message, {Map<String, dynamic>? context, String? module}) =>
      log(LogLevel.debug, message, context: context, module: module);

  void info(String message, {Map<String, dynamic>? context, String? module}) =>
      log(LogLevel.info, message, context: context, module: module);

  void warning(String message,
          {Map<String, dynamic>? context, String? module}) =>
      log(LogLevel.warning, message, context: context, module: module);

  void error(String message,
      {Map<String, dynamic>? context, String? module, Object? error}) {
    final errorContext = {
      if (context != null) ...context,
      if (error != null) 'error': error.toString(),
    };
    log(LogLevel.error, message, context: errorContext, module: module);
  }
}

/// 错误处理器
///
/// 负责错误识别、分类、记录和通知
class ErrorHandler {
  /// 日志记录器
  final ScraperLogger logger;

  /// 错误历史记录
  final List<ErrorEntry> _errors = [];

  /// 最大错误记录数
  final int maxErrors;

  /// Cookie 过期回调
  final Future<void> Function()? onCookieExpired;

  /// 反爬虫检测回调
  final Future<void> Function()? onAntiBotDetected;

  /// 错误计数器（用于统计）
  final Map<ScraperErrorType, int> _errorCounts = {};

  ErrorHandler({
    ScraperLogger? logger,
    this.maxErrors = 1000,
    this.onCookieExpired,
    this.onAntiBotDetected,
  }) : logger = logger ?? ScraperLogger();

  /// 识别错误类型
  ScraperErrorType identifyError(dynamic error, {String? pageUrl}) {
    if (error is ScraperException) {
      return error.type;
    }

    final errorStr = error.toString().toLowerCase();

    // Cookie 过期检测
    if (errorStr.contains('cookie') ||
        errorStr.contains('login') ||
        errorStr.contains('登录') ||
        errorStr.contains('未登录')) {
      return ScraperErrorType.cookieExpired;
    }

    // 反爬虫检测
    if (errorStr.contains('验证码') ||
        errorStr.contains('captcha') ||
        errorStr.contains('频繁') ||
        errorStr.contains('blocked') ||
        errorStr.contains('forbidden')) {
      return ScraperErrorType.antiBotDetected;
    }

    // 网络错误
    if (errorStr.contains('network') ||
        errorStr.contains('socket') ||
        errorStr.contains('connection') ||
        errorStr.contains('refused')) {
      return ScraperErrorType.networkError;
    }

    // 超时错误
    if (errorStr.contains('timeout') || errorStr.contains('超时')) {
      return ScraperErrorType.timeout;
    }

    // URL 检查
    if (pageUrl != null) {
      if (pageUrl.contains('passport') || pageUrl.contains('login')) {
        return ScraperErrorType.cookieExpired;
      }
    }

    return ScraperErrorType.unknown;
  }

  /// 处理错误
  Future<void> handleError(
    dynamic error, {
    String? skuId,
    String? pageUrl,
    Map<String, dynamic>? details,
  }) async {
    final errorType = identifyError(error, pageUrl: pageUrl);

    // 记录错误
    await logError(
      errorType,
      error.toString(),
      skuId: skuId,
      details: {
        if (pageUrl != null) 'pageUrl': pageUrl,
        if (details != null) ...details,
      },
    );

    // 触发回调
    switch (errorType) {
      case ScraperErrorType.cookieExpired:
        if (onCookieExpired != null) {
          await onCookieExpired!();
        }
        break;
      case ScraperErrorType.antiBotDetected:
        if (onAntiBotDetected != null) {
          await onAntiBotDetected!();
        }
        break;
      default:
        break;
    }
  }

  /// 记录错误
  Future<void> logError(
    ScraperErrorType type,
    String message, {
    String? skuId,
    Map<String, dynamic>? details,
  }) async {
    final error = ErrorEntry(
      id: _generateErrorId(),
      type: type,
      message: message,
      skuId: skuId,
      timestamp: DateTime.now(),
      details: details ?? {},
    );

    // 添加到历史记录
    _errors.add(error);
    if (_errors.length > maxErrors) {
      _errors.removeAt(0);
    }

    // 更新统计
    _errorCounts[type] = (_errorCounts[type] ?? 0) + 1;

    // 记录到日志
    logger.error(
      'Scraper error: ${type.name} - $message',
      context: {
        'errorId': error.id,
        'skuId': skuId,
        'details': details,
      },
      module: 'ErrorHandler',
    );
  }

  /// 获取错误历史
  List<ErrorEntry> getErrors({
    ScraperErrorType? type,
    int? limit,
    DateTime? since,
  }) {
    var errors = List<ErrorEntry>.from(_errors);

    if (type != null) {
      errors = errors.where((e) => e.type == type).toList();
    }

    if (since != null) {
      errors = errors.where((e) => e.timestamp.isAfter(since)).toList();
    }

    errors.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (limit != null) {
      errors = errors.take(limit).toList();
    }

    return errors;
  }

  /// 获取错误统计
  Map<String, dynamic> getStatistics() {
    final now = DateTime.now();
    final last24h = now.subtract(const Duration(hours: 24));
    final lastHour = now.subtract(const Duration(hours: 1));

    return {
      'total': _errors.length,
      'byType': _errorCounts.map((k, v) => MapEntry(k.name, v)),
      'last24h': _errors.where((e) => e.timestamp.isAfter(last24h)).length,
      'lastHour': _errors.where((e) => e.timestamp.isAfter(lastHour)).length,
    };
  }

  /// 清除错误历史
  void clearErrors() {
    _errors.clear();
    _errorCounts.clear();
    logger.info('Error history cleared', module: 'ErrorHandler');
  }

  /// 生成错误 ID
  String _generateErrorId() {
    return 'err_${DateTime.now().millisecondsSinceEpoch}_${_errors.length}';
  }
}

/// 性能监控器
///
/// 监控请求性能和统计数据
class PerformanceMonitor {
  /// 请求时长记录
  final Map<String, List<Duration>> _requestDurations = {};

  /// 请求计数
  final Map<String, int> _requestCounts = {};

  /// 错误计数
  final Map<String, int> _errorCounts = {};

  /// 最大记录数
  final int maxRecords;

  PerformanceMonitor({this.maxRecords = 1000});

  /// 记录请求
  void recordRequest(String endpoint, Duration duration) {
    _requestDurations.putIfAbsent(endpoint, () => []).add(duration);
    _requestCounts[endpoint] = (_requestCounts[endpoint] ?? 0) + 1;

    // 限制记录数量
    final durations = _requestDurations[endpoint]!;
    if (durations.length > maxRecords) {
      durations.removeAt(0);
    }
  }

  /// 记录错误
  void recordError(String endpoint) {
    _errorCounts[endpoint] = (_errorCounts[endpoint] ?? 0) + 1;
  }

  /// 获取端点统计
  Map<String, dynamic> getStats(String endpoint) {
    final durations = _requestDurations[endpoint] ?? [];
    if (durations.isEmpty) {
      return {
        'endpoint': endpoint,
        'count': 0,
        'avgDuration': 0,
        'minDuration': 0,
        'maxDuration': 0,
        'errorCount': _errorCounts[endpoint] ?? 0,
      };
    }

    final sortedDurations = List<Duration>.from(durations)..sort();
    final sum =
        durations.fold<int>(0, (sum, d) => sum + d.inMilliseconds);

    return {
      'endpoint': endpoint,
      'count': durations.length,
      'avgDuration': (sum / durations.length).round(),
      'minDuration': sortedDurations.first.inMilliseconds,
      'maxDuration': sortedDurations.last.inMilliseconds,
      'p50': sortedDurations[durations.length ~/ 2].inMilliseconds,
      'p95': sortedDurations[(durations.length * 0.95).round().clamp(0, durations.length - 1)]
          .inMilliseconds,
      'errorCount': _errorCounts[endpoint] ?? 0,
      'errorRate': (_errorCounts[endpoint] ?? 0) / durations.length,
    };
  }

  /// 获取所有统计
  Map<String, dynamic> getAllStats() {
    final endpoints = {
      ..._requestDurations.keys,
      ..._requestCounts.keys,
      ..._errorCounts.keys,
    };

    return {
      'endpoints': endpoints.map((e) => getStats(e)).toList(),
      'totalRequests':
          _requestCounts.values.fold<int>(0, (sum, c) => sum + c),
      'totalErrors': _errorCounts.values.fold<int>(0, (sum, c) => sum + c),
    };
  }

  /// 重置统计
  void reset() {
    _requestDurations.clear();
    _requestCounts.clear();
    _errorCounts.clear();
  }
}











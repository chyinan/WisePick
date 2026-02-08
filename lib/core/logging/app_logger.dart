import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 日志级别
enum LogLevel {
  trace(0, 'TRACE'),
  debug(1, 'DEBUG'),
  info(2, 'INFO'),
  warning(3, 'WARN'),
  error(4, 'ERROR'),
  fatal(5, 'FATAL');

  final int value;
  final String label;

  const LogLevel(this.value, this.label);
}

/// 日志条目
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? module;
  final Map<String, dynamic>? context;
  final Object? error;
  final StackTrace? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.module,
    this.context,
    this.error,
    this.stackTrace,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'level': level.label,
        'message': message,
        if (module != null) 'module': module,
        if (context != null) 'context': context,
        if (error != null) 'error': error.toString(),
        if (stackTrace != null) 'stackTrace': stackTrace.toString(),
      };

  String toFormattedString({bool includeTimestamp = true, bool colored = false}) {
    final buffer = StringBuffer();

    if (includeTimestamp) {
      buffer.write(_formatTimestamp(timestamp));
      buffer.write(' ');
    }

    final levelStr = colored ? _coloredLevel(level) : '[${level.label}]';
    buffer.write(levelStr);

    if (module != null) {
      buffer.write(' [$module]');
    }

    buffer.write(' $message');

    if (context != null && context!.isNotEmpty) {
      buffer.write(' ${jsonEncode(context)}');
    }

    if (error != null) {
      buffer.write('\n  Error: $error');
    }

    if (stackTrace != null) {
      buffer.write('\n  Stack: ${_formatStackTrace(stackTrace!)}');
    }

    return buffer.toString();
  }

  String _formatTimestamp(DateTime ts) {
    return '${ts.hour.toString().padLeft(2, '0')}:'
        '${ts.minute.toString().padLeft(2, '0')}:'
        '${ts.second.toString().padLeft(2, '0')}.'
        '${ts.millisecond.toString().padLeft(3, '0')}';
  }

  String _coloredLevel(LogLevel level) {
    // ANSI color codes
    switch (level) {
      case LogLevel.trace:
        return '\x1B[90m[TRACE]\x1B[0m'; // Gray
      case LogLevel.debug:
        return '\x1B[36m[DEBUG]\x1B[0m'; // Cyan
      case LogLevel.info:
        return '\x1B[32m[INFO]\x1B[0m'; // Green
      case LogLevel.warning:
        return '\x1B[33m[WARN]\x1B[0m'; // Yellow
      case LogLevel.error:
        return '\x1B[31m[ERROR]\x1B[0m'; // Red
      case LogLevel.fatal:
        return '\x1B[35m[FATAL]\x1B[0m'; // Magenta
    }
  }

  String _formatStackTrace(StackTrace stack) {
    final lines = stack.toString().split('\n');
    if (lines.length <= 5) {
      return lines.join('\n    ');
    }
    return '${lines.take(5).join('\n    ')}\n    ... ${lines.length - 5} more lines';
  }
}

/// 日志输出目标接口
abstract class LogOutput {
  void write(LogEntry entry);
  Future<void> flush();
  Future<void> close();
}

/// 控制台日志输出
class ConsoleLogOutput implements LogOutput {
  final bool useColors;
  final bool includeTimestamp;

  ConsoleLogOutput({
    this.useColors = true,
    this.includeTimestamp = true,
  });

  @override
  void write(LogEntry entry) {
    final output = entry.toFormattedString(
      includeTimestamp: includeTimestamp,
      colored: useColors,
    );

    if (entry.level.value >= LogLevel.error.value) {
      stderr.writeln(output);
    } else {
      stdout.writeln(output);
    }
  }

  @override
  Future<void> flush() async {
    await stdout.flush();
    await stderr.flush();
  }

  @override
  Future<void> close() async {}
}

/// 文件日志输出
class FileLogOutput implements LogOutput {
  final String logDirectory;
  final String filePrefix;
  final int maxFileSizeBytes;
  final int maxFiles;
  final bool jsonFormat;

  IOSink? _currentSink;
  String? _currentFilePath;
  int _currentFileSize = 0;

  FileLogOutput({
    required this.logDirectory,
    this.filePrefix = 'app',
    this.maxFileSizeBytes = 10 * 1024 * 1024, // 10MB
    this.maxFiles = 5,
    this.jsonFormat = false,
  });

  @override
  void write(LogEntry entry) {
    _ensureFileReady();

    final output = jsonFormat
        ? '${jsonEncode(entry.toJson())}\n'
        : '${entry.toFormattedString()}\n';

    _currentSink?.write(output);
    _currentFileSize += output.length;

    // 检查文件大小
    if (_currentFileSize >= maxFileSizeBytes) {
      _rotateFiles();
    }
  }

  void _ensureFileReady() {
    if (_currentSink != null) return;

    final dir = Directory(logDirectory);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final date = DateTime.now().toIso8601String().split('T')[0];
    _currentFilePath = '$logDirectory/${filePrefix}_$date.log';
    _currentSink = File(_currentFilePath!).openWrite(mode: FileMode.append);
    _currentFileSize = 0;
  }

  void _rotateFiles() {
    _currentSink?.close();
    _currentSink = null;

    // 删除旧文件
    final dir = Directory(logDirectory);
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains(filePrefix))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    while (files.length >= maxFiles) {
      files.removeLast().deleteSync();
    }

    _ensureFileReady();
  }

  @override
  Future<void> flush() async {
    await _currentSink?.flush();
  }

  @override
  Future<void> close() async {
    await _currentSink?.close();
    _currentSink = null;
  }
}

/// 内存日志输出（用于测试和调试）
class MemoryLogOutput implements LogOutput {
  final int maxEntries;
  final List<LogEntry> _entries = [];

  MemoryLogOutput({this.maxEntries = 1000});

  List<LogEntry> get entries => List.unmodifiable(_entries);

  @override
  void write(LogEntry entry) {
    _entries.add(entry);
    while (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    _entries.clear();
  }

  void clear() => _entries.clear();

  List<LogEntry> where(bool Function(LogEntry) test) {
    return _entries.where(test).toList();
  }
}

/// 应用日志器
class AppLogger {
  static AppLogger? _instance;

  final String name;
  final LogLevel minLevel;
  final List<LogOutput> _outputs;

  AppLogger._({
    required this.name,
    required this.minLevel,
    required List<LogOutput> outputs,
  }) : _outputs = outputs;

  /// 获取全局实例
  static AppLogger get instance {
    _instance ??= AppLogger._(
      name: 'App',
      minLevel: LogLevel.debug,
      outputs: [ConsoleLogOutput()],
    );
    return _instance!;
  }

  /// 初始化全局日志器
  static void initialize({
    String name = 'App',
    LogLevel minLevel = LogLevel.debug,
    List<LogOutput>? outputs,
  }) {
    _instance = AppLogger._(
      name: name,
      minLevel: minLevel,
      outputs: outputs ?? [ConsoleLogOutput()],
    );
  }

  /// 创建子日志器（带模块名）
  ModuleLogger module(String moduleName) {
    return ModuleLogger(parent: this, moduleName: moduleName);
  }

  /// 记录日志
  void log(
    LogLevel level,
    String message, {
    String? module,
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.value < minLevel.value) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      module: module,
      context: context,
      error: error,
      stackTrace: stackTrace,
    );

    for (final output in _outputs) {
      try {
        output.write(entry);
      } catch (e) {
        stderr.writeln('Failed to write log: $e');
      }
    }
  }

  // 便捷方法
  void trace(String message, {Map<String, dynamic>? context}) =>
      log(LogLevel.trace, message, context: context);

  void debug(String message, {Map<String, dynamic>? context}) =>
      log(LogLevel.debug, message, context: context);

  void info(String message, {Map<String, dynamic>? context}) =>
      log(LogLevel.info, message, context: context);

  void warning(String message, {Map<String, dynamic>? context, Object? error}) =>
      log(LogLevel.warning, message, context: context, error: error);

  void error(String message, {Map<String, dynamic>? context, Object? error, StackTrace? stackTrace}) =>
      log(LogLevel.error, message, context: context, error: error, stackTrace: stackTrace);

  void fatal(String message, {Map<String, dynamic>? context, Object? error, StackTrace? stackTrace}) =>
      log(LogLevel.fatal, message, context: context, error: error, stackTrace: stackTrace);

  /// 刷新所有输出
  Future<void> flush() async {
    for (final output in _outputs) {
      await output.flush();
    }
  }

  /// 关闭所有输出
  Future<void> close() async {
    for (final output in _outputs) {
      await output.close();
    }
  }
}

/// 模块日志器
class ModuleLogger {
  final AppLogger parent;
  final String moduleName;

  ModuleLogger({
    required this.parent,
    required this.moduleName,
  });

  void log(
    LogLevel level,
    String message, {
    Map<String, dynamic>? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    parent.log(
      level,
      message,
      module: moduleName,
      context: context,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void trace(String message, {Map<String, dynamic>? context}) =>
      log(LogLevel.trace, message, context: context);

  void debug(String message, {Map<String, dynamic>? context}) =>
      log(LogLevel.debug, message, context: context);

  void info(String message, {Map<String, dynamic>? context}) =>
      log(LogLevel.info, message, context: context);

  void warning(String message, {Map<String, dynamic>? context, Object? error}) =>
      log(LogLevel.warning, message, context: context, error: error);

  void error(String message, {Map<String, dynamic>? context, Object? error, StackTrace? stackTrace}) =>
      log(LogLevel.error, message, context: context, error: error, stackTrace: stackTrace);

  void fatal(String message, {Map<String, dynamic>? context, Object? error, StackTrace? stackTrace}) =>
      log(LogLevel.fatal, message, context: context, error: error, stackTrace: stackTrace);
}

/// 便捷的全局日志函数
void logTrace(String message, {Map<String, dynamic>? context}) =>
    AppLogger.instance.trace(message, context: context);

void logDebug(String message, {Map<String, dynamic>? context}) =>
    AppLogger.instance.debug(message, context: context);

void logInfo(String message, {Map<String, dynamic>? context}) =>
    AppLogger.instance.info(message, context: context);

void logWarning(String message, {Map<String, dynamic>? context, Object? error}) =>
    AppLogger.instance.warning(message, context: context, error: error);

void logError(String message, {Map<String, dynamic>? context, Object? error, StackTrace? stackTrace}) =>
    AppLogger.instance.error(message, context: context, error: error, stackTrace: stackTrace);

void logFatal(String message, {Map<String, dynamic>? context, Object? error, StackTrace? stackTrace}) =>
    AppLogger.instance.fatal(message, context: context, error: error, stackTrace: stackTrace);

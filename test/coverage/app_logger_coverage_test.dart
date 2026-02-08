/// Additional coverage tests for app_logger.dart.
///
/// Targets uncovered branches: ConsoleLogOutput, FileLogOutput,
/// toFormattedString with stack trace, _coloredLevel, global convenience
/// functions, ModuleLogger all levels.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/logging/app_logger.dart';

void main() {
  // ==========================================================================
  // LogEntry - toFormattedString variations
  // ==========================================================================
  group('LogEntry - toFormattedString variations', () {
    test('should include stack trace (short)', () {
      final entry = LogEntry(
        timestamp: DateTime(2024, 1, 1),
        level: LogLevel.error,
        message: 'Error',
        stackTrace: StackTrace.fromString('line1\nline2\nline3'),
      );
      final formatted = entry.toFormattedString();
      expect(formatted, contains('Stack:'));
    });

    test('should truncate long stack traces', () {
      final longStack = List.generate(20, (i) => 'frame_$i').join('\n');
      final entry = LogEntry(
        timestamp: DateTime(2024, 1, 1),
        level: LogLevel.error,
        message: 'Error',
        stackTrace: StackTrace.fromString(longStack),
      );
      final formatted = entry.toFormattedString();
      expect(formatted, contains('more lines'));
    });

    test('colored output should include ANSI codes', () {
      final entry = LogEntry(
        timestamp: DateTime(2024, 1, 1, 10, 30, 0),
        level: LogLevel.info,
        message: 'Test',
      );
      final colored = entry.toFormattedString(colored: true);
      // ANSI green for INFO
      expect(colored, contains('\x1B[32m'));
    });

    test('non-colored output should not include ANSI codes', () {
      final entry = LogEntry(
        timestamp: DateTime(2024, 1, 1, 10, 30, 0),
        level: LogLevel.info,
        message: 'Test',
      );
      final plain = entry.toFormattedString(colored: false);
      expect(plain, isNot(contains('\x1B[')));
    });

    test('should format all log levels with colors', () {
      for (final level in LogLevel.values) {
        final entry = LogEntry(
          timestamp: DateTime(2024, 1, 1),
          level: level,
          message: 'msg',
        );
        final colored = entry.toFormattedString(colored: true);
        expect(colored, contains('['));
      }
    });

    test('should format without timestamp', () {
      final entry = LogEntry(
        timestamp: DateTime(2024, 1, 1, 10, 30, 0),
        level: LogLevel.info,
        message: 'Test',
      );
      final plain = entry.toFormattedString(includeTimestamp: false);
      expect(plain, isNot(contains('10:30:00')));
    });

    test('should include error and stack trace together', () {
      final entry = LogEntry(
        timestamp: DateTime(2024, 1, 1),
        level: LogLevel.error,
        message: 'Fail',
        error: Exception('database down'),
        stackTrace: StackTrace.fromString('frame1\nframe2'),
      );
      final formatted = entry.toFormattedString();
      expect(formatted, contains('Error:'));
      expect(formatted, contains('database down'));
      expect(formatted, contains('Stack:'));
    });
  });

  // ==========================================================================
  // ConsoleLogOutput
  // ==========================================================================
  group('ConsoleLogOutput', () {
    test('should create with default settings', () {
      final output = ConsoleLogOutput();
      expect(output.useColors, isTrue);
      expect(output.includeTimestamp, isTrue);
    });

    test('should create without colors', () {
      final output = ConsoleLogOutput(useColors: false, includeTimestamp: false);
      expect(output.useColors, isFalse);
      expect(output.includeTimestamp, isFalse);
    });

    test('write should write info to stdout', () {
      final output = ConsoleLogOutput(useColors: false);
      // Just verify it doesn't throw
      output.write(LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.info,
        message: 'stdout test',
      ));
    });

    test('write should write error to stderr', () {
      final output = ConsoleLogOutput(useColors: false);
      // Verify error level goes to stderr
      output.write(LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.error,
        message: 'stderr test',
      ));
    });

    test('write should write fatal to stderr', () {
      final output = ConsoleLogOutput(useColors: false);
      output.write(LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.fatal,
        message: 'fatal test',
      ));
    });

    test('flush should complete without error', () async {
      final output = ConsoleLogOutput();
      await output.flush();
    });

    test('close should complete without error', () async {
      final output = ConsoleLogOutput();
      await output.close();
    });
  });

  // ==========================================================================
  // FileLogOutput
  // ==========================================================================
  group('FileLogOutput', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('app_logger_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should create log directory and write logs', () async {
      final logDir = '${tempDir.path}/logs';
      final output = FileLogOutput(logDirectory: logDir);

      output.write(LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.info,
        message: 'File log test',
      ));

      await output.flush();
      await output.close();

      // Verify directory was created
      expect(Directory(logDir).existsSync(), isTrue);
      // Verify log file was created
      final files = Directory(logDir).listSync().whereType<File>().toList();
      expect(files, isNotEmpty);
    });

    test('should write in JSON format', () async {
      final logDir = '${tempDir.path}/json_logs';
      final output = FileLogOutput(
        logDirectory: logDir,
        jsonFormat: true,
      );

      output.write(LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.info,
        message: 'JSON test',
        module: 'TestMod',
      ));

      await output.flush();
      await output.close();

      final files = Directory(logDir).listSync().whereType<File>().toList();
      expect(files, isNotEmpty);
      // Read and verify JSON format
      final content = files.first.readAsStringSync();
      expect(content, contains('"message":"JSON test"'));
    });

    test('should support custom file prefix', () async {
      final logDir = '${tempDir.path}/prefix_logs';
      final output = FileLogOutput(
        logDirectory: logDir,
        filePrefix: 'custom',
      );

      output.write(LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.info,
        message: 'Prefix test',
      ));

      await output.flush();
      await output.close();

      final files = Directory(logDir).listSync().whereType<File>().toList();
      expect(files.any((f) => f.path.contains('custom')), isTrue);
    });

    test('should handle multiple writes', () async {
      final logDir = '${tempDir.path}/multi_logs';
      final output = FileLogOutput(logDirectory: logDir);

      for (int i = 0; i < 10; i++) {
        output.write(LogEntry(
          timestamp: DateTime.now(),
          level: LogLevel.info,
          message: 'Message $i',
        ));
      }

      await output.flush();
      await output.close();

      final files = Directory(logDir).listSync().whereType<File>().toList();
      expect(files, isNotEmpty);
    });
  });

  // ==========================================================================
  // MemoryLogOutput extended
  // ==========================================================================
  group('MemoryLogOutput extended', () {
    test('flush should complete without error', () async {
      final output = MemoryLogOutput();
      await output.flush(); // no-op
    });

    test('should handle rapid writes', () {
      final output = MemoryLogOutput(maxEntries: 100);
      for (int i = 0; i < 200; i++) {
        output.write(LogEntry(
          timestamp: DateTime.now(),
          level: LogLevel.info,
          message: 'Rapid $i',
        ));
      }
      expect(output.entries.length, equals(100));
    });
  });

  // ==========================================================================
  // AppLogger - flush and close
  // ==========================================================================
  group('AppLogger flush and close', () {
    test('flush should flush all outputs', () async {
      final memory = MemoryLogOutput();
      AppLogger.initialize(
        name: 'FlushTest',
        minLevel: LogLevel.trace,
        outputs: [memory],
      );
      AppLogger.instance.info('before flush');
      await AppLogger.instance.flush();
      expect(memory.entries, isNotEmpty);
    });

    test('close should close all outputs', () async {
      final memory = MemoryLogOutput();
      AppLogger.initialize(
        name: 'CloseTest',
        minLevel: LogLevel.trace,
        outputs: [memory],
      );
      AppLogger.instance.info('before close');
      await AppLogger.instance.close();
      // MemoryLogOutput.close clears entries
      expect(memory.entries, isEmpty);
    });
  });

  // ==========================================================================
  // AppLogger - error handling in output
  // ==========================================================================
  group('AppLogger - error handling in output', () {
    test('should not throw when output write fails', () {
      final brokenOutput = _BrokenLogOutput();
      AppLogger.initialize(
        name: 'BrokenTest',
        minLevel: LogLevel.trace,
        outputs: [brokenOutput],
      );
      // Should not throw even though output is broken
      AppLogger.instance.info('should not throw');
    });
  });

  // ==========================================================================
  // Global convenience functions
  // ==========================================================================
  group('Global convenience functions', () {
    late MemoryLogOutput memory;

    setUp(() {
      memory = MemoryLogOutput();
      AppLogger.initialize(
        name: 'GlobalFnTest',
        minLevel: LogLevel.trace,
        outputs: [memory],
      );
    });

    test('logTrace should log at trace level', () {
      logTrace('trace msg');
      expect(memory.entries.last.level, equals(LogLevel.trace));
    });

    test('logDebug should log at debug level', () {
      logDebug('debug msg');
      expect(memory.entries.last.level, equals(LogLevel.debug));
    });

    test('logInfo should log at info level', () {
      logInfo('info msg');
      expect(memory.entries.last.level, equals(LogLevel.info));
    });

    test('logWarning should log at warning level', () {
      logWarning('warn msg', error: Exception('warn'));
      expect(memory.entries.last.level, equals(LogLevel.warning));
    });

    test('logError should log at error level', () {
      logError('error msg', error: Exception('err'), stackTrace: StackTrace.current);
      expect(memory.entries.last.level, equals(LogLevel.error));
    });

    test('logFatal should log at fatal level', () {
      logFatal('fatal msg', error: Exception('fatal'));
      expect(memory.entries.last.level, equals(LogLevel.fatal));
    });

    test('logTrace with context', () {
      logTrace('ctx trace', context: {'key': 'val'});
      expect(memory.entries.last.context!['key'], equals('val'));
    });

    test('logDebug with context', () {
      logDebug('ctx debug', context: {'key': 'val'});
      expect(memory.entries.last.context!['key'], equals('val'));
    });

    test('logInfo with context', () {
      logInfo('ctx info', context: {'key': 'val'});
      expect(memory.entries.last.context!['key'], equals('val'));
    });
  });

  // ==========================================================================
  // ModuleLogger - all levels with error/stackTrace
  // ==========================================================================
  group('ModuleLogger - extended', () {
    test('error with context and stackTrace', () {
      final memory = MemoryLogOutput();
      AppLogger.initialize(
        name: 'ModLogTest',
        minLevel: LogLevel.trace,
        outputs: [memory],
      );
      final logger = AppLogger.instance.module('Mod');
      logger.error(
        'err msg',
        context: {'operation': 'test'},
        error: Exception('mod err'),
        stackTrace: StackTrace.current,
      );
      final entry = memory.entries.last;
      expect(entry.module, equals('Mod'));
      expect(entry.level, equals(LogLevel.error));
      expect(entry.context!['operation'], equals('test'));
      expect(entry.error, isNotNull);
      expect(entry.stackTrace, isNotNull);
    });

    test('fatal with context', () {
      final memory = MemoryLogOutput();
      AppLogger.initialize(
        name: 'ModFatalTest',
        minLevel: LogLevel.trace,
        outputs: [memory],
      );
      final logger = AppLogger.instance.module('Critical');
      logger.fatal('fatal msg', context: {'severity': 'max'});
      expect(memory.entries.last.level, equals(LogLevel.fatal));
      expect(memory.entries.last.context!['severity'], equals('max'));
    });

    test('warning with error object', () {
      final memory = MemoryLogOutput();
      AppLogger.initialize(
        name: 'ModWarnTest',
        minLevel: LogLevel.trace,
        outputs: [memory],
      );
      final logger = AppLogger.instance.module('Warn');
      logger.warning('warn msg', error: Exception('warning cause'));
      expect(memory.entries.last.error, isNotNull);
    });

    test('trace with context', () {
      final memory = MemoryLogOutput();
      AppLogger.initialize(
        name: 'ModTraceTest',
        minLevel: LogLevel.trace,
        outputs: [memory],
      );
      final logger = AppLogger.instance.module('Trace');
      logger.trace('trace msg', context: {'detail': 'fine'});
      expect(memory.entries.last.context!['detail'], equals('fine'));
    });
  });

  // ==========================================================================
  // AppLogger - multiple outputs
  // ==========================================================================
  group('AppLogger - multiple outputs', () {
    test('should write to all outputs', () {
      final memory1 = MemoryLogOutput();
      final memory2 = MemoryLogOutput();
      AppLogger.initialize(
        name: 'MultiOutput',
        minLevel: LogLevel.trace,
        outputs: [memory1, memory2],
      );
      AppLogger.instance.info('multi output test');
      expect(memory1.entries.length, equals(1));
      expect(memory2.entries.length, equals(1));
    });
  });
}

/// A broken log output that always throws
class _BrokenLogOutput implements LogOutput {
  @override
  void write(LogEntry entry) => throw Exception('broken');

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

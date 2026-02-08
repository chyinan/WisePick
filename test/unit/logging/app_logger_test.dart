import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/logging/app_logger.dart';

void main() {
  group('LogLevel', () {
    test('should have correct ordering', () {
      expect(LogLevel.trace.value, lessThan(LogLevel.debug.value));
      expect(LogLevel.debug.value, lessThan(LogLevel.info.value));
      expect(LogLevel.info.value, lessThan(LogLevel.warning.value));
      expect(LogLevel.warning.value, lessThan(LogLevel.error.value));
      expect(LogLevel.error.value, lessThan(LogLevel.fatal.value));
    });

    test('should have correct labels', () {
      expect(LogLevel.trace.label, equals('TRACE'));
      expect(LogLevel.debug.label, equals('DEBUG'));
      expect(LogLevel.info.label, equals('INFO'));
      expect(LogLevel.warning.label, equals('WARN'));
      expect(LogLevel.error.label, equals('ERROR'));
      expect(LogLevel.fatal.label, equals('FATAL'));
    });
  });

  group('LogEntry', () {
    test('should store all fields', () {
      final entry = LogEntry(
        timestamp: DateTime(2024, 1, 1, 12, 0, 0),
        level: LogLevel.info,
        message: 'Test message',
        module: 'TestModule',
        context: {'key': 'value'},
      );

      expect(entry.level, equals(LogLevel.info));
      expect(entry.message, equals('Test message'));
      expect(entry.module, equals('TestModule'));
      expect(entry.context!['key'], equals('value'));
    });

    test('toJson should serialize correctly', () {
      final entry = LogEntry(
        timestamp: DateTime(2024, 1, 1),
        level: LogLevel.error,
        message: 'Error occurred',
        module: 'API',
        error: Exception('test'),
      );

      final json = entry.toJson();
      expect(json['level'], equals('ERROR'));
      expect(json['message'], equals('Error occurred'));
      expect(json['module'], equals('API'));
      expect(json['error'], contains('test'));
    });

    test('toJson should omit null fields', () {
      final entry = LogEntry(
        timestamp: DateTime(2024, 1, 1),
        level: LogLevel.info,
        message: 'Simple',
      );

      final json = entry.toJson();
      expect(json.containsKey('module'), isFalse);
      expect(json.containsKey('error'), isFalse);
      expect(json.containsKey('context'), isFalse);
    });

    test('toFormattedString should include level and message', () {
      final entry = LogEntry(
        timestamp: DateTime(2024, 1, 1, 12, 30, 45, 123),
        level: LogLevel.info,
        message: 'Hello',
      );

      final formatted = entry.toFormattedString();
      expect(formatted, contains('[INFO]'));
      expect(formatted, contains('Hello'));
      expect(formatted, contains('12:30:45.123'));
    });

    test('toFormattedString with module should include module', () {
      final entry = LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.debug,
        message: 'Debug msg',
        module: 'Auth',
      );

      final formatted = entry.toFormattedString(includeTimestamp: false);
      expect(formatted, contains('[Auth]'));
      expect(formatted, contains('Debug msg'));
    });

    test('toFormattedString with context should include context', () {
      final entry = LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.info,
        message: 'Request',
        context: {'method': 'GET', 'path': '/api'},
      );

      final formatted = entry.toFormattedString(includeTimestamp: false);
      expect(formatted, contains('method'));
      expect(formatted, contains('GET'));
    });

    test('toFormattedString with error should include error', () {
      final entry = LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.error,
        message: 'Failed',
        error: Exception('database down'),
      );

      final formatted = entry.toFormattedString(includeTimestamp: false);
      expect(formatted, contains('Error:'));
      expect(formatted, contains('database down'));
    });
  });

  group('MemoryLogOutput', () {
    test('should store log entries', () {
      final output = MemoryLogOutput();
      output.write(LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.info,
        message: 'Test',
      ));

      expect(output.entries.length, equals(1));
      expect(output.entries.first.message, equals('Test'));
    });

    test('should respect maxEntries', () {
      final output = MemoryLogOutput(maxEntries: 3);
      for (int i = 0; i < 5; i++) {
        output.write(LogEntry(
          timestamp: DateTime.now(),
          level: LogLevel.info,
          message: 'Msg $i',
        ));
      }

      expect(output.entries.length, equals(3));
      // Should keep newest entries
      expect(output.entries.last.message, equals('Msg 4'));
    });

    test('clear should remove all entries', () {
      final output = MemoryLogOutput();
      output.write(LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.info,
        message: 'Test',
      ));
      output.clear();
      expect(output.entries, isEmpty);
    });

    test('where should filter entries', () {
      final output = MemoryLogOutput();
      output.write(LogEntry(timestamp: DateTime.now(), level: LogLevel.info, message: 'info'));
      output.write(LogEntry(timestamp: DateTime.now(), level: LogLevel.error, message: 'error'));
      output.write(LogEntry(timestamp: DateTime.now(), level: LogLevel.info, message: 'info2'));

      final errors = output.where((e) => e.level == LogLevel.error);
      expect(errors.length, equals(1));
      expect(errors.first.message, equals('error'));
    });

    test('close should clear entries', () async {
      final output = MemoryLogOutput();
      output.write(LogEntry(timestamp: DateTime.now(), level: LogLevel.info, message: 'Test'));
      await output.close();
      expect(output.entries, isEmpty);
    });
  });

  group('AppLogger', () {
    test('should filter by minLevel', () {
      final memory = MemoryLogOutput();
      AppLogger.initialize(
        name: 'Test',
        minLevel: LogLevel.warning,
        outputs: [memory],
      );

      AppLogger.instance.debug('should not appear');
      AppLogger.instance.info('should not appear');
      AppLogger.instance.warning('should appear');
      AppLogger.instance.error('should appear');

      expect(memory.entries.length, equals(2));
    });

    test('convenience methods should log at correct levels', () {
      final memory = MemoryLogOutput();
      AppLogger.initialize(
        name: 'Test',
        minLevel: LogLevel.trace,
        outputs: [memory],
      );

      AppLogger.instance.trace('t');
      AppLogger.instance.debug('d');
      AppLogger.instance.info('i');
      AppLogger.instance.warning('w');
      AppLogger.instance.error('e');
      AppLogger.instance.fatal('f');

      expect(memory.entries.length, equals(6));
      expect(memory.entries[0].level, equals(LogLevel.trace));
      expect(memory.entries[1].level, equals(LogLevel.debug));
      expect(memory.entries[2].level, equals(LogLevel.info));
      expect(memory.entries[3].level, equals(LogLevel.warning));
      expect(memory.entries[4].level, equals(LogLevel.error));
      expect(memory.entries[5].level, equals(LogLevel.fatal));
    });

    test('should support context in messages', () {
      final memory = MemoryLogOutput();
      AppLogger.initialize(
        name: 'Test',
        minLevel: LogLevel.trace,
        outputs: [memory],
      );

      AppLogger.instance.info('Request processed', context: {'duration': '50ms'});
      expect(memory.entries.first.context!['duration'], equals('50ms'));
    });

    test('module should create ModuleLogger', () {
      final memory = MemoryLogOutput();
      AppLogger.initialize(
        name: 'Test',
        minLevel: LogLevel.trace,
        outputs: [memory],
      );

      final moduleLogger = AppLogger.instance.module('Auth');
      moduleLogger.info('User logged in');

      expect(memory.entries.first.module, equals('Auth'));
      expect(memory.entries.first.message, equals('User logged in'));
    });
  });

  group('ModuleLogger', () {
    test('should delegate to parent with module name', () {
      final memory = MemoryLogOutput();
      AppLogger.initialize(
        name: 'Test',
        minLevel: LogLevel.trace,
        outputs: [memory],
      );

      final logger = AppLogger.instance.module('Database');
      logger.trace('t');
      logger.debug('d');
      logger.info('i');
      logger.warning('w', error: Exception('warn'));
      logger.error('e', error: Exception('err'), stackTrace: StackTrace.current);
      logger.fatal('f');

      expect(memory.entries.length, equals(6));
      for (final entry in memory.entries) {
        expect(entry.module, equals('Database'));
      }
    });
  });
}

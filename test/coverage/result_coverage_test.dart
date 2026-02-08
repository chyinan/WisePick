/// Additional coverage tests for Result type.
///
/// Targets uncovered branches: mapAsync, recoverAsync, getOrThrow with stackTrace,
/// Success/FailureResult equality/toString, Failure.toJson edge cases, Unit type.
library;

import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/resilience/result.dart';

void main() {
  // ==========================================================================
  // mapAsync
  // ==========================================================================
  group('Result.mapAsync', () {
    test('should map success value asynchronously', () async {
      final result = Result<int>.success(5);
      final mapped = await result.mapAsync((v) async => v.toString());
      expect(mapped.isSuccess, isTrue);
      expect(mapped.getOrThrow(), equals('5'));
    });

    test('should propagate failure without calling mapper', () async {
      final result = Result<int>.failure(Failure(message: 'err'));
      var called = false;
      final mapped = await result.mapAsync((v) async {
        called = true;
        return v.toString();
      });
      expect(mapped.isFailure, isTrue);
      expect(called, isFalse);
    });

    test('should catch mapper exceptions and return failure', () async {
      final result = Result<int>.success(5);
      final mapped = await result.mapAsync<String>((v) async {
        throw FormatException('mapper error');
      });
      expect(mapped.isFailure, isTrue);
      expect(mapped.failureOrNull?.message, contains('FormatException'));
    });
  });

  // ==========================================================================
  // recoverAsync
  // ==========================================================================
  group('Result.recoverAsync', () {
    test('should recover failure asynchronously', () async {
      final result = Result<int>.failure(Failure(message: 'err'));
      final recovered = await result.recoverAsync((f) async => 42);
      expect(recovered.isSuccess, isTrue);
      expect(recovered.getOrThrow(), equals(42));
    });

    test('should pass through success', () async {
      final result = Result<int>.success(10);
      final recovered = await result.recoverAsync((f) async => 42);
      expect(recovered.isSuccess, isTrue);
      expect(recovered.getOrThrow(), equals(10));
    });

    test('should catch recovery exceptions', () async {
      final result = Result<int>.failure(Failure(message: 'err'));
      final recovered = await result.recoverAsync((f) async {
        throw Exception('recovery failed');
      });
      expect(recovered.isFailure, isTrue);
    });
  });

  // ==========================================================================
  // getOrThrow with error and stackTrace
  // ==========================================================================
  group('Result.getOrThrow edge cases', () {
    test('should re-throw with original stack trace when available', () {
      try {
        throw FormatException('original');
      } catch (e, stack) {
        final result = Result<int>.failure(Failure(
          message: 'wrapped',
          error: e,
          stackTrace: stack,
        ));
        expect(() => result.getOrThrow(), throwsA(isA<FormatException>()));
      }
    });

    test('should throw error without stackTrace', () {
      final result = Result<int>.failure(Failure(
        message: 'no stack',
        error: StateError('bad state'),
      ));
      expect(() => result.getOrThrow(), throwsA(isA<StateError>()));
    });

    test('should throw Exception when no error object', () {
      final result = Result<int>.failure(Failure(message: 'just message'));
      expect(() => result.getOrThrow(), throwsA(isA<Exception>()));
    });
  });

  // ==========================================================================
  // Success equality and toString
  // ==========================================================================
  group('Success equality and toString', () {
    test('should be equal when values are equal', () {
      final s1 = Success(42);
      final s2 = Success(42);
      expect(s1, equals(s2));
      expect(s1.hashCode, equals(s2.hashCode));
    });

    test('should not be equal when values differ', () {
      final s1 = Success(42);
      final s2 = Success(99);
      expect(s1, isNot(equals(s2)));
    });

    test('toString should include value', () {
      expect(Success(42).toString(), equals('Success(42)'));
      expect(Success('hello').toString(), equals('Success(hello)'));
    });

    test('identical success should be equal', () {
      final s = Success(10);
      expect(s == s, isTrue);
    });

    test('should not be equal to non-Success', () {
      final s = Success(10);
      // ignore: unrelated_type_equality_checks
      expect(s == 10, isFalse);
    });
  });

  // ==========================================================================
  // FailureResult equality and toString
  // ==========================================================================
  group('FailureResult equality and toString', () {
    test('should be equal when failures are equal', () {
      final f1 = FailureResult<int>(Failure(message: 'err', code: 'E1'));
      final f2 = FailureResult<int>(Failure(message: 'err', code: 'E1'));
      expect(f1, equals(f2));
      expect(f1.hashCode, equals(f2.hashCode));
    });

    test('should not be equal when failures differ', () {
      final f1 = FailureResult<int>(Failure(message: 'err1'));
      final f2 = FailureResult<int>(Failure(message: 'err2'));
      expect(f1, isNot(equals(f2)));
    });

    test('toString should include failure', () {
      final fr = FailureResult<int>(Failure(message: 'err', code: 'ERR'));
      expect(fr.toString(), contains('Failure'));
    });

    test('identical FailureResult should be equal', () {
      final f = FailureResult<int>(Failure(message: 'err'));
      expect(f == f, isTrue);
    });
  });

  // ==========================================================================
  // Failure.toString and toJson edge cases
  // ==========================================================================
  group('Failure extended edge cases', () {
    test('Failure.toString without code', () {
      final f = Failure(message: 'test');
      expect(f.toString(), equals('Failure(UNKNOWN: test)'));
    });

    test('Failure.toString with code', () {
      final f = Failure(message: 'test', code: 'MY_CODE');
      expect(f.toString(), equals('Failure(MY_CODE: test)'));
    });

    test('Failure.toJson with error object', () {
      final f = Failure(
        message: 'err',
        error: Exception('inner'),
        context: {'key': 'val'},
      );
      final json = f.toJson();
      expect(json['error'], contains('inner'));
      expect(json['context'], isNotNull);
      expect(json['context']['key'], equals('val'));
    });

    test('Failure.toJson omits null fields', () {
      final f = Failure(message: 'minimal');
      final json = f.toJson();
      expect(json.containsKey('code'), isFalse);
      expect(json.containsKey('error'), isFalse);
      expect(json.containsKey('context'), isFalse);
      expect(json['retryable'], isTrue);
    });

    test('Failure.network with error and stackTrace', () {
      final err = Exception('net');
      final stack = StackTrace.current;
      final f = Failure.network(error: err, stackTrace: stack);
      expect(f.code, equals('NETWORK_ERROR'));
      expect(f.error, equals(err));
      expect(f.stackTrace, equals(stack));
    });

    test('Failure.timeout with error and stackTrace', () {
      final err = Exception('slow');
      final f = Failure.timeout(error: err);
      expect(f.code, equals('TIMEOUT'));
      expect(f.error, equals(err));
    });

    test('Failure.authentication with error', () {
      final err = Exception('bad token');
      final f = Failure.authentication(error: err);
      expect(f.code, equals('AUTH_ERROR'));
      expect(f.retryable, isFalse);
    });

    test('Failure.server with error', () {
      final f = Failure.server(error: Exception('500'));
      expect(f.code, equals('SERVER_ERROR'));
      expect(f.retryable, isTrue);
    });

    test('Failure.validation with context', () {
      final f = Failure.validation(
        message: 'invalid',
        context: {'field': 'email'},
      );
      expect(f.context!['field'], equals('email'));
    });

    test('Failure.unknown with error and stackTrace', () {
      final err = Exception('mystery');
      final stack = StackTrace.current;
      final f = Failure.unknown(error: err, stackTrace: stack);
      expect(f.code, equals('UNKNOWN_ERROR'));
      expect(f.retryable, isFalse);
      expect(f.error, equals(err));
      expect(f.stackTrace, equals(stack));
    });
  });

  // ==========================================================================
  // recover edge case: recovery function throws
  // ==========================================================================
  group('Result.recover when recovery throws', () {
    test('should return new failure when recovery throws', () {
      final result = Result<int>.failure(Failure(message: 'original'));
      final recovered = result.recover((f) => throw Exception('recovery boom'));
      expect(recovered.isFailure, isTrue);
      expect(recovered.failureOrNull?.message, contains('recovery boom'));
    });
  });

  // ==========================================================================
  // Unit type
  // ==========================================================================
  group('Unit type', () {
    test('Unit.instance should be singleton', () {
      expect(identical(Unit.instance, Unit.instance), isTrue);
    });

    test('unitSuccess should create Result<Unit> success', () {
      final result = unitSuccess();
      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, equals(Unit.instance));
    });

    test('unitFailure should create Result<Unit> failure', () {
      final result = unitFailure(Failure(message: 'fail'));
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull?.message, equals('fail'));
    });
  });

  // ==========================================================================
  // fromSync and fromAsync error details
  // ==========================================================================
  group('fromSync / fromAsync error details', () {
    test('fromSync should capture error and stackTrace', () {
      final result = Result.fromSync<int>(() => throw StateError('sync err'));
      expect(result.isFailure, isTrue);
      final f = result.failureOrNull!;
      expect(f.message, contains('sync err'));
      expect(f.error, isA<StateError>());
      expect(f.stackTrace, isNotNull);
    });

    test('fromAsync should capture error and stackTrace', () async {
      final result = await Result.fromAsync<int>(
        () async => throw ArgumentError('async err'),
      );
      expect(result.isFailure, isTrue);
      final f = result.failureOrNull!;
      expect(f.error, isA<ArgumentError>());
      expect(f.stackTrace, isNotNull);
    });
  });
}

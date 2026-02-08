import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/resilience/result.dart';

void main() {
  group('Result - Success', () {
    test('should create a Success result with value', () {
      final result = Result<int>.success(42);
      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.valueOrNull, equals(42));
      expect(result.getOrThrow(), equals(42));
    });

    test('should allow null value in Success', () {
      final result = Result<String?>.success(null);
      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, isNull);
    });

    test('should have null failureOrNull for Success', () {
      final result = Result<int>.success(42);
      expect(result.failureOrNull, isNull);
    });

    test('getOrThrow should return value for Success', () {
      final result = Result<String>.success('hello');
      expect(result.getOrThrow(), equals('hello'));
    });

    test('getOrDefault should return value for Success', () {
      final result = Result<int>.success(42);
      expect(result.getOrDefault(0), equals(42));
    });

    test('getOrElse should return value for Success', () {
      final result = Result<int>.success(42);
      expect(result.getOrElse((f) => -1), equals(42));
    });
  });

  group('Result - Failure', () {
    test('should create a Failure result with message', () {
      final result = Result<int>.failure(Failure(message: 'something broke'));
      expect(result.isSuccess, isFalse);
      expect(result.isFailure, isTrue);
      expect(result.valueOrNull, isNull);
    });

    test('should contain Failure details', () {
      final failure = Failure(
        message: 'not found',
        code: '404',
        retryable: false,
      );
      final result = Result<String>.failure(failure);
      final f = result.failureOrNull;
      expect(f, isNotNull);
      expect(f!.message, equals('not found'));
      expect(f.code, equals('404'));
      expect(f.retryable, isFalse);
    });

    test('getOrThrow should throw for Failure', () {
      final result = Result<int>.failure(Failure(message: 'error'));
      expect(() => result.getOrThrow(), throwsA(isA<Exception>()));
    });

    test('getOrDefault should return default for Failure', () {
      final result = Result<int>.failure(Failure(message: 'error'));
      expect(result.getOrDefault(99), equals(99));
    });

    test('getOrElse should call function for Failure', () {
      final result = Result<int>.failure(Failure(message: 'error'));
      expect(result.getOrElse((f) => -1), equals(-1));
    });

    test('should carry error object and stack trace', () {
      final originalError = FormatException('bad format');
      final stackTrace = StackTrace.current;
      final failure = Failure(
        message: 'parse error',
        error: originalError,
        stackTrace: stackTrace,
      );
      expect(failure.error, equals(originalError));
      expect(failure.stackTrace, equals(stackTrace));
    });
  });

  group('Result - Factory constructors', () {
    test('fromSync should capture synchronous success', () {
      final result = Result.fromSync(() => 100);
      expect(result.isSuccess, isTrue);
      expect(result.getOrThrow(), equals(100));
    });

    test('fromSync should capture synchronous failure', () {
      final result = Result.fromSync<int>(() => throw FormatException('bad'));
      expect(result.isFailure, isTrue);
    });

    test('fromAsync should capture async success', () async {
      final result = await Result.fromAsync(() async => 'async_value');
      expect(result.isSuccess, isTrue);
      expect(result.getOrThrow(), equals('async_value'));
    });

    test('fromAsync should capture async failure', () async {
      final result = await Result.fromAsync<int>(() async {
        throw StateError('async error');
      });
      expect(result.isFailure, isTrue);
    });
  });

  group('Result - Functional operations', () {
    test('map should transform Success value', () {
      final result = Result<int>.success(5);
      final mapped = result.map((v) => v * 2);
      expect(mapped.isSuccess, isTrue);
      expect(mapped.getOrThrow(), equals(10));
    });

    test('map should pass through Failure', () {
      final result = Result<int>.failure(Failure(message: 'err'));
      final mapped = result.map((v) => v * 2);
      expect(mapped.isFailure, isTrue);
    });

    test('flatMap should chain Success operations', () {
      final result = Result<int>.success(10);
      final chained = result.flatMap((v) => Result.success('value: $v'));
      expect(chained.isSuccess, isTrue);
      expect(chained.getOrThrow(), equals('value: 10'));
    });

    test('flatMap should pass through Failure', () {
      final result = Result<int>.failure(Failure(message: 'err'));
      final chained = result.flatMap((v) => Result.success('value: $v'));
      expect(chained.isFailure, isTrue);
    });

    test('flatMap should propagate inner Failure', () {
      final result = Result<int>.success(10);
      final chained = result.flatMap<String>(
        (v) => Result.failure(Failure(message: 'inner fail')),
      );
      expect(chained.isFailure, isTrue);
    });

    test('onSuccess should execute callback for Success', () {
      var called = false;
      int? receivedValue;
      Result<int>.success(42).onSuccess((v) {
        called = true;
        receivedValue = v;
      });
      expect(called, isTrue);
      expect(receivedValue, equals(42));
    });

    test('onSuccess should not execute for Failure', () {
      var called = false;
      Result<int>.failure(Failure(message: 'err')).onSuccess((v) {
        called = true;
      });
      expect(called, isFalse);
    });

    test('onFailure should execute callback for Failure', () {
      var called = false;
      Result<int>.failure(Failure(message: 'err')).onFailure((f) {
        called = true;
        expect(f.message, equals('err'));
      });
      expect(called, isTrue);
    });

    test('onFailure should not execute for Success', () {
      var called = false;
      Result<int>.success(1).onFailure((f) {
        called = true;
      });
      expect(called, isFalse);
    });

    test('recover should convert Failure to Success', () {
      final result = Result<int>.failure(Failure(message: 'err'));
      final recovered = result.recover((f) => -1);
      expect(recovered.isSuccess, isTrue);
      expect(recovered.getOrThrow(), equals(-1));
    });

    test('recover should pass through Success', () {
      final result = Result<int>.success(42);
      final recovered = result.recover((f) => -1);
      expect(recovered.isSuccess, isTrue);
      expect(recovered.getOrThrow(), equals(42));
    });

    test('fold should apply onSuccess for Success', () {
      final result = Result<int>.success(5);
      final folded = result.fold(
        onSuccess: (v) => 'got $v',
        onFailure: (f) => 'failed: ${f.message}',
      );
      expect(folded, equals('got 5'));
    });

    test('fold should apply onFailure for Failure', () {
      final result = Result<int>.failure(Failure(message: 'oops'));
      final folded = result.fold(
        onSuccess: (v) => 'got $v',
        onFailure: (f) => 'failed: ${f.message}',
      );
      expect(folded, equals('failed: oops'));
    });
  });

  group('Failure - Factory constructors', () {
    test('Failure.network should have correct code', () {
      final f = Failure.network(message: 'timeout');
      expect(f.code, equals('NETWORK_ERROR'));
      expect(f.retryable, isTrue);
      expect(f.message, equals('timeout'));
    });

    test('Failure.network default message', () {
      final f = Failure.network();
      expect(f.code, equals('NETWORK_ERROR'));
      expect(f.message, isNotEmpty);
    });

    test('Failure.server should have correct code', () {
      final f = Failure.server(message: '500 error');
      expect(f.code, equals('SERVER_ERROR'));
      expect(f.retryable, isTrue);
    });

    test('Failure.validation should not be retryable', () {
      final f = Failure.validation(message: 'invalid input');
      expect(f.code, equals('VALIDATION_ERROR'));
      expect(f.retryable, isFalse);
    });

    test('Failure.authentication should not be retryable', () {
      final f = Failure.authentication();
      expect(f.code, equals('AUTH_ERROR'));
      expect(f.retryable, isFalse);
    });

    test('Failure.unknown should not be retryable', () {
      final f = Failure.unknown();
      expect(f.code, equals('UNKNOWN_ERROR'));
      expect(f.retryable, isFalse);
    });

    test('Failure.timeout should be retryable', () {
      final f = Failure.timeout();
      expect(f.code, equals('TIMEOUT'));
      expect(f.retryable, isTrue);
    });

    test('Failure with context should carry context', () {
      final f = Failure(
        message: 'err',
        context: {'key': 'value', 'count': 3},
      );
      expect(f.context, isNotNull);
      expect(f.context!['key'], equals('value'));
      expect(f.context!['count'], equals(3));
    });

    test('Failure toJson should contain fields', () {
      final f = Failure(
        message: 'test error',
        code: 'TEST',
        retryable: false,
      );
      final json = f.toJson();
      expect(json['message'], equals('test error'));
      expect(json['code'], equals('TEST'));
      expect(json['retryable'], isFalse);
    });

    test('Failure equality should compare message and code', () {
      final f1 = Failure(message: 'err', code: 'ERR');
      final f2 = Failure(message: 'err', code: 'ERR');
      final f3 = Failure(message: 'other', code: 'ERR');
      expect(f1, equals(f2));
      expect(f1, isNot(equals(f3)));
    });
  });

  group('UnitResult', () {
    test('unitSuccess should create unit success', () {
      final result = unitSuccess();
      expect(result.isSuccess, isTrue);
    });

    test('unitFailure should create unit failure', () {
      final result = unitFailure(Failure(message: 'fail'));
      expect(result.isFailure, isTrue);
    });
  });
}

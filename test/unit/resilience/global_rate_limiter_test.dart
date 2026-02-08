import 'dart:async';
import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/resilience/global_rate_limiter.dart';

void main() {
  group('RateLimiterConfig', () {
    test('default config should have sensible values', () {
      const config = RateLimiterConfig();
      expect(config.maxRequestsPerSecond, greaterThan(0));
      expect(config.maxConcurrentRequests, greaterThan(0));
      expect(config.maxQueueLength, greaterThan(0));
    });

    test('AI service config should have lower limits', () {
      expect(RateLimiterConfig.aiService.maxRequestsPerSecond,
          lessThan(const RateLimiterConfig().maxRequestsPerSecond));
    });

    test('scraper config should have specific limits', () {
      expect(RateLimiterConfig.scraper.maxRequestsPerSecond, equals(2));
    });
  });

  group('GlobalRateLimiter - Basic execution', () {
    late GlobalRateLimiter limiter;

    setUp(() {
      limiter = GlobalRateLimiter(
        name: 'test_limiter',
        config: const RateLimiterConfig(
          maxRequestsPerSecond: 100,
          maxConcurrentRequests: 10,
          maxQueueLength: 50,
          waitTimeout: Duration(seconds: 5),
        ),
      );
    });

    tearDown(() {
      limiter.dispose();
    });

    test('should execute operation and return result', () async {
      final result = await limiter.execute(() async => 42);
      expect(result, equals(42));
    });

    test('should track active requests', () async {
      final completer = Completer<void>();

      // Start a long-running operation
      final future = limiter.execute(() async {
        await completer.future;
        return 'done';
      });

      // Give it a moment to start
      await Future.delayed(const Duration(milliseconds: 50));
      expect(limiter.activeRequests, equals(1));

      completer.complete();
      await future;
      expect(limiter.activeRequests, equals(0));
    });

    test('should respect concurrent request limit', () async {
      final blockers = <Completer<void>>[];

      // Fill up concurrent slots
      final futures = <Future>[];
      for (int i = 0; i < 10; i++) {
        final completer = Completer<void>();
        blockers.add(completer);
        futures.add(limiter.execute(() async {
          await completer.future;
          return i;
        }));
      }

      await Future.delayed(const Duration(milliseconds: 100));
      expect(limiter.activeRequests, equals(10));

      // Release all
      for (final c in blockers) {
        c.complete();
      }
      await Future.wait(futures);
    });
  });

  group('GlobalRateLimiter - Queue behavior', () {
    late GlobalRateLimiter limiter;

    setUp(() {
      limiter = GlobalRateLimiter(
        name: 'queue_test',
        config: const RateLimiterConfig(
          maxRequestsPerSecond: 100,
          maxConcurrentRequests: 1,
          maxQueueLength: 5,
          waitTimeout: Duration(seconds: 2),
        ),
      );
    });

    tearDown(() {
      limiter.dispose();
    });

    test('should queue excess requests', () async {
      final blocker = Completer<void>();

      // Block the single slot
      final first = limiter.execute(() async {
        await blocker.future;
        return 'first';
      });

      // Queue a second request
      final second = limiter.execute(() async => 'second');

      await Future.delayed(const Duration(milliseconds: 50));
      expect(limiter.queueLength, greaterThanOrEqualTo(1));

      blocker.complete();
      await first;
      final secondResult = await second;
      expect(secondResult, equals('second'));
    });

    test('should reject when queue is full', () async {
      final blocker = Completer<void>();
      final futures = <Future>[];

      // Block the single slot
      futures.add(limiter.execute(() async {
        await blocker.future;
        return 'blocking';
      }));

      // Fill the queue (5 slots)
      for (int i = 0; i < 5; i++) {
        futures.add(limiter.execute(() async => i));
      }

      await Future.delayed(const Duration(milliseconds: 50));

      // This should be rejected
      expect(
        () => limiter.execute(() async => 'overflow'),
        throwsA(isA<RateLimitException>()),
      );

      blocker.complete();
      // Wait for all queued operations to complete
      await Future.wait(futures);
    });
  });

  group('GlobalRateLimiter - Dispose', () {
    test('should throw after disposal', () async {
      final limiter = GlobalRateLimiter(name: 'dispose_test');
      limiter.dispose();

      // execute is async, so use expectLater with the returned Future
      await expectLater(
        limiter.execute(() async => 'test'),
        throwsA(isA<StateError>()),
      );
    });

    test('should reject queued requests on dispose', () async {
      final limiter = GlobalRateLimiter(
        name: 'dispose_queue_test',
        config: const RateLimiterConfig(
          maxConcurrentRequests: 1,
          maxQueueLength: 10,
        ),
      );

      final blocker = Completer<void>();

      // Block the slot
      final blockingFuture = limiter.execute(() async {
        await blocker.future;
        return 'blocking';
      });

      // Queue some requests
      final queuedFuture = limiter.execute(() async => 'queued');

      await Future.delayed(const Duration(milliseconds: 50));

      // Dispose should reject queued requests
      limiter.dispose();
      blocker.complete();

      // The queued future should be rejected with RateLimitException
      await expectLater(queuedFuture, throwsA(isA<RateLimitException>()));

      // The blocking future should complete (it was already running)
      try {
        await blockingFuture;
      } catch (_) {
        // May also fail if dispose interferes, that's OK
      }
    });
  });

  group('GlobalRateLimiter - Statistics', () {
    late GlobalRateLimiter limiter;

    setUp(() {
      limiter = GlobalRateLimiter(name: 'stats_test');
    });

    tearDown(() {
      limiter.dispose();
    });

    test('should track statistics', () async {
      await limiter.execute(() async => 'a');
      await limiter.execute(() async => 'b');

      final stats = limiter.getStats();
      expect(stats['name'], equals('stats_test'));
      expect(stats['totalRequests'], equals(2));
    });

    test('resetStats should clear statistics', () async {
      await limiter.execute(() async => 'a');
      limiter.resetStats();

      final stats = limiter.getStats();
      expect(stats['totalRequests'], equals(0));
    });
  });

  group('GlobalRateLimiterRegistry', () {
    tearDown(() {
      GlobalRateLimiterRegistry.instance.clear();
    });

    test('should create and retrieve limiters', () {
      final limiter = GlobalRateLimiterRegistry.instance.getOrCreate('svc');
      expect(limiter, isNotNull);

      final same = GlobalRateLimiterRegistry.instance.getOrCreate('svc');
      expect(identical(limiter, same), isTrue);
    });

    test('should return null for non-existent', () {
      expect(GlobalRateLimiterRegistry.instance.get('missing'), isNull);
    });

    test('getAllStats should return stats for all limiters', () {
      GlobalRateLimiterRegistry.instance.getOrCreate('a');
      GlobalRateLimiterRegistry.instance.getOrCreate('b');

      final stats = GlobalRateLimiterRegistry.instance.getAllStats();
      expect(stats.containsKey('a'), isTrue);
      expect(stats.containsKey('b'), isTrue);
    });
  });

  group('RateLimitException', () {
    test('should carry message and retryAfter', () {
      final ex = RateLimitException(
        'queue full',
        retryAfter: const Duration(seconds: 5),
      );
      expect(ex.message, equals('queue full'));
      expect(ex.retryAfter, equals(const Duration(seconds: 5)));
      expect(ex.toString(), contains('queue full'));
    });
  });
}

import 'dart:async';

import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/resilience/global_rate_limiter.dart';

void main() {
  group('RateLimiterConfig', () {
    test('default config', () {
      const c = RateLimiterConfig();
      expect(c.maxRequestsPerSecond, 10);
      expect(c.maxConcurrentRequests, 5);
      expect(c.maxQueueLength, 100);
      expect(c.waitTimeout, const Duration(seconds: 30));
      expect(c.enableBackpressure, isTrue);
      expect(c.backpressureThreshold, 0.7);
    });

    test('aiService preset', () {
      expect(RateLimiterConfig.aiService.maxRequestsPerSecond, 3);
      expect(RateLimiterConfig.aiService.maxConcurrentRequests, 2);
    });

    test('scraper preset', () {
      expect(RateLimiterConfig.scraper.maxRequestsPerSecond, 2);
      expect(RateLimiterConfig.scraper.maxConcurrentRequests, 3);
    });
  });

  group('RateLimitException', () {
    test('toString', () {
      final e = RateLimitException('test msg', retryAfter: const Duration(seconds: 5));
      expect(e.toString(), 'RateLimitException: test msg');
      expect(e.retryAfter, const Duration(seconds: 5));
    });

    test('without retryAfter', () {
      final e = RateLimitException('msg');
      expect(e.retryAfter, isNull);
    });
  });

  group('GlobalRateLimiter', () {
    late GlobalRateLimiter limiter;

    setUp(() {
      limiter = GlobalRateLimiter(
        name: 'test-limiter',
        config: const RateLimiterConfig(
          maxRequestsPerSecond: 100,
          maxConcurrentRequests: 10,
          maxQueueLength: 5,
        ),
      );
    });

    tearDown(() {
      limiter.dispose();
    });

    test('basic execution', () async {
      final result = await limiter.execute(() async => 42);
      expect(result, 42);
    });

    test('execution with operation name', () async {
      final result = await limiter.execute(
        () async => 'hello',
        operationName: 'test-op',
      );
      expect(result, 'hello');
    });

    test('properties after execution', () async {
      await limiter.execute(() async => 1);
      expect(limiter.activeRequests, 0);
      expect(limiter.queueLength, 0);
    });

    test('isAtLimit', () {
      expect(limiter.isAtLimit, isFalse);
    });

    test('isQueueFull', () {
      expect(limiter.isQueueFull, isFalse);
    });

    test('currentQps', () {
      expect(limiter.currentQps, 0);
    });

    test('getStats', () {
      final stats = limiter.getStats();
      expect(stats['name'], 'test-limiter');
      expect(stats['activeRequests'], 0);
      expect(stats['totalRequests'], 0);
      expect(stats['rejectedRequests'], 0);
      expect(stats['timeoutRequests'], 0);
      expect(stats['config'], isA<Map>());
    });

    test('resetStats', () async {
      await limiter.execute(() async => 1);
      limiter.resetStats();
      final stats = limiter.getStats();
      expect(stats['totalRequests'], 0);
    });

    test('dispose rejects waiting requests', () async {
      final slowLimiter = GlobalRateLimiter(
        name: 'slow',
        config: const RateLimiterConfig(
          maxRequestsPerSecond: 1,
          maxConcurrentRequests: 1,
          maxQueueLength: 10,
        ),
      );

      // Start a slow operation
      // ignore: unawaited_futures
      slowLimiter.execute(() async {
        await Future.delayed(const Duration(seconds: 5));
        return 1;
      });

      // Wait a bit for the first request to be executing
      await Future.delayed(const Duration(milliseconds: 50));

      // Queue another
      final future = slowLimiter.execute(() async => 2);

      // Dispose while request is queued
      slowLimiter.dispose();

      expect(future, throwsA(isA<RateLimitException>()));
    });

    test('throws when disposed', () {
      limiter.dispose();
      expect(
        () => limiter.execute(() async => 1),
        throwsA(isA<StateError>()),
      );
    });

    test('queue full rejects', () async {
      final tinyLimiter = GlobalRateLimiter(
        name: 'tiny',
        config: const RateLimiterConfig(
          maxRequestsPerSecond: 100,
          maxConcurrentRequests: 1,
          maxQueueLength: 1,
        ),
      );

      final completer = Completer<int>();

      // First request executes immediately (concurrent slot open)
      final firstFuture = tinyLimiter.execute(() => completer.future);

      // Wait for first to start executing
      await Future.delayed(const Duration(milliseconds: 50));

      // Second request goes into queue (queue has space: 0 < 1)
      final secondFuture = tinyLimiter.execute(() async => 2);

      // Third request should be rejected (queue full: 1 >= 1)
      expect(
        tinyLimiter.execute(() async => 3),
        throwsA(isA<RateLimitException>()),
      );

      // Complete first request to unblock
      completer.complete(1);
      await firstFuture;
      await secondFuture;
      tinyLimiter.dispose();
    });

    test('concurrent execution', () async {
      final results = await Future.wait([
        limiter.execute(() async => 1),
        limiter.execute(() async => 2),
        limiter.execute(() async => 3),
      ]);
      expect(results, [1, 2, 3]);
    });

    test('operation error propagates', () async {
      expect(
        () => limiter.execute(() async => throw Exception('op failed')),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('GlobalRateLimiterRegistry', () {
    setUp(() {
      GlobalRateLimiterRegistry.instance.clear();
    });

    tearDown(() {
      GlobalRateLimiterRegistry.instance.clear();
    });

    test('getOrCreate', () {
      final l1 = GlobalRateLimiterRegistry.instance.getOrCreate('svc1');
      final l2 = GlobalRateLimiterRegistry.instance.getOrCreate('svc1');
      expect(identical(l1, l2), isTrue);
    });

    test('getOrCreate with config', () {
      final limiter = GlobalRateLimiterRegistry.instance.getOrCreate(
        'custom-svc',
        config: RateLimiterConfig.aiService,
      );
      expect(limiter.config.maxRequestsPerSecond, 3);
    });

    test('get existing', () {
      GlobalRateLimiterRegistry.instance.getOrCreate('svc1');
      expect(GlobalRateLimiterRegistry.instance.get('svc1'), isNotNull);
    });

    test('get non-existing', () {
      expect(GlobalRateLimiterRegistry.instance.get('unknown'), isNull);
    });

    test('getAllStats', () {
      GlobalRateLimiterRegistry.instance.getOrCreate('svc1');
      GlobalRateLimiterRegistry.instance.getOrCreate('svc2');
      final stats = GlobalRateLimiterRegistry.instance.getAllStats();
      expect(stats, hasLength(2));
    });

    test('disposeAll', () {
      GlobalRateLimiterRegistry.instance.getOrCreate('svc1');
      GlobalRateLimiterRegistry.instance.disposeAll();
      expect(GlobalRateLimiterRegistry.instance.get('svc1'), isNull);
    });
  });

  group('withRateLimit convenience function', () {
    setUp(() {
      GlobalRateLimiterRegistry.instance.clear();
    });

    tearDown(() {
      GlobalRateLimiterRegistry.instance.clear();
    });

    test('basic usage', () async {
      final result = await withRateLimit('test', () async => 42);
      expect(result, 42);
    });

    test('with config', () async {
      final result = await withRateLimit(
        'custom',
        () async => 'hello',
        config: const RateLimiterConfig(maxRequestsPerSecond: 50),
        operationName: 'my-op',
      );
      expect(result, 'hello');
    });
  });
}

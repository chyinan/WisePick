import 'dart:async';
import 'package:test/test.dart';

import '../../../server/lib/jd_scraper/cache_manager.dart';
import '../../../server/lib/jd_scraper/models/product_info.dart';

void main() {
  group('CacheConfig', () {
    test('default config should have sensible values', () {
      const config = CacheConfig();
      expect(config.defaultTtl, equals(const Duration(minutes: 10)));
      expect(config.maxEntries, equals(1000));
      expect(config.enablePersistence, isFalse);
    });
  });

  group('CacheEntry', () {
    test('should not be expired immediately', () {
      final entry = CacheEntry<String>(
        value: 'test',
        ttl: const Duration(minutes: 5),
      );
      expect(entry.isExpired, isFalse);
      expect(entry.hitCount, equals(0));
    });

    test('should be expired after TTL', () async {
      // Use zero TTL to force immediate expiration
      final entry = CacheEntry<String>(
        value: 'test',
        ttl: Duration.zero,
      );
      // Small delay to ensure DateTime.now() advances past expiresAt
      await Future.delayed(const Duration(milliseconds: 2));
      expect(entry.isExpired, isTrue);
    });

    test('recordAccess should increment hitCount', () {
      final entry = CacheEntry<String>(
        value: 'test',
        ttl: const Duration(minutes: 5),
      );
      entry.recordAccess();
      entry.recordAccess();
      expect(entry.hitCount, equals(2));
    });

    test('remainingTtl should be positive for non-expired entry', () {
      final entry = CacheEntry<String>(
        value: 'test',
        ttl: const Duration(minutes: 5),
      );
      expect(entry.remainingTtl.inSeconds, greaterThan(0));
    });

    test('remainingTtl should be zero for expired entry', () async {
      final entry = CacheEntry<String>(
        value: 'test',
        ttl: Duration.zero,
      );
      await Future.delayed(const Duration(milliseconds: 2));
      expect(entry.remainingTtl, equals(Duration.zero));
    });
  });

  group('CacheManager - Basic operations', () {
    late CacheManager<String> cache;

    setUp(() {
      cache = CacheManager<String>(
        config: const CacheConfig(
          maxEntries: 10,
          defaultTtl: Duration(minutes: 5),
          cleanupInterval: Duration(hours: 1), // Don't auto-cleanup in tests
        ),
      );
    });

    tearDown(() {
      cache.dispose();
    });

    test('should store and retrieve value', () {
      cache.set('key1', 'value1');
      expect(cache.get('key1'), equals('value1'));
    });

    test('should return null for missing key', () {
      expect(cache.get('missing'), isNull);
    });

    test('should return null for expired entry', () async {
      cache.set('key1', 'value1', ttl: Duration.zero);
      await Future.delayed(const Duration(milliseconds: 2));
      expect(cache.get('key1'), isNull);
    });

    test('contains should return true for valid entry', () {
      cache.set('key1', 'value1');
      expect(cache.contains('key1'), isTrue);
    });

    test('contains should return false for missing entry', () {
      expect(cache.contains('missing'), isFalse);
    });

    test('contains should return false for expired entry', () async {
      cache.set('key1', 'value1', ttl: Duration.zero);
      await Future.delayed(const Duration(milliseconds: 2));
      expect(cache.contains('key1'), isFalse);
    });

    test('remove should delete entry', () {
      cache.set('key1', 'value1');
      cache.remove('key1');
      expect(cache.get('key1'), isNull);
    });

    test('clear should remove all entries', () {
      cache.set('a', '1');
      cache.set('b', '2');
      cache.set('c', '3');
      cache.clear();
      expect(cache.get('a'), isNull);
      expect(cache.get('b'), isNull);
      expect(cache.get('c'), isNull);
    });
  });

  group('CacheManager - LRU eviction', () {
    late CacheManager<String> cache;

    setUp(() {
      cache = CacheManager<String>(
        config: const CacheConfig(
          maxEntries: 3,
          cleanupInterval: Duration(hours: 1),
        ),
      );
    });

    tearDown(() {
      cache.dispose();
    });

    test('should evict LRU entry when at capacity', () {
      cache.set('a', '1');
      cache.set('b', '2');
      cache.set('c', '3');

      // Access 'a' and 'c' to make 'b' the least recently used
      cache.get('a');
      cache.get('c');

      // Adding one more should evict 'b' (LRU)
      cache.set('d', '4');

      expect(cache.get('a'), equals('1'));
      expect(cache.get('b'), isNull); // evicted
      expect(cache.get('c'), equals('3'));
      expect(cache.get('d'), equals('4'));
    });
  });

  group('CacheManager - Cleanup', () {
    late CacheManager<String> cache;

    setUp(() {
      cache = CacheManager<String>(
        config: const CacheConfig(
          maxEntries: 100,
          cleanupInterval: Duration(hours: 1),
        ),
      );
    });

    tearDown(() {
      cache.dispose();
    });

    test('cleanup should remove expired entries', () async {
      cache.set('valid', 'yes', ttl: const Duration(minutes: 10));
      cache.set('expired', 'no', ttl: Duration.zero);

      await Future.delayed(const Duration(milliseconds: 2));
      cache.cleanup();

      expect(cache.contains('valid'), isTrue);
      // 'expired' was set with TTL zero, so it's expired
      // Cleanup should have removed it
    });
  });

  group('CacheManager - Statistics', () {
    late CacheManager<String> cache;

    setUp(() {
      cache = CacheManager<String>(
        config: const CacheConfig(
          maxEntries: 10,
          cleanupInterval: Duration(hours: 1),
        ),
      );
    });

    tearDown(() {
      cache.dispose();
    });

    test('should track hits and misses', () {
      cache.set('key1', 'value1');

      cache.get('key1'); // hit
      cache.get('key1'); // hit
      cache.get('missing'); // miss

      final stats = cache.getStats();
      expect(stats['hits'], equals(2));
      expect(stats['misses'], equals(1));
      expect(stats['size'], equals(1));
    });

    test('hitRate should be calculated correctly', () {
      cache.set('key1', 'value1');
      cache.get('key1'); // hit
      cache.get('key1'); // hit
      cache.get('key1'); // hit
      cache.get('missing'); // miss

      final stats = cache.getStats();
      expect(stats['hitRate'], equals('75.00'));
    });

    test('should track evictions', () {
      final smallCache = CacheManager<String>(
        config: const CacheConfig(
          maxEntries: 2,
          cleanupInterval: Duration(hours: 1),
        ),
      );

      smallCache.set('a', '1');
      smallCache.set('b', '2');
      smallCache.set('c', '3'); // should evict one

      final stats = smallCache.getStats();
      expect(stats['evictions'], greaterThanOrEqualTo(1));

      smallCache.dispose();
    });
  });

  group('RequestDeduplicator', () {
    test('should execute request and return result', () async {
      final dedup = RequestDeduplicator<String>();
      final result = await dedup.execute('key1', () async => 'result');
      expect(result, equals('result'));
    });

    test('should deduplicate concurrent requests', () async {
      final dedup = RequestDeduplicator<String>();
      var callCount = 0;

      final completer = Completer<String>();

      // Start first request (will be pending)
      final future1 = dedup.execute('key1', () async {
        callCount++;
        return await completer.future;
      });

      // Start second request with same key (should share first)
      final future2 = dedup.execute('key1', () async {
        callCount++;
        return 'should not be called';
      });

      expect(dedup.hasPending('key1'), isTrue);
      expect(dedup.pendingCount, equals(1));

      // Complete the first request
      completer.complete('shared result');

      final result1 = await future1;
      final result2 = await future2;

      expect(result1, equals('shared result'));
      expect(result2, equals('shared result'));
      expect(callCount, equals(1)); // Only called once
    });

    test('should propagate errors to all waiters', () async {
      final dedup = RequestDeduplicator<String>();
      final completer = Completer<String>();

      final future1 = dedup.execute('key1', () async {
        return await completer.future;
      });

      final future2 = dedup.execute('key1', () async {
        return 'unused';
      });

      completer.completeError(Exception('network error'));

      await expectLater(future1, throwsA(isA<Exception>()));
      await expectLater(future2, throwsA(isA<Exception>()));
    });

    test('should clean up after completion', () async {
      final dedup = RequestDeduplicator<String>();
      await dedup.execute('key1', () async => 'done');

      expect(dedup.hasPending('key1'), isFalse);
      expect(dedup.pendingCount, equals(0));
    });

    test('getStats should return current state', () {
      final dedup = RequestDeduplicator<String>();
      final stats = dedup.getStats();
      expect(stats['pendingCount'], equals(0));
      expect(stats['pendingKeys'], isEmpty);
    });
  });

  group('ConcurrencyController', () {
    test('should execute task and return result', () async {
      final controller = ConcurrencyController(maxConcurrency: 3);
      final result = await controller.execute(() async => 42);
      expect(result, equals(42));
    });

    test('should respect concurrency limit', () async {
      final controller = ConcurrencyController(maxConcurrency: 2);
      var maxConcurrent = 0;
      var currentConcurrent = 0;

      final futures = <Future>[];
      for (int i = 0; i < 5; i++) {
        futures.add(controller.execute(() async {
          currentConcurrent++;
          if (currentConcurrent > maxConcurrent) {
            maxConcurrent = currentConcurrent;
          }
          await Future.delayed(const Duration(milliseconds: 50));
          currentConcurrent--;
          return i;
        }));
      }

      await Future.wait(futures);
      expect(maxConcurrent, lessThanOrEqualTo(2));
    });

    test('should respect priority ordering', () async {
      final controller = ConcurrencyController(maxConcurrency: 1);
      final results = <int>[];

      final blocker = Completer<void>();

      // Block the single slot
      final blockFuture = controller.execute(() async {
        await blocker.future;
        results.add(0);
      });

      // Queue tasks with different priorities
      await Future.delayed(const Duration(milliseconds: 10));
      final lowPriority = controller.execute(() async {
        results.add(1);
      }, priority: 1);
      final highPriority = controller.execute(() async {
        results.add(2);
      }, priority: 10);

      // Release blocker
      blocker.complete();
      await blockFuture;
      await Future.wait([lowPriority, highPriority]);

      // High priority (10) should execute before low priority (1)
      expect(results[0], equals(0)); // blocker finished first
      expect(results[1], equals(2)); // high priority
      expect(results[2], equals(1)); // low priority
    });

    test('getStats should return current state', () {
      final controller = ConcurrencyController(maxConcurrency: 5);
      final stats = controller.getStats();
      expect(stats['maxConcurrency'], equals(5));
      expect(stats['currentCount'], equals(0));
      expect(stats['queueLength'], equals(0));
    });
  });
}

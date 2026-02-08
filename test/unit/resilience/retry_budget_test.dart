import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/resilience/retry_budget.dart';

void main() {
  group('RetryBudgetConfig', () {
    test('default config should have sensible values', () {
      const config = RetryBudgetConfig();
      expect(config.maxRetryRatio, greaterThan(0));
      expect(config.maxRetryRatio, lessThan(1));
      expect(config.minRetriesPerWindow, greaterThan(0));
      expect(config.windowDuration.inSeconds, greaterThan(0));
    });

    test('conservative should have lower ratio than aggressive', () {
      expect(RetryBudgetConfig.conservative.maxRetryRatio,
          lessThan(RetryBudgetConfig.aggressive.maxRetryRatio));
    });
  });

  group('RetryBudget - Basic operations', () {
    late RetryBudget budget;

    setUp(() {
      budget = RetryBudget(
        name: 'test',
        config: const RetryBudgetConfig(
          maxRetryRatio: 0.2,
          minRetriesPerWindow: 5,
          windowDuration: Duration(seconds: 10),
          allowOverdraft: false,
        ),
      );
    });

    test('should allow retries when budget is available', () {
      // Record some requests first
      for (int i = 0; i < 10; i++) {
        budget.recordRequest();
      }

      // Should allow retries (min is 5, and 20% of 10 = 2, so budget is max(5, 2) = 5)
      expect(budget.canRetry(), isTrue);
      expect(budget.tryAcquireRetryPermit(), isTrue);
    });

    test('should have minimum retries even with no requests', () {
      // No requests recorded, but minRetriesPerWindow = 5
      expect(budget.canRetry(), isTrue);
      for (int i = 0; i < 5; i++) {
        expect(budget.tryAcquireRetryPermit(), isTrue);
      }
      // 6th retry should be denied (budget is 5)
      expect(budget.tryAcquireRetryPermit(), isFalse);
    });

    test('should deny retries when budget is exhausted', () {
      // Exhaust the minimum retry budget
      for (int i = 0; i < 5; i++) {
        budget.tryAcquireRetryPermit();
      }
      expect(budget.canRetry(), isFalse);
      expect(budget.tryAcquireRetryPermit(), isFalse);
    });

    test('remainingBudget should decrease with retries', () {
      final initial = budget.remainingBudget;
      budget.tryAcquireRetryPermit();
      expect(budget.remainingBudget, equals(initial - 1));
    });

    test('currentRetryRate should reflect actual rate', () {
      budget.recordRequest();
      budget.recordRequest();
      budget.tryAcquireRetryPermit();

      // 3 total records: 2 requests + 1 retry
      // retry rate = 1/3
      expect(budget.currentRetryRate, closeTo(1.0 / 3.0, 0.01));
    });

    test('reset should clear all state', () {
      budget.recordRequest();
      budget.tryAcquireRetryPermit();

      budget.reset();

      expect(budget.remainingBudget, equals(5)); // minRetriesPerWindow
      expect(budget.currentRetryRate, equals(0.0));
    });
  });

  group('RetryBudget - Overdraft', () {
    late RetryBudget budget;

    setUp(() {
      budget = RetryBudget(
        name: 'overdraft_test',
        config: const RetryBudgetConfig(
          maxRetryRatio: 0.2,
          minRetriesPerWindow: 2,
          // Use short window so old retries expire during cooldown wait
          windowDuration: Duration(milliseconds: 100),
          allowOverdraft: true,
          overdraftCooldown: Duration(milliseconds: 200),
        ),
      );
    });

    test('should allow overdraft when enabled', () {
      // Exhaust budget
      budget.tryAcquireRetryPermit();
      budget.tryAcquireRetryPermit();

      // Third retry should succeed via overdraft
      expect(budget.tryAcquireRetryPermit(), isTrue);
    });

    test('should enter cooldown after overdraft', () async {
      // Exhaust budget
      budget.tryAcquireRetryPermit();
      budget.tryAcquireRetryPermit();

      // Use overdraft
      budget.tryAcquireRetryPermit();

      // Should be in cooldown now
      expect(budget.canRetry(), isFalse);
      expect(budget.tryAcquireRetryPermit(), isFalse);
    });

    test('should recover after cooldown period', () async {
      // Exhaust and overdraft
      budget.tryAcquireRetryPermit();
      budget.tryAcquireRetryPermit();
      budget.tryAcquireRetryPermit(); // overdraft

      // Wait for cooldown
      await Future.delayed(const Duration(milliseconds: 300));

      // Should be able to retry again (new window)
      expect(budget.canRetry(), isTrue);
    });
  });

  group('RetryBudget - Statistics', () {
    test('getStats should return comprehensive statistics', () {
      final budget = RetryBudget(name: 'stats_test');
      budget.recordRequest();
      budget.recordRequest();
      budget.tryAcquireRetryPermit();

      final stats = budget.getStats();
      expect(stats['name'], equals('stats_test'));
      expect(stats.containsKey('windowRequests'), isTrue);
      expect(stats.containsKey('windowRetries'), isTrue);
      expect(stats.containsKey('currentBudget'), isTrue);
      expect(stats.containsKey('remainingBudget'), isTrue);
      expect(stats.containsKey('currentRetryRate'), isTrue);
      expect(stats.containsKey('total'), isTrue);
    });
  });

  group('RetryBudgetRegistry', () {
    tearDown(() {
      RetryBudgetRegistry.instance.resetAll();
    });

    test('should create and retrieve budgets', () {
      final budget = RetryBudgetRegistry.instance.getOrCreate('svc_a');
      expect(budget, isNotNull);
      expect(budget.name, equals('svc_a'));

      final same = RetryBudgetRegistry.instance.getOrCreate('svc_a');
      expect(identical(budget, same), isTrue);
    });

    test('should return null for non-existent budget', () {
      expect(RetryBudgetRegistry.instance.get('missing'), isNull);
    });
  });

  group('Convenience functions', () {
    tearDown(() {
      RetryBudgetRegistry.instance.resetAll();
    });

    test('recordRequest should record to correct budget', () {
      recordRequest('conv_test');
      final budget = RetryBudgetRegistry.instance.get('conv_test');
      expect(budget, isNotNull);
    });

    test('canRetry should check correct budget', () {
      expect(canRetry('conv_test'), isTrue);
    });

    test('tryAcquireRetryPermit should use correct budget', () {
      expect(tryAcquireRetryPermit('conv_test'), isTrue);
    });
  });
}

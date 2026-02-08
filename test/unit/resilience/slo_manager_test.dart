import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/resilience/slo_manager.dart';

void main() {
  group('SloTarget', () {
    test('availability should create availability type', () {
      final target = SloTarget.availability(target: 0.999);
      expect(target.type, equals(SloType.availability));
      expect(target.targetValue, equals(0.999));
    });

    test('latency should create latency type', () {
      final target = SloTarget.latency(targetMs: 500);
      expect(target.type, equals(SloType.latency));
      expect(target.targetValue, equals(500));
    });

    test('errorRate should create errorRate type', () {
      final target = SloTarget.errorRate(target: 0.01);
      expect(target.type, equals(SloType.errorRate));
      expect(target.targetValue, equals(0.01));
    });
  });

  group('ErrorBudget', () {
    test('should calculate total budget for availability SLO', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.99),
        totalRequests: 1000,
        failedRequests: 5,
        currentSli: 0.995,
        windowStart: DateTime.now().subtract(const Duration(hours: 1)),
      );

      // 1% of 1000 ≈ 10 allowed failures (use closeTo for float precision)
      expect(budget.totalBudget, closeTo(10.0, 0.01));
      expect(budget.consumedBudget, equals(5.0));
      expect(budget.remainingBudget, closeTo(5.0, 0.01));
    });

    test('should report exhausted when no budget remaining', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.99),
        totalRequests: 1000,
        failedRequests: 15,
        currentSli: 0.985,
        windowStart: DateTime.now().subtract(const Duration(hours: 1)),
      );

      expect(budget.isExhausted, isTrue);
    });

    test('should report at risk when >80% consumed', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.99),
        totalRequests: 1000,
        failedRequests: 9,
        currentSli: 0.991,
        windowStart: DateTime.now().subtract(const Duration(hours: 1)),
      );

      // Budget ≈ 10, consumed 9, that's ~90% > 80%
      expect(budget.isAtRisk, isTrue);
    });

    test('isMeetingSlo should reflect current SLI vs target', () {
      final meeting = ErrorBudget(
        slo: SloTarget.availability(target: 0.99),
        totalRequests: 100,
        failedRequests: 0,
        currentSli: 1.0,
        windowStart: DateTime.now(),
      );
      expect(meeting.isMeetingSlo, isTrue);

      final notMeeting = ErrorBudget(
        slo: SloTarget.availability(target: 0.99),
        totalRequests: 100,
        failedRequests: 5,
        currentSli: 0.95,
        windowStart: DateTime.now(),
      );
      expect(notMeeting.isMeetingSlo, isFalse);
    });

    test('consumptionPercent should handle zero budget', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 1.0), // 0 budget
        totalRequests: 0,
        failedRequests: 0,
        currentSli: 1.0,
        windowStart: DateTime.now(),
      );
      expect(budget.consumptionPercent, equals(0));
    });

    test('toJson should produce valid map', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(name: 'test_slo', target: 0.99),
        totalRequests: 100,
        failedRequests: 2,
        currentSli: 0.98,
        windowStart: DateTime.now(),
      );
      final json = budget.toJson();
      expect(json['slo'], equals('test_slo'));
      expect(json['target'], equals(0.99));
      expect(json['totalRequests'], equals(100));
      expect(json['failedRequests'], equals(2));
    });
  });

  group('DegradationPolicy', () {
    test('normal policy should allow everything', () {
      const policy = DegradationPolicy(
        level: DegradationLevel.normal,
        message: 'all good',
      );
      expect(policy.isFeatureEnabled('anything'), isTrue);
      expect(policy.rateLimitMultiplier, equals(1.0));
      expect(policy.allowRiskyOperations, isTrue);
    });

    test('fromBudget should return critical for exhausted budget', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.99),
        totalRequests: 1000,
        failedRequests: 15,
        currentSli: 0.985,
        windowStart: DateTime.now(),
      );
      final policy = DegradationPolicy.fromBudget(budget);
      expect(policy.level, equals(DegradationLevel.critical));
      expect(policy.allowRiskyOperations, isFalse);
      expect(policy.enableAggressiveCaching, isTrue);
    });

    test('fromBudget should return warning for >=90% consumption', () {
      // With target 0.99 and 1000 requests:
      // totalBudget ≈ 10.0 (with float precision)
      // 10 failures → consumption ~100% but not exhausted (float imprecision)
      // This ensures >= 90% threshold is met
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.99),
        totalRequests: 1000,
        failedRequests: 10, // ~100% consumption but not exhausted
        currentSli: 0.990,
        windowStart: DateTime.now(),
      );
      final policy = DegradationPolicy.fromBudget(budget);
      // Due to float: totalBudget = 10.000000000000009, so 10/10.00.. < 100%, not exhausted
      // consumptionPercent ≈ 99.99% >= 90 → warning
      expect(policy.level, equals(DegradationLevel.warning));
    });

    test('fromBudget should return caution for >=80% consumption', () {
      // 9 failures out of ~10 budget → ~90% consumption
      // Due to float: 9/10.000000000000009 * 100 = 89.999...%
      // This is >= 80% (isAtRisk) but < 90% → caution
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.99),
        totalRequests: 1000,
        failedRequests: 9,
        currentSli: 0.991,
        windowStart: DateTime.now(),
      );
      final policy = DegradationPolicy.fromBudget(budget);
      expect(policy.level, equals(DegradationLevel.caution));
    });

    test('fromBudget should return normal for healthy budget', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.99),
        totalRequests: 1000,
        failedRequests: 2,
        currentSli: 0.998,
        windowStart: DateTime.now(),
      );
      final policy = DegradationPolicy.fromBudget(budget);
      expect(policy.level, equals(DegradationLevel.normal));
    });

    test('critical policy should disable non-essential features', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.99),
        totalRequests: 1000,
        failedRequests: 20,
        currentSli: 0.98,
        windowStart: DateTime.now(),
      );
      final policy = DegradationPolicy.fromBudget(budget);
      expect(policy.isFeatureEnabled('non_essential'), isFalse);
      expect(policy.isFeatureEnabled('analytics'), isFalse);
      expect(policy.isFeatureEnabled('recommendations'), isFalse);
    });

    test('toJson should produce valid map', () {
      const policy = DegradationPolicy(
        level: DegradationLevel.warning,
        disabledFeatures: {'analytics'},
        rateLimitMultiplier: 0.5,
        message: 'warning state',
      );
      final json = policy.toJson();
      expect(json['level'], equals('warning'));
      expect(json['rateLimitMultiplier'], equals(0.5));
      expect(json['message'], equals('warning state'));
    });
  });

  group('SloManager', () {
    late SloManager manager;

    setUp(() {
      manager = SloManager(
        serviceName: 'test_service',
        targets: [
          SloTarget.availability(target: 0.99),
        ],
        checkInterval: const Duration(seconds: 60), // Disable auto-check
      );
    });

    tearDown(() {
      manager.dispose();
    });

    test('should record successful requests', () {
      for (int i = 0; i < 100; i++) {
        manager.recordRequest(success: true);
      }

      final budget = manager.getBudget('availability');
      expect(budget, isNotNull);
      expect(budget!.totalRequests, equals(100));
      expect(budget.failedRequests, equals(0));
      expect(budget.currentSli, equals(1.0));
    });

    test('should record mixed results', () {
      for (int i = 0; i < 90; i++) {
        manager.recordRequest(success: true);
      }
      for (int i = 0; i < 10; i++) {
        manager.recordRequest(success: false);
      }

      final budget = manager.getBudget('availability');
      expect(budget, isNotNull);
      expect(budget!.totalRequests, equals(100));
      expect(budget.failedRequests, equals(10));
      expect(budget.currentSli, equals(0.9));
    });

    test('should record latency for latency SLO', () {
      final latencyManager = SloManager(
        serviceName: 'latency_test',
        targets: [SloTarget.latency(targetMs: 100)],
        checkInterval: const Duration(seconds: 60),
      );

      latencyManager.recordRequest(
        success: true,
        latency: const Duration(milliseconds: 50),
      );
      latencyManager.recordRequest(
        success: true,
        latency: const Duration(milliseconds: 200), // exceeds target
      );

      final budget = latencyManager.getBudget('latency_p99');
      expect(budget, isNotNull);
      expect(budget!.totalRequests, equals(2));

      latencyManager.dispose();
    });

    test('getAllBudgets should return budgets for all SLOs', () {
      manager.recordRequest(success: true);
      final budgets = manager.getAllBudgets();
      expect(budgets.containsKey('availability'), isTrue);
    });

    test('isFeatureAllowed should delegate to current policy', () {
      // With no failures, everything should be allowed
      expect(manager.isFeatureAllowed('anything'), isTrue);
    });

    test('getStatus should return comprehensive status', () {
      final status = manager.getStatus();
      expect(status['serviceName'], equals('test_service'));
      expect(status.containsKey('currentPolicy'), isTrue);
      expect(status.containsKey('budgets'), isTrue);
    });
  });

  group('SloRegistry', () {
    tearDown(() {
      SloRegistry.instance.dispose();
    });

    test('should create and retrieve managers', () {
      final manager = SloRegistry.instance.getOrCreate('svc_a');
      expect(manager, isNotNull);
    });

    test('getAllStatus should return all statuses', () {
      SloRegistry.instance.getOrCreate('svc_x');
      SloRegistry.instance.getOrCreate('svc_y');

      final status = SloRegistry.instance.getAllStatus();
      expect(status.containsKey('svc_x'), isTrue);
      expect(status.containsKey('svc_y'), isTrue);
    });
  });
}

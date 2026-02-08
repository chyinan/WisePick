import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/resilience/slo_manager.dart';

void main() {
  group('SloTarget', () {
    test('availability preset', () {
      final target = SloTarget.availability();
      expect(target.name, 'availability');
      expect(target.targetValue, 0.999);
      expect(target.type, SloType.availability);
      expect(target.window, const Duration(days: 30));
    });

    test('availability preset with custom values', () {
      final target = SloTarget.availability(
        name: 'custom-avail',
        target: 0.95,
        window: const Duration(days: 7),
      );
      expect(target.name, 'custom-avail');
      expect(target.targetValue, 0.95);
      expect(target.window, const Duration(days: 7));
    });

    test('latency preset', () {
      final target = SloTarget.latency();
      expect(target.name, 'latency_p99');
      expect(target.targetValue, 500);
      expect(target.type, SloType.latency);
      expect(target.window, const Duration(hours: 1));
    });

    test('latency preset with custom values', () {
      final target = SloTarget.latency(
        name: 'custom-lat',
        targetMs: 200,
        window: const Duration(minutes: 30),
      );
      expect(target.name, 'custom-lat');
      expect(target.targetValue, 200);
    });

    test('errorRate preset', () {
      final target = SloTarget.errorRate();
      expect(target.name, 'error_rate');
      expect(target.targetValue, 0.001);
      expect(target.type, SloType.errorRate);
    });

    test('errorRate preset with custom values', () {
      final target = SloTarget.errorRate(
        name: 'custom-err',
        target: 0.01,
        window: const Duration(minutes: 15),
      );
      expect(target.name, 'custom-err');
      expect(target.targetValue, 0.01);
    });

    test('constructor', () {
      final target = SloTarget(
        name: 'throughput',
        targetValue: 100,
        window: const Duration(hours: 1),
        type: SloType.throughput,
      );
      expect(target.name, 'throughput');
      expect(target.type, SloType.throughput);
    });
  });

  group('SloType', () {
    test('all values', () {
      expect(SloType.values, hasLength(4));
      expect(SloType.values, contains(SloType.availability));
      expect(SloType.values, contains(SloType.latency));
      expect(SloType.values, contains(SloType.errorRate));
      expect(SloType.values, contains(SloType.throughput));
    });
  });

  group('ErrorBudget', () {
    test('availability budget - no failures', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.99),
        totalRequests: 1000,
        failedRequests: 0,
        currentSli: 1.0,
        windowStart: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(budget.totalBudget, closeTo(10.0, 0.01)); // (1-0.99)*1000
      expect(budget.consumedBudget, 0);
      expect(budget.remainingBudget, closeTo(10.0, 0.01));
      expect(budget.consumptionPercent, 0);
      expect(budget.isExhausted, isFalse);
      expect(budget.isAtRisk, isFalse);
      expect(budget.isMeetingSlo, isTrue);
    });

    test('availability budget - at risk', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.99),
        totalRequests: 1000,
        failedRequests: 9,
        currentSli: 0.991,
        windowStart: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(budget.totalBudget, closeTo(10.0, 0.01));
      expect(budget.consumedBudget, 9.0);
      expect(budget.remainingBudget, closeTo(1.0, 0.01));
      expect(budget.consumptionPercent, closeTo(90.0, 0.1));
      expect(budget.isExhausted, isFalse);
      expect(budget.isAtRisk, isTrue);
      expect(budget.isMeetingSlo, isTrue);
    });

    test('availability budget - exhausted', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.99),
        totalRequests: 1000,
        failedRequests: 15,
        currentSli: 0.985,
        windowStart: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(budget.isExhausted, isTrue);
      expect(budget.remainingBudget, 0);
      expect(budget.isMeetingSlo, isFalse);
    });

    test('errorRate budget type', () {
      final budget = ErrorBudget(
        slo: SloTarget.errorRate(target: 0.01),
        totalRequests: 1000,
        failedRequests: 5,
        currentSli: 0.995,
        windowStart: DateTime.now().subtract(const Duration(hours: 1)),
      );
      // errorRate: totalBudget = (1-0.01)*1000 = 990
      expect(budget.totalBudget, 990.0);
    });

    test('latency budget type', () {
      final budget = ErrorBudget(
        slo: SloTarget.latency(targetMs: 500),
        totalRequests: 100,
        failedRequests: 5,
        currentSli: 0.95,
        windowStart: DateTime.now().subtract(const Duration(hours: 1)),
      );
      // latency type: totalBudget = targetValue = 500
      expect(budget.totalBudget, 500);
    });

    test('throughput budget type', () {
      final budget = ErrorBudget(
        slo: SloTarget(
          name: 'tp',
          targetValue: 100,
          window: const Duration(hours: 1),
          type: SloType.throughput,
        ),
        totalRequests: 50,
        failedRequests: 0,
        currentSli: 1.0,
        windowStart: DateTime.now().subtract(const Duration(hours: 1)),
      );
      // throughput: totalBudget = targetValue
      expect(budget.totalBudget, 100);
    });

    test('zero budget edge case', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 1.0), // 100% - no budget
        totalRequests: 100,
        failedRequests: 0,
        currentSli: 1.0,
        windowStart: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(budget.totalBudget, 0);
      expect(budget.consumptionPercent, 0); // 0/0 → 0
    });

    test('burnRate', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.99),
        totalRequests: 1000,
        failedRequests: 5,
        currentSli: 0.995,
        windowStart: DateTime.now().subtract(const Duration(hours: 2)),
      );
      expect(budget.burnRate, closeTo(2.5, 0.5)); // 5 failures / 2 hours
    });

    test('burnRate early window', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.99),
        totalRequests: 10,
        failedRequests: 1,
        currentSli: 0.9,
        windowStart: DateTime.now(), // just started
      );
      expect(budget.burnRate, 0); // less than 1 minute
    });

    test('projectedExhaustionTime', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.99),
        totalRequests: 1000,
        failedRequests: 5,
        currentSli: 0.995,
        windowStart: DateTime.now().subtract(const Duration(hours: 2)),
      );
      final projection = budget.projectedExhaustionTime;
      expect(projection, isNotNull);
    });

    test('projectedExhaustionTime null when no burnRate', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.99),
        totalRequests: 10,
        failedRequests: 0,
        currentSli: 1.0,
        windowStart: DateTime.now(),
      );
      expect(budget.projectedExhaustionTime, isNull);
    });

    test('projectedExhaustionTime null when exhausted', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.99),
        totalRequests: 1000,
        failedRequests: 20,
        currentSli: 0.98,
        windowStart: DateTime.now().subtract(const Duration(hours: 2)),
      );
      expect(budget.projectedExhaustionTime, isNull);
    });

    test('windowRemaining', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(window: const Duration(hours: 1)),
        totalRequests: 100,
        failedRequests: 0,
        currentSli: 1.0,
        windowStart: DateTime.now().subtract(const Duration(minutes: 30)),
      );
      expect(budget.windowRemaining.inMinutes, greaterThan(20));
    });

    test('windowRemaining expired', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(window: const Duration(hours: 1)),
        totalRequests: 100,
        failedRequests: 0,
        currentSli: 1.0,
        windowStart: DateTime.now().subtract(const Duration(hours: 2)),
      );
      expect(budget.windowRemaining, Duration.zero);
    });

    test('toJson', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.99),
        totalRequests: 1000,
        failedRequests: 5,
        currentSli: 0.995,
        windowStart: DateTime.now().subtract(const Duration(hours: 2)),
      );
      final json = budget.toJson();
      expect(json['slo'], 'availability');
      expect(json['target'], 0.99);
      expect(json['currentSli'], 0.995);
      expect(json['totalRequests'], 1000);
      expect(json['failedRequests'], 5);
      expect(json['totalBudget'], isA<double>());
      expect(json['consumedBudget'], isA<double>());
      expect(json['remainingBudget'], isA<double>());
      expect(json['consumptionPercent'], isA<String>());
      expect(json['isExhausted'], isFalse);
      expect(json['isAtRisk'], isFalse);
      expect(json['isMeetingSlo'], isTrue);
      expect(json['burnRate'], isA<String>());
    });

    test('toJson with projectedExhaustion', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.99),
        totalRequests: 1000,
        failedRequests: 5,
        currentSli: 0.995,
        windowStart: DateTime.now().subtract(const Duration(hours: 2)),
      );
      final json = budget.toJson();
      expect(json.containsKey('projectedExhaustion'), isTrue);
    });
  });

  group('DegradationLevel', () {
    test('all values', () {
      expect(DegradationLevel.values, hasLength(4));
      expect(DegradationLevel.normal.index, 0);
      expect(DegradationLevel.caution.index, 1);
      expect(DegradationLevel.warning.index, 2);
      expect(DegradationLevel.critical.index, 3);
    });
  });

  group('DegradationPolicy', () {
    test('fromBudget normal', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.99),
        totalRequests: 1000,
        failedRequests: 0,
        currentSli: 1.0,
        windowStart: DateTime.now(),
      );
      final policy = DegradationPolicy.fromBudget(budget);
      expect(policy.level, DegradationLevel.normal);
      expect(policy.allowRiskyOperations, isTrue);
      expect(policy.enableAggressiveCaching, isFalse);
      expect(policy.rateLimitMultiplier, 1.0);
      expect(policy.disabledFeatures, isEmpty);
    });

    test('fromBudget at risk not warning', () {
      // Use 0.9 target, 100 requests, 8 failures => totalBudget=10, consumption=80%
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.9),
        totalRequests: 100,
        failedRequests: 8,
        currentSli: 0.92,
        windowStart: DateTime.now(),
      );
      final policy = DegradationPolicy.fromBudget(budget);
      // isAtRisk=true, consumptionPercent=80%, <90 => caution
      expect(policy.level, DegradationLevel.caution);
    });

    test('fromBudget warning (>=90%)', () {
      // totalBudget=10, consumed=9, consumption=90% but not exhausted
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.9),
        totalRequests: 100,
        failedRequests: 9,
        currentSli: 0.91,
        windowStart: DateTime.now(),
      );
      final policy = DegradationPolicy.fromBudget(budget);
      expect(policy.level, DegradationLevel.warning);
      expect(policy.allowRiskyOperations, isFalse);
      expect(policy.enableAggressiveCaching, isTrue);
      expect(policy.rateLimitMultiplier, 0.5);
    });

    test('fromBudget critical (exhausted)', () {
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.9),
        totalRequests: 100,
        failedRequests: 20,
        currentSli: 0.8,
        windowStart: DateTime.now(),
      );
      final policy = DegradationPolicy.fromBudget(budget);
      expect(policy.level, DegradationLevel.critical);
      expect(policy.allowRiskyOperations, isFalse);
      expect(policy.enableAggressiveCaching, isTrue);
      expect(policy.rateLimitMultiplier, 0.25);
      expect(policy.disabledFeatures, contains('non_essential'));
      expect(policy.disabledFeatures, contains('analytics'));
      expect(policy.disabledFeatures, contains('recommendations'));
    });

    test('fromBudget caution level (isAtRisk, <90%)', () {
      // totalBudget=10, consumed=8, consumption=80% => isAtRisk=true
      final budget = ErrorBudget(
        slo: SloTarget.availability(target: 0.9),
        totalRequests: 100,
        failedRequests: 8,
        currentSli: 0.92,
        windowStart: DateTime.now(),
      );
      final policy = DegradationPolicy.fromBudget(budget);
      expect(policy.level, DegradationLevel.caution);
      expect(policy.rateLimitMultiplier, 0.75);
      expect(policy.disabledFeatures, contains('analytics'));
    });

    test('isFeatureEnabled', () {
      const policy = DegradationPolicy(
        level: DegradationLevel.warning,
        disabledFeatures: {'analytics', 'recommendations'},
      );
      expect(policy.isFeatureEnabled('core'), isTrue);
      expect(policy.isFeatureEnabled('analytics'), isFalse);
      expect(policy.isFeatureEnabled('recommendations'), isFalse);
    });

    test('toJson', () {
      const policy = DegradationPolicy(
        level: DegradationLevel.caution,
        disabledFeatures: {'analytics'},
        rateLimitMultiplier: 0.75,
        allowRiskyOperations: true,
        enableAggressiveCaching: false,
        message: 'test msg',
      );
      final json = policy.toJson();
      expect(json['level'], 'caution');
      expect(json['disabledFeatures'], ['analytics']);
      expect(json['rateLimitMultiplier'], 0.75);
      expect(json['allowRiskyOperations'], isTrue);
      expect(json['enableAggressiveCaching'], isFalse);
      expect(json['message'], 'test msg');
    });
  });

  group('SloManager', () {
    late SloManager manager;

    setUp(() {
      manager = SloManager(
        serviceName: 'test-svc',
        targets: [
          SloTarget.availability(target: 0.99),
          SloTarget.latency(targetMs: 500),
          SloTarget.errorRate(target: 0.01),
        ],
        checkInterval: const Duration(milliseconds: 100),
      );
    });

    tearDown(() {
      manager.dispose();
    });

    test('initial state', () {
      expect(manager.currentPolicy.level, DegradationLevel.normal);
      expect(manager.degradationLevel, DegradationLevel.normal);
      expect(manager.serviceName, 'test-svc');
    });

    test('recordRequest for availability', () {
      manager.recordRequest(success: true);
      manager.recordRequest(success: false);
      final budget = manager.getBudget('availability');
      expect(budget, isNotNull);
      expect(budget!.totalRequests, 2);
      expect(budget.failedRequests, 1);
    });

    test('recordRequest for latency', () {
      manager.recordRequest(
        success: true,
        latency: const Duration(milliseconds: 100),
      );
      manager.recordRequest(
        success: true,
        latency: const Duration(milliseconds: 600), // over target
      );
      final budget = manager.getBudget('latency_p99');
      expect(budget, isNotNull);
      expect(budget!.totalRequests, 2);
    });

    test('recordRequest with specific sloName', () {
      manager.recordRequest(success: true, sloName: 'availability');
      final availBudget = manager.getBudget('availability');
      final errBudget = manager.getBudget('error_rate');
      expect(availBudget!.totalRequests, 1);
      expect(errBudget!.totalRequests, 0);
    });

    test('recordRequest for throughput type', () {
      final m = SloManager(
        serviceName: 'tp-svc',
        targets: [
          SloTarget(
            name: 'throughput',
            targetValue: 100,
            window: const Duration(hours: 1),
            type: SloType.throughput,
          ),
        ],
      );
      m.recordRequest(success: true);
      final budget = m.getBudget('throughput');
      expect(budget!.totalRequests, 1);
      expect(budget.failedRequests, 0);
      m.dispose();
    });

    test('getAllBudgets', () {
      manager.recordRequest(success: true);
      final budgets = manager.getAllBudgets();
      expect(budgets, hasLength(3));
      expect(budgets.containsKey('availability'), isTrue);
      expect(budgets.containsKey('latency_p99'), isTrue);
      expect(budgets.containsKey('error_rate'), isTrue);
    });

    test('getBudget returns null for unknown', () {
      expect(manager.getBudget('unknown'), isNull);
    });

    test('isFeatureAllowed', () {
      // Initially normal policy - all features allowed
      expect(manager.isFeatureAllowed('analytics'), isTrue);
      expect(manager.isFeatureAllowed('non_essential'), isTrue);
    });

    test('rateLimitMultiplier', () {
      expect(manager.rateLimitMultiplier, 1.0);
    });

    test('getStatus', () {
      final status = manager.getStatus();
      expect(status['serviceName'], 'test-svc');
      expect(status['currentPolicy'], isA<Map>());
      expect(status['budgets'], isA<Map>());
    });

    test('policy changes when budget exhausted', () async {
      DegradationPolicy? lastPolicy;
      final m = SloManager(
        serviceName: 'policy-svc',
        targets: [SloTarget.availability(target: 0.99)],
        checkInterval: const Duration(milliseconds: 50),
        onPolicyChange: (p) => lastPolicy = p,
      );

      // Record many failures to exhaust budget
      for (var i = 0; i < 100; i++) {
        m.recordRequest(success: false);
      }

      // Wait for check interval to fire
      await Future.delayed(const Duration(milliseconds: 200));
      expect(lastPolicy, isNotNull);
      expect(lastPolicy!.level, DegradationLevel.critical);
      m.dispose();
    });

    test('budget alert callback', () async {
      String? alertedSlo;
      final m = SloManager(
        serviceName: 'alert-svc',
        targets: [SloTarget.availability(target: 0.99)],
        checkInterval: const Duration(milliseconds: 50),
        onBudgetAlert: (name, budget) => alertedSlo = name,
      );

      // Exhaust budget
      for (var i = 0; i < 100; i++) {
        m.recordRequest(success: false);
      }

      await Future.delayed(const Duration(milliseconds: 200));
      expect(alertedSlo, 'availability');
      m.dispose();
    });
  });

  group('SloRegistry', () {
    setUp(() {
      // Clean existing managers
      SloRegistry.instance.dispose();
    });

    tearDown(() {
      SloRegistry.instance.dispose();
    });

    test('getOrCreate creates new manager', () {
      final manager = SloRegistry.instance.getOrCreate('reg-svc');
      expect(manager.serviceName, 'reg-svc');
    });

    test('getOrCreate returns same manager', () {
      final m1 = SloRegistry.instance.getOrCreate('reg-svc');
      final m2 = SloRegistry.instance.getOrCreate('reg-svc');
      expect(identical(m1, m2), isTrue);
    });

    test('getOrCreate with custom targets', () {
      final manager = SloRegistry.instance.getOrCreate(
        'custom-svc',
        targets: [SloTarget.availability(target: 0.95)],
      );
      expect(manager.serviceName, 'custom-svc');
    });

    test('getAllStatus', () {
      SloRegistry.instance.getOrCreate('getAllStatus-svc1');
      SloRegistry.instance.getOrCreate('getAllStatus-svc2');
      final status = SloRegistry.instance.getAllStatus();
      // At least has these two
      expect(status.containsKey('getAllStatus-svc1'), isTrue);
      expect(status.containsKey('getAllStatus-svc2'), isTrue);
    });
  });
}

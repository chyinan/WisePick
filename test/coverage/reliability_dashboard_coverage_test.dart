import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/reliability/reliability_dashboard.dart';
import 'package:wisepick_dart_version/core/resilience/circuit_breaker.dart';
import 'package:wisepick_dart_version/core/resilience/slo_manager.dart';

void main() {
  group('RefreshInterval', () {
    test('values', () {
      expect(RefreshInterval.values, hasLength(4));
      expect(RefreshInterval.realtime.duration, const Duration(seconds: 1));
      expect(RefreshInterval.fast.duration, const Duration(seconds: 5));
      expect(RefreshInterval.normal.duration, const Duration(seconds: 15));
      expect(RefreshInterval.slow.duration, const Duration(seconds: 60));
    });
  });

  group('SystemHealthScore', () {
    test('construction', () {
      final score = SystemHealthScore(
        overallScore: 85,
        availabilityScore: 90,
        latencyScore: 80,
        errorRateScore: 85,
        resourceScore: 70,
        calculatedAt: DateTime(2025, 1, 1),
        grade: HealthGrade.good,
        criticalIssues: ['issue1'],
        warnings: ['warn1'],
      );
      expect(score.overallScore, 85);
      expect(score.grade, HealthGrade.good);
      expect(score.criticalIssues, ['issue1']);
      expect(score.warnings, ['warn1']);
    });

    test('toJson', () {
      final score = SystemHealthScore(
        overallScore: 95,
        availabilityScore: 100,
        latencyScore: 90,
        errorRateScore: 95,
        resourceScore: 100,
        calculatedAt: DateTime(2025, 1, 1),
        grade: HealthGrade.excellent,
      );
      final json = score.toJson();
      expect(json['overallScore'], 95);
      expect(json['grade'], 'excellent');
      expect(json['scores']['availability'], 100);
      expect(json['scores']['latency'], 90);
      expect(json['criticalIssues'], isEmpty);
      expect(json['warnings'], isEmpty);
    });
  });

  group('HealthGrade', () {
    test('all values', () {
      expect(HealthGrade.values, hasLength(5));
    });
  });

  group('ServiceStatusSummary', () {
    test('toJson', () {
      final summary = ServiceStatusSummary(
        serviceName: 'svc',
        status: ServiceStatus.healthy,
        successRate: 0.999,
        avgLatency: const Duration(milliseconds: 100),
        p95Latency: const Duration(milliseconds: 200),
        p99Latency: const Duration(milliseconds: 500),
        requestsPerMinute: 1000,
        activeConnections: 5,
        circuitBreakerState: CircuitState.closed,
        degradationLevel: DegradationLevel.normal,
        lastUpdated: DateTime(2025, 1, 1),
      );
      final json = summary.toJson();
      expect(json['serviceName'], 'svc');
      expect(json['status'], 'healthy');
      expect(json['successRate'], contains('99.9'));
      expect(json['latency']['avg'], '100ms');
      expect(json['latency']['p95'], '200ms');
      expect(json['latency']['p99'], '500ms');
      expect(json['requestsPerMinute'], 1000);
      expect(json['circuitBreaker'], 'closed');
      expect(json['degradation'], 'normal');
    });

    test('toJson without optional fields', () {
      final summary = ServiceStatusSummary(
        serviceName: 'svc',
        status: ServiceStatus.unknown,
        successRate: 1.0,
        avgLatency: Duration.zero,
        p95Latency: Duration.zero,
        p99Latency: Duration.zero,
        requestsPerMinute: 0,
        activeConnections: 0,
        lastUpdated: DateTime(2025, 1, 1),
      );
      final json = summary.toJson();
      expect(json.containsKey('circuitBreaker'), isFalse);
      expect(json.containsKey('degradation'), isFalse);
    });
  });

  group('ServiceStatus', () {
    test('all values', () {
      expect(ServiceStatus.values, hasLength(4));
    });
  });

  group('SloStatusSummary', () {
    test('toJson', () {
      const summary = SloStatusSummary(
        sloName: 'availability',
        targetValue: 0.999,
        currentValue: 0.998,
        budgetRemaining: 0.5,
        budgetConsumptionRate: 2.0,
        estimatedExhaustionTime: Duration(minutes: 30),
        isAtRisk: true,
        isViolated: false,
      );
      final json = summary.toJson();
      expect(json['sloName'], 'availability');
      expect(json['target'], 0.999);
      expect(json['current'], 0.998);
      expect(json['budgetRemaining'], contains('50.0'));
      expect(json['burnRate'], contains('2.00'));
      expect(json['estimatedExhaustion'], '30min');
      expect(json['isAtRisk'], isTrue);
      expect(json['isViolated'], isFalse);
    });

    test('toJson negative exhaustion time', () {
      const summary = SloStatusSummary(
        sloName: 'test',
        targetValue: 0.99,
        currentValue: 0.95,
        budgetRemaining: 0,
        budgetConsumptionRate: 0,
        estimatedExhaustionTime: Duration(hours: -1),
        isAtRisk: false,
        isViolated: true,
      );
      final json = summary.toJson();
      expect(json['estimatedExhaustion'], 'N/A');
    });
  });

  group('ReliabilityAlert', () {
    test('construction', () {
      final alert = ReliabilityAlert(
        id: 'alert-1',
        severity: AlertSeverity.warning,
        title: 'Test Alert',
        description: 'Test description',
        source: 'test',
        timestamp: DateTime(2025, 1, 1),
      );
      expect(alert.acknowledged, isFalse);
      expect(alert.metadata, isEmpty);
    });

    test('toJson', () {
      final alert = ReliabilityAlert(
        id: 'alert-1',
        severity: AlertSeverity.critical,
        title: 'Critical Alert',
        description: 'desc',
        source: 'health_check',
        timestamp: DateTime(2025, 1, 1),
        acknowledged: true,
        metadata: {'key': 'val'},
      );
      final json = alert.toJson();
      expect(json['id'], 'alert-1');
      expect(json['severity'], 'critical');
      expect(json['title'], 'Critical Alert');
      expect(json['acknowledged'], isTrue);
      expect(json['metadata'], {'key': 'val'});
    });
  });

  group('AlertSeverity', () {
    test('all values', () {
      expect(AlertSeverity.values, hasLength(4));
    });
  });

  group('DashboardSnapshot', () {
    test('toJson', () {
      final snapshot = DashboardSnapshot(
        timestamp: DateTime(2025, 1, 1),
        healthScore: SystemHealthScore(
          overallScore: 90,
          availabilityScore: 95,
          latencyScore: 85,
          errorRateScore: 90,
          resourceScore: 80,
          calculatedAt: DateTime(2025, 1, 1),
          grade: HealthGrade.excellent,
        ),
        services: const [],
        slos: const [],
        activeAlerts: const [],
        metrics: const {},
        predictions: const {},
        chaosStatus: const {},
      );
      final json = snapshot.toJson();
      expect(json['timestamp'], isA<String>());
      expect(json['healthScore'], isA<Map>());
      expect(json['services'], isA<List>());
      expect(json['slos'], isA<List>());
      expect(json['activeAlerts'], isA<List>());
    });
  });

  group('ReliabilityDashboard', () {
    late ReliabilityDashboard dashboard;

    setUp(() {
      dashboard = ReliabilityDashboard();
    });

    tearDown(() {
      dashboard.dispose();
    });

    test('initial state', () {
      expect(dashboard.latestSnapshot, isNull);
      expect(dashboard.activeAlerts, isEmpty);
    });

    test('registerService', () {
      dashboard.registerService('svc-1');
      dashboard.registerService('svc-1'); // duplicate, should not add twice
    });

    test('startAutoRefresh and stopAutoRefresh', () {
      dashboard.startAutoRefresh(interval: RefreshInterval.slow);
      dashboard.stopAutoRefresh();
    });

    test('refresh', () async {
      final snapshot = await dashboard.refresh();
      expect(snapshot.healthScore, isNotNull);
      expect(snapshot.services, isA<List>());
      expect(snapshot.slos, isA<List>());
      expect(dashboard.latestSnapshot, isNotNull);
    });

    test('refresh with registered service', () async {
      dashboard.registerService('test-svc');
      final snapshot = await dashboard.refresh();
      expect(snapshot.services, isNotEmpty);
    });

    test('acknowledgeAlert', () async {
      // Trigger a refresh to potentially generate alerts
      await dashboard.refresh();
      // Add a manual test alert
      dashboard.acknowledgeAlert('nonexistent'); // should not crash
    });

    test('clearAcknowledgedAlerts', () {
      dashboard.clearAcknowledgedAlerts();
    });

    test('exportData', () {
      final data = dashboard.exportData();
      expect(data['exportedAt'], isA<String>());
      expect(data.containsKey('latestSnapshot'), isTrue);
      expect(data.containsKey('alertHistory'), isTrue);
    });

    test('exportData after refresh', () async {
      await dashboard.refresh();
      final data = dashboard.exportData();
      expect(data['latestSnapshot'], isNotNull);
    });

    test('snapshotStream emits on refresh', () async {
      final streamEvents = <DashboardSnapshot>[];
      final sub = dashboard.snapshotStream.listen(streamEvents.add);
      await dashboard.refresh();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(streamEvents, isNotEmpty);
      await sub.cancel();
    });
  });

  group('ReliabilityDashboardRegistry', () {
    test('singleton', () {
      final r1 = ReliabilityDashboardRegistry.instance;
      final r2 = ReliabilityDashboardRegistry.instance;
      expect(identical(r1, r2), isTrue);
    });

    test('dashboard getter', () {
      final d = ReliabilityDashboardRegistry.instance.dashboard;
      expect(d, isNotNull);
    });

    test('configure', () {
      ReliabilityDashboardRegistry.instance.configure(
        errorRateAlertThreshold: 0.1,
        latencyAlertThreshold: const Duration(seconds: 10),
        budgetWarningThreshold: 0.3,
      );
      final d = ReliabilityDashboardRegistry.instance.dashboard;
      expect(d.errorRateAlertThreshold, 0.1);
    });
  });
}

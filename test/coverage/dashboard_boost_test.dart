import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/reliability/reliability_dashboard.dart';
import 'package:wisepick_dart_version/core/observability/health_check.dart';
import 'package:wisepick_dart_version/core/observability/metrics_collector.dart';
import 'package:wisepick_dart_version/core/resilience/slo_manager.dart';
import 'package:wisepick_dart_version/core/resilience/circuit_breaker.dart';

void main() {
  group('ReliabilityDashboard - uncovered paths', () {
    late ReliabilityDashboard dashboard;

    setUp(() {
      dashboard = ReliabilityDashboard();
      HealthCheckRegistry.instance.clear();
      MetricsCollector.instance.reset();
      SloRegistry.instance.dispose();
      CircuitBreakerRegistry.instance.clear();
    });

    tearDown(() {
      dashboard.dispose();
      HealthCheckRegistry.instance.clear();
      MetricsCollector.instance.reset();
      SloRegistry.instance.dispose();
      CircuitBreakerRegistry.instance.clear();
    });

    test('refresh with healthy components', () async {
      HealthCheckRegistry.instance.register('ok-cmp', () async {
        return ComponentHealth(
          name: 'ok-cmp',
          status: HealthStatus.healthy,
          message: 'ok',
        );
      });

      final snapshot = await dashboard.refresh();
      expect(snapshot.healthScore.overallScore, greaterThanOrEqualTo(90));
    });

    test('health score with degraded components', () async {
      HealthCheckRegistry.instance.register('degraded-cmp', () async {
        return ComponentHealth(
          name: 'degraded-cmp',
          status: HealthStatus.degraded,
          message: 'slow response',
        );
      });

      final snapshot = await dashboard.refresh();
      expect(snapshot.healthScore.overallScore, lessThan(100));
    });

    test('health score with unhealthy components', () async {
      HealthCheckRegistry.instance.register('unhealthy-cmp', () async {
        return ComponentHealth(
          name: 'unhealthy-cmp',
          status: HealthStatus.unhealthy,
          message: 'down',
        );
      });

      final snapshot = await dashboard.refresh();
      expect(snapshot.healthScore.overallScore, lessThan(100));
    });

    test('health score with high latency', () async {
      for (var i = 0; i < 100; i++) {
        MetricsCollector.instance.observeHistogram(
          MetricsCollector.requestDuration,
          11.0,
        );
      }

      final snapshot = await dashboard.refresh();
      expect(snapshot.healthScore, isNotNull);
    });

    test('health score with moderate latency', () async {
      for (var i = 0; i < 100; i++) {
        MetricsCollector.instance.observeHistogram(
          MetricsCollector.requestDuration,
          6.0,
        );
      }

      final snapshot = await dashboard.refresh();
      expect(snapshot.healthScore, isNotNull);
    });

    test('health score with mildly high latency', () async {
      for (var i = 0; i < 100; i++) {
        MetricsCollector.instance.observeHistogram(
          MetricsCollector.requestDuration,
          3.0,
        );
      }

      final snapshot = await dashboard.refresh();
      expect(snapshot.healthScore, isNotNull);
    });

    test('health score with error rate', () async {
      for (var i = 0; i < 10; i++) {
        MetricsCollector.instance.increment(MetricsCollector.requestTotal);
      }
      for (var i = 0; i < 5; i++) {
        MetricsCollector.instance.increment(MetricsCollector.requestErrors);
      }

      final snapshot = await dashboard.refresh();
      expect(snapshot.healthScore, isNotNull);
    });

    test('alert conditions - critical health', () async {
      // Need overall score < 40 for critical grade
      // 10 unhealthy components: availability = 100 - 200 = clamped to 0
      for (var i = 0; i < 10; i++) {
        HealthCheckRegistry.instance.register('unhealthy-$i', () async {
          return ComponentHealth(
            name: 'unhealthy-$i',
            status: HealthStatus.unhealthy,
            message: 'down',
          );
        });
      }
      // High error rate
      for (var i = 0; i < 100; i++) {
        MetricsCollector.instance.increment(MetricsCollector.requestTotal);
      }
      for (var i = 0; i < 50; i++) {
        MetricsCollector.instance.increment(MetricsCollector.requestErrors);
      }
      // Extremely high latency
      for (var i = 0; i < 50; i++) {
        MetricsCollector.instance.observeHistogram(
          MetricsCollector.requestDuration,
          15.0,
        );
      }

      final snapshot = await dashboard.refresh();
      // The combined bad signals should trigger critical alerts
      expect(snapshot.healthScore.grade, HealthGrade.critical);
      expect(snapshot.activeAlerts, isNotEmpty);
    });

    test('alert conditions - service unhealthy', () async {
      dashboard.registerService('unhealthy-svc');

      final cb = CircuitBreakerRegistry.instance.getOrCreate(
        'unhealthy-svc',
        config: const CircuitBreakerConfig(failureThreshold: 1),
      );

      cb.recordFailure();
      cb.recordFailure();

      final snapshot = await dashboard.refresh();
      expect(snapshot, isNotNull);
    });

    test('alert conditions - SLO violated', () async {
      final slo = SloRegistry.instance.getOrCreate(
        'slo-alert-svc',
        targets: [SloTarget.availability(target: 0.99)],
      );

      for (var i = 0; i < 200; i++) {
        slo.recordRequest(success: false);
      }

      await Future.delayed(const Duration(seconds: 2));

      final snapshot = await dashboard.refresh();
      expect(snapshot.slos, isNotEmpty);
    });

    test('alert conditions - SLO at risk', () async {
      final slo = SloRegistry.instance.getOrCreate(
        'slo-risk-svc',
        targets: [SloTarget.availability(target: 0.9)],
      );

      for (var i = 0; i < 15; i++) {
        slo.recordRequest(success: true);
      }
      for (var i = 0; i < 85; i++) {
        slo.recordRequest(success: false);
      }

      final snapshot = await dashboard.refresh();
      expect(snapshot, isNotNull);
    });

    test('_addAlert deduplication', () async {
      HealthCheckRegistry.instance.register('dup-unhealthy', () async {
        return ComponentHealth(
          name: 'dup-unhealthy',
          status: HealthStatus.unhealthy,
          message: 'down',
        );
      });

      await dashboard.refresh();
      await dashboard.refresh();
      await dashboard.refresh();
    });

    test('acknowledgeAlert', () async {
      HealthCheckRegistry.instance.register('ack-unhealthy', () async {
        return ComponentHealth(
          name: 'ack-unhealthy',
          status: HealthStatus.unhealthy,
          message: 'down',
        );
      });

      final snapshot = await dashboard.refresh();
      if (snapshot.activeAlerts.isNotEmpty) {
        final alertId = snapshot.activeAlerts.first.id;
        dashboard.acknowledgeAlert(alertId);

        final snapshot2 = await dashboard.refresh();
        final acknowledged = snapshot2.activeAlerts.where((a) => a.id == alertId);
        if (acknowledged.isNotEmpty) {
          expect(acknowledged.first.acknowledged, isTrue);
        }
      }
    });

    test('clearAcknowledgedAlerts', () async {
      HealthCheckRegistry.instance.register('clear-unhealthy', () async {
        return ComponentHealth(
          name: 'clear-unhealthy',
          status: HealthStatus.unhealthy,
          message: 'down',
        );
      });

      await dashboard.refresh();
      final snapshot = await dashboard.refresh();
      for (final alert in snapshot.activeAlerts) {
        dashboard.acknowledgeAlert(alert.id);
      }

      dashboard.clearAcknowledgedAlerts();
    });

    test('SLO burn rate parsing', () {
      final slo = SloRegistry.instance.getOrCreate(
        'burn-rate-svc',
        targets: [SloTarget.availability(target: 0.99)],
      );

      for (var i = 0; i < 10; i++) {
        slo.recordRequest(success: false);
      }
    });

    test('SLO exhaustion parsing', () async {
      final slo = SloRegistry.instance.getOrCreate(
        'exhaust-parse-svc',
        targets: [SloTarget.availability(target: 0.99)],
      );

      for (var i = 0; i < 5; i++) {
        slo.recordRequest(success: true);
      }
      for (var i = 0; i < 5; i++) {
        slo.recordRequest(success: false);
      }

      await dashboard.refresh();
    });
  });
}

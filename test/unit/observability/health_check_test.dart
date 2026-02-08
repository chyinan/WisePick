import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/observability/health_check.dart';

void main() {
  group('ComponentHealth', () {
    test('healthy component should report isHealthy', () {
      final health = ComponentHealth(
        name: 'db',
        status: HealthStatus.healthy,
      );
      expect(health.isHealthy, isTrue);
      expect(health.isDegraded, isFalse);
      expect(health.isUnhealthy, isFalse);
    });

    test('degraded component should report isDegraded', () {
      final health = ComponentHealth(
        name: 'cache',
        status: HealthStatus.degraded,
        message: 'slow',
      );
      expect(health.isHealthy, isFalse);
      expect(health.isDegraded, isTrue);
    });

    test('unhealthy component should report isUnhealthy', () {
      final health = ComponentHealth(
        name: 'api',
        status: HealthStatus.unhealthy,
        message: 'down',
      );
      expect(health.isUnhealthy, isTrue);
    });

    test('toJson should include all fields', () {
      final health = ComponentHealth(
        name: 'db',
        status: HealthStatus.healthy,
        message: 'ok',
        latency: const Duration(milliseconds: 50),
        details: {'connections': 5},
      );

      final json = health.toJson();
      expect(json['name'], equals('db'));
      expect(json['status'], equals('healthy'));
      expect(json['message'], equals('ok'));
      expect(json['latencyMs'], equals(50));
      expect(json['details']['connections'], equals(5));
    });

    test('toJson should exclude null fields', () {
      final health = ComponentHealth(
        name: 'db',
        status: HealthStatus.healthy,
      );

      final json = health.toJson();
      expect(json.containsKey('message'), isFalse);
      expect(json.containsKey('latencyMs'), isFalse);
      expect(json.containsKey('details'), isFalse);
    });
  });

  group('SystemHealth', () {
    test('should aggregate healthy status', () {
      final system = SystemHealth(
        status: HealthStatus.healthy,
        components: [
          ComponentHealth(name: 'a', status: HealthStatus.healthy),
          ComponentHealth(name: 'b', status: HealthStatus.healthy),
        ],
        checkedAt: DateTime.now(),
        totalLatency: const Duration(milliseconds: 100),
      );
      expect(system.isHealthy, isTrue);
    });

    test('toJson should include all components', () {
      final system = SystemHealth(
        status: HealthStatus.healthy,
        components: [
          ComponentHealth(name: 'a', status: HealthStatus.healthy),
        ],
        checkedAt: DateTime.now(),
        totalLatency: const Duration(milliseconds: 50),
      );

      final json = system.toJson();
      expect(json['status'], equals('healthy'));
      expect(json['components'], isA<List>());
      expect(json['totalLatencyMs'], equals(50));
    });
  });

  group('HealthCheckRegistry', () {
    setUp(() {
      HealthCheckRegistry.instance.clear();
    });

    test('should register and run health checkers', () async {
      HealthCheckRegistry.instance.register('test', () async {
        return ComponentHealth(
          name: 'test',
          status: HealthStatus.healthy,
        );
      });

      final result = await HealthCheckRegistry.instance.checkAll();
      expect(result.isHealthy, isTrue);
      expect(result.components.length, equals(1));
      expect(result.components.first.name, equals('test'));
    });

    test('should detect unhealthy components', () async {
      HealthCheckRegistry.instance.register('healthy', () async {
        return ComponentHealth(name: 'healthy', status: HealthStatus.healthy);
      });
      HealthCheckRegistry.instance.register('broken', () async {
        return ComponentHealth(name: 'broken', status: HealthStatus.unhealthy);
      });

      final result = await HealthCheckRegistry.instance.checkAll();
      expect(result.status, equals(HealthStatus.unhealthy));
    });

    test('should detect degraded status', () async {
      HealthCheckRegistry.instance.register('ok', () async {
        return ComponentHealth(name: 'ok', status: HealthStatus.healthy);
      });
      HealthCheckRegistry.instance.register('slow', () async {
        return ComponentHealth(name: 'slow', status: HealthStatus.degraded);
      });

      final result = await HealthCheckRegistry.instance.checkAll();
      expect(result.status, equals(HealthStatus.degraded));
    });

    test('should handle timeout', () async {
      HealthCheckRegistry.instance.register('slow', () async {
        await Future.delayed(const Duration(seconds: 10));
        return ComponentHealth(name: 'slow', status: HealthStatus.healthy);
      });

      final result = await HealthCheckRegistry.instance.checkAll(
        timeout: const Duration(milliseconds: 100),
      );
      expect(result.components.first.status, equals(HealthStatus.unhealthy));
      expect(result.components.first.message, contains('timed out'));
    });

    test('should handle exceptions gracefully', () async {
      // Use Future.error instead of throw to avoid test zone
      // intercepting the exception before the try/catch in checkAll
      HealthCheckRegistry.instance.register('error', () =>
        Future<ComponentHealth>.error(Exception('database connection failed')),
      );

      final result = await HealthCheckRegistry.instance.checkAll();
      expect(result.components.first.status, equals(HealthStatus.unhealthy));
      expect(result.components.first.message, contains('failed'));
    });

    test('check single component should work', () async {
      HealthCheckRegistry.instance.register('db', () async {
        return ComponentHealth(name: 'db', status: HealthStatus.healthy);
      });

      final result = await HealthCheckRegistry.instance.check('db');
      expect(result.isHealthy, isTrue);
    });

    test('check non-existent component should return unhealthy', () async {
      final result = await HealthCheckRegistry.instance.check('missing');
      expect(result.isUnhealthy, isTrue);
      expect(result.message, contains('not registered'));
    });

    test('should unregister components', () async {
      HealthCheckRegistry.instance.register('temp', () async {
        return ComponentHealth(name: 'temp', status: HealthStatus.healthy);
      });

      expect(HealthCheckRegistry.instance.registeredComponents, contains('temp'));

      HealthCheckRegistry.instance.unregister('temp');
      expect(HealthCheckRegistry.instance.registeredComponents, isNot(contains('temp')));
    });

    test('empty registry should be healthy', () async {
      final result = await HealthCheckRegistry.instance.checkAll();
      expect(result.isHealthy, isTrue);
      expect(result.components, isEmpty);
    });
  });

  group('HealthCheckers - Ping', () {
    test('successful ping should be healthy', () async {
      final checker = HealthCheckers.ping('api', () async => true);
      final result = await checker();
      expect(result.isHealthy, isTrue);
      expect(result.latency, isNotNull);
    });

    test('failed ping should be unhealthy', () async {
      final checker = HealthCheckers.ping('api', () async => false);
      final result = await checker();
      expect(result.isUnhealthy, isTrue);
    });

    test('exception in ping should be unhealthy', () async {
      final checker = HealthCheckers.ping('api', () async {
        throw Exception('connection refused');
      });
      final result = await checker();
      expect(result.isUnhealthy, isTrue);
      expect(result.message, contains('connection refused'));
    });
  });

  group('HealthCheckers - Threshold', () {
    test('value below warning should be healthy', () async {
      final checker = HealthCheckers.threshold(
        'cpu',
        () async => 50.0,
        warnThreshold: 80.0,
        criticalThreshold: 95.0,
      );
      final result = await checker();
      expect(result.isHealthy, isTrue);
    });

    test('value above warning should be degraded', () async {
      final checker = HealthCheckers.threshold(
        'cpu',
        () async => 85.0,
        warnThreshold: 80.0,
        criticalThreshold: 95.0,
      );
      final result = await checker();
      expect(result.isDegraded, isTrue);
    });

    test('value above critical should be unhealthy', () async {
      final checker = HealthCheckers.threshold(
        'cpu',
        () async => 98.0,
        warnThreshold: 80.0,
        criticalThreshold: 95.0,
      );
      final result = await checker();
      expect(result.isUnhealthy, isTrue);
    });

    test('higherIsBetter should invert thresholds', () async {
      final checker = HealthCheckers.threshold(
        'availability',
        () async => 50.0,
        warnThreshold: 95.0,
        criticalThreshold: 90.0,
        higherIsBetter: true,
      );
      final result = await checker();
      expect(result.isUnhealthy, isTrue);
    });
  });

  group('HealthCheckers - Circuit Breaker', () {
    test('closed circuit should be healthy', () async {
      final checker = HealthCheckers.circuitBreaker(
        'api_cb',
        () => {'state': 'closed'},
      );
      final result = await checker();
      expect(result.isHealthy, isTrue);
    });

    test('half-open circuit should be degraded', () async {
      final checker = HealthCheckers.circuitBreaker(
        'api_cb',
        () => {'state': 'halfOpen'},
      );
      final result = await checker();
      expect(result.isDegraded, isTrue);
    });

    test('open circuit should be unhealthy', () async {
      final checker = HealthCheckers.circuitBreaker(
        'api_cb',
        () => {'state': 'open'},
      );
      final result = await checker();
      expect(result.isUnhealthy, isTrue);
    });

    test('null status should be healthy', () async {
      final checker = HealthCheckers.circuitBreaker(
        'api_cb',
        () => null,
      );
      final result = await checker();
      expect(result.isHealthy, isTrue);
    });
  });

  group('Convenience functions', () {
    setUp(() {
      HealthCheckRegistry.instance.clear();
    });

    test('registerHealthCheck should register to global registry', () {
      registerHealthCheck('test', () async {
        return ComponentHealth(name: 'test', status: HealthStatus.healthy);
      });
      expect(HealthCheckRegistry.instance.registeredComponents, contains('test'));
    });

    test('runHealthChecks should run all checks', () async {
      registerHealthCheck('test', () async {
        return ComponentHealth(name: 'test', status: HealthStatus.healthy);
      });
      final result = await runHealthChecks();
      expect(result.isHealthy, isTrue);
    });
  });
}

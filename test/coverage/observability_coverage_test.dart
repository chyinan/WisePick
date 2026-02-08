/// Additional coverage tests for observability components.
///
/// Targets uncovered branches in metrics_collector.dart, health_check.dart,
/// distributed_tracing.dart - utility functions, edge cases, formatters.
library;

import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/observability/metrics_collector.dart';
import 'package:wisepick_dart_version/core/observability/health_check.dart';
import 'package:wisepick_dart_version/core/observability/distributed_tracing.dart';

void main() {
  // ==========================================================================
  // MetricsCollector - recordRequest and advanced metrics
  // ==========================================================================
  group('MetricsCollector - recordRequest', () {
    setUp(() {
      MetricsCollector.instance.reset();
    });

    test('should record successful request', () {
      MetricsCollector.instance.recordRequest(
        service: 'test-svc',
        operation: 'op1',
        success: true,
        duration: const Duration(milliseconds: 100),
      );
      final summary = MetricsCollector.instance.getSummary();
      expect(summary['requests'], isNotNull);
      expect((summary['requests'] as Map)['total'], greaterThan(0));
    });

    test('should record failed request', () {
      MetricsCollector.instance.recordRequest(
        service: 'test-svc',
        operation: 'op1',
        success: false,
        duration: const Duration(milliseconds: 500),
      );
      final summary = MetricsCollector.instance.getSummary();
      expect(summary['requests'], isNotNull);
      expect((summary['requests'] as Map)['errors'], greaterThan(0));
    });

    test('should record latency histogram', () {
      for (var i = 0; i < 20; i++) {
        MetricsCollector.instance.recordLatency(
          'slow_op',
          Duration(milliseconds: 50 * i),
        );
      }
      final summary = MetricsCollector.instance.getSummary();
      // The latency appears in the summary under 'latency' key
      // Also verify the histogram data is accessible directly
      final histogram = MetricsCollector.instance.getHistogram(
        MetricsCollector.requestDuration,
        labels: MetricLabels().add('operation', 'slow_op'),
      );
      expect(histogram, isNotNull);
      expect(histogram!.count, equals(20));
    });

    test('should track timer context', () async {
      final timer = MetricsCollector.instance.startTimer('test_timer');
      await Future.delayed(const Duration(milliseconds: 10));
      final duration = timer.stop();
      expect(duration.inMilliseconds, greaterThanOrEqualTo(5));
    });

    test('should support MetricLabels chaining', () {
      final labels = MetricLabels()
          .add('service', 'svc1')
          .add('operation', 'op1')
          .add('region', 'us-east');
      final key = labels.toKey();
      expect(key, contains('service=svc1'));
      expect(key, contains('operation=op1'));
      expect(key, contains('region=us-east'));
    });

    test('should handle empty labels', () {
      final labels = MetricLabels();
      expect(labels.toKey(), isEmpty);
    });

    test('MetricLabels toString', () {
      final labels = MetricLabels().add('k', 'v');
      expect(labels.toString(), contains('k'));
    });

    test('HistogramData should compute statistics', () {
      final data = HistogramData();
      data.observe(10);
      data.observe(20);
      data.observe(30);
      data.observe(40);
      data.observe(50);

      expect(data.count, equals(5));
      expect(data.sum, equals(150));
      expect(data.min, equals(10));
      expect(data.max, equals(50));
      expect(data.mean, equals(30));
    });

    test('HistogramData percentile', () {
      final data = HistogramData();
      for (var i = 1; i <= 100; i++) {
        data.observe(i.toDouble());
      }
      final p50 = data.percentile(50);
      expect(p50, closeTo(50, 5));
      final p99 = data.percentile(99);
      expect(p99, closeTo(99, 2));
    });
  });

  // ==========================================================================
  // HealthCheckRegistry - utility health checkers
  // ==========================================================================
  group('HealthCheckRegistry - utility checkers', () {
    setUp(() {
      HealthCheckRegistry.instance.clear();
    });

    tearDown(() {
      HealthCheckRegistry.instance.clear();
    });

    test('ping checker should detect healthy endpoint', () async {
      HealthCheckRegistry.instance.register(
        'ping-test',
        HealthCheckers.ping('ping-svc', () async => true),
      );
      final health = await HealthCheckRegistry.instance.check('ping-test');
      expect(health?.status, equals(HealthStatus.healthy));
    });

    test('ping checker should detect unhealthy endpoint', () async {
      HealthCheckRegistry.instance.register(
        'ping-down',
        HealthCheckers.ping('ping-svc', () async => false),
      );
      final health = await HealthCheckRegistry.instance.check('ping-down');
      expect(health?.status, equals(HealthStatus.unhealthy));
    });

    test('ping checker should handle exception', () async {
      HealthCheckRegistry.instance.register(
        'ping-err',
        HealthCheckers.ping('ping-svc', () async => throw Exception('connect failed')),
      );
      final health = await HealthCheckRegistry.instance.check('ping-err');
      expect(health?.status, equals(HealthStatus.unhealthy));
    });

    test('threshold checker healthy below threshold', () async {
      HealthCheckRegistry.instance.register(
        'threshold-ok',
        HealthCheckers.threshold(
          'memory',
          () async => 50.0,
          warnThreshold: 70,
          criticalThreshold: 90,
        ),
      );
      final health = await HealthCheckRegistry.instance.check('threshold-ok');
      expect(health?.status, equals(HealthStatus.healthy));
    });

    test('threshold checker warning at threshold', () async {
      HealthCheckRegistry.instance.register(
        'threshold-warn',
        HealthCheckers.threshold(
          'memory',
          () async => 75.0,
          warnThreshold: 70,
          criticalThreshold: 90,
        ),
      );
      final health = await HealthCheckRegistry.instance.check('threshold-warn');
      expect(health?.status, equals(HealthStatus.degraded));
    });

    test('threshold checker critical above threshold', () async {
      HealthCheckRegistry.instance.register(
        'threshold-crit',
        HealthCheckers.threshold(
          'memory',
          () async => 95.0,
          warnThreshold: 70,
          criticalThreshold: 90,
        ),
      );
      final health = await HealthCheckRegistry.instance.check('threshold-crit');
      expect(health?.status, equals(HealthStatus.unhealthy));
    });

    test('circuit breaker checker closed state', () async {
      HealthCheckRegistry.instance.register(
        'cb-check',
        HealthCheckers.circuitBreaker(
          'cb-svc',
          () => {'state': 'closed', 'failures': 0},
        ),
      );
      final health = await HealthCheckRegistry.instance.check('cb-check');
      expect(health?.status, equals(HealthStatus.healthy));
    });

    test('circuit breaker checker half_open state', () async {
      HealthCheckRegistry.instance.register(
        'cb-half',
        HealthCheckers.circuitBreaker(
          'cb-svc',
          () => {'state': 'halfOpen', 'failures': 5},
        ),
      );
      final health = await HealthCheckRegistry.instance.check('cb-half');
      expect(health?.status, equals(HealthStatus.degraded));
    });

    test('circuit breaker checker open state', () async {
      HealthCheckRegistry.instance.register(
        'cb-open',
        HealthCheckers.circuitBreaker(
          'cb-svc',
          () => {'state': 'open', 'failures': 20},
        ),
      );
      final health = await HealthCheckRegistry.instance.check('cb-open');
      expect(health?.status, equals(HealthStatus.unhealthy));
    });

    test('SystemHealth should aggregate correctly', () async {
      HealthCheckRegistry.instance.register(
        'svc-a',
        () async => ComponentHealth(
          name: 'svc-a',
          status: HealthStatus.healthy,
          latency: const Duration(milliseconds: 10),
        ),
      );
      HealthCheckRegistry.instance.register(
        'svc-b',
        () async => ComponentHealth(
          name: 'svc-b',
          status: HealthStatus.degraded,
          latency: const Duration(milliseconds: 50),
        ),
      );

      final system = await HealthCheckRegistry.instance.checkAll();
      expect(system.status, equals(HealthStatus.degraded));
      expect(system.components.length, equals(2));
      expect(system.isHealthy, isFalse);
    });

    test('SystemHealth all healthy', () async {
      HealthCheckRegistry.instance.register(
        'svc-ok',
        () async => ComponentHealth(
          name: 'svc-ok',
          status: HealthStatus.healthy,
          latency: const Duration(milliseconds: 5),
        ),
      );

      final system = await HealthCheckRegistry.instance.checkAll();
      expect(system.status, equals(HealthStatus.healthy));
      expect(system.isHealthy, isTrue);
    });

    test('ComponentHealth details', () {
      final health = ComponentHealth(
        name: 'test',
        status: HealthStatus.healthy,
        latency: const Duration(milliseconds: 5),
        details: {'version': '1.0'},
      );
      expect(health.details!['version'], equals('1.0'));
    });

    test('ComponentHealth unhealthy with message', () {
      final health = ComponentHealth(
        name: 'db',
        status: HealthStatus.unhealthy,
        latency: const Duration(seconds: 5),
        message: 'Connection timeout',
      );
      expect(health.message, equals('Connection timeout'));
    });

    test('ComponentHealth toJson', () {
      final health = ComponentHealth(
        name: 'svc',
        status: HealthStatus.healthy,
        latency: const Duration(milliseconds: 10),
      );
      final json = health.toJson();
      expect(json['name'], equals('svc'));
      expect(json['status'], equals('healthy'));
    });
  });

  // ==========================================================================
  // Distributed Tracing - Span edge cases
  // ==========================================================================
  group('Distributed Tracing - extended coverage', () {
    test('Span baggage propagation', () {
      final span = Tracer.instance.startSpan('parent');
      span.context.baggage['user_id'] = '123';
      expect(span.context.baggage['user_id'], equals('123'));
    });

    test('Span multiple events', () {
      final span = Tracer.instance.startSpan('op');
      span.addEvent('step1', {'progress': '25%'});
      span.addEvent('step2', {'progress': '50%'});
      span.addEvent('step3', {'progress': '100%'});
      span.finish();

      expect(span.events.length, equals(3));
    });

    test('Span setAttribute override', () {
      final span = Tracer.instance.startSpan('op');
      span.setAttribute('key', 'v1');
      span.setAttribute('key', 'v2');
      span.finish();

      expect(span.attributes['key'], equals('v2'));
    });

    test('InMemorySpanExporter export and shutdown', () async {
      final exporter = InMemorySpanExporter();

      final span = Tracer.instance.startSpan('op');
      span.finish();

      // Directly export spans to the exporter
      await exporter.export([span]);
      expect(exporter.spans.length, greaterThan(0));

      await exporter.shutdown();
      expect(exporter.spans, isEmpty);
    });

    test('Tracer.instance should be a singleton', () {
      final t1 = Tracer.instance;
      final t2 = Tracer.instance;
      expect(identical(t1, t2), isTrue);
    });

    test('TraceContext.newTrace generates unique IDs', () {
      final c1 = TraceContext.newTrace();
      final c2 = TraceContext.newTrace();
      expect(c1.traceId, isNot(equals(c2.traceId)));
      expect(c1.spanId, isNot(equals(c2.spanId)));
    });

    test('TraceContext createChildSpan creates new span ID but same trace ID', () {
      final parent = TraceContext.newTrace();
      final child = parent.createChildSpan();
      expect(child.traceId, equals(parent.traceId));
      expect(child.spanId, isNot(equals(parent.spanId)));
      expect(child.parentSpanId, equals(parent.spanId));
    });

    test('Span error recording', () {
      final span = Tracer.instance.startSpan('err-op');
      span.setError(Exception('test error'), StackTrace.current);
      span.finish();
      expect(span.status, equals(SpanStatus.error));
      expect(span.errorMessage, contains('test error'));
      // Error details are in events, not attributes
      expect(span.events.any((e) => e.name == 'error'), isTrue);
    });

    test('Span isFinished', () {
      final span = Tracer.instance.startSpan('fin-op');
      expect(span.isFinished, isFalse);
      span.finish();
      expect(span.isFinished, isTrue);
    });
  });
}

import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/observability/metrics_collector.dart';

void main() {
  group('MetricLabels', () {
    test('empty labels should produce empty key', () {
      final labels = MetricLabels();
      expect(labels.toKey(), equals(''));
    });

    test('should produce sorted key', () {
      final labels = MetricLabels({'b': '2', 'a': '1'});
      expect(labels.toKey(), equals('a=1,b=2'));
    });

    test('add should create new instance with added label', () {
      final labels = MetricLabels().add('service', 'api').add('method', 'GET');
      expect(labels.toKey(), contains('method=GET'));
      expect(labels.toKey(), contains('service=api'));
    });

    test('toString should return toKey result', () {
      final labels = MetricLabels({'k': 'v'});
      expect(labels.toString(), equals(labels.toKey()));
    });
  });

  group('HistogramData', () {
    test('should compute basic statistics', () {
      final histogram = HistogramData();
      histogram.observe(1.0);
      histogram.observe(2.0);
      histogram.observe(3.0);

      expect(histogram.count, equals(3));
      expect(histogram.sum, equals(6.0));
      expect(histogram.mean, closeTo(2.0, 0.001));
      expect(histogram.min, equals(1.0));
      expect(histogram.max, equals(3.0));
    });

    test('empty histogram should return zeros', () {
      final histogram = HistogramData();
      expect(histogram.count, equals(0));
      expect(histogram.sum, equals(0));
      expect(histogram.mean, equals(0));
      expect(histogram.min, equals(0));
      expect(histogram.max, equals(0));
      expect(histogram.p50, equals(0));
      expect(histogram.p95, equals(0));
      expect(histogram.p99, equals(0));
    });

    test('should compute percentiles', () {
      final histogram = HistogramData();
      for (int i = 1; i <= 100; i++) {
        histogram.observe(i.toDouble());
      }

      expect(histogram.p50, closeTo(50, 2));
      expect(histogram.p95, closeTo(95, 2));
      expect(histogram.p99, closeTo(99, 2));
    });

    test('should fill correct buckets', () {
      final histogram = HistogramData(boundaries: [1.0, 5.0, 10.0]);
      histogram.observe(0.5); // bucket <= 1.0
      histogram.observe(3.0); // bucket <= 5.0
      histogram.observe(7.0); // bucket <= 10.0
      histogram.observe(15.0); // bucket <= infinity

      expect(histogram.buckets[0].count, equals(1)); // <= 1.0
      expect(histogram.buckets[1].count, equals(1)); // <= 5.0
      expect(histogram.buckets[2].count, equals(1)); // <= 10.0
      expect(histogram.buckets[3].count, equals(1)); // <= infinity
    });

    test('toJson should produce valid map', () {
      final histogram = HistogramData();
      histogram.observe(1.0);
      histogram.observe(2.0);

      final json = histogram.toJson();
      expect(json['count'], equals(2));
      expect(json['sum'], equals(3.0));
      expect(json['buckets'], isA<List>());
    });
  });

  group('MetricsCollector - Counters', () {
    setUp(() {
      MetricsCollector.instance.reset();
    });

    test('should increment counter', () {
      MetricsCollector.instance.increment('test_counter');
      expect(MetricsCollector.instance.getCounter('test_counter'), equals(1));
    });

    test('should increment counter by delta', () {
      MetricsCollector.instance.increment('test_counter', delta: 5);
      expect(MetricsCollector.instance.getCounter('test_counter'), equals(5));
    });

    test('should return 0 for non-existent counter', () {
      expect(MetricsCollector.instance.getCounter('missing'), equals(0));
    });

    test('should support labels', () {
      final labels = MetricLabels().add('method', 'GET');
      MetricsCollector.instance.increment('requests', labels: labels);
      MetricsCollector.instance.increment('requests', labels: labels);

      expect(
        MetricsCollector.instance.getCounter('requests', labels: labels),
        equals(2),
      );
    });

    test('different labels should have different counters', () {
      final get = MetricLabels().add('method', 'GET');
      final post = MetricLabels().add('method', 'POST');

      MetricsCollector.instance.increment('requests', labels: get);
      MetricsCollector.instance.increment('requests', labels: post, delta: 3);

      expect(MetricsCollector.instance.getCounter('requests', labels: get), equals(1));
      expect(MetricsCollector.instance.getCounter('requests', labels: post), equals(3));
    });
  });

  group('MetricsCollector - Gauges', () {
    setUp(() {
      MetricsCollector.instance.reset();
    });

    test('should set and get gauge', () {
      MetricsCollector.instance.setGauge('cpu_usage', 75.5);
      expect(MetricsCollector.instance.getGauge('cpu_usage'), equals(75.5));
    });

    test('should return null for non-existent gauge', () {
      expect(MetricsCollector.instance.getGauge('missing'), isNull);
    });

    test('should overwrite gauge value', () {
      MetricsCollector.instance.setGauge('temp', 10);
      MetricsCollector.instance.setGauge('temp', 20);
      expect(MetricsCollector.instance.getGauge('temp'), equals(20));
    });
  });

  group('MetricsCollector - Histograms', () {
    setUp(() {
      MetricsCollector.instance.reset();
    });

    test('should observe histogram values', () {
      MetricsCollector.instance.observeHistogram('latency', 0.1);
      MetricsCollector.instance.observeHistogram('latency', 0.5);
      MetricsCollector.instance.observeHistogram('latency', 1.0);

      final histogram = MetricsCollector.instance.getHistogram('latency');
      expect(histogram, isNotNull);
      expect(histogram!.count, equals(3));
    });

    test('should return null for non-existent histogram', () {
      expect(MetricsCollector.instance.getHistogram('missing'), isNull);
    });
  });

  group('MetricsCollector - Request tracking', () {
    setUp(() {
      MetricsCollector.instance.reset();
    });

    test('should record request with all fields', () {
      MetricsCollector.instance.recordRequest(
        service: 'api',
        operation: 'getUser',
        success: true,
        duration: const Duration(milliseconds: 100),
      );

      final summary = MetricsCollector.instance.getSummary();
      expect(summary['requests']['total'], greaterThan(0));
    });

    test('should track errors separately', () {
      MetricsCollector.instance.recordRequest(
        service: 'api',
        operation: 'getUser',
        success: false,
      );

      final summary = MetricsCollector.instance.getSummary();
      expect(summary['requests']['errors'], greaterThan(0));
    });
  });

  group('MetricsCollector - Cache tracking', () {
    setUp(() {
      MetricsCollector.instance.reset();
    });

    test('should track cache hits and misses', () {
      MetricsCollector.instance.recordCacheAccess(cache: 'product', hit: true);
      MetricsCollector.instance.recordCacheAccess(cache: 'product', hit: true);
      MetricsCollector.instance.recordCacheAccess(cache: 'product', hit: false);

      final summary = MetricsCollector.instance.getSummary();
      expect(summary['cacheHitRate'], isNot(equals('N/A')));
    });
  });

  group('MetricsCollector - Circuit Breaker', () {
    setUp(() {
      MetricsCollector.instance.reset();
    });

    test('should record circuit breaker state changes', () {
      MetricsCollector.instance.recordCircuitBreakerStateChange(
        name: 'api',
        state: 'closed',
      );

      final gauge = MetricsCollector.instance.getGauge(
        MetricsCollector.circuitBreakerState,
        labels: MetricLabels().add('name', 'api'),
      );
      expect(gauge, equals(0)); // closed = 0
    });

    test('should map open state to 1', () {
      MetricsCollector.instance.recordCircuitBreakerStateChange(
        name: 'api',
        state: 'open',
      );

      final gauge = MetricsCollector.instance.getGauge(
        MetricsCollector.circuitBreakerState,
        labels: MetricLabels().add('name', 'api'),
      );
      expect(gauge, equals(1));
    });
  });

  group('MetricsCollector - Timer', () {
    setUp(() {
      MetricsCollector.instance.reset();
    });

    test('startTimer should measure duration', () async {
      final timer = MetricsCollector.instance.startTimer('test_timer');
      await Future.delayed(const Duration(milliseconds: 50));
      final duration = timer.stop();

      expect(duration.inMilliseconds, greaterThanOrEqualTo(40));
      final histogram = MetricsCollector.instance.getHistogram('test_timer');
      expect(histogram, isNotNull);
      expect(histogram!.count, equals(1));
    });
  });

  group('MetricsCollector - Summary and Exports', () {
    setUp(() {
      MetricsCollector.instance.reset();
    });

    test('getAllMetrics should return all categories', () {
      MetricsCollector.instance.increment('c');
      MetricsCollector.instance.setGauge('g', 1);
      MetricsCollector.instance.observeHistogram('h', 1);

      final all = MetricsCollector.instance.getAllMetrics();
      expect(all.containsKey('counters'), isTrue);
      expect(all.containsKey('gauges'), isTrue);
      expect(all.containsKey('histograms'), isTrue);
      expect(all.containsKey('collectedAt'), isTrue);
    });

    test('getSummary should work with no data', () {
      final summary = MetricsCollector.instance.getSummary();
      expect(summary['requests']['total'], equals(0));
      expect(summary['cacheHitRate'], equals('N/A'));
    });

    test('reset should clear all data', () {
      MetricsCollector.instance.increment('c');
      MetricsCollector.instance.setGauge('g', 1);
      MetricsCollector.instance.observeHistogram('h', 1);

      MetricsCollector.instance.reset();

      expect(MetricsCollector.instance.getCounter('c'), equals(0));
      expect(MetricsCollector.instance.getGauge('g'), isNull);
      expect(MetricsCollector.instance.getHistogram('h'), isNull);
    });
  });

  group('Convenience functions', () {
    setUp(() {
      MetricsCollector.instance.reset();
    });

    test('recordRequest function should work', () {
      recordRequest(service: 'api', operation: 'test', success: true);
      final summary = MetricsCollector.instance.getSummary();
      expect(summary['requests']['total'], greaterThan(0));
    });

    test('incrementCounter function should work', () {
      incrementCounter('my_counter');
      expect(MetricsCollector.instance.getCounter('my_counter'), equals(1));
    });

    test('withTimer should measure operation duration', () async {
      final result = await withTimer('op', () async {
        await Future.delayed(const Duration(milliseconds: 10));
        return 42;
      });

      expect(result, equals(42));
      final histogram = MetricsCollector.instance.getHistogram('op');
      expect(histogram, isNotNull);
      expect(histogram!.count, equals(1));
    });
  });
}

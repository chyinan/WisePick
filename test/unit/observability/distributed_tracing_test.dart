import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/observability/distributed_tracing.dart';

void main() {
  group('TraceContext', () {
    test('newTrace should create unique IDs', () {
      final ctx1 = TraceContext.newTrace();
      final ctx2 = TraceContext.newTrace();

      expect(ctx1.traceId, isNotEmpty);
      expect(ctx1.spanId, isNotEmpty);
      expect(ctx1.parentSpanId, isNull);
      expect(ctx1.traceId, isNot(equals(ctx2.traceId)));
    });

    test('createChildSpan should inherit traceId', () {
      final parent = TraceContext.newTrace();
      final child = parent.createChildSpan();

      expect(child.traceId, equals(parent.traceId));
      expect(child.parentSpanId, equals(parent.spanId));
      expect(child.spanId, isNot(equals(parent.spanId)));
    });

    test('withBaggage should add baggage items', () {
      final ctx = TraceContext.newTrace()
          .withBaggage('userId', '123')
          .withBaggage('tenant', 'acme');

      expect(ctx.baggage['userId'], equals('123'));
      expect(ctx.baggage['tenant'], equals('acme'));
    });

    test('toHeaders should produce trace headers', () {
      final ctx = TraceContext.newTrace().withBaggage('key', 'value');
      final headers = ctx.toHeaders();

      expect(headers['X-Trace-Id'], equals(ctx.traceId));
      expect(headers['X-Span-Id'], equals(ctx.spanId));
      expect(headers['X-Baggage-key'], equals('value'));
    });

    test('fromHeaders should parse trace headers', () {
      final original = TraceContext.newTrace().withBaggage('test', 'data');
      final headers = original.toHeaders();
      final parsed = TraceContext.fromHeaders(headers);

      expect(parsed, isNotNull);
      expect(parsed!.traceId, equals(original.traceId));
      expect(parsed.baggage['test'], equals('data'));
    });

    test('fromHeaders should return null when no trace header', () {
      final parsed = TraceContext.fromHeaders({'Content-Type': 'text/plain'});
      expect(parsed, isNull);
    });

    test('fromHeaders should handle lowercase headers', () {
      final parsed = TraceContext.fromHeaders({
        'x-trace-id': 'abc123',
        'x-span-id': 'span456',
      });
      expect(parsed, isNotNull);
      expect(parsed!.traceId, equals('abc123'));
    });

    test('toString should include IDs', () {
      final ctx = TraceContext.newTrace();
      expect(ctx.toString(), contains('Trace('));
    });

    test('child span should inherit baggage', () {
      final parent = TraceContext.newTrace().withBaggage('session', 's1');
      final child = parent.createChildSpan();
      expect(child.baggage['session'], equals('s1'));
    });
  });

  group('Span', () {
    test('should track name and context', () {
      final ctx = TraceContext.newTrace();
      final span = Span(name: 'test_op', context: ctx);

      expect(span.name, equals('test_op'));
      expect(span.context.traceId, equals(ctx.traceId));
      expect(span.isFinished, isFalse);
      expect(span.status, equals(SpanStatus.ok));
    });

    test('setAttribute should store key-value pairs', () {
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.setAttribute('key', 'value');
      span.setAttribute('count', 42);

      expect(span.attributes['key'], equals('value'));
      expect(span.attributes['count'], equals(42));
    });

    test('setAttributes should batch-add attributes', () {
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.setAttributes({'a': 1, 'b': 2, 'c': 3});

      expect(span.attributes.length, equals(3));
    });

    test('addEvent should record events', () {
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.addEvent('cache_hit', {'key': 'product_123'});

      expect(span.events.length, equals(1));
      expect(span.events.first.name, equals('cache_hit'));
    });

    test('setError should set error status', () {
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.setError(Exception('database error'));

      expect(span.status, equals(SpanStatus.error));
      expect(span.errorMessage, contains('database error'));
      expect(span.events.any((e) => e.name == 'error'), isTrue);
    });

    test('finish should set end time and duration', () {
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.finish();

      expect(span.isFinished, isTrue);
      expect(span.endTime, isNotNull);
      expect(span.duration, isNotNull);
    });

    test('finish should not overwrite if already finished', () {
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.finish(SpanStatus.ok);
      final firstEndTime = span.endTime;

      span.finish(SpanStatus.error);
      expect(span.endTime, equals(firstEndTime));
      expect(span.status, equals(SpanStatus.ok)); // Should not change
    });

    test('finish with status should set final status', () {
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.finish(SpanStatus.timeout);
      expect(span.status, equals(SpanStatus.timeout));
    });

    test('toJson should include all relevant fields', () {
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.setAttribute('key', 'val');
      span.addEvent('ev');
      span.finish();

      final json = span.toJson();
      expect(json['name'], equals('test'));
      expect(json['traceId'], isNotEmpty);
      expect(json['spanId'], isNotEmpty);
      expect(json['status'], equals('ok'));
      expect(json['attributes'], isNotEmpty);
      expect(json['events'], isNotEmpty);
      expect(json['durationMs'], isNotNull);
    });

    test('unfinished span toJson should omit duration', () {
      final span = Span(name: 'test', context: TraceContext.newTrace());
      final json = span.toJson();
      expect(json.containsKey('durationMs'), isFalse);
      expect(json.containsKey('endTime'), isFalse);
    });
  });

  group('SpanEvent', () {
    test('toJson should serialize correctly', () {
      final event = SpanEvent(
        name: 'test_event',
        timestamp: DateTime(2024, 1, 1),
        attributes: {'key': 'value'},
      );

      final json = event.toJson();
      expect(json['name'], equals('test_event'));
      expect(json['timestamp'], isNotEmpty);
      expect(json['attributes']['key'], equals('value'));
    });

    test('toJson should exclude empty attributes', () {
      final event = SpanEvent(
        name: 'test',
        timestamp: DateTime.now(),
        attributes: {},
      );

      final json = event.toJson();
      expect(json.containsKey('attributes'), isFalse);
    });
  });

  group('InMemorySpanExporter', () {
    test('should store exported spans', () async {
      final exporter = InMemorySpanExporter();
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.finish();

      await exporter.export([span]);
      expect(exporter.spans.length, equals(1));
    });

    test('should respect maxSpans limit', () async {
      final exporter = InMemorySpanExporter(maxSpans: 2);
      for (int i = 0; i < 5; i++) {
        final span = Span(name: 'span_$i', context: TraceContext.newTrace());
        span.finish();
        await exporter.export([span]);
      }
      expect(exporter.spans.length, lessThanOrEqualTo(2));
    });

    test('getSpansByTrace should filter by traceId', () async {
      final exporter = InMemorySpanExporter();
      final ctx = TraceContext.newTrace();

      final span1 = Span(name: 's1', context: ctx);
      span1.finish();
      final span2 = Span(name: 's2', context: ctx.createChildSpan());
      span2.finish();
      final other = Span(name: 'other', context: TraceContext.newTrace());
      other.finish();

      await exporter.export([span1, span2, other]);

      final traceSpans = exporter.getSpansByTrace(ctx.traceId);
      expect(traceSpans.length, equals(2));
    });

    test('getRecentErrors should filter error spans', () async {
      final exporter = InMemorySpanExporter();

      final ok = Span(name: 'ok', context: TraceContext.newTrace());
      ok.finish(SpanStatus.ok);

      final error = Span(name: 'error', context: TraceContext.newTrace());
      error.setError(Exception('fail'));
      error.finish(SpanStatus.error);

      await exporter.export([ok, error]);

      final errors = exporter.getRecentErrors();
      expect(errors.length, equals(1));
      expect(errors.first.name, equals('error'));
    });

    test('shutdown should clear spans', () async {
      final exporter = InMemorySpanExporter();
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.finish();
      await exporter.export([span]);

      await exporter.shutdown();
      expect(exporter.spans, isEmpty);
    });
  });

  group('Tracer', () {
    // Use a dedicated exporter per test to avoid singleton interference
    late InMemorySpanExporter exporter;

    setUp(() {
      exporter = InMemorySpanExporter();
      Tracer.instance.addExporter(exporter);
      Tracer.instance.enabled = true;
    });

    test('trace should execute operation and record span', () async {
      final result = await Tracer.instance.trace('test_op', (span) async {
        span.setAttribute('key', 'value');
        return 42;
      });

      expect(result, equals(42));

      await Tracer.instance.flush();
      expect(exporter.spans.any((s) => s.name == 'test_op'), isTrue);
    });

    test('trace should capture errors', () async {
      // Must await the expect when using throwsA with async closures
      await expectLater(
        () => Tracer.instance.trace('error_op', (span) async {
          throw Exception('test error');
        }),
        throwsA(isA<Exception>()),
      );

      await Tracer.instance.flush();
      final errorSpans = exporter.spans.where((s) => s.name == 'error_op');
      expect(errorSpans.any((s) => s.status == SpanStatus.error), isTrue);
    });

    test('traceSync should work with sync operations', () {
      final result = Tracer.instance.traceSync('sync_op', (span) {
        return 'hello';
      });

      expect(result, equals('hello'));
    });

    test('startSpan should create new span', () {
      final span = Tracer.instance.startSpan('manual_span');
      expect(span.name, equals('manual_span'));
      expect(span.isFinished, isFalse);
    });

    test('recordSpan should auto-finish unfinished spans', () {
      final span = Tracer.instance.startSpan('auto_finish');
      Tracer.instance.recordSpan(span);
      expect(span.isFinished, isTrue);
    });

    test('disabled tracer should not record spans', () {
      Tracer.instance.enabled = false;
      final span = Tracer.instance.startSpan('disabled_test');
      span.finish();
      Tracer.instance.recordSpan(span);
      // Should not throw, just silently ignored
      Tracer.instance.enabled = true;
    });
  });
}

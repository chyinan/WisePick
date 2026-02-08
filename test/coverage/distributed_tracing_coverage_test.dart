import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/observability/distributed_tracing.dart';

void main() {
  group('TraceContext', () {
    test('newTrace creates unique ids', () {
      final t1 = TraceContext.newTrace();
      final t2 = TraceContext.newTrace();
      expect(t1.traceId, isNot(t2.traceId));
      expect(t1.spanId, isNot(t2.spanId));
      expect(t1.parentSpanId, isNull);
      expect(t1.baggage, isEmpty);
    });

    test('createChildSpan', () {
      final parent = TraceContext.newTrace();
      final child = parent.createChildSpan();
      expect(child.traceId, parent.traceId); // same trace
      expect(child.spanId, isNot(parent.spanId)); // different span
      expect(child.parentSpanId, parent.spanId); // parent reference
    });

    test('withBaggage', () {
      final ctx = TraceContext.newTrace();
      final withB = ctx.withBaggage('userId', '123');
      expect(withB.baggage['userId'], '123');
      expect(withB.traceId, ctx.traceId);
      expect(withB.spanId, ctx.spanId);
    });

    test('toHeaders', () {
      final ctx = TraceContext.newTrace().withBaggage('key', 'val');
      final headers = ctx.toHeaders();
      expect(headers['X-Trace-Id'], ctx.traceId);
      expect(headers['X-Span-Id'], ctx.spanId);
      expect(headers['X-Baggage-key'], 'val');
    });

    test('toHeaders with parent', () {
      final parent = TraceContext.newTrace();
      final child = parent.createChildSpan();
      final headers = child.toHeaders();
      expect(headers['X-Parent-Span-Id'], parent.spanId);
    });

    test('fromHeaders valid', () {
      final ctx = TraceContext.newTrace();
      final headers = ctx.toHeaders();
      final parsed = TraceContext.fromHeaders(headers);
      expect(parsed, isNotNull);
      expect(parsed!.traceId, ctx.traceId);
      expect(parsed.spanId, ctx.spanId);
    });

    test('fromHeaders lowercase', () {
      final ctx = TraceContext.fromHeaders({
        'x-trace-id': 'abc123',
        'x-span-id': 'span456',
        'x-parent-span-id': 'parent789',
        'x-baggage-user': 'john',
      });
      expect(ctx, isNotNull);
      expect(ctx!.traceId, 'abc123');
      expect(ctx.spanId, 'span456');
      expect(ctx.parentSpanId, 'parent789');
    });

    test('fromHeaders missing traceId', () {
      final ctx = TraceContext.fromHeaders({});
      expect(ctx, isNull);
    });

    test('fromHeaders generates spanId if missing', () {
      final ctx = TraceContext.fromHeaders({'X-Trace-Id': 'abc'});
      expect(ctx, isNotNull);
      expect(ctx!.spanId, isNotEmpty);
    });

    test('toString', () {
      final ctx = TraceContext.newTrace();
      expect(ctx.toString(), startsWith('Trace('));
    });

    test('child span inherits baggage', () {
      final parent = TraceContext.newTrace().withBaggage('key', 'val');
      final child = parent.createChildSpan();
      expect(child.baggage['key'], 'val');
    });
  });

  group('SpanStatus', () {
    test('all values', () {
      expect(SpanStatus.values, hasLength(4));
    });
  });

  group('Span', () {
    test('basic creation', () {
      final ctx = TraceContext.newTrace();
      final span = Span(name: 'test-span', context: ctx);
      expect(span.name, 'test-span');
      expect(span.status, SpanStatus.ok);
      expect(span.isFinished, isFalse);
      expect(span.duration, isNull);
      expect(span.errorMessage, isNull);
    });

    test('setAttribute', () {
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.setAttribute('key', 'value');
      expect(span.attributes['key'], 'value');
    });

    test('setAttributes', () {
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.setAttributes({'a': 1, 'b': 2});
      expect(span.attributes['a'], 1);
      expect(span.attributes['b'], 2);
    });

    test('addEvent', () {
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.addEvent('my-event', {'detail': 'info'});
      expect(span.events, hasLength(1));
      expect(span.events.first.name, 'my-event');
    });

    test('addEvent without attributes', () {
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.addEvent('simple-event');
      expect(span.events, hasLength(1));
      expect(span.events.first.attributes, isEmpty);
    });

    test('setError', () {
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.setError(Exception('test error'), StackTrace.current);
      expect(span.status, SpanStatus.error);
      expect(span.errorMessage, contains('test error'));
      expect(span.events, hasLength(1));
      expect(span.events.first.name, 'error');
    });

    test('setError without stack trace', () {
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.setError('simple error');
      expect(span.status, SpanStatus.error);
    });

    test('finish', () {
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.finish();
      expect(span.isFinished, isTrue);
      expect(span.duration, isNotNull);
    });

    test('finish with status', () {
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.finish(SpanStatus.timeout);
      expect(span.status, SpanStatus.timeout);
    });

    test('double finish is no-op', () {
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.finish(SpanStatus.ok);
      final endTime = span.endTime;
      span.finish(SpanStatus.error);
      expect(span.endTime, endTime);
      expect(span.status, SpanStatus.ok); // not changed
    });

    test('toJson minimal', () {
      final ctx = TraceContext.newTrace();
      final span = Span(name: 'test', context: ctx);
      span.finish();
      final json = span.toJson();
      expect(json['name'], 'test');
      expect(json['traceId'], ctx.traceId);
      expect(json['spanId'], ctx.spanId);
      expect(json['startTime'], isA<String>());
      expect(json['endTime'], isA<String>());
      expect(json['durationMs'], isA<int>());
      expect(json['status'], 'ok');
    });

    test('toJson with error and attributes', () {
      final parent = TraceContext.newTrace();
      final child = parent.createChildSpan();
      final span = Span(name: 'err-span', context: child);
      span.setAttribute('key', 'val');
      span.setError(Exception('err'));
      span.finish();
      final json = span.toJson();
      expect(json['parentSpanId'], isNotNull);
      expect(json['error'], isNotNull);
      expect(json['attributes'], isA<Map>());
      expect(json['events'], isA<List>());
    });
  });

  group('SpanEvent', () {
    test('toJson with attributes', () {
      final e = SpanEvent(
        name: 'evt',
        timestamp: DateTime.now(),
        attributes: {'k': 'v'},
      );
      final json = e.toJson();
      expect(json['name'], 'evt');
      expect(json['timestamp'], isA<String>());
      expect(json['attributes'], {'k': 'v'});
    });

    test('toJson without attributes', () {
      final e = SpanEvent(
        name: 'evt',
        timestamp: DateTime.now(),
        attributes: {},
      );
      final json = e.toJson();
      expect(json.containsKey('attributes'), isFalse);
    });
  });

  group('ConsoleSpanExporter', () {
    test('export and shutdown', () async {
      final exporter = ConsoleSpanExporter();
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.finish();
      await exporter.export([span]);
      await exporter.shutdown();
    });

    test('export with error span', () async {
      final exporter = ConsoleSpanExporter();
      final span = Span(name: 'err', context: TraceContext.newTrace());
      span.setError(Exception('failed'));
      span.finish();
      await exporter.export([span]);
    });
  });

  group('InMemorySpanExporter', () {
    test('basic export', () async {
      final exporter = InMemorySpanExporter();
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.finish();
      await exporter.export([span]);
      expect(exporter.spans, hasLength(1));
    });

    test('respects maxSpans', () async {
      final exporter = InMemorySpanExporter(maxSpans: 2);
      for (var i = 0; i < 5; i++) {
        final span = Span(name: 'span-$i', context: TraceContext.newTrace());
        span.finish();
        await exporter.export([span]);
      }
      expect(exporter.spans.length, 2);
    });

    test('getSpansByTrace', () async {
      final exporter = InMemorySpanExporter();
      final ctx = TraceContext.newTrace();
      final span1 = Span(name: 's1', context: ctx);
      final span2 = Span(name: 's2', context: ctx.createChildSpan());
      final span3 = Span(name: 's3', context: TraceContext.newTrace());
      span1.finish();
      span2.finish();
      span3.finish();
      await exporter.export([span1, span2, span3]);
      final traceSpans = exporter.getSpansByTrace(ctx.traceId);
      expect(traceSpans, hasLength(2));
    });

    test('getRecentErrors', () async {
      final exporter = InMemorySpanExporter();
      final ok = Span(name: 'ok', context: TraceContext.newTrace());
      ok.finish();
      final err = Span(name: 'err', context: TraceContext.newTrace());
      err.setError(Exception('fail'));
      err.finish();
      await exporter.export([ok, err]);
      final errors = exporter.getRecentErrors();
      expect(errors, hasLength(1));
      expect(errors.first.name, 'err');
    });

    test('shutdown clears spans', () async {
      final exporter = InMemorySpanExporter();
      final span = Span(name: 'test', context: TraceContext.newTrace());
      span.finish();
      await exporter.export([span]);
      await exporter.shutdown();
      expect(exporter.spans, isEmpty);
    });
  });

  group('Tracer', () {
    setUp(() async {
      // Reset tracer state
      Tracer.instance.enabled = true;
      await Tracer.instance.flush();
    });

    tearDown(() async {
      await Tracer.instance.shutdown();
    });

    test('startSpan', () {
      final span = Tracer.instance.startSpan('test-span');
      expect(span.name, 'test-span');
      expect(span.context.traceId, isNotEmpty);
    });

    test('startSpan with context', () {
      final ctx = TraceContext.newTrace();
      final span = Tracer.instance.startSpan('child', context: ctx);
      expect(span.context.traceId, ctx.traceId);
    });

    test('recordSpan', () {
      final span = Tracer.instance.startSpan('rec');
      span.finish();
      Tracer.instance.recordSpan(span);
    });

    test('recordSpan auto-finishes', () {
      final span = Tracer.instance.startSpan('unfin');
      Tracer.instance.recordSpan(span);
      expect(span.isFinished, isTrue);
    });

    test('recordSpan when disabled', () {
      Tracer.instance.enabled = false;
      final span = Tracer.instance.startSpan('skip');
      span.finish();
      Tracer.instance.recordSpan(span);
    });

    test('trace async operation success', () async {
      final exporter = InMemorySpanExporter();
      Tracer.instance.addExporter(exporter);

      final result = await Tracer.instance.trace('op', (span) async {
        span.setAttribute('key', 'val');
        return 42;
      });

      expect(result, 42);
      await Tracer.instance.flush();
      expect(exporter.spans, isNotEmpty);
    });

    test('trace async operation error', () async {
      final exporter = InMemorySpanExporter();
      Tracer.instance.addExporter(exporter);

      expect(
        () => Tracer.instance.trace('fail-op', (span) async {
          throw Exception('trace error');
        }),
        throwsA(isA<Exception>()),
      );
      await Tracer.instance.flush();
    });

    test('trace with parent context', () async {
      final parentCtx = TraceContext.newTrace();
      final result = await Tracer.instance.trace(
        'child-op',
        (span) async => 'ok',
        context: parentCtx,
      );
      expect(result, 'ok');
    });

    test('trace with attributes', () async {
      final result = await Tracer.instance.trace(
        'attr-op',
        (span) async => 'ok',
        attributes: {'key': 'val'},
      );
      expect(result, 'ok');
    });

    test('traceSync success', () {
      final exporter = InMemorySpanExporter();
      Tracer.instance.addExporter(exporter);

      final result = Tracer.instance.traceSync('sync-op', (span) {
        span.setAttribute('sync', true);
        return 'hello';
      });

      expect(result, 'hello');
    });

    test('traceSync error', () {
      expect(
        () => Tracer.instance.traceSync('fail-sync', (span) {
          throw Exception('sync error');
        }),
        throwsA(isA<Exception>()),
      );
    });

    test('traceSync with context and attributes', () {
      final ctx = TraceContext.newTrace();
      final result = Tracer.instance.traceSync(
        'sync-ctx',
        (span) => 42,
        context: ctx,
        attributes: {'key': 'val'},
      );
      expect(result, 42);
    });

    test('flush with no pending spans', () async {
      await Tracer.instance.flush();
    });
  });

  group('Convenience functions', () {
    test('trace function', () async {
      final result = await trace('conv-op', (span) async => 'result');
      expect(result, 'result');
    });

    test('trace function with attributes', () async {
      final result = await trace(
        'attr-op',
        (span) async => 42,
        attributes: {'key': 'val'},
      );
      expect(result, 42);
    });

    test('currentTraceId outside trace is null', () {
      expect(currentTraceId, isNull);
    });

    test('currentSpanId outside trace is null', () {
      expect(currentSpanId, isNull);
    });
  });
}

import 'dart:async';
import 'dart:developer' as dev;
import 'dart:math';

/// Unique trace context for distributed tracing
class TraceContext {
  final String traceId;
  final String spanId;
  final String? parentSpanId;
  final Map<String, String> baggage;
  final DateTime startTime;

  TraceContext._({
    required this.traceId,
    required this.spanId,
    this.parentSpanId,
    Map<String, String>? baggage,
  })  : baggage = baggage ?? {},
        startTime = DateTime.now();

  /// Create a new root trace
  factory TraceContext.newTrace() {
    return TraceContext._(
      traceId: _generateId(),
      spanId: _generateId(),
    );
  }

  /// Create a child span
  TraceContext createChildSpan() {
    return TraceContext._(
      traceId: traceId,
      spanId: _generateId(),
      parentSpanId: spanId,
      baggage: Map.from(baggage),
    );
  }

  /// Add baggage item
  TraceContext withBaggage(String key, String value) {
    return TraceContext._(
      traceId: traceId,
      spanId: spanId,
      parentSpanId: parentSpanId,
      baggage: {...baggage, key: value},
    );
  }

  /// Convert to HTTP headers
  Map<String, String> toHeaders() => {
        'X-Trace-Id': traceId,
        'X-Span-Id': spanId,
        if (parentSpanId != null) 'X-Parent-Span-Id': parentSpanId!,
        ...baggage.map((k, v) => MapEntry('X-Baggage-$k', v)),
      };

  /// Parse from HTTP headers
  static TraceContext? fromHeaders(Map<String, String> headers) {
    final traceId = headers['X-Trace-Id'] ?? headers['x-trace-id'];
    if (traceId == null) return null;

    final baggage = <String, String>{};
    headers.forEach((k, v) {
      if (k.toLowerCase().startsWith('x-baggage-')) {
        baggage[k.substring(10)] = v;
      }
    });

    return TraceContext._(
      traceId: traceId,
      spanId: headers['X-Span-Id'] ?? headers['x-span-id'] ?? _generateId(),
      parentSpanId: headers['X-Parent-Span-Id'] ?? headers['x-parent-span-id'],
      baggage: baggage,
    );
  }

  static String _generateId() {
    final random = Random.secure();
    final bytes = List.generate(8, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  String toString() => 'Trace($traceId/$spanId)';
}

/// Span status
enum SpanStatus { ok, error, timeout, cancelled }

/// A single span in the trace
class Span {
  final String name;
  final TraceContext context;
  final DateTime startTime;
  DateTime? endTime;
  SpanStatus status = SpanStatus.ok;
  String? errorMessage;
  final Map<String, dynamic> attributes = {};
  final List<SpanEvent> events = [];

  Span({
    required this.name,
    required this.context,
  }) : startTime = DateTime.now();

  Duration? get duration => endTime?.difference(startTime);
  bool get isFinished => endTime != null;

  void setAttribute(String key, dynamic value) => attributes[key] = value;
  void setAttributes(Map<String, dynamic> attrs) => attributes.addAll(attrs);

  void addEvent(String name, [Map<String, dynamic>? attributes]) {
    events.add(SpanEvent(
      name: name,
      timestamp: DateTime.now(),
      attributes: attributes ?? {},
    ));
  }

  void setError(Object error, [StackTrace? stackTrace]) {
    status = SpanStatus.error;
    errorMessage = error.toString();
    addEvent('error', {
      'error.type': error.runtimeType.toString(),
      'error.message': error.toString(),
      if (stackTrace != null) 'error.stack': stackTrace.toString().split('\n').take(10).join('\n'),
    });
  }

  void finish([SpanStatus? finalStatus]) {
    if (isFinished) return;
    endTime = DateTime.now();
    if (finalStatus != null) status = finalStatus;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'traceId': context.traceId,
        'spanId': context.spanId,
        if (context.parentSpanId != null) 'parentSpanId': context.parentSpanId,
        'startTime': startTime.toIso8601String(),
        if (endTime != null) 'endTime': endTime!.toIso8601String(),
        if (duration != null) 'durationMs': duration!.inMilliseconds,
        'status': status.name,
        if (errorMessage != null) 'error': errorMessage,
        if (attributes.isNotEmpty) 'attributes': attributes,
        if (events.isNotEmpty) 'events': events.map((e) => e.toJson()).toList(),
      };
}

/// Span event
class SpanEvent {
  final String name;
  final DateTime timestamp;
  final Map<String, dynamic> attributes;

  SpanEvent({
    required this.name,
    required this.timestamp,
    required this.attributes,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'timestamp': timestamp.toIso8601String(),
        if (attributes.isNotEmpty) 'attributes': attributes,
      };
}

/// Span exporter interface
abstract class SpanExporter {
  Future<void> export(List<Span> spans);
  Future<void> shutdown();
}

/// Console span exporter for debugging
class ConsoleSpanExporter implements SpanExporter {
  @override
  Future<void> export(List<Span> spans) async {
    for (final span in spans) {
      final duration = span.duration?.inMilliseconds ?? 0;
      final status = span.status == SpanStatus.ok ? '✓' : '✗';
      dev.log('[$status] ${span.context.traceId.substring(0, 8)} '
          '${span.name} ${duration}ms ${span.errorMessage ?? ''}', name: 'Tracing');
    }
  }

  @override
  Future<void> shutdown() async {}
}

/// In-memory span exporter for testing/analysis
class InMemorySpanExporter implements SpanExporter {
  final List<Span> spans = [];
  final int maxSpans;

  InMemorySpanExporter({this.maxSpans = 1000});

  @override
  Future<void> export(List<Span> newSpans) async {
    spans.addAll(newSpans);
    while (spans.length > maxSpans) {
      spans.removeAt(0);
    }
  }

  @override
  Future<void> shutdown() async => spans.clear();

  List<Span> getSpansByTrace(String traceId) =>
      spans.where((s) => s.context.traceId == traceId).toList();

  List<Span> getRecentErrors({int limit = 50}) => spans
      .where((s) => s.status == SpanStatus.error)
      .toList()
      .reversed
      .take(limit)
      .toList();
}

/// Global tracer
class Tracer {
  static final Tracer _instance = Tracer._();
  static Tracer get instance => _instance;

  Tracer._();

  final List<SpanExporter> _exporters = [];
  final List<Span> _pendingSpans = [];
  Timer? _exportTimer;
  bool enabled = true;

  static final _currentContext = Zone.current[#traceContext] as TraceContext?;

  /// Get current trace context from zone
  TraceContext? get currentContext => Zone.current[#traceContext] as TraceContext?;

  /// Add an exporter
  void addExporter(SpanExporter exporter) {
    _exporters.add(exporter);
    _startExportTimer();
  }

  void _startExportTimer() {
    _exportTimer?.cancel();
    _exportTimer = Timer.periodic(const Duration(seconds: 5), (_) => flush());
  }

  /// Start a new span
  Span startSpan(String name, {TraceContext? context}) {
    final ctx = context ?? currentContext ?? TraceContext.newTrace();
    return Span(name: name, context: ctx);
  }

  /// Record a finished span
  void recordSpan(Span span) {
    if (!enabled) return;
    if (!span.isFinished) span.finish();
    _pendingSpans.add(span);
  }

  /// Run operation with tracing
  Future<T> trace<T>(
    String name,
    Future<T> Function(Span span) operation, {
    TraceContext? context,
    Map<String, dynamic>? attributes,
  }) async {
    final parentCtx = context ?? currentContext;
    final spanCtx = parentCtx?.createChildSpan() ?? TraceContext.newTrace();
    final span = Span(name: name, context: spanCtx);
    if (attributes != null) span.setAttributes(attributes);

    try {
      final result = await runZoned(
        () => operation(span),
        zoneValues: {#traceContext: spanCtx},
      );
      span.finish(SpanStatus.ok);
      recordSpan(span);
      return result;
    } catch (e, stack) {
      span.setError(e, stack);
      span.finish(SpanStatus.error);
      recordSpan(span);
      rethrow;
    }
  }

  /// Synchronous trace
  T traceSync<T>(
    String name,
    T Function(Span span) operation, {
    TraceContext? context,
    Map<String, dynamic>? attributes,
  }) {
    final parentCtx = context ?? currentContext;
    final spanCtx = parentCtx?.createChildSpan() ?? TraceContext.newTrace();
    final span = Span(name: name, context: spanCtx);
    if (attributes != null) span.setAttributes(attributes);

    try {
      final result = runZoned(
        () => operation(span),
        zoneValues: {#traceContext: spanCtx},
      );
      span.finish(SpanStatus.ok);
      recordSpan(span);
      return result;
    } catch (e, stack) {
      span.setError(e, stack);
      span.finish(SpanStatus.error);
      recordSpan(span);
      rethrow;
    }
  }

  /// Flush pending spans to exporters
  Future<void> flush() async {
    if (_pendingSpans.isEmpty) return;
    final spans = List<Span>.from(_pendingSpans);
    _pendingSpans.clear();

    for (final exporter in _exporters) {
      try {
        await exporter.export(spans);
      } catch (e) {
        // Log but don't fail
        dev.log('Span export failed: $e', name: 'Tracing');
      }
    }
  }

  /// Shutdown tracer
  Future<void> shutdown() async {
    _exportTimer?.cancel();
    await flush();
    for (final exporter in _exporters) {
      await exporter.shutdown();
    }
  }
}

/// Convenience function to trace an operation
Future<T> trace<T>(
  String name,
  Future<T> Function(Span span) operation, {
  Map<String, dynamic>? attributes,
}) {
  return Tracer.instance.trace(name, operation, attributes: attributes);
}

/// Get current trace ID
String? get currentTraceId => Tracer.instance.currentContext?.traceId;

/// Get current span ID
String? get currentSpanId => Tracer.instance.currentContext?.spanId;

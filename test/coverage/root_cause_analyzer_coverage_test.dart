import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/reliability/root_cause_analyzer.dart';
import 'package:wisepick_dart_version/core/resilience/circuit_breaker.dart';

void main() {
  group('EventSeverity', () {
    test('all values', () {
      expect(EventSeverity.values, hasLength(4));
      expect(EventSeverity.info.index, 0);
      expect(EventSeverity.critical.index, 3);
    });
  });

  group('EventCategory', () {
    test('all values', () {
      expect(EventCategory.values, hasLength(8));
    });
  });

  group('IncidentEvent', () {
    test('construction', () {
      final now = DateTime.now();
      final event = IncidentEvent(
        id: 'evt-1',
        timestamp: now,
        service: 'svc',
        component: 'comp',
        category: EventCategory.network,
        severity: EventSeverity.error,
        description: 'Network error',
      );
      expect(event.id, 'evt-1');
      expect(event.service, 'svc');
      expect(event.component, 'comp');
      expect(event.category, EventCategory.network);
      expect(event.severity, EventSeverity.error);
      expect(event.description, 'Network error');
      expect(event.attributes, isEmpty);
      expect(event.duration, isNull);
      expect(event.stackTrace, isNull);
    });

    test('toJson without duration', () {
      final event = IncidentEvent(
        id: 'evt-1',
        timestamp: DateTime(2025, 1, 1),
        service: 'svc',
        component: 'comp',
        category: EventCategory.error,
        severity: EventSeverity.warning,
        description: 'test',
        attributes: {'key': 'val'},
      );
      final json = event.toJson();
      expect(json['id'], 'evt-1');
      expect(json['service'], 'svc');
      expect(json['category'], 'error');
      expect(json['severity'], 'warning');
      expect(json['attributes'], {'key': 'val'});
      expect(json.containsKey('durationMs'), isFalse);
    });

    test('toJson with duration', () {
      final event = IncidentEvent(
        id: 'evt-2',
        timestamp: DateTime.now(),
        service: 'svc',
        component: 'comp',
        category: EventCategory.latency,
        severity: EventSeverity.warning,
        description: 'slow',
        duration: const Duration(milliseconds: 500),
      );
      final json = event.toJson();
      expect(json['durationMs'], 500);
    });
  });

  group('RootCauseHypothesis', () {
    test('high confidence', () {
      const h = RootCauseHypothesis(
        id: 'h1',
        description: 'Network issue',
        confidence: 0.8,
        category: EventCategory.network,
        supportingEvidence: ['evidence1'],
        suggestedActions: ['action1'],
      );
      expect(h.isHighConfidence, isTrue);
      expect(h.isMediumConfidence, isFalse);
      expect(h.isLowConfidence, isFalse);
    });

    test('medium confidence', () {
      const h = RootCauseHypothesis(
        id: 'h2',
        description: 'Maybe resource',
        confidence: 0.5,
        category: EventCategory.resource,
      );
      expect(h.isHighConfidence, isFalse);
      expect(h.isMediumConfidence, isTrue);
      expect(h.isLowConfidence, isFalse);
    });

    test('low confidence', () {
      const h = RootCauseHypothesis(
        id: 'h3',
        description: 'Unknown',
        confidence: 0.2,
        category: EventCategory.error,
      );
      expect(h.isHighConfidence, isFalse);
      expect(h.isMediumConfidence, isFalse);
      expect(h.isLowConfidence, isTrue);
    });

    test('toJson', () {
      const h = RootCauseHypothesis(
        id: 'h1',
        description: 'desc',
        confidence: 0.8,
        category: EventCategory.dependency,
        supportingEvidence: ['ev1'],
        suggestedActions: ['act1'],
        metadata: {'key': 'val'},
      );
      final json = h.toJson();
      expect(json['id'], 'h1');
      expect(json['confidence'], 0.8);
      expect(json['confidenceLevel'], 'high');
      expect(json['category'], 'dependency');
      expect(json['supportingEvidence'], ['ev1']);
      expect(json['suggestedActions'], ['act1']);
      expect(json['metadata'], {'key': 'val'});
    });

    test('toJson medium confidence level', () {
      const h = RootCauseHypothesis(
        id: 'h2',
        description: 'desc',
        confidence: 0.5,
        category: EventCategory.error,
      );
      final json = h.toJson();
      expect(json['confidenceLevel'], 'medium');
    });

    test('toJson low confidence level', () {
      const h = RootCauseHypothesis(
        id: 'h3',
        description: 'desc',
        confidence: 0.2,
        category: EventCategory.error,
      );
      final json = h.toJson();
      expect(json['confidenceLevel'], 'low');
    });
  });

  group('RootCauseAnalysisResult', () {
    test('primaryCause with hypotheses', () {
      final result = RootCauseAnalysisResult(
        incidentId: 'inc-1',
        analyzedAt: DateTime(2025, 1, 1),
        analysisTime: const Duration(milliseconds: 100),
        hypotheses: [
          RootCauseHypothesis(
            id: 'h1',
            description: 'Primary',
            confidence: 0.9,
            category: EventCategory.network,
          ),
          RootCauseHypothesis(
            id: 'h2',
            description: 'Secondary',
            confidence: 0.5,
            category: EventCategory.error,
          ),
        ],
        correlatedEvents: [],
        timeline: {},
        summary: 'test',
      );
      expect(result.primaryCause?.id, 'h1');
      expect(result.hasConfidentCause, isTrue);
    });

    test('primaryCause without hypotheses', () {
      final result = RootCauseAnalysisResult(
        incidentId: 'inc-2',
        analyzedAt: DateTime.now(),
        analysisTime: const Duration(milliseconds: 50),
        hypotheses: const [],
        correlatedEvents: const [],
        timeline: const {},
        summary: 'no cause',
      );
      expect(result.primaryCause, isNull);
      expect(result.hasConfidentCause, isFalse);
    });

    test('toJson', () {
      final result = RootCauseAnalysisResult(
        incidentId: 'inc-1',
        analyzedAt: DateTime(2025, 1, 1),
        analysisTime: const Duration(milliseconds: 100),
        hypotheses: const [
          RootCauseHypothesis(
            id: 'h1',
            description: 'desc',
            confidence: 0.8,
            category: EventCategory.network,
          ),
        ],
        correlatedEvents: const [],
        timeline: const {'key': 'val'},
        summary: 'summary',
      );
      final json = result.toJson();
      expect(json['incidentId'], 'inc-1');
      expect(json['summary'], 'summary');
      expect(json['primaryCause'], isA<Map>());
      expect(json['hypotheses'], isA<List>());
      expect(json['correlatedEventsCount'], 0);
    });
  });

  group('DependencyNode', () {
    test('construction', () {
      final node = DependencyNode(
        service: 'svc-a',
        upstreamDependencies: ['svc-b'],
        downstreamDependencies: ['svc-c'],
        healthScores: {'overall': 0.95},
      );
      expect(node.service, 'svc-a');
      expect(node.upstreamDependencies, ['svc-b']);
      expect(node.downstreamDependencies, ['svc-c']);
      expect(node.healthScores['overall'], 0.95);
    });
  });

  group('CorrelationAnalyzer', () {
    test('pearsonCorrelation perfect positive', () {
      final r = CorrelationAnalyzer.pearsonCorrelation(
        [1, 2, 3, 4, 5],
        [2, 4, 6, 8, 10],
      );
      expect(r, closeTo(1.0, 0.01));
    });

    test('pearsonCorrelation perfect negative', () {
      final r = CorrelationAnalyzer.pearsonCorrelation(
        [1, 2, 3, 4, 5],
        [10, 8, 6, 4, 2],
      );
      expect(r, closeTo(-1.0, 0.01));
    });

    test('pearsonCorrelation no correlation', () {
      final r = CorrelationAnalyzer.pearsonCorrelation(
        [1, 2, 3, 4, 5],
        [5, 3, 5, 3, 5],
      );
      expect(r.abs(), lessThan(0.5));
    });

    test('pearsonCorrelation short lists', () {
      expect(CorrelationAnalyzer.pearsonCorrelation([1], [2]), 0);
    });

    test('pearsonCorrelation different lengths', () {
      expect(CorrelationAnalyzer.pearsonCorrelation([1, 2], [1, 2, 3]), 0);
    });

    test('pearsonCorrelation constant values', () {
      final r = CorrelationAnalyzer.pearsonCorrelation(
        [5, 5, 5, 5],
        [1, 2, 3, 4],
      );
      expect(r, 0);
    });

    test('lagCorrelation', () {
      final results = CorrelationAnalyzer.lagCorrelation(
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
        maxLag: 2,
      );
      expect(results.containsKey(0), isTrue);
      expect(results.containsKey(1), isTrue);
      expect(results.containsKey(-1), isTrue);
    });

    test('detectAnomalies', () {
      final data = [
        10.0, 10.1, 9.9, 10.0, 10.2,
        9.8, 10.0, 50.0, // anomaly
        10.1, 9.9,
      ];
      final anomalies = CorrelationAnalyzer.detectAnomalies(data);
      expect(anomalies, contains(7)); // index of 50.0
    });

    test('detectAnomalies short list', () {
      final anomalies = CorrelationAnalyzer.detectAnomalies([1, 2, 3]);
      expect(anomalies, isEmpty);
    });

    test('detectAnomalies no anomalies', () {
      final data = [10.0, 10.1, 9.9, 10.0, 10.2, 9.8, 10.0, 10.1, 9.9, 10.0];
      final anomalies = CorrelationAnalyzer.detectAnomalies(data);
      expect(anomalies, isEmpty);
    });
  });

  group('FailurePatternRecognizer', () {
    test('matchPatterns with dependency events', () {
      final events = [
        IncidentEvent(
          id: 'e1',
          timestamp: DateTime.now(),
          service: 'svc-a',
          component: 'comp',
          category: EventCategory.dependency,
          severity: EventSeverity.error,
          description: 'dep failed',
        ),
        IncidentEvent(
          id: 'e2',
          timestamp: DateTime.now(),
          service: 'svc-b',
          component: 'comp',
          category: EventCategory.error,
          severity: EventSeverity.error,
          description: 'error',
        ),
      ];
      final patterns = FailurePatternRecognizer.matchPatterns(events);
      expect(patterns, isNotEmpty);
      // cascading_failure pattern matches dependency + error
      expect(patterns.any((e) => e.key == 'cascading_failure'), isTrue);
    });

    test('matchPatterns with network events', () {
      final events = [
        IncidentEvent(
          id: 'e1',
          timestamp: DateTime.now(),
          service: 'svc',
          component: 'comp',
          category: EventCategory.network,
          severity: EventSeverity.error,
          description: 'net err',
        ),
        IncidentEvent(
          id: 'e2',
          timestamp: DateTime.now(),
          service: 'svc',
          component: 'comp',
          category: EventCategory.latency,
          severity: EventSeverity.warning,
          description: 'slow',
        ),
      ];
      final patterns = FailurePatternRecognizer.matchPatterns(events);
      expect(patterns.any((e) => e.key == 'network_partition'), isTrue);
    });

    test('getSuggestedActions all patterns', () {
      final allPatterns = [
        'cascading_failure',
        'resource_exhaustion',
        'network_partition',
        'thundering_herd',
        'configuration_drift',
        'dependency_failure',
        'memory_leak',
        'connection_pool_exhaustion',
        'unknown_pattern',
      ];
      for (final p in allPatterns) {
        final actions = FailurePatternRecognizer.getSuggestedActions(p);
        expect(actions, isNotEmpty);
      }
    });
  });

  group('RootCauseAnalyzer', () {
    late RootCauseAnalyzer analyzer;

    setUp(() {
      analyzer = RootCauseAnalyzer(
        correlationWindow: const Duration(minutes: 5),
        minEventsForAnalysis: 2,
      );
    });

    test('registerDependency', () {
      analyzer.registerDependency(
        'svc-a',
        upstreamDependencies: ['svc-b'],
        downstreamDependencies: ['svc-c'],
      );
      final status = analyzer.getStatus();
      expect((status['registeredDependencies'] as List).contains('svc-a'), isTrue);
    });

    test('recordEvent', () {
      final event = IncidentEvent(
        id: 'evt-1',
        timestamp: DateTime.now(),
        service: 'svc',
        component: 'comp',
        category: EventCategory.error,
        severity: EventSeverity.info,
        description: 'info event',
      );
      analyzer.recordEvent(event);
      expect(analyzer.getStatus()['eventHistorySize'], 1);
    });

    test('recordError network', () {
      analyzer.recordError(
        service: 'svc',
        component: 'comp',
        error: Exception('Connection timeout'),
      );
      expect(analyzer.getStatus()['eventHistorySize'], 1);
    });

    test('recordError memory', () {
      analyzer.recordError(
        service: 'svc',
        component: 'comp',
        error: Exception('Out of memory'),
      );
      expect(analyzer.getStatus()['eventHistorySize'], 1);
    });

    test('recordError rate limit', () {
      analyzer.recordError(
        service: 'svc',
        component: 'comp',
        error: Exception('Rate limit exceeded'),
      );
      expect(analyzer.getStatus()['eventHistorySize'], 1);
    });

    test('recordError auth', () {
      analyzer.recordError(
        service: 'svc',
        component: 'comp',
        error: Exception('Auth failed'),
      );
      expect(analyzer.getStatus()['eventHistorySize'], 1);
    });

    test('recordError config', () {
      analyzer.recordError(
        service: 'svc',
        component: 'comp',
        error: Exception('Config error'),
      );
      expect(analyzer.getStatus()['eventHistorySize'], 1);
    });

    test('recordError fatal severity', () {
      analyzer.recordError(
        service: 'svc',
        component: 'comp',
        error: Exception('Fatal crash occurred'),
      );
      expect(analyzer.getStatus()['eventHistorySize'], 1);
    });

    test('recordError StateError severity', () {
      analyzer.recordError(
        service: 'svc',
        component: 'comp',
        error: StateError('bad state'),
        stackTrace: StackTrace.current,
      );
      expect(analyzer.getStatus()['eventHistorySize'], 1);
    });

    test('recordError with attributes', () {
      analyzer.recordError(
        service: 'svc',
        component: 'comp',
        error: Exception('test'),
        attributes: {'key': 'val'},
      );
      expect(analyzer.getStatus()['eventHistorySize'], 1);
    });

    test('recordCircuitBreakerEvent open', () {
      final cb = CircuitBreaker(name: 'test-cb');
      analyzer.recordCircuitBreakerEvent(cb, CircuitState.open);
      expect(analyzer.getStatus()['eventHistorySize'], 1);
    });

    test('recordCircuitBreakerEvent halfOpen', () {
      final cb = CircuitBreaker(name: 'test-cb');
      analyzer.recordCircuitBreakerEvent(cb, CircuitState.halfOpen);
      expect(analyzer.getStatus()['eventHistorySize'], 1);
    });

    test('recordCircuitBreakerEvent closed', () {
      final cb = CircuitBreaker(name: 'test-cb');
      analyzer.recordCircuitBreakerEvent(cb, CircuitState.closed);
      expect(analyzer.getStatus()['eventHistorySize'], 1);
    });

    test('recordLatencyAnomaly warning', () {
      analyzer.recordLatencyAnomaly(
        service: 'svc',
        operation: 'op',
        latency: const Duration(milliseconds: 600),
        threshold: const Duration(milliseconds: 500),
      );
      expect(analyzer.getStatus()['eventHistorySize'], 1);
    });

    test('recordLatencyAnomaly critical', () {
      analyzer.recordLatencyAnomaly(
        service: 'svc',
        operation: 'op',
        latency: const Duration(milliseconds: 2000),
        threshold: const Duration(milliseconds: 500),
      );
      expect(analyzer.getStatus()['eventHistorySize'], 1);
    });

    test('analyze with no events', () async {
      final result = await analyzer.analyze();
      expect(result.hypotheses, isEmpty);
      expect(result.summary, contains('没有'));
    });

    test('analyze with events', () async {
      // Record enough error events to trigger analysis
      for (var i = 0; i < 5; i++) {
        analyzer.recordError(
          service: 'svc-a',
          component: 'comp',
          error: Exception('Connection timeout $i'),
        );
      }
      final result = await analyzer.analyze();
      expect(result.correlatedEvents, isNotEmpty);
      expect(result.timeline, isNotEmpty);
    });

    test('analyze with dependency chain', () async {
      analyzer.registerDependency(
        'svc-a',
        upstreamDependencies: ['svc-b'],
      );
      analyzer.registerDependency(
        'svc-b',
        downstreamDependencies: ['svc-a'],
      );

      // Record events for both services
      for (var i = 0; i < 3; i++) {
        final event = IncidentEvent(
          id: 'evt-b-$i',
          timestamp: DateTime.now(),
          service: 'svc-b',
          component: 'comp',
          category: EventCategory.dependency,
          severity: EventSeverity.error,
          description: 'upstream failure $i',
        );
        analyzer.recordEvent(event);
      }
      for (var i = 0; i < 3; i++) {
        final event = IncidentEvent(
          id: 'evt-a-$i',
          timestamp: DateTime.now(),
          service: 'svc-a',
          component: 'comp',
          category: EventCategory.error,
          severity: EventSeverity.error,
          description: 'downstream failure $i',
        );
        analyzer.recordEvent(event);
      }

      final result = await analyzer.analyze();
      expect(result.hypotheses, isNotEmpty);
    });

    test('analyze triggers auto-analysis on critical events', () async {
      RootCauseAnalysisResult? completedResult;
      final a = RootCauseAnalyzer(
        correlationWindow: const Duration(minutes: 5),
        minEventsForAnalysis: 2,
        onAnalysisComplete: (result) => completedResult = result,
      );

      // Record enough critical events to trigger auto-analysis
      for (var i = 0; i < 3; i++) {
        final event = IncidentEvent(
          id: 'evt-$i',
          timestamp: DateTime.now(),
          service: 'svc',
          component: 'comp',
          category: EventCategory.error,
          severity: EventSeverity.critical,
          description: 'critical error $i',
        );
        a.recordEvent(event);
      }

      // Auto analysis should have been triggered
      await Future.delayed(const Duration(milliseconds: 100));
      expect(completedResult, isNotNull);
    });

    test('getAnalysis caches results', () async {
      for (var i = 0; i < 3; i++) {
        analyzer.recordError(
          service: 'svc',
          component: 'comp',
          error: Exception('error $i'),
        );
      }
      final result = await analyzer.analyze();
      final cached = analyzer.getAnalysis(result.incidentId);
      expect(cached, isNotNull);
      expect(cached!.incidentId, result.incidentId);
    });

    test('getRecentAnalyses', () async {
      for (var i = 0; i < 3; i++) {
        analyzer.recordError(
          service: 'svc',
          component: 'comp',
          error: Exception('error $i'),
        );
      }
      await analyzer.analyze();
      await analyzer.analyze();
      final recent = analyzer.getRecentAnalyses(limit: 5);
      expect(recent, isNotEmpty);
    });

    test('getStatus', () {
      final status = analyzer.getStatus();
      expect(status.containsKey('eventHistorySize'), isTrue);
      expect(status.containsKey('registeredDependencies'), isTrue);
      expect(status.containsKey('cachedAnalyses'), isTrue);
    });

    test('clear', () {
      analyzer.recordError(
        service: 'svc',
        component: 'comp',
        error: Exception('test'),
      );
      analyzer.clear();
      expect(analyzer.getStatus()['eventHistorySize'], 0);
      expect(analyzer.getStatus()['cachedAnalyses'], 0);
    });
  });

  group('RootCauseAnalyzerRegistry', () {
    test('singleton', () {
      final r1 = RootCauseAnalyzerRegistry.instance;
      final r2 = RootCauseAnalyzerRegistry.instance;
      expect(identical(r1, r2), isTrue);
    });

    test('analyzer getter', () {
      final a = RootCauseAnalyzerRegistry.instance.analyzer;
      expect(a, isNotNull);
    });

    test('configure', () {
      RootCauseAnalyzerRegistry.instance.configure(
        eventRetention: const Duration(hours: 12),
        correlationWindow: const Duration(minutes: 10),
      );
      final a = RootCauseAnalyzerRegistry.instance.analyzer;
      expect(a.correlationWindow, const Duration(minutes: 10));
    });
  });
}

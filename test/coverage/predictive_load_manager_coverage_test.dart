import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/reliability/predictive_load_manager.dart';

void main() {
  group('TimeSeriesPoint', () {
    test('construction', () {
      final p = TimeSeriesPoint(
        timestamp: DateTime(2025, 1, 1),
        value: 42.0,
      );
      expect(p.value, 42.0);
      expect(p.metadata, isNull);
    });

    test('construction with metadata', () {
      final p = TimeSeriesPoint(
        timestamp: DateTime(2025, 1, 1),
        value: 10.0,
        metadata: {'source': 'test'},
      );
      expect(p.metadata?['source'], 'test');
    });

    test('toJson without metadata', () {
      final p = TimeSeriesPoint(
        timestamp: DateTime(2025, 1, 1),
        value: 5.0,
      );
      final json = p.toJson();
      expect(json['value'], 5.0);
      expect(json['timestamp'], isA<String>());
      expect(json.containsKey('metadata'), isFalse);
    });

    test('toJson with metadata', () {
      final p = TimeSeriesPoint(
        timestamp: DateTime(2025, 1, 1),
        value: 5.0,
        metadata: {'key': 'val'},
      );
      final json = p.toJson();
      expect(json['metadata'], {'key': 'val'});
    });
  });

  group('LoadPrediction', () {
    test('properties', () {
      final p = LoadPrediction(
        predictedTime: DateTime(2025, 1, 1),
        predictedLoad: 0.8,
        confidenceLevel: 0.85,
        lowerBound: 0.6,
        upperBound: 1.0,
        predictionMethod: 'fusion',
      );
      expect(p.isHighConfidence, isTrue);
      expect(p.isHighLoad, isTrue);
      expect(p.uncertaintyRange, closeTo(0.4, 0.01));
    });

    test('not high confidence', () {
      final p = LoadPrediction(
        predictedTime: DateTime(2025, 1, 1),
        predictedLoad: 0.3,
        confidenceLevel: 0.5,
        lowerBound: 0.1,
        upperBound: 0.5,
        predictionMethod: 'ewma',
      );
      expect(p.isHighConfidence, isFalse);
      expect(p.isHighLoad, isFalse);
    });

    test('toJson', () {
      final p = LoadPrediction(
        predictedTime: DateTime(2025, 1, 1),
        predictedLoad: 0.5,
        confidenceLevel: 0.7,
        lowerBound: 0.3,
        upperBound: 0.7,
        predictionMethod: 'linear',
        factors: {'key': 'val'},
      );
      final json = p.toJson();
      expect(json['predictedLoad'], 0.5);
      expect(json['confidenceLevel'], 0.7);
      expect(json['predictionMethod'], 'linear');
      expect(json['factors'], {'key': 'val'});
    });
  });

  group('TrendAnalysis', () {
    test('significant increasing trend', () {
      const t = TrendAnalysis(
        direction: TrendDirection.increasing,
        slope: 0.05,
        acceleration: 0.02,
        rSquared: 0.85,
        timeToThreshold: Duration(minutes: 10),
        currentValue: 0.5,
        projectedValue: 0.8,
      );
      expect(t.isSignificant, isTrue);
      expect(t.isAccelerating, isTrue);
    });

    test('not significant', () {
      const t = TrendAnalysis(
        direction: TrendDirection.stable,
        slope: 0.0,
        acceleration: 0.0,
        rSquared: 0.3,
        timeToThreshold: Duration(hours: 999),
        currentValue: 0.2,
        projectedValue: 0.2,
      );
      expect(t.isSignificant, isFalse);
      expect(t.isAccelerating, isFalse);
    });

    test('toJson', () {
      const t = TrendAnalysis(
        direction: TrendDirection.decreasing,
        slope: -0.01,
        acceleration: -0.005,
        rSquared: 0.6,
        timeToThreshold: Duration(minutes: 30),
        currentValue: 0.4,
        projectedValue: 0.3,
      );
      final json = t.toJson();
      expect(json['direction'], 'decreasing');
      expect(json['slope'], -0.01);
      expect(json['rSquared'], 0.6);
      expect(json['timeToThresholdMinutes'], 30);
    });
  });

  group('TrendDirection', () {
    test('all values', () {
      expect(TrendDirection.values, hasLength(4));
    });
  });

  group('LoadManagementAction', () {
    test('all values', () {
      expect(LoadManagementAction.values, hasLength(7));
    });
  });

  group('PredictiveLoadManager', () {
    late PredictiveLoadManager manager;

    setUp(() {
      manager = PredictiveLoadManager(
        serviceName: 'test-svc',
        minDataPointsForPrediction: 5,
      );
    });

    tearDown(() {
      manager.dispose();
    });

    test('initial state', () {
      expect(manager.latestPrediction, isNull);
      expect(manager.latestTrend, isNull);
      expect(manager.serviceName, 'test-svc');
    });

    test('recordRequestRate', () {
      manager.recordRequestRate(10.0);
      final status = manager.getStatus();
      expect(status['dataPoints']['requestRate'], 1);
    });

    test('recordLatency', () {
      manager.recordLatency(const Duration(milliseconds: 100));
      final status = manager.getStatus();
      expect(status['dataPoints']['latency'], 1);
    });

    test('recordErrorRate', () {
      manager.recordErrorRate(0.05);
      final status = manager.getStatus();
      expect(status['dataPoints']['errorRate'], 1);
    });

    test('recordResourceUsage', () {
      manager.recordResourceUsage(0.7);
      final status = manager.getStatus();
      expect(status['dataPoints']['resourceUsage'], 1);
    });

    test('predictLoad insufficient data', () {
      manager.recordRequestRate(0.5);
      final prediction = manager.predictLoad(const Duration(minutes: 15));
      expect(prediction.predictionMethod, 'insufficient_data');
      expect(prediction.confidenceLevel, 0.3);
    });

    test('predictLoad with sufficient data', () {
      for (var i = 0; i < 30; i++) {
        manager.recordRequestRate(0.3 + i * 0.01);
      }
      final prediction = manager.predictLoad(const Duration(minutes: 15));
      expect(prediction.predictionMethod, 'fusion');
      expect(prediction.predictedLoad, greaterThanOrEqualTo(0));
      expect(prediction.predictedLoad, lessThanOrEqualTo(1));
    });

    test('analyzeTrend insufficient data', () {
      for (var i = 0; i < 5; i++) {
        manager.recordRequestRate(0.5);
      }
      final trend = manager.analyzeTrend();
      expect(trend.direction, TrendDirection.stable);
      expect(trend.rSquared, 0);
    });

    test('analyzeTrend with enough data', () {
      for (var i = 0; i < 30; i++) {
        manager.recordRequestRate(0.1 + i * 0.02);
      }
      final trend = manager.analyzeTrend();
      expect(trend.direction, isNotNull);
      expect(trend.currentValue, greaterThan(0));
    });

    test('analyzeTrend stable', () {
      for (var i = 0; i < 30; i++) {
        manager.recordRequestRate(0.5);
      }
      final trend = manager.analyzeTrend();
      expect(trend.slope.abs(), lessThan(0.01));
    });

    test('getStatus', () {
      manager.recordRequestRate(0.5);
      final status = manager.getStatus();
      expect(status['serviceName'], 'test-svc');
      expect(status['dataPoints'], isA<Map>());
      expect(status['currentLoad'], 0.5);
    });

    test('exportHistory', () {
      manager.recordRequestRate(0.5);
      manager.recordRequestRate(0.6);
      final history = manager.exportHistory();
      expect(history, hasLength(2));
      expect(history.first['value'], 0.5);
    });

    test('startPredictionEngine and stop', () {
      manager.startPredictionEngine(
        interval: const Duration(milliseconds: 100),
      );
      manager.stopPredictionEngine();
    });

    test('predictLoad with acceleration', () {
      // Generate enough data for acceleration calculation (>= 20 points)
      for (var i = 0; i < 30; i++) {
        manager.recordRequestRate(0.1 + i * 0.02);
      }
      final trend = manager.analyzeTrend();
      expect(trend, isNotNull);
    });

    test('predictLoad with holt-winters (>= 24 points)', () {
      for (var i = 0; i < 30; i++) {
        manager.recordRequestRate(0.3 + (i % 5) * 0.05);
      }
      final prediction = manager.predictLoad(const Duration(minutes: 15));
      expect(prediction.predictionMethod, 'fusion');
    });
  });

  group('PredictiveLoadManagerRegistry', () {
    setUp(() {
      PredictiveLoadManagerRegistry.instance.dispose();
    });

    tearDown(() {
      PredictiveLoadManagerRegistry.instance.dispose();
    });

    test('getOrCreate', () {
      final m = PredictiveLoadManagerRegistry.instance.getOrCreate('svc1');
      expect(m.serviceName, 'svc1');
    });

    test('getOrCreate returns same instance', () {
      final m1 = PredictiveLoadManagerRegistry.instance.getOrCreate('svc1');
      final m2 = PredictiveLoadManagerRegistry.instance.getOrCreate('svc1');
      expect(identical(m1, m2), isTrue);
    });

    test('get', () {
      PredictiveLoadManagerRegistry.instance.getOrCreate('svc1');
      expect(PredictiveLoadManagerRegistry.instance.get('svc1'), isNotNull);
      expect(PredictiveLoadManagerRegistry.instance.get('unknown'), isNull);
    });

    test('startAll and stopAll', () {
      PredictiveLoadManagerRegistry.instance.getOrCreate('svc1');
      PredictiveLoadManagerRegistry.instance.getOrCreate('svc2');
      PredictiveLoadManagerRegistry.instance.startAll();
      PredictiveLoadManagerRegistry.instance.stopAll();
    });

    test('getAllStatus', () {
      PredictiveLoadManagerRegistry.instance.getOrCreate('svc1');
      PredictiveLoadManagerRegistry.instance.getOrCreate('svc2');
      final status = PredictiveLoadManagerRegistry.instance.getAllStatus();
      expect(status, hasLength(2));
    });
  });
}

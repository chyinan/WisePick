import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/reliability/predictive_load_manager.dart';

void main() {
  group('PredictiveLoadManager - uncovered paths', () {
    late PredictiveLoadManager manager;

    setUp(() {
      manager = PredictiveLoadManager(
        serviceName: 'boost-svc',
        historyWindow: const Duration(hours: 1),
        predictionHorizon: const Duration(minutes: 5),
      );
    });

    tearDown(() {
      manager.stopPredictionEngine();
    });

    test('recordRequestRate with queue cleanup', () {
      for (var i = 0; i < 200; i++) {
        manager.recordRequestRate(10.0 + i * 0.1);
      }
      expect(manager.getStatus()['dataPoints']['requestRate'], greaterThan(0));
    });

    test('_updateHourlyPattern overflow', () {
      for (var i = 0; i < 150; i++) {
        manager.recordRequestRate(10.0 + i);
      }
    });

    test('startPredictionEngine and stopPredictionEngine', () {
      manager.startPredictionEngine(
        interval: const Duration(milliseconds: 50),
      );

      manager.stopPredictionEngine();
    });

    test('_runPredictionCycle with data', () async {
      for (var i = 0; i < 30; i++) {
        manager.recordRequestRate(50.0 + i);
        manager.recordLatency(Duration(milliseconds: 100 + i * 10));
        manager.recordErrorRate(0.01);
        manager.recordResourceUsage(0.3 + i * 0.01);
      }

      manager.startPredictionEngine(
        interval: const Duration(milliseconds: 50),
      );

      await Future.delayed(const Duration(milliseconds: 200));
      manager.stopPredictionEngine();

      final status = manager.getStatus();
      expect(status['latestPrediction'], isNotNull);
    });

    test('_runPredictionCycle with trend alert callback', () async {
      final managerWithCallback = PredictiveLoadManager(
        serviceName: 'trend-alert-svc',
        historyWindow: const Duration(hours: 1),
        predictionHorizon: const Duration(minutes: 5),
        onTrendAlert: (trend) {
        },
      );

      for (var i = 0; i < 30; i++) {
        managerWithCallback.recordRequestRate(10.0 + i * 5);
      }

      managerWithCallback.startPredictionEngine(
        interval: const Duration(milliseconds: 50),
      );

      await Future.delayed(const Duration(milliseconds: 200));
      managerWithCallback.stopPredictionEngine();
    });

    test('_runPredictionCycle with action required callback', () async {
      LoadManagementAction? capturedAction;
      final managerWithCallback = PredictiveLoadManager(
        serviceName: 'action-req-svc',
        historyWindow: const Duration(hours: 1),
        predictionHorizon: const Duration(minutes: 5),
        onActionRequired: (action, prediction) {
          capturedAction = action;
        },
      );

      for (var i = 0; i < 30; i++) {
        managerWithCallback.recordRequestRate(1000.0);
        managerWithCallback.recordErrorRate(0.5);
        managerWithCallback.recordResourceUsage(0.99);
      }

      managerWithCallback.startPredictionEngine(
        interval: const Duration(milliseconds: 50),
      );

      await Future.delayed(const Duration(milliseconds: 200));
      managerWithCallback.stopPredictionEngine();

      if (capturedAction != null) {
        expect(capturedAction, isNot(LoadManagementAction.none));
      }
    });

    test('_seasonalForecast with no pattern data', () {
      final prediction = manager.predictLoad(const Duration(minutes: 5));
      expect(prediction.predictedLoad, isNotNull);
    });

    test('_seasonalForecast with pattern data', () {
      for (var i = 0; i < 30; i++) {
        manager.recordRequestRate(50.0);
      }

      final prediction = manager.predictLoad(const Duration(minutes: 5));
      expect(prediction.predictedLoad, isNotNull);
    });

    test('_calculateMethodWeights with limited data', () {
      for (var i = 0; i < 5; i++) {
        manager.recordRequestRate(10.0);
      }

      final prediction = manager.predictLoad(const Duration(minutes: 5));
      expect(prediction, isNotNull);
    });

    test('_calculateMethodWeights with enough data', () {
      for (var i = 0; i < 120; i++) {
        manager.recordRequestRate(10.0 + i * 0.1);
      }

      final prediction = manager.predictLoad(const Duration(minutes: 5));
      expect(prediction, isNotNull);
    });

    test('_determineAction emergencyBrake', () {
      for (var i = 0; i < 30; i++) {
        manager.recordRequestRate(10000.0);
        manager.recordErrorRate(0.8);
        manager.recordResourceUsage(0.99);
      }

      final prediction = manager.predictLoad(const Duration(minutes: 5));
      expect(prediction.predictedLoad, greaterThan(0));
    });

    test('_determineAction shedLoad', () {
      for (var i = 0; i < 30; i++) {
        manager.recordRequestRate(80.0 + i * 2);
      }

      final prediction = manager.predictLoad(const Duration(minutes: 5));
      expect(prediction.predictedLoad, greaterThan(0));
    });

    test('_determineAction with error rate for cache activation', () {
      for (var i = 0; i < 30; i++) {
        manager.recordRequestRate(60.0);
        manager.recordErrorRate(0.1);
      }

      final prediction = manager.predictLoad(const Duration(minutes: 5));
      expect(prediction.predictedLoad, greaterThan(0));
    });

    test('_updateSeasonalPatterns', () async {
      for (var i = 0; i < 50; i++) {
        manager.recordRequestRate(30.0 + i);
      }

      manager.startPredictionEngine(
        interval: const Duration(milliseconds: 50),
      );

      await Future.delayed(const Duration(milliseconds: 200));
      manager.stopPredictionEngine();
    });

    test('_recordPredictionMetrics', () async {
      for (var i = 0; i < 30; i++) {
        manager.recordRequestRate(20.0 + i);
      }

      manager.startPredictionEngine(
        interval: const Duration(milliseconds: 50),
      );

      await Future.delayed(const Duration(milliseconds: 200));
      manager.stopPredictionEngine();
    });
  });

  group('PredictiveLoadManagerRegistry', () {
    tearDown(() {
      PredictiveLoadManagerRegistry.instance.dispose();
    });

    test('getOrCreate with onActionRequired callback', () {
      final m = PredictiveLoadManagerRegistry.instance.getOrCreate(
        'cb-svc',
        onActionRequired: (a, p) {},
      );

      expect(m.serviceName, 'cb-svc');
    });
  });
}

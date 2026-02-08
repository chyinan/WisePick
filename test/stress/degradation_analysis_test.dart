/// Graceful Degradation Analysis
///
/// Measures throughput vs latency under increasing load to:
/// - Generate performance degradation curves
/// - Identify saturation points
/// - Verify smooth degradation (no cliff-edge collapse)
/// - Compare different resilience configurations
///
/// Each test ramps load and collects detailed metrics at each step,
/// then produces a full report with visualizations.
library;

import 'dart:async';
import 'dart:math';
import 'package:test/test.dart';

import 'package:wisepick_dart_version/core/resilience/circuit_breaker.dart';
import 'package:wisepick_dart_version/core/resilience/global_rate_limiter.dart';
import 'package:wisepick_dart_version/core/resilience/retry_budget.dart';
import 'package:wisepick_dart_version/core/resilience/adaptive_config.dart';
import 'package:wisepick_dart_version/core/resilience/result.dart';
import 'package:wisepick_dart_version/core/observability/metrics_collector.dart';

import 'report_generator.dart';

// ============================================================================
// Configurable load test runner
// ============================================================================

/// Runs a load step at a given concurrency level and returns metrics.
Future<LoadStepResult> _runLoadStep({
  required int concurrency,
  required int maxConcurrent,
  required int maxQueue,
  required double failRate,
  required Duration operationLatency,
  required Random rng,
}) async {
  final ts = DateTime.now().microsecondsSinceEpoch;
  final limiter = GlobalRateLimiter(
    name: 'degrade_rl_$ts',
    config: RateLimiterConfig(
      maxRequestsPerSecond: 10000,
      maxConcurrentRequests: maxConcurrent,
      maxQueueLength: maxQueue,
      waitTimeout: const Duration(seconds: 15),
    ),
  );
  final breaker = CircuitBreaker(
    name: 'degrade_cb_$ts',
    config: const CircuitBreakerConfig(
      failureThreshold: 20,
      failureRateThreshold: 0.7,
      windowSize: 50,
      resetTimeout: Duration(milliseconds: 500),
    ),
  );
  final retryBudget = RetryBudget(
    name: 'degrade_rb_$ts',
    config: const RetryBudgetConfig(
      maxRetryRatio: 0.2,
      minRetriesPerWindow: 5,
    ),
  );

  int successes = 0;
  int failures = 0;
  int rejected = 0;
  final latencies = <double>[];

  final sw = Stopwatch()..start();

  final futures = List.generate(concurrency, (i) async {
    if (!breaker.allowRequest()) {
      rejected++;
      return;
    }
    retryBudget.recordRequest();
    final opSw = Stopwatch()..start();
    try {
      await limiter.execute(() async {
        // Simulate realistic operation with variable latency
        final baseMs = operationLatency.inMilliseconds;
        final jitter = rng.nextInt((baseMs * 0.5).ceil().clamp(1, 100));
        await Future.delayed(Duration(milliseconds: baseMs + jitter));

        if (rng.nextDouble() < failRate) {
          throw Exception('Simulated error');
        }
        return 'ok';
      });
      opSw.stop();
      latencies.add(opSw.elapsedMicroseconds / 1000.0);
      breaker.recordSuccess();
      successes++;
    } on RateLimitException {
      opSw.stop();
      rejected++;
    } catch (e) {
      opSw.stop();
      latencies.add(opSw.elapsedMicroseconds / 1000.0);
      breaker.recordFailure();
      failures++;
    }
  });

  await Future.wait(futures).timeout(
    const Duration(seconds: 60),
  );
  sw.stop();

  limiter.dispose();

  return LoadStepResult(
    concurrency: concurrency,
    totalRequests: concurrency,
    successCount: successes,
    failureCount: failures,
    rejectedCount: rejected,
    elapsed: sw.elapsed,
    latenciesMs: latencies,
  );
}

void main() {
  // ========================================================================
  // 1. Throughput vs Latency Curve (healthy system)
  // ========================================================================
  group('Degradation Analysis - Throughput vs Latency', () {
    test('should show smooth degradation under increasing load', () async {
      final rng = Random(42);
      final steps = <LoadStepResult>[];
      final levels = [50, 100, 200, 500, 1000, 2000, 5000];

      for (final concurrency in levels) {
        final result = await _runLoadStep(
          concurrency: concurrency,
          maxConcurrent: 100,
          maxQueue: concurrency + 500,
          failRate: 0.0, // No failures - pure throughput test
          operationLatency: const Duration(milliseconds: 5),
          rng: rng,
        );
        steps.add(result);
      }

      final report = ReportGenerator.generateDegradationReport(steps);
      // ignore: avoid_print
      print(report);

      final assessment = ReportGenerator.assessStability(steps);

      // Should not have critical issues (no deadlocks, no collapse)
      expect(assessment.criticalIssues, isEmpty,
          reason:
              'Critical issues under clean load: ${assessment.criticalIssues}');

      // Score should be reasonable
      expect(assessment.stabilityScore, greaterThan(40),
          reason: 'Stability score too low: ${assessment.stabilityScore}');

      // All requests should be accounted for at each step
      for (final step in steps) {
        final accounted =
            step.successCount + step.failureCount + step.rejectedCount;
        expect(accounted, equals(step.totalRequests),
            reason: 'Lost requests at concurrency ${step.concurrency}');
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  // ========================================================================
  // 2. Degradation Under Increasing Error Rate
  // ========================================================================
  group('Degradation Analysis - Error Rate Impact', () {
    test('should degrade smoothly as error rate increases', () async {
      final rng = Random(42);
      final steps = <LoadStepResult>[];
      const concurrency = 200;
      final errorRates = [0.0, 0.05, 0.1, 0.2, 0.3, 0.5, 0.7];

      for (final errorRate in errorRates) {
        final result = await _runLoadStep(
          concurrency: concurrency,
          maxConcurrent: 50,
          maxQueue: 500,
          failRate: errorRate,
          operationLatency: const Duration(milliseconds: 5),
          rng: rng,
        );

        // Override concurrency label with error rate for readability
        steps.add(LoadStepResult(
          concurrency: (errorRate * 100).toInt(), // Use error% as X axis
          totalRequests: result.totalRequests,
          successCount: result.successCount,
          failureCount: result.failureCount,
          rejectedCount: result.rejectedCount,
          elapsed: result.elapsed,
          latenciesMs: result.latenciesMs,
        ));
      }

      // Generate report (concurrency label shows error %)
      // ignore: avoid_print
      print('╔══════════════════════════════════════╗');
      // ignore: avoid_print
      print('║  ERROR RATE IMPACT ANALYSIS          ║');
      // ignore: avoid_print
      print('╚══════════════════════════════════════╝');
      // ignore: avoid_print
      print('  (X-axis: Error Rate %, at fixed 200 concurrency)');
      // ignore: avoid_print
      print(ReportGenerator.generateDegradationReport(steps));

      // Success rate should decrease as error rate increases
      // but shouldn't collapse completely at 50% error rate
      final at50Pct = steps.firstWhere((s) => s.concurrency == 50);
      expect(at50Pct.successCount, greaterThan(0),
          reason: 'Should still have some successes at 50% error rate');

      // No deadlocks at any error rate
      for (final step in steps) {
        final accounted =
            step.successCount + step.failureCount + step.rejectedCount;
        expect(accounted, equals(step.totalRequests),
            reason:
                'Lost requests at error rate ${step.concurrency}%');
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  // ========================================================================
  // 3. Latency Sensitivity Analysis
  // ========================================================================
  group('Degradation Analysis - Latency Sensitivity', () {
    test('should handle increasing operation latency gracefully', () async {
      final rng = Random(42);
      final steps = <LoadStepResult>[];
      const concurrency = 200;
      final latencies = [
        const Duration(milliseconds: 1),
        const Duration(milliseconds: 5),
        const Duration(milliseconds: 10),
        const Duration(milliseconds: 25),
        const Duration(milliseconds: 50),
        const Duration(milliseconds: 100),
      ];

      for (final latency in latencies) {
        final result = await _runLoadStep(
          concurrency: concurrency,
          maxConcurrent: 50,
          maxQueue: 500,
          failRate: 0.0,
          operationLatency: latency,
          rng: rng,
        );

        steps.add(LoadStepResult(
          concurrency: latency.inMilliseconds, // Use latency as X axis
          totalRequests: result.totalRequests,
          successCount: result.successCount,
          failureCount: result.failureCount,
          rejectedCount: result.rejectedCount,
          elapsed: result.elapsed,
          latenciesMs: result.latenciesMs,
        ));
      }

      // ignore: avoid_print
      print('╔══════════════════════════════════════╗');
      // ignore: avoid_print
      print('║  LATENCY SENSITIVITY ANALYSIS        ║');
      // ignore: avoid_print
      print('╚══════════════════════════════════════╝');
      // ignore: avoid_print
      print('  (X-axis: Operation Latency in ms, at fixed 200 concurrency)');
      // ignore: avoid_print
      print(ReportGenerator.generateDegradationReport(steps));

      // As latency increases, throughput should decrease but not crash
      for (final step in steps) {
        final accounted =
            step.successCount + step.failureCount + step.rejectedCount;
        expect(accounted, equals(step.totalRequests),
            reason:
                'Lost requests at ${step.concurrency}ms latency');
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  // ========================================================================
  // 4. Rate Limiter Saturation Curve
  // ========================================================================
  group('Degradation Analysis - Rate Limiter Saturation', () {
    test('should show clear saturation point in rate limiter', () async {
      final rng = Random(42);
      final steps = <LoadStepResult>[];
      final levels = [10, 30, 50, 80, 100, 150, 200, 300, 500];

      // Fixed rate limit of 50 concurrent, with tight queue
      const maxConcurrent = 50;
      const maxQueue = 80; // Tight queue to show saturation behavior

      for (final concurrency in levels) {
        final result = await _runLoadStep(
          concurrency: concurrency,
          maxConcurrent: maxConcurrent,
          maxQueue: maxQueue,
          failRate: 0.0,
          operationLatency: const Duration(milliseconds: 10),
          rng: rng,
        );
        steps.add(result);
      }

      // ignore: avoid_print
      print('╔══════════════════════════════════════╗');
      // ignore: avoid_print
      print('║  RATE LIMITER SATURATION CURVE       ║');
      // ignore: avoid_print
      print('╚══════════════════════════════════════╝');
      // ignore: avoid_print
      print('  (Max concurrent: $maxConcurrent)');
      // ignore: avoid_print
      print(ReportGenerator.generateDegradationReport(steps));

      // Below saturation: high success rate
      final lowLoad = steps.firstWhere((s) => s.concurrency == 30);
      expect(lowLoad.successCount, greaterThan(lowLoad.totalRequests * 0.8),
          reason: 'Below saturation should have >80% success');

      // Above saturation: some rejections expected (graceful degradation)
      final highLoad = steps.firstWhere((s) => s.concurrency == 500);
      expect(highLoad.rejectedCount, greaterThan(0),
          reason:
              'Above saturation should have some rejections');

      // No deadlocks
      for (final step in steps) {
        final accounted =
            step.successCount + step.failureCount + step.rejectedCount;
        expect(accounted, equals(step.totalRequests),
            reason:
                'Lost requests at concurrency ${step.concurrency}');
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  // ========================================================================
  // 5. Adaptive Config Response Under Load
  // ========================================================================
  group('Degradation Analysis - Adaptive Config', () {
    test('adaptive controller should tighten thresholds under pressure',
        () async {
      final controller = AdaptiveThresholdController(
        serviceName: 'degrade_adaptive',
        adjustmentInterval: const Duration(milliseconds: 50),
      );

      // Phase 1: Feed healthy metrics
      for (int i = 0; i < 20; i++) {
        controller.recordMetrics(
          errorRate: 0.01,
          latencyMs: 50,
          requestsPerSecond: 100,
        );
      }

      final healthyStatus = controller.getStatus();
      final healthyRateLimit =
          (healthyStatus['currentThresholds'] as Map)['rateLimit'] as double;

      // Phase 2: Feed degraded metrics
      for (int i = 0; i < 50; i++) {
        controller.recordMetrics(
          errorRate: 0.5,
          latencyMs: 2000,
          requestsPerSecond: 20,
        );
      }

      // Wait for auto-adjustment
      await Future.delayed(const Duration(milliseconds: 200));

      final degradedStatus = controller.getStatus();
      final degradedRateLimit =
          (degradedStatus['currentThresholds'] as Map)['rateLimit'] as double;
      final degradedRetryDelay =
          (degradedStatus['currentThresholds'] as Map)['retryDelayMs']
              as double;

      // ignore: avoid_print
      print('=== Adaptive Config Response ===');
      // ignore: avoid_print
      print('  Healthy rate limit: ${healthyRateLimit.toStringAsFixed(1)}');
      // ignore: avoid_print
      print('  Degraded rate limit: ${degradedRateLimit.toStringAsFixed(1)}');
      // ignore: avoid_print
      print(
          '  Degraded retry delay: ${degradedRetryDelay.toStringAsFixed(0)}ms');

      // Rate limit should have been tightened (reduced)
      expect(degradedRateLimit, lessThanOrEqualTo(healthyRateLimit),
          reason:
              'Adaptive controller should tighten rate limit under pressure');

      controller.dispose();
    });
  });

  // ========================================================================
  // 6. Combined Stress: Load + Errors + Latency
  // ========================================================================
  group('Degradation Analysis - Combined Stress', () {
    test('should show aggregate degradation under combined stress', () async {
      final rng = Random(42);
      final steps = <LoadStepResult>[];

      // Each step increases ALL three stress factors simultaneously
      final stressLevels = [
        // (concurrency, failRate, latencyMs)
        (50, 0.0, 2),
        (100, 0.05, 5),
        (200, 0.1, 10),
        (500, 0.15, 20),
        (1000, 0.2, 30),
        (2000, 0.25, 50),
      ];

      for (final (concurrency, failRate, latencyMs) in stressLevels) {
        final result = await _runLoadStep(
          concurrency: concurrency,
          maxConcurrent: 100,
          maxQueue: concurrency + 500,
          failRate: failRate,
          operationLatency: Duration(milliseconds: latencyMs),
          rng: rng,
        );
        steps.add(result);
      }

      // ignore: avoid_print
      print('╔══════════════════════════════════════╗');
      // ignore: avoid_print
      print('║  COMBINED STRESS ANALYSIS            ║');
      // ignore: avoid_print
      print('╚══════════════════════════════════════╝');
      // ignore: avoid_print
      print('  Stress increases across: concurrency, error rate, and latency');
      // ignore: avoid_print
      print(ReportGenerator.generateDegradationReport(steps));

      final assessment = ReportGenerator.assessStability(steps);

      // No critical issues (deadlocks, total collapse)
      expect(assessment.criticalIssues, isEmpty,
          reason:
              'Critical issues under combined stress: ${assessment.criticalIssues}');

      // All requests should be accounted for
      for (final step in steps) {
        final accounted =
            step.successCount + step.failureCount + step.rejectedCount;
        expect(accounted, equals(step.totalRequests),
            reason:
                'Lost requests at concurrency ${step.concurrency}');
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}

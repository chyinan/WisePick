/// Performance Report Generator
///
/// Shared utility for generating:
/// - ASCII-art throughput/latency charts
/// - Stability scorecards
/// - Degradation curve summaries
/// - Percentile distribution tables
/// - Resource usage trend analysis
///
/// Used by all stress/chaos/degradation test suites.
library;

import 'dart:math' as math;

// ============================================================================
// Data structures
// ============================================================================

/// A single data point captured during a load test step.
class LoadStepResult {
  final int concurrency;
  final int totalRequests;
  final int successCount;
  final int failureCount;
  final int rejectedCount;
  final Duration elapsed;
  final List<double> latenciesMs;

  LoadStepResult({
    required this.concurrency,
    required this.totalRequests,
    required this.successCount,
    required this.failureCount,
    required this.rejectedCount,
    required this.elapsed,
    required this.latenciesMs,
  });

  double get errorRate =>
      totalRequests > 0 ? (failureCount + rejectedCount) / totalRequests : 0;

  double get throughputPerSec =>
      elapsed.inMilliseconds > 0
          ? successCount / (elapsed.inMilliseconds / 1000.0)
          : 0;

  double get p50 => _percentile(50);
  double get p90 => _percentile(90);
  double get p95 => _percentile(95);
  double get p99 => _percentile(99);
  double get meanLatency =>
      latenciesMs.isEmpty
          ? 0
          : latenciesMs.reduce((a, b) => a + b) / latenciesMs.length;
  double get maxLatency =>
      latenciesMs.isEmpty ? 0 : latenciesMs.reduce(math.max);
  double get minLatency =>
      latenciesMs.isEmpty ? 0 : latenciesMs.reduce(math.min);

  double _percentile(double p) {
    if (latenciesMs.isEmpty) return 0;
    final sorted = List<double>.from(latenciesMs)..sort();
    final idx = ((sorted.length - 1) * p / 100).floor();
    return sorted[idx.clamp(0, sorted.length - 1)];
  }
}

/// Summary of a chaos experiment run.
class ChaosRunSummary {
  final String experimentName;
  final String faultType;
  final Duration totalDuration;
  final int totalRequests;
  final int successCount;
  final int failureCount;
  final int rejectedCount;
  final int retryCount;
  final String circuitBreakerFinalState;
  final bool stormDetected;
  final List<double> latenciesMs;
  final List<String> observations;

  ChaosRunSummary({
    required this.experimentName,
    required this.faultType,
    required this.totalDuration,
    required this.totalRequests,
    required this.successCount,
    required this.failureCount,
    required this.rejectedCount,
    required this.retryCount,
    required this.circuitBreakerFinalState,
    required this.stormDetected,
    required this.latenciesMs,
    this.observations = const [],
  });

  double get errorRate =>
      totalRequests > 0 ? (failureCount + rejectedCount) / totalRequests : 0;
}

/// Stability assessment result.
class StabilityAssessment {
  final bool passed;
  final double stabilityScore; // 0–100
  final List<String> findings;
  final List<String> warnings;
  final List<String> criticalIssues;
  final Map<String, dynamic> metrics;

  StabilityAssessment({
    required this.passed,
    required this.stabilityScore,
    this.findings = const [],
    this.warnings = const [],
    this.criticalIssues = const [],
    this.metrics = const {},
  });
}

// ============================================================================
// Report Generator
// ============================================================================

class ReportGenerator {
  static const int _chartWidth = 60;
  static const int _chartHeight = 15;

  // --------------------------------------------------------------------------
  // 1. Degradation Curve Report
  // --------------------------------------------------------------------------

  /// Generates a full-text degradation report from a list of load steps.
  static String generateDegradationReport(List<LoadStepResult> steps) {
    final buf = StringBuffer();
    buf.writeln(_banner('DEGRADATION CURVE REPORT'));
    buf.writeln();

    // -- Summary Table --
    buf.writeln(_sectionHeader('Load Step Summary'));
    buf.writeln(_padRight('Concurrency', 14) +
        _padRight('Throughput', 14) +
        _padRight('p50(ms)', 10) +
        _padRight('p95(ms)', 10) +
        _padRight('p99(ms)', 10) +
        _padRight('Error%', 10) +
        _padRight('Success', 10));
    buf.writeln('─' * 78);

    for (final s in steps) {
      buf.writeln(_padRight('${s.concurrency}', 14) +
          _padRight('${s.throughputPerSec.toStringAsFixed(1)}/s', 14) +
          _padRight(s.p50.toStringAsFixed(1), 10) +
          _padRight(s.p95.toStringAsFixed(1), 10) +
          _padRight(s.p99.toStringAsFixed(1), 10) +
          _padRight('${(s.errorRate * 100).toStringAsFixed(1)}%', 10) +
          _padRight('${s.successCount}/${s.totalRequests}', 10));
    }

    // -- Throughput Chart --
    buf.writeln();
    buf.writeln(_sectionHeader('Throughput vs Concurrency'));
    buf.writeln(_asciiBarChart(
      labels: steps.map((s) => '${s.concurrency}').toList(),
      values: steps.map((s) => s.throughputPerSec).toList(),
      unit: 'req/s',
    ));

    // -- Latency Chart --
    buf.writeln();
    buf.writeln(_sectionHeader('p99 Latency vs Concurrency'));
    buf.writeln(_asciiBarChart(
      labels: steps.map((s) => '${s.concurrency}').toList(),
      values: steps.map((s) => s.p99).toList(),
      unit: 'ms',
    ));

    // -- Error Rate Chart --
    buf.writeln();
    buf.writeln(_sectionHeader('Error Rate vs Concurrency'));
    buf.writeln(_asciiBarChart(
      labels: steps.map((s) => '${s.concurrency}').toList(),
      values: steps.map((s) => s.errorRate * 100).toList(),
      unit: '%',
    ));

    // -- Saturation Point Analysis --
    buf.writeln();
    buf.writeln(_sectionHeader('Saturation Point Analysis'));
    final saturationIdx = _findSaturationPoint(steps);
    if (saturationIdx >= 0) {
      final sat = steps[saturationIdx];
      buf.writeln(
          '  ⚠ Saturation detected at ${sat.concurrency} concurrent requests');
      buf.writeln(
          '    Throughput: ${sat.throughputPerSec.toStringAsFixed(1)} req/s');
      buf.writeln('    p99 Latency: ${sat.p99.toStringAsFixed(1)} ms');
      buf.writeln(
          '    Error Rate: ${(sat.errorRate * 100).toStringAsFixed(1)}%');
    } else {
      buf.writeln(
          '  ✓ No clear saturation point detected within tested range.');
    }

    // -- Stability Assessment --
    buf.writeln();
    final assessment = assessStability(steps);
    buf.writeln(_sectionHeader('Stability Assessment'));
    buf.writeln(
        '  Score: ${assessment.stabilityScore.toStringAsFixed(1)}/100  ${assessment.passed ? "✓ PASS" : "✗ FAIL"}');
    for (final f in assessment.findings) {
      buf.writeln('  ● $f');
    }
    for (final w in assessment.warnings) {
      buf.writeln('  ⚠ $w');
    }
    for (final c in assessment.criticalIssues) {
      buf.writeln('  ✗ $c');
    }

    buf.writeln();
    buf.writeln(_banner('END OF DEGRADATION REPORT'));
    return buf.toString();
  }

  // --------------------------------------------------------------------------
  // 2. Chaos Test Report
  // --------------------------------------------------------------------------

  static String generateChaosReport(List<ChaosRunSummary> runs) {
    final buf = StringBuffer();
    buf.writeln(_banner('CHAOS RESILIENCE REPORT'));
    buf.writeln();

    for (final run in runs) {
      buf.writeln(_sectionHeader('Experiment: ${run.experimentName}'));
      buf.writeln('  Fault type       : ${run.faultType}');
      buf.writeln(
          '  Duration         : ${run.totalDuration.inMilliseconds} ms');
      buf.writeln('  Total requests   : ${run.totalRequests}');
      buf.writeln('  Successes        : ${run.successCount}');
      buf.writeln('  Failures         : ${run.failureCount}');
      buf.writeln('  Rejected         : ${run.rejectedCount}');
      buf.writeln('  Retries          : ${run.retryCount}');
      buf.writeln(
          '  Error rate       : ${(run.errorRate * 100).toStringAsFixed(1)}%');
      buf.writeln('  Circuit state    : ${run.circuitBreakerFinalState}');
      buf.writeln('  Storm detected   : ${run.stormDetected}');

      if (run.latenciesMs.isNotEmpty) {
        final sorted = List<double>.from(run.latenciesMs)..sort();
        final p50 = sorted[((sorted.length - 1) * 0.5).floor()];
        final p99 = sorted[((sorted.length - 1) * 0.99).floor()];
        buf.writeln('  p50 latency      : ${p50.toStringAsFixed(1)} ms');
        buf.writeln('  p99 latency      : ${p99.toStringAsFixed(1)} ms');
      }

      for (final obs in run.observations) {
        buf.writeln('  → $obs');
      }
      buf.writeln();
    }

    // -- Overall Chaos Summary --
    buf.writeln(_sectionHeader('Overall Chaos Summary'));
    final allPassed =
        runs.every((r) => r.circuitBreakerFinalState != 'stuck');
    buf.writeln(
        '  Experiments run  : ${runs.length}');
    buf.writeln(
        '  All stabilized   : ${allPassed ? "✓ YES" : "✗ NO"}');

    final avgErrorRate = runs.isEmpty
        ? 0.0
        : runs.map((r) => r.errorRate).reduce((a, b) => a + b) / runs.length;
    buf.writeln(
        '  Avg error rate   : ${(avgErrorRate * 100).toStringAsFixed(1)}%');

    buf.writeln();
    buf.writeln(_banner('END OF CHAOS REPORT'));
    return buf.toString();
  }

  // --------------------------------------------------------------------------
  // 3. Concurrency Stability Report
  // --------------------------------------------------------------------------

  static String generateConcurrencyReport({
    required int concurrency,
    required int totalRequests,
    required int successCount,
    required int failureCount,
    required int rejectedCount,
    required Duration elapsed,
    required List<double> latenciesMs,
    required int maxObservedConcurrency,
    required int maxConcurrencyLimit,
    required bool deadlockDetected,
    required bool memoryGrowthDetected,
  }) {
    final buf = StringBuffer();
    buf.writeln(_banner('CONCURRENCY STABILITY REPORT'));
    buf.writeln();

    buf.writeln(_sectionHeader('Configuration'));
    buf.writeln('  Target concurrency    : $concurrency');
    buf.writeln('  Max concurrency limit : $maxConcurrencyLimit');
    buf.writeln('  Total requests        : $totalRequests');
    buf.writeln('  Duration              : ${elapsed.inMilliseconds} ms');

    buf.writeln();
    buf.writeln(_sectionHeader('Results'));
    buf.writeln('  Successes             : $successCount');
    buf.writeln('  Failures              : $failureCount');
    buf.writeln('  Rejected              : $rejectedCount');
    buf.writeln(
        '  Max observed conc.    : $maxObservedConcurrency');
    buf.writeln(
        '  Throughput            : ${totalRequests > 0 && elapsed.inMilliseconds > 0 ? (successCount / (elapsed.inMilliseconds / 1000.0)).toStringAsFixed(1) : "0"} req/s');

    if (latenciesMs.isNotEmpty) {
      final sorted = List<double>.from(latenciesMs)..sort();
      buf.writeln();
      buf.writeln(_sectionHeader('Latency Distribution'));
      buf.writeln(
          '  min   : ${sorted.first.toStringAsFixed(1)} ms');
      buf.writeln(
          '  p50   : ${sorted[((sorted.length - 1) * 0.5).floor()].toStringAsFixed(1)} ms');
      buf.writeln(
          '  p90   : ${sorted[((sorted.length - 1) * 0.9).floor()].toStringAsFixed(1)} ms');
      buf.writeln(
          '  p95   : ${sorted[((sorted.length - 1) * 0.95).floor()].toStringAsFixed(1)} ms');
      buf.writeln(
          '  p99   : ${sorted[((sorted.length - 1) * 0.99).floor()].toStringAsFixed(1)} ms');
      buf.writeln(
          '  max   : ${sorted.last.toStringAsFixed(1)} ms');
    }

    buf.writeln();
    buf.writeln(_sectionHeader('Stability Checks'));
    buf.writeln(
        '  Deadlock free         : ${deadlockDetected ? "✗ FAIL" : "✓ PASS"}');
    buf.writeln(
        '  Memory stable         : ${memoryGrowthDetected ? "✗ FAIL" : "✓ PASS"}');
    buf.writeln(
        '  Concurrency bounded   : ${maxObservedConcurrency <= maxConcurrencyLimit ? "✓ PASS" : "✗ FAIL"}');
    buf.writeln(
        '  All completed         : ${successCount + failureCount + rejectedCount == totalRequests ? "✓ PASS" : "✗ FAIL"}');

    final passed = !deadlockDetected &&
        !memoryGrowthDetected &&
        maxObservedConcurrency <= maxConcurrencyLimit &&
        (successCount + failureCount + rejectedCount == totalRequests);
    buf.writeln();
    buf.writeln('  OVERALL: ${passed ? "✓ PASS" : "✗ FAIL"}');

    buf.writeln();
    buf.writeln(_banner('END OF CONCURRENCY REPORT'));
    return buf.toString();
  }

  // --------------------------------------------------------------------------
  // 4. Stability Assessment
  // --------------------------------------------------------------------------

  static StabilityAssessment assessStability(List<LoadStepResult> steps) {
    double score = 100;
    final findings = <String>[];
    final warnings = <String>[];
    final criticals = <String>[];

    if (steps.isEmpty) {
      return StabilityAssessment(
        passed: false,
        stabilityScore: 0,
        criticalIssues: ['No load step data available'],
      );
    }

    // Check 1: Error rate trend - should not spike suddenly
    for (int i = 1; i < steps.length; i++) {
      final prev = steps[i - 1];
      final curr = steps[i];
      final errorDelta = curr.errorRate - prev.errorRate;
      if (errorDelta > 0.3) {
        score -= 20;
        criticals.add(
            'Error rate spiked by ${(errorDelta * 100).toStringAsFixed(1)}% '
            'between ${prev.concurrency} and ${curr.concurrency} concurrency');
      } else if (errorDelta > 0.1) {
        score -= 5;
        warnings.add(
            'Error rate increased by ${(errorDelta * 100).toStringAsFixed(1)}% '
            'between ${prev.concurrency} and ${curr.concurrency} concurrency');
      }
    }

    // Check 2: Throughput should not collapse
    if (steps.length >= 2) {
      final peakThroughput =
          steps.map((s) => s.throughputPerSec).reduce(math.max);
      final lastThroughput = steps.last.throughputPerSec;
      if (peakThroughput > 0 && lastThroughput / peakThroughput < 0.1) {
        score -= 30;
        criticals.add(
            'Throughput collapsed to ${(lastThroughput / peakThroughput * 100).toStringAsFixed(0)}% of peak');
      } else if (peakThroughput > 0 &&
          lastThroughput / peakThroughput < 0.3) {
        score -= 10;
        warnings.add(
            'Throughput dropped to ${(lastThroughput / peakThroughput * 100).toStringAsFixed(0)}% of peak');
      }
    }

    // Check 3: Latency should grow sublinearly
    if (steps.length >= 3) {
      final firstP99 = steps.first.p99;
      final lastP99 = steps.last.p99;
      final concurrencyGrowth =
          steps.last.concurrency / math.max(1, steps.first.concurrency);
      if (firstP99 > 0) {
        final latencyGrowth = lastP99 / firstP99;
        if (latencyGrowth > concurrencyGrowth * 5) {
          score -= 15;
          warnings.add(
              'p99 latency grew ${latencyGrowth.toStringAsFixed(1)}x '
              'while concurrency grew ${concurrencyGrowth.toStringAsFixed(1)}x (superlinear)');
        } else {
          findings.add(
              'p99 latency grew ${latencyGrowth.toStringAsFixed(1)}x '
              'for ${concurrencyGrowth.toStringAsFixed(1)}x concurrency increase');
        }
      }
    }

    // Check 4: No step should have > 50% error rate
    for (final step in steps) {
      if (step.errorRate > 0.5) {
        score -= 10;
        warnings.add(
            'Error rate exceeded 50% at ${step.concurrency} concurrency '
            '(${(step.errorRate * 100).toStringAsFixed(1)}%)');
      }
    }

    // Check 5: All requests should complete (no lost requests)
    for (final step in steps) {
      final accounted =
          step.successCount + step.failureCount + step.rejectedCount;
      if (accounted != step.totalRequests) {
        score -= 25;
        criticals.add(
            'Lost ${step.totalRequests - accounted} requests at '
            '${step.concurrency} concurrency (possible deadlock)');
      }
    }

    score = score.clamp(0, 100);
    final passed = score >= 60 && criticals.isEmpty;

    return StabilityAssessment(
      passed: passed,
      stabilityScore: score,
      findings: findings,
      warnings: warnings,
      criticalIssues: criticals,
    );
  }

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------

  static int _findSaturationPoint(List<LoadStepResult> steps) {
    if (steps.length < 3) return -1;

    // Find where throughput stops growing and error rate starts climbing
    double peakThroughput = 0;
    int peakIdx = 0;

    for (int i = 0; i < steps.length; i++) {
      if (steps[i].throughputPerSec > peakThroughput) {
        peakThroughput = steps[i].throughputPerSec;
        peakIdx = i;
      }
    }

    // Check if throughput drops after peak and error rate rises
    for (int i = peakIdx + 1; i < steps.length; i++) {
      if (steps[i].throughputPerSec < peakThroughput * 0.8 &&
          steps[i].errorRate > 0.05) {
        return peakIdx;
      }
    }

    return -1;
  }

  static String _banner(String title) {
    final line = '═' * (title.length + 4);
    return '╔$line╗\n║  $title  ║\n╚$line╝';
  }

  static String _sectionHeader(String title) {
    return '┌─ $title ${'─' * math.max(0, 60 - title.length - 4)}┐';
  }

  static String _padRight(String s, int width) {
    if (s.length >= width) return s.substring(0, width);
    return s + ' ' * (width - s.length);
  }

  /// Generates a horizontal ASCII bar chart.
  static String _asciiBarChart({
    required List<String> labels,
    required List<double> values,
    required String unit,
    int barMaxWidth = 40,
  }) {
    if (values.isEmpty) return '  (no data)';

    final maxVal = values.reduce(math.max);
    if (maxVal == 0) return '  (all zero)';

    final maxLabelLen = labels.map((l) => l.length).reduce(math.max);
    final buf = StringBuffer();

    for (int i = 0; i < labels.length; i++) {
      final label = labels[i].padLeft(maxLabelLen);
      final barLen =
          (values[i] / maxVal * barMaxWidth).round().clamp(0, barMaxWidth);
      final bar = '█' * barLen;
      buf.writeln(
          '  $label │$bar ${values[i].toStringAsFixed(1)} $unit');
    }

    return buf.toString();
  }
}

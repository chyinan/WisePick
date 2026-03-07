import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

/// 压力测试结果仪表盘组件
class StressTestResultsWidget extends StatelessWidget {
  final List<Map<String, dynamic>> loadSteps;
  final List<Map<String, dynamic>> chaosExperiments;
  final Map<String, dynamic>? stabilityAssessment;
  final VoidCallback? onRunStressTest;
  final VoidCallback? onRunChaosTest;
  final bool isRunning;

  const StressTestResultsWidget({
    super.key,
    this.loadSteps = const [],
    this.chaosExperiments = const [],
    this.stabilityAssessment,
    this.onRunStressTest,
    this.onRunChaosTest,
    this.isRunning = false,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 24),
          if (stabilityAssessment != null) ...[
            _buildStabilityScorecard(context),
            const SizedBox(height: 24),
          ],
          if (loadSteps.isNotEmpty) ...[
            _buildLoadStepTable(context),
            const SizedBox(height: 24),
            _buildChartsSection(context),
            const SizedBox(height: 24),
          ],
          if (chaosExperiments.isNotEmpty) ...[
            _buildChaosExperimentsSummary(context),
          ],
          if (loadSteps.isEmpty && chaosExperiments.isEmpty)
            _buildEmptyState(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A1A2E).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.speed, color: Colors.cyanAccent, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '可靠性与弹性验证',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '并发稳定性 · 混沌测试 · 退化分析',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (isRunning)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.cyanAccent,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text('测试中...', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            )
          else ...[
            _ActionButton(
              label: '压力测试',
              icon: Icons.flash_on,
              color: const Color(0xFFFF9800),
              onPressed: onRunStressTest,
            ),
            const SizedBox(width: 10),
            _ActionButton(
              label: '混沌测试',
              icon: Icons.bug_report,
              color: const Color(0xFFEF5350),
              onPressed: onRunChaosTest,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStabilityScorecard(BuildContext context) {
    final score =
        (stabilityAssessment!['stabilityScore'] as num?)?.toDouble() ?? 0;
    final passed = stabilityAssessment!['passed'] as bool? ?? false;
    final grade = stabilityAssessment!['grade'] as String? ?? '';
    final summary = stabilityAssessment!['summary'] as String? ?? '';
    final findings =
        (stabilityAssessment!['findings'] as List?)?.cast<String>() ?? [];
    final warnings =
        (stabilityAssessment!['warnings'] as List?)?.cast<String>() ?? [];
    final criticals =
        (stabilityAssessment!['criticalIssues'] as List?)?.cast<String>() ?? [];

    final color = passed
        ? const Color(0xFF4CAF50)
        : score >= 40
            ? const Color(0xFFFF9800)
            : const Color(0xFFF44336);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部：标题 + 评分环
          Row(
            children: [
              Icon(
                passed ? Icons.verified_rounded : Icons.warning_amber_rounded,
                color: color,
                size: 24,
              ),
              const SizedBox(width: 10),
              Text(
                '稳定性评估',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const Spacer(),
              // 圆形评分
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: score / 100,
                        strokeWidth: 5,
                        backgroundColor: Colors.grey[200],
                        color: color,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          grade,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        Text(
                          '${score.toStringAsFixed(0)}分',
                          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  passed ? '通过' : '未通过',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              summary,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
          const SizedBox(height: 16),
          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / 100,
              backgroundColor: Colors.grey[100],
              color: color,
              minHeight: 6,
            ),
          ),
          if (findings.isNotEmpty || warnings.isNotEmpty || criticals.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            for (final f in findings)
              _buildFindingRow(Icons.check_circle_outline, const Color(0xFF4CAF50), f),
            for (final w in warnings)
              _buildFindingRow(Icons.warning_amber_rounded, const Color(0xFFFF9800), w),
            for (final c in criticals)
              _buildFindingRow(Icons.error_outline, const Color(0xFFF44336), c),
          ],
        ],
      ),
    );
  }

  Widget _buildFindingRow(IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartsSection(BuildContext context) {
    final hasErrors = loadSteps
        .any((s) => ((s['errorRate'] as num?)?.toDouble() ?? 0) > 0);
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildThroughputChart(context)),
            const SizedBox(width: 20),
            Expanded(child: _buildLatencyChart(context)),
          ],
        ),
        if (hasErrors) ...[
          const SizedBox(height: 20),
          _buildErrorRateChart(context),
        ],
      ],
    );
  }

  Widget _buildLoadStepTable(BuildContext context) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.table_chart_outlined, color: Colors.grey[700], size: 20),
              const SizedBox(width: 8),
              Text(
                '负载阶梯汇总',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor:
                  WidgetStateProperty.all(const Color(0xFFF8F9FA)),
              columnSpacing: 28,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 48,
              columns: const [
                DataColumn(label: Text('并发数', style: _headerStyle)),
                DataColumn(label: Text('吞吐量', style: _headerStyle)),
                DataColumn(label: Text('p50 (ms)', style: _headerStyle)),
                DataColumn(label: Text('p95 (ms)', style: _headerStyle)),
                DataColumn(label: Text('p99 (ms)', style: _headerStyle)),
                DataColumn(label: Text('错误率', style: _headerStyle)),
                DataColumn(label: Text('成功/总数', style: _headerStyle)),
              ],
              rows: loadSteps.map((step) {
                final errorRate =
                    (step['errorRate'] as num?)?.toDouble() ?? 0;
                return DataRow(
                  color: errorRate > 0.05
                      ? WidgetStateProperty.all(
                          const Color(0xFFF44336).withOpacity(0.05))
                      : null,
                  cells: [
                    DataCell(Text(
                      '${step['concurrency'] ?? 0}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    )),
                    DataCell(Text(
                      '${((step['throughput'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}/s',
                    )),
                    DataCell(Text(_fmtMs(step['p50']))),
                    DataCell(Text(_fmtMs(step['p95']))),
                    DataCell(Text(_fmtMs(step['p99']))),
                    DataCell(Text(
                      '${(errorRate * 100).toStringAsFixed(2)}%',
                      style: TextStyle(
                        color: errorRate > 0.05
                            ? const Color(0xFFF44336)
                            : errorRate > 0.01
                                ? const Color(0xFFFF9800)
                                : const Color(0xFF4CAF50),
                        fontWeight: FontWeight.w600,
                      ),
                    )),
                    DataCell(Text(
                      '${step['successCount'] ?? 0}/${step['totalRequests'] ?? 0}',
                    )),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThroughputChart(BuildContext context) {
    return _buildChartCard(
      title: '吞吐量 vs 并发数',
      icon: Icons.bar_chart_rounded,
      chart: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: _maxVal(loadSteps, 'throughput') * 1.2,
          barGroups: loadSteps.asMap().entries.map((e) {
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: (e.value['throughput'] as num?)?.toDouble() ?? 0,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2196F3), Color(0xFF64B5F6)],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                  width: 20,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                ),
              ],
            );
          }).toList(),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, _) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= loadSteps.length) {
                    return const SizedBox();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${loadSteps[idx]['concurrency']}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF666666)),
                    ),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 50),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
        ),
      ),
    );
  }

  Widget _buildLatencyChart(BuildContext context) {
    return _buildChartCard(
      title: '延迟百分位 (ms)',
      icon: Icons.timeline_rounded,
      legend: const [
        _LegendItem('p50', Color(0xFF4CAF50)),
        _LegendItem('p95', Color(0xFFFF9800)),
        _LegendItem('p99', Color(0xFFF44336)),
      ],
      chart: LineChart(
        LineChartData(
          lineBarsData: [
            _latencyLine('p50', const Color(0xFF4CAF50)),
            _latencyLine('p95', const Color(0xFFFF9800)),
            _latencyLine('p99', const Color(0xFFF44336)),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, _) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= loadSteps.length) {
                    return const SizedBox();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${loadSteps[idx]['concurrency']}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF666666)),
                    ),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 50),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
        ),
      ),
    );
  }

  LineChartBarData _latencyLine(String key, Color color) {
    return LineChartBarData(
      spots: loadSteps.asMap().entries.map((e) {
        return FlSpot(
            e.key.toDouble(), (e.value[key] as num?)?.toDouble() ?? 0);
      }).toList(),
      isCurved: true,
      color: color,
      barWidth: 2,
      dotData: const FlDotData(show: true),
    );
  }

  Widget _buildErrorRateChart(BuildContext context) {
    return _buildChartCard(
      title: '错误率退化曲线 (%)',
      icon: Icons.trending_up_rounded,
      chart: LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: loadSteps.asMap().entries.map((e) {
                return FlSpot(
                  e.key.toDouble(),
                  ((e.value['errorRate'] as num?)?.toDouble() ?? 0) * 100,
                );
              }).toList(),
              isCurved: true,
              color: const Color(0xFFF44336),
              barWidth: 2.5,
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFF44336).withOpacity(0.15),
                    const Color(0xFFF44336).withOpacity(0.02),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              dotData: const FlDotData(show: true),
            ),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, _) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= loadSteps.length) {
                    return const SizedBox();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${loadSteps[idx]['concurrency']}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF666666)),
                    ),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 40),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
        ),
      ),
    );
  }

  Widget _buildChaosExperimentsSummary(BuildContext context) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF44336).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.bug_report_rounded, color: Color(0xFFF44336), size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                '混沌实验结果',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const Spacer(),
              Text(
                '${chaosExperiments.length} 个实验',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...chaosExperiments.map((exp) => _buildChaosCard(exp)),
        ],
      ),
    );
  }

  Widget _buildChaosCard(Map<String, dynamic> exp) {
    final errorRate = (exp['errorRate'] as num?)?.toDouble() ?? 0;
    final stormDetected = exp['stormDetected'] as bool? ?? false;
    final cbState = exp['circuitBreakerFinalState'] as String? ?? 'unknown';
    final successCount = (exp['successCount'] as num?)?.toInt() ?? 0;
    final failureCount = (exp['failureCount'] as num?)?.toInt() ?? 0;
    final rejectedCount = (exp['rejectedCount'] as num?)?.toInt() ?? 0;
    final retryCount = (exp['retryCount'] as num?)?.toInt() ?? 0;
    final total = successCount + failureCount;
    final faultType = exp['faultType'] as String? ?? 'unknown';

    final cbStateZh = switch (cbState.toLowerCase()) {
      'closed' => '正常',
      'open' => '熔断中',
      'halfopen' || 'half-open' || 'half_open' => '恢复中',
      _ => cbState,
    };
    final cbColor = switch (cbState.toLowerCase()) {
      'closed' => const Color(0xFF4CAF50),
      'open' => const Color(0xFFF44336),
      _ => const Color(0xFFFF9800),
    };

    final faultIcon = switch (faultType) {
      'latency' => Icons.hourglass_top_rounded,
      'error' => Icons.error_outline_rounded,
      'timeout' => Icons.timer_off_rounded,
      _ => Icons.help_outline_rounded,
    };
    final faultLabel = switch (faultType) {
      'latency' => '延迟注入',
      'error' => '错误注入',
      'timeout' => '超时注入',
      _ => faultType,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Column(
        children: [
          // 标题行
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Icon(faultIcon, color: Colors.grey[600], size: 18),
                const SizedBox(width: 8),
                Text(
                  exp['experimentName'] as String? ?? '未知实验',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    faultLabel,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ),
                const Spacer(),
                if (stormDetected)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.whatshot_rounded,
                            color: const Color(0xFFF44336), size: 14),
                        const SizedBox(width: 3),
                        Text('故障风暴',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFF44336))),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cbColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: cbColor.withOpacity(0.2)),
                  ),
                  child: Text(
                    cbStateZh,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cbColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 指标行 — 用简洁的数字 + 标签
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildMetricCell('成功', '$successCount', const Color(0xFF4CAF50)),
                _buildDivider(),
                _buildMetricCell('失败', '$failureCount', const Color(0xFFF44336)),
                _buildDivider(),
                _buildMetricCell('重试', '$retryCount', const Color(0xFF2196F3)),
                _buildDivider(),
                _buildMetricCell('拒绝', '$rejectedCount', const Color(0xFFFF9800)),
                _buildDivider(),
                _buildMetricCell(
                  '错误率',
                  '${(errorRate * 100).toStringAsFixed(1)}%',
                  errorRate > 0.1
                      ? const Color(0xFFF44336)
                      : const Color(0xFF4CAF50),
                ),
                if (total > 0) ...[
                  _buildDivider(),
                  Expanded(
                    child: Column(
                      children: [
                        SizedBox(
                          height: 4,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: successCount / total,
                              backgroundColor: const Color(0xFFF44336).withOpacity(0.15),
                              color: const Color(0xFF4CAF50),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('$successCount/$total',
                            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 观察结果
          if (exp['observations'] != null &&
              (exp['observations'] as List).isNotEmpty) ...[
            const Divider(height: 20, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final obs in (exp['observations'] as List))
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.subdirectory_arrow_right_rounded,
                            size: 13, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Text(
                          obs.toString(),
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ),
                ],
              ),
            ),
          ] else
            const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _buildMetricCell(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 28,
      color: const Color(0xFFEEEEEE),
    );
  }

  Widget _buildChartCard({
    required String title,
    required Widget chart,
    IconData? icon,
    List<_LegendItem>? legend,
  }) {
    return Container(
      height: 320,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: Colors.grey[700], size: 18),
                const SizedBox(width: 8),
              ],
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              if (legend != null) ...[
                const Spacer(),
                ...legend.map((l) => Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 3,
                            decoration: BoxDecoration(
                              color: l.color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(l.label,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[600])),
                        ],
                      ),
                    )),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Expanded(child: chart),
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Icon(Icons.science_outlined, size: 48, color: Colors.grey[400]),
            ),
            const SizedBox(height: 20),
            Text(
              '暂无测试结果',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击上方按钮执行压力测试或混沌实验',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  static const TextStyle _headerStyle = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 12,
    color: Color(0xFF555555),
  );

  String _fmtMs(dynamic v) =>
      ((v as num?)?.toDouble() ?? 0).toStringAsFixed(1);

  double _maxVal(List<Map<String, dynamic>> data, String key) {
    if (data.isEmpty) return 100;
    return data
        .map((d) => (d[key] as num?)?.toDouble() ?? 0)
        .reduce((a, b) => a > b ? a : b);
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

class _LegendItem {
  final String label;
  final Color color;
  const _LegendItem(this.label, this.color);
}

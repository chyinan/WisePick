import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

/// 压力测试结果仪表盘组件
///
/// 展示压力测试结果，包括：
/// - 负载阶梯汇总表
/// - 吞吐量 vs 并发数图表
/// - 延迟百分位图表
/// - 错误率退化曲线
/// - 混沌实验摘要
/// - 稳定性评估记分卡
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 20),
          if (stabilityAssessment != null) ...[
            _buildStabilityScorecard(context),
            const SizedBox(height: 20),
          ],
          if (loadSteps.isNotEmpty) ...[
            _buildLoadStepTable(context),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildThroughputChart(context)),
                const SizedBox(width: 16),
                Expanded(child: _buildLatencyChart(context)),
              ],
            ),
            const SizedBox(height: 20),
            _buildErrorRateChart(context),
            const SizedBox(height: 20),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.speed, color: Colors.cyanAccent, size: 32),
          const SizedBox(width: 12),
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
                  ),
                ),
                Text(
                  '并发稳定性 · 混沌测试 · 退化分析',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (isRunning)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.cyanAccent,
              ),
            )
          else ...[
            _ActionButton(
              label: '执行压力测试',
              icon: Icons.flash_on,
              color: Colors.orangeAccent,
              onPressed: onRunStressTest,
            ),
            const SizedBox(width: 8),
            _ActionButton(
              label: '执行混沌测试',
              icon: Icons.bug_report,
              color: Colors.redAccent,
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
    final findings =
        (stabilityAssessment!['findings'] as List?)?.cast<String>() ?? [];
    final warnings =
        (stabilityAssessment!['warnings'] as List?)?.cast<String>() ?? [];
    final criticals =
        (stabilityAssessment!['criticalIssues'] as List?)?.cast<String>() ?? [];

    final color = score >= 80
        ? Colors.green
        : score >= 60
            ? Colors.orange
            : Colors.red;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                passed ? Icons.verified : Icons.warning_amber,
                color: color,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(
                '稳定性评估',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${score.toStringAsFixed(0)}/100  ${passed ? "通过" : "未通过"}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 评分进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / 100,
              backgroundColor: Colors.grey[200],
              color: color,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 16),
          // 发现项
          for (final f in findings)
            _buildFindingRow(Icons.check_circle_outline, Colors.green, f),
          for (final w in warnings)
            _buildFindingRow(Icons.warning_amber, Colors.orange, w),
          for (final c in criticals)
            _buildFindingRow(Icons.error_outline, Colors.red, c),
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

  Widget _buildLoadStepTable(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '负载阶梯汇总',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor:
                  WidgetStateProperty.all(const Color(0xFFF5F5F5)),
              columnSpacing: 24,
              columns: const [
                DataColumn(label: Text('并发数', style: _headerStyle)),
                DataColumn(label: Text('吞吐量', style: _headerStyle)),
                DataColumn(label: Text('p50 (ms)', style: _headerStyle)),
                DataColumn(label: Text('p95 (ms)', style: _headerStyle)),
                DataColumn(label: Text('p99 (ms)', style: _headerStyle)),
                DataColumn(label: Text('错误率', style: _headerStyle)),
                DataColumn(label: Text('成功数', style: _headerStyle)),
              ],
              rows: loadSteps.map((step) {
                final errorRate =
                    (step['errorRate'] as num?)?.toDouble() ?? 0;
                return DataRow(
                  color: errorRate > 0.5
                      ? WidgetStateProperty.all(Colors.red.withOpacity(0.05))
                      : null,
                  cells: [
                    DataCell(Text('${step['concurrency'] ?? 0}')),
                    DataCell(Text(
                        '${((step['throughput'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)}/秒')),
                    DataCell(Text(_fmtMs(step['p50']))),
                    DataCell(Text(_fmtMs(step['p95']))),
                    DataCell(Text(_fmtMs(step['p99']))),
                    DataCell(Text(
                      '${(errorRate * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: errorRate > 0.3
                            ? Colors.red
                            : errorRate > 0.1
                                ? Colors.orange
                                : Colors.green,
                        fontWeight: FontWeight.w500,
                      ),
                    )),
                    DataCell(Text(
                        '${step['successCount'] ?? 0}/${step['totalRequests'] ?? 0}')),
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
                  color: const Color(0xFF3498DB),
                  width: 16,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
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
                  return Text(
                    '${loadSteps[idx]['concurrency']}',
                    style: const TextStyle(fontSize: 10),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 60),
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
      title: '延迟百分位分布 (毫秒)',
      chart: LineChart(
        LineChartData(
          lineBarsData: [
            _latencyLine('p50', const Color(0xFF2ECC71)),
            _latencyLine('p95', const Color(0xFFF39C12)),
            _latencyLine('p99', const Color(0xFFE74C3C)),
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
                  return Text(
                    '${loadSteps[idx]['concurrency']}',
                    style: const TextStyle(fontSize: 10),
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
    final hasErrors = loadSteps
        .any((s) => ((s['errorRate'] as num?)?.toDouble() ?? 0) > 0);
    if (!hasErrors) return const SizedBox();

    return _buildChartCard(
      title: '错误率退化曲线',
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
              color: Colors.red,
              barWidth: 2,
              belowBarData: BarAreaData(
                show: true,
                color: Colors.red.withOpacity(0.1),
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
                  return Text(
                    '${loadSteps[idx]['concurrency']}',
                    style: const TextStyle(fontSize: 10),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bug_report, color: Colors.red, size: 24),
              const SizedBox(width: 8),
              Text(
                '混沌实验结果',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...chaosExperiments.map((exp) => _buildChaosCard(exp)),
        ],
      ),
    );
  }

  Widget _buildChaosCard(Map<String, dynamic> exp) {
    final errorRate = (exp['errorRate'] as num?)?.toDouble() ?? 0;
    final stormDetected = exp['stormDetected'] as bool? ?? false;
    final cbState = exp['circuitBreakerFinalState'] as String? ?? 'unknown';

    // 熔断器状态中文映射
    final cbStateZh = switch (cbState) {
      'closed' => '关闭（正常）',
      'open' => '打开（熔断中）',
      'halfOpen' || 'half-open' || 'half_open' => '半开（恢复中）',
      _ => cbState,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: stormDetected ? Colors.red : Colors.green,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exp['experimentName'] as String? ?? '未知实验',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            '故障类型: ${exp['faultType'] ?? '无'}',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _metric('成功', '${exp['successCount'] ?? 0}', Colors.green),
              _metric('失败', '${exp['failureCount'] ?? 0}', Colors.red),
              _metric('拒绝', '${exp['rejectedCount'] ?? 0}', Colors.orange),
              _metric('重试', '${exp['retryCount'] ?? 0}', Colors.blue),
              _metric(
                '错误率',
                '${(errorRate * 100).toStringAsFixed(1)}%',
                errorRate > 0.5 ? Colors.red : Colors.green,
              ),
              _metric(
                '熔断器',
                cbStateZh,
                cbState == 'closed' ? Colors.green : Colors.orange,
              ),
              if (stormDetected)
                _metric('故障风暴', '已检测', Colors.red),
            ],
          ),
          if (exp['observations'] != null) ...[
            const SizedBox(height: 8),
            for (final obs in (exp['observations'] as List))
              Text(
                '→ $obs',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
          ],
        ],
      ),
    );
  }

  Widget _metric(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildChartCard({required String title, required Widget chart}) {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(child: chart),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.science, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              '暂无压力测试结果',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击上方按钮执行压力测试或混沌实验，\n'
              '结果将在此处展示。\n'
              '也可通过命令行在本地运行：\n'
              'dart test test/stress/',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
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
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

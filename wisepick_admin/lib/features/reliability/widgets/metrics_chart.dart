import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

/// 时间序列图表组件
class MetricsChart extends StatefulWidget {
  final String title;
  final String metric;
  final List<Map<String, dynamic>> data;
  final Color color;
  final String? unit;
  final double? threshold;
  final bool showArea;

  const MetricsChart({
    super.key,
    required this.title,
    required this.metric,
    required this.data,
    this.color = const Color(0xFF6366F1),
    this.unit,
    this.threshold,
    this.showArea = true,
  });

  @override
  State<MetricsChart> createState() => _MetricsChartState();
}

class _MetricsChartState extends State<MetricsChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              if (_touchedIndex != null && _touchedIndex! < widget.data.length)
                _buildTooltipValue(),
            ],
          ),
          const SizedBox(height: 8),
          _buildStats(),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: widget.data.isEmpty
                ? _buildEmptyState()
                : _buildChart(),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    if (widget.data.isEmpty) return const SizedBox.shrink();

    // 安全提取数值，过滤无效数据
    final values = widget.data
        .map((d) => (d['value'] as num?)?.toDouble())
        .where((v) => v != null)
        .cast<double>()
        .toList();
    
    // 如果没有有效值，返回空
    if (values.isEmpty) return const SizedBox.shrink();

    final avg = values.reduce((a, b) => a + b) / values.length;
    final max = values.reduce((a, b) => a > b ? a : b);
    final min = values.reduce((a, b) => a < b ? a : b);
    final latest = values.last;

    return Row(
      children: [
        _buildStatChip('当前', latest, widget.color),
        const SizedBox(width: 12),
        _buildStatChip('平均', avg, Colors.grey),
        const SizedBox(width: 12),
        _buildStatChip('最高', max, Colors.orange),
        const SizedBox(width: 12),
        _buildStatChip('最低', min, Colors.blue),
      ],
    );
  }

  Widget _buildStatChip(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color.withOpacity(0.8),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _formatValue(value),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTooltipValue() {
    final point = widget.data[_touchedIndex!];
    final timestampStr = point['timestamp'] as String?;
    final timestamp = timestampStr != null ? DateTime.tryParse(timestampStr) : null;
    final value = (point['value'] as num?)?.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: widget.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            timestamp != null ? DateFormat('HH:mm').format(timestamp) : '--:--',
            style: TextStyle(
              fontSize: 12,
              color: widget.color.withOpacity(0.7),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatValue(value),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: widget.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.show_chart,
            size: 48,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 8),
          Text(
            '暂无数据',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final spots = <FlSpot>[];
    for (int i = 0; i < widget.data.length; i++) {
      final value = (widget.data[i]['value'] as num?)?.toDouble() ?? 0;
      spots.add(FlSpot(i.toDouble(), value));
    }

    // 安全处理空数据情况
    if (spots.isEmpty) {
      return _buildEmptyState();
    }

    final values = spots.map((s) => s.y).toList();
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final range = maxY - minY;
    final padding = range > 0 ? range * 0.1 : 1.0;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: range > 0 ? range / 4 : 1,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withOpacity(0.1),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              getTitlesWidget: (value, meta) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    _formatValue(value),
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: (widget.data.length / 6).ceilToDouble(),
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= widget.data.length) {
                  return const SizedBox.shrink();
                }
                final timestampStr = widget.data[index]['timestamp'] as String?;
                final timestamp = timestampStr != null ? DateTime.tryParse(timestampStr) : null;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    timestamp != null ? DateFormat('HH:mm').format(timestamp) : '--:--',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minY: minY - padding,
        maxY: maxY + padding,
        lineTouchData: LineTouchData(
          enabled: true,
          touchCallback: (event, response) {
            if (event is FlTapUpEvent || event is FlPanUpdateEvent) {
              setState(() {
                _touchedIndex = response?.lineBarSpots?.first.spotIndex;
              });
            }
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => widget.color.withOpacity(0.8),
            getTooltipItems: (spots) => spots.map((spot) {
              return LineTooltipItem(
                _formatValue(spot.y),
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              );
            }).toList(),
          ),
        ),
        extraLinesData: widget.threshold != null
            ? ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: widget.threshold!,
                    color: Colors.red.withOpacity(0.5),
                    strokeWidth: 2,
                    dashArray: [5, 5],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      style: TextStyle(
                        color: Colors.red[400],
                        fontSize: 10,
                      ),
                      labelResolver: (_) => '阈值',
                    ),
                  ),
                ],
              )
            : null,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: widget.color,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: widget.showArea
                ? BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        widget.color.withOpacity(0.3),
                        widget.color.withOpacity(0.0),
                      ],
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  String _formatValue(double value) {
    if (widget.unit == '%') {
      return '${(value * 100).toStringAsFixed(1)}%';
    }
    if (widget.unit == 'ms') {
      return '${value.toStringAsFixed(0)}ms';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.toStringAsFixed(value < 1 ? 3 : 1);
  }
}

/// 多指标对比图表
class MultiMetricsChart extends StatelessWidget {
  final String title;
  final List<MetricSeries> series;
  final double height;

  const MultiMetricsChart({
    super.key,
    required this.title,
    required this.series,
    this.height = 250,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              _buildLegend(),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: height,
            child: _buildChart(),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: series.map((s) => Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 3,
              decoration: BoxDecoration(
                color: s.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              s.name,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }

  Widget _buildChart() {
    if (series.isEmpty || series.first.data.isEmpty) {
      return const Center(child: Text('暂无数据'));
    }

    final lineBars = <LineChartBarData>[];
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (final s in series) {
      final spots = <FlSpot>[];
      for (int i = 0; i < s.data.length; i++) {
        final value = (s.data[i]['value'] as num?)?.toDouble() ?? 0;
        spots.add(FlSpot(i.toDouble(), value));
        if (value < minY) minY = value;
        if (value > maxY) maxY = value;
      }

      lineBars.add(LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.3,
        color: s.color,
        barWidth: 2,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
      ));
    }

    // 安全处理 minY/maxY 未被更新的情况
    if (minY == double.infinity) minY = 0;
    if (maxY == double.negativeInfinity) maxY = 1;

    final range = maxY - minY;
    final padding = range > 0 ? range * 0.1 : 1.0;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withOpacity(0.1),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 45,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  value.toStringAsFixed(0),
                  style: TextStyle(color: Colors.grey[500], fontSize: 10),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: (series.first.data.length / 6).ceilToDouble(),
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= series.first.data.length) {
                  return const SizedBox.shrink();
                }
                final timestampStr = series.first.data[index]['timestamp'] as String?;
                final timestamp = timestampStr != null ? DateTime.tryParse(timestampStr) : null;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    timestamp != null ? DateFormat('HH:mm').format(timestamp) : '--:--',
                    style: TextStyle(color: Colors.grey[500], fontSize: 10),
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minY: minY - padding,
        maxY: maxY + padding,
        lineBarsData: lineBars,
      ),
    );
  }
}

class MetricSeries {
  final String name;
  final List<Map<String, dynamic>> data;
  final Color color;

  const MetricSeries({
    required this.name,
    required this.data,
    required this.color,
  });
}

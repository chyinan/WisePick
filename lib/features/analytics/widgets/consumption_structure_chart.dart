import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../analytics_models.dart';

/// 消费结构图表组件
/// 
/// 支持饼图和柱状图两种展示方式
class ConsumptionStructureChart extends StatelessWidget {
  final List<CategoryDistribution> data;
  final bool showPieChart;

  const ConsumptionStructureChart({
    super.key,
    required this.data,
    this.showPieChart = true,
  });

  // 图表颜色方案（基于UI设计规范）
  static const List<Color> chartColors = [
    Color(0xFF6750A4), // 主色
    Color(0xFF625B71), // 次色
    Color(0xFFE53935), // 京东红
    Color(0xFFFF5722), // 淘宝橙
    Color(0xFFFF4E4E), // 拼多多粉
    Color(0xFF2E7D32), // 成功绿
    Color(0xFFF57C00), // 警告橙
  ];

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return _buildEmptyState(context);
    }

    return showPieChart ? _buildPieChart(context) : _buildBarChart(context);
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.pie_chart_outline,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无消费数据',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPieChart(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: _buildPieSections(),
              pieTouchData: PieTouchData(
                touchCallback: (FlTouchEvent event, pieTouchResponse) {
                  // TODO: 处理触摸交互
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildLegend(context),
      ],
    );
  }

  List<PieChartSectionData> _buildPieSections() {
    return data.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final color = chartColors[index % chartColors.length];

      return PieChartSectionData(
        color: color,
        value: item.percentage,
        title: '${item.percentage.toStringAsFixed(1)}%',
        radius: 80,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  Widget _buildBarChart(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: data.map((e) => e.percentage).reduce((a, b) => a > b ? a : b) * 1.2,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) => colorScheme.surfaceContainerHighest,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final item = data[group.x.toInt()];
                    return BarTooltipItem(
                      '${item.category}\n',
                      TextStyle(color: colorScheme.onSurface),
                      children: [
                        TextSpan(
                          text: '${item.count}件 · ¥${item.amount.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index >= 0 && index < data.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _truncateText(data[index].category, 4),
                            style: TextStyle(
                              fontSize: 10,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        '${value.toInt()}%',
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 10,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: colorScheme.outlineVariant.withOpacity(0.3),
                  strokeWidth: 1,
                ),
              ),
              barGroups: _buildBarGroups(),
            ),
          ),
        ),
      ],
    );
  }

  List<BarChartGroupData> _buildBarGroups() {
    return data.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final color = chartColors[index % chartColors.length];

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: item.percentage,
            color: color,
            width: 20,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      );
    }).toList();
  }

  Widget _buildLegend(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: data.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        final color = chartColors[index % chartColors.length];

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              item.category,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      }).toList(),
    );
  }

  String _truncateText(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
}

/// 平台偏好图表组件
class PlatformPreferenceChart extends StatelessWidget {
  final List<PlatformPreference> data;

  const PlatformPreferenceChart({
    super.key,
    required this.data,
  });

  // 平台颜色
  static const Map<String, Color> platformColors = {
    'taobao': Color(0xFFFF5722),
    'jd': Color(0xFFE53935),
    'pdd': Color(0xFFFF4E4E),
  };

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(child: Text('暂无数据'));
    }

    return Column(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 50,
              sections: _buildPieSections(context),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildLegend(context),
      ],
    );
  }

  List<PieChartSectionData> _buildPieSections(BuildContext context) {
    return data.map((item) {
      final color = platformColors[item.platform] ?? Theme.of(context).colorScheme.primary;

      return PieChartSectionData(
        color: color,
        value: item.percentage,
        title: '${item.percentage.toStringAsFixed(0)}%',
        radius: 60,
        titleStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  Widget _buildLegend(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: data.map((item) {
        final color = platformColors[item.platform] ?? Theme.of(context).colorScheme.primary;

        return Column(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.displayName,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              '${item.count}件',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

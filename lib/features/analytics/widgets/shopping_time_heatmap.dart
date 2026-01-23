import 'package:flutter/material.dart';
import '../analytics_models.dart';

/// 购物时间热力图组件
/// 
/// 展示用户购物时间分布：24小时 x 7天的热力图
class ShoppingTimeHeatmap extends StatelessWidget {
  final ShoppingTimeAnalysis data;

  const ShoppingTimeHeatmap({
    super.key,
    required this.data,
  });

  // 热力图颜色方案（从浅到深）
  static const List<Color> heatmapColors = [
    Color(0xFFE8EAF6), // 最低值（浅色）
    Color(0xFFC5CAE9),
    Color(0xFF9FA8DA),
    Color(0xFF7986CB),
    Color(0xFF5C6BC0),
    Color(0xFF3F51B5),
    Color(0xFF6750A4), // 最高值（深色）
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 热力图
        _buildHeatmap(context),
        
        const SizedBox(height: 16),
        
        // 图例
        _buildLegend(context),
        
        const SizedBox(height: 24),
        
        // 统计信息
        _buildStats(context),
      ],
    );
  }

  Widget _buildHeatmap(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

    // 计算最大值用于归一化
    int maxValue = 1;
    for (final row in data.heatmapData) {
      for (final value in row) {
        if (value > maxValue) maxValue = value;
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 小时标签行
          Row(
            children: [
              const SizedBox(width: 40), // 星期标签的宽度
              ...List.generate(24, (hour) {
                return SizedBox(
                  width: 24,
                  child: hour % 3 == 0
                      ? Text(
                          '$hour',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        )
                      : const SizedBox.shrink(),
                );
              }),
            ],
          ),
          
          const SizedBox(height: 4),
          
          // 热力图网格
          ...List.generate(7, (dayIndex) {
            return Row(
              children: [
                // 星期标签
                SizedBox(
                  width: 40,
                  child: Text(
                    weekdays[dayIndex],
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                
                // 小时格子
                ...List.generate(24, (hourIndex) {
                  final value = data.heatmapData[dayIndex][hourIndex];
                  final colorIndex = ((value / maxValue) * (heatmapColors.length - 1)).round();
                  final color = heatmapColors[colorIndex.clamp(0, heatmapColors.length - 1)];

                  return Tooltip(
                    message: '${weekdays[dayIndex]} ${hourIndex}:00 - ${hourIndex + 1}:00\n活跃度: $value',
                    child: Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildLegend(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '低',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        ...heatmapColors.map((color) {
          return Container(
            width: 20,
            height: 12,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
        const SizedBox(width: 8),
        Text(
          '高',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildStats(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: _buildStatItem(
            context: context,
            icon: Icons.access_time,
            label: '最活跃时段',
            value: data.peakHours,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatItem(
            context: context,
            icon: Icons.calendar_today,
            label: '最活跃日期',
            value: data.peakDays,
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 小时分布柱状图组件
class HourlyDistributionChart extends StatelessWidget {
  final List<HourlyDistribution> data;

  const HourlyDistributionChart({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    // 找到最大值
    final maxCount = data.map((e) => e.count).reduce((a, b) => a > b ? a : b);
    if (maxCount == 0) {
      return const Center(child: Text('暂无数据'));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data.map((item) {
          final height = maxCount > 0 ? (item.count / maxCount) * 150 : 0.0;
          final isHighlight = item.count > maxCount * 0.7;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isHighlight)
                  Text(
                    '${item.count}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: colorScheme.primary,
                    ),
                  ),
                Container(
                  width: 16,
                  height: height.clamp(4.0, 150.0),
                  decoration: BoxDecoration(
                    color: isHighlight 
                        ? colorScheme.primary 
                        : colorScheme.primaryContainer,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.hour % 4 == 0 ? '${item.hour}' : '',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

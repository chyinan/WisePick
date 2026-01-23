import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'admin_models.dart';
import 'admin_providers.dart';

/// 管理员后台仪表板页面
/// 
/// 展示用户统计、系统监控、搜索热词统计等数据
class AdminDashboardPage extends ConsumerStatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  ConsumerState<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends ConsumerState<AdminDashboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      ref.read(adminTabIndexProvider.notifier).state = _tabController.index;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理员后台'),
        actions: [
          _buildTimeRangeSelector(context),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => refreshAdminStats(ref),
            tooltip: '刷新数据',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _showExportDialog(context),
            tooltip: '导出数据',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '用户统计', icon: Icon(Icons.people_outline)),
            Tab(text: '系统监控', icon: Icon(Icons.monitor_heart_outlined)),
            Tab(text: '搜索热词', icon: Icon(Icons.trending_up)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUserStatsTab(),
          _buildSystemStatsTab(),
          _buildKeywordStatsTab(),
        ],
      ),
    );
  }

  Widget _buildTimeRangeSelector(BuildContext context) {
    final timeRange = ref.watch(adminTimeRangeProvider);
    
    return PopupMenuButton<AdminStatsTimeRange>(
      icon: const Icon(Icons.date_range),
      tooltip: '选择时间范围',
      initialValue: timeRange,
      onSelected: (value) {
        ref.read(adminTimeRangeProvider.notifier).state = value;
      },
      itemBuilder: (context) => AdminStatsTimeRange.values
          .map((range) => PopupMenuItem(
                value: range,
                child: Text(range.displayName),
              ))
          .toList(),
    );
  }

  /// 用户统计 Tab
  Widget _buildUserStatsTab() {
    final statsAsync = ref.watch(userStatisticsProvider);

    return statsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _buildErrorWidget(error.toString()),
      data: (data) => _buildUserStatsContent(data),
    );
  }

  Widget _buildUserStatsContent(UserStatistics data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 核心指标卡片
          _buildStatsGrid([
            _StatItem(
              icon: Icons.people,
              label: '总用户数',
              value: _formatNumber(data.totalUsers),
              color: Colors.blue,
            ),
            _StatItem(
              icon: Icons.person_outline,
              label: '日活跃',
              value: _formatNumber(data.activeUsers.daily),
              color: Colors.green,
            ),
            _StatItem(
              icon: Icons.group_outlined,
              label: '周活跃',
              value: _formatNumber(data.activeUsers.weekly),
              color: Colors.orange,
            ),
            _StatItem(
              icon: Icons.groups_outlined,
              label: '月活跃',
              value: _formatNumber(data.activeUsers.monthly),
              color: Colors.purple,
            ),
          ]),

          const SizedBox(height: 24),

          // 留存率卡片
          _buildCard(
            title: '用户留存率',
            child: Column(
              children: [
                _buildRetentionRow('次日留存', data.retentionRate.day1),
                _buildRetentionRow('7日留存', data.retentionRate.day7),
                _buildRetentionRow('30日留存', data.retentionRate.day30),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 新增用户趋势
          _buildCard(
            title: '新增用户趋势',
            child: SizedBox(
              height: 200,
              child: _buildTrendChart(data.newUserTrend),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRetentionRow(String label, double rate) {
    final percentage = (rate * 100).toStringAsFixed(1);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 24,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: rate.clamp(0.0, 1.0),
                  child: Container(
                    height: 24,
                    decoration: BoxDecoration(
                      color: _getRetentionColor(rate),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 50,
            child: Text(
              '$percentage%',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Color _getRetentionColor(double rate) {
    if (rate >= 0.3) return Colors.green;
    if (rate >= 0.2) return Colors.orange;
    return Colors.red;
  }

  /// 系统监控 Tab
  Widget _buildSystemStatsTab() {
    final statsAsync = ref.watch(systemStatisticsProvider);

    return statsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _buildErrorWidget(error.toString()),
      data: (data) => _buildSystemStatsContent(data),
    );
  }

  Widget _buildSystemStatsContent(SystemStatistics data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // API调用统计
          _buildStatsGrid([
            _StatItem(
              icon: Icons.api,
              label: 'API调用总数',
              value: _formatNumber(data.apiCalls.total),
              color: Colors.blue,
            ),
            _StatItem(
              icon: Icons.check_circle_outline,
              label: '成功率',
              value: '${(data.apiCalls.successRate * 100).toStringAsFixed(1)}%',
              color: Colors.green,
            ),
            _StatItem(
              icon: Icons.timer_outlined,
              label: '平均响应时间',
              value: '${data.apiCalls.avgResponseTime.toStringAsFixed(0)}ms',
              color: Colors.orange,
            ),
            _StatItem(
              icon: Icons.error_outline,
              label: '错误率',
              value: '${(data.errorStats.errorRate * 100).toStringAsFixed(2)}%',
              color: Colors.red,
            ),
          ]),

          const SizedBox(height: 24),

          // 搜索成功率
          _buildCard(
            title: '搜索统计',
            child: Column(
              children: [
                _buildStatRow('总搜索次数', _formatNumber(data.searchStats.totalSearches)),
                _buildStatRow('成功搜索', _formatNumber(data.searchStats.successfulSearches)),
                _buildStatRow('成功率', '${(data.searchStats.successRate * 100).toStringAsFixed(1)}%'),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 错误类型分布
          _buildCard(
            title: '错误类型分布',
            child: Column(
              children: data.errorStats.errorTypes.map((e) => 
                _buildErrorTypeRow(e)
              ).toList(),
            ),
          ),

          const SizedBox(height: 16),

          // 响应时间分布
          _buildCard(
            title: '响应时间分布',
            child: Column(
              children: data.responseTimeDistribution.map((d) =>
                _buildResponseTimeRow(d)
              ).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildErrorTypeRow(ErrorTypeCount error) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(error.type, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            flex: 3,
            child: Text(error.description),
          ),
          SizedBox(
            width: 60,
            child: Text(
              '${error.count}',
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponseTimeRow(ResponseTimeDistribution dist) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(dist.range, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 20,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: (dist.percentage / 100).clamp(0.0, 1.0),
                  child: Container(
                    height: 20,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 45,
            child: Text(
              '${dist.percentage.toStringAsFixed(0)}%',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  /// 搜索热词 Tab
  Widget _buildKeywordStatsTab() {
    final statsAsync = ref.watch(searchKeywordStatsProvider);

    return statsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _buildErrorWidget(error.toString()),
      data: (data) => _buildKeywordStatsContent(data),
    );
  }

  Widget _buildKeywordStatsContent(SearchKeywordStats data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 热门搜索词排行
          _buildCard(
            title: '热门搜索词 Top 10',
            child: Column(
              children: data.topKeywords.take(10).toList().asMap().entries.map((entry) {
                final index = entry.key;
                final keyword = entry.value;
                return _buildKeywordRow(index + 1, keyword);
              }).toList(),
            ),
          ),

          const SizedBox(height: 16),

          // 搜索失败的关键词
          _buildCard(
            title: '搜索失败关键词',
            subtitle: '以下关键词搜索无结果，可能需要优化',
            child: Column(
              children: data.failedKeywords.map((k) => 
                _buildKeywordRow(null, k, isFailure: true)
              ).toList(),
            ),
          ),

          const SizedBox(height: 16),

          // 搜索趋势
          _buildCard(
            title: '搜索量趋势',
            child: SizedBox(
              height: 200,
              child: _buildSearchTrendChart(data.trends),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeywordRow(int? rank, KeywordCount keyword, {bool isFailure = false}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (rank != null)
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: rank <= 3 
                    ? (rank == 1 ? Colors.amber : rank == 2 ? Colors.grey.shade400 : Colors.brown.shade300)
                    : colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$rank',
                  style: TextStyle(
                    color: rank <= 3 ? Colors.white : colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              keyword.keyword,
              style: TextStyle(
                color: isFailure ? colorScheme.error : null,
              ),
            ),
          ),
          Text(
            '${keyword.count}次',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendChart(List<DailyCount> data) {
    if (data.isEmpty) {
      return const Center(child: Text('暂无数据'));
    }

    return CustomPaint(
      painter: _SimpleTrendChartPainter(
        data: data.map((d) => d.count.toDouble()).toList(),
        color: Theme.of(context).colorScheme.primary,
        gridColor: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }

  Widget _buildSearchTrendChart(List<DailyKeywordTrend> trends) {
    if (trends.isEmpty) {
      return const Center(child: Text('暂无数据'));
    }

    return CustomPaint(
      painter: _SimpleTrendChartPainter(
        data: trends.map((t) => t.searchCount.toDouble()).toList(),
        color: Theme.of(context).colorScheme.primary,
        gridColor: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }

  Widget _buildStatsGrid(List<_StatItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        final crossAxisCount = isWide ? 4 : 2;
        
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: isWide ? 1.5 : 1.3,
          children: items.map((item) => _buildStatCard(item)).toList(),
        );
      },
    );
  }

  Widget _buildStatCard(_StatItem item) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(item.icon, size: 20, color: item.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text('加载失败: $message'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => refreshAdminStats(ref),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  String _formatNumber(int number) {
    if (number >= 10000) {
      return '${(number / 10000).toStringAsFixed(1)}万';
    }
    if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}千';
    }
    return '$number';
  }

  void _showExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导出数据'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('选择要导出的数据类型和格式'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('导出功能开发中...')),
              );
            },
            child: const Text('导出CSV'),
          ),
        ],
      ),
    );
  }
}

class _StatItem {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}

/// 简单的趋势图绘制器
class _SimpleTrendChartPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final Color gridColor;

  _SimpleTrendChartPainter({
    required this.data,
    required this.color,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    const leftPadding = 40.0;
    const rightPadding = 16.0;
    const topPadding = 16.0;
    const bottomPadding = 24.0;

    final chartWidth = size.width - leftPadding - rightPadding;
    final chartHeight = size.height - topPadding - bottomPadding;

    final maxValue = data.reduce((a, b) => a > b ? a : b) * 1.1;
    final minValue = data.reduce((a, b) => a < b ? a : b) * 0.9;
    final valueRange = maxValue - minValue;

    // 绘制网格
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    for (int i = 0; i <= 4; i++) {
      final y = topPadding + (chartHeight / 4) * i;
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );
    }

    // 绘制线条
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final linePath = Path();
    final fillPath = Path();

    fillPath.moveTo(leftPadding, topPadding + chartHeight);

    for (int i = 0; i < data.length; i++) {
      final x = leftPadding + (chartWidth / (data.length - 1)) * i;
      final normalizedValue = valueRange > 0 
          ? (data[i] - minValue) / valueRange 
          : 0.5;
      final y = topPadding + chartHeight - (normalizedValue * chartHeight);

      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
      fillPath.lineTo(x, y);
    }

    fillPath.lineTo(leftPadding + chartWidth, topPadding + chartHeight);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(covariant _SimpleTrendChartPainter oldDelegate) {
    return data != oldDelegate.data || color != oldDelegate.color;
  }
}

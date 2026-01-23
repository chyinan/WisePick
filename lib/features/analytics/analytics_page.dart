import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'analytics_models.dart';
import 'analytics_providers.dart';
import 'widgets/consumption_structure_chart.dart';
import 'widgets/preferences_card.dart';
import 'widgets/shopping_time_heatmap.dart';

/// 数据分析页面
/// 
/// 展示消费结构分析、用户偏好分析、购物时间分析等数据洞察
class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({super.key});

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      ref.read(analyticsTabIndexProvider.notifier).state = _tabController.index;
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
        title: const Text('数据分析'),
        actions: [
          // 时间范围选择
          _buildTimeRangeSelector(context),
          // 刷新按钮
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => refreshAnalyticsData(ref),
            tooltip: '刷新数据',
          ),
          // 导出报告按钮
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _showExportDialog(context),
            tooltip: '导出报告',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '消费结构', icon: Icon(Icons.pie_chart_outline)),
            Tab(text: '偏好分析', icon: Icon(Icons.person_outline)),
            Tab(text: '时间分析', icon: Icon(Icons.schedule_outlined)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildConsumptionTab(),
          _buildPreferencesTab(),
          _buildTimeAnalysisTab(),
        ],
      ),
    );
  }

  Widget _buildTimeRangeSelector(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.date_range),
      tooltip: '选择时间范围',
      onSelected: (value) {
        AnalyticsDateRange range;
        switch (value) {
          case 'week':
            range = AnalyticsDateRange.lastWeek();
            break;
          case 'month':
            range = AnalyticsDateRange.lastMonth();
            break;
          case 'threeMonths':
            range = AnalyticsDateRange.lastThreeMonths();
            break;
          case 'year':
            range = AnalyticsDateRange.lastYear();
            break;
          default:
            range = AnalyticsDateRange.lastMonth();
        }
        ref.read(selectedTimeRangeProvider.notifier).state = range;
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'week',
          child: Text('近一周'),
        ),
        const PopupMenuItem(
          value: 'month',
          child: Text('近一个月'),
        ),
        const PopupMenuItem(
          value: 'threeMonths',
          child: Text('近三个月'),
        ),
        const PopupMenuItem(
          value: 'year',
          child: Text('近一年'),
        ),
      ],
    );
  }

  /// 消费结构分析 Tab
  Widget _buildConsumptionTab() {
    final consumptionAsync = ref.watch(consumptionStructureProvider);

    return consumptionAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _buildErrorWidget(error.toString()),
      data: (data) => _buildConsumptionContent(data),
    );
  }

  Widget _buildConsumptionContent(ConsumptionStructure data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部统计面板
          _buildStatsPanels(data),
          
          const SizedBox(height: 24),

          // 品类分布图表
          _buildChartCard(
            title: '品类分布',
            subtitle: '按商品数量统计',
            trailing: _buildChartTypeToggle(categoryChartTypeProvider),
            child: SizedBox(
              height: 300,
              child: ConsumptionStructureChart(
                data: data.categoryDistribution,
                showPieChart: ref.watch(categoryChartTypeProvider) == ChartType.pie,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 平台偏好图表
          _buildChartCard(
            title: '平台偏好',
            subtitle: '各平台购买分布',
            child: SizedBox(
              height: 280,
              child: PlatformPreferenceChart(
                data: data.platformPreference,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 价格区间分布
          _buildChartCard(
            title: '价格区间分布',
            subtitle: '商品价格分布情况',
            child: SizedBox(
              height: 200,
              child: _buildPriceRangeChart(data.priceRangeDistribution),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsPanels(ConsumptionStructure data) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildStatCard(
              icon: Icons.shopping_bag_outlined,
              label: '商品总数',
              value: '${data.totalProducts}',
              unit: '件',
              width: isWide ? (constraints.maxWidth - 48) / 3 : (constraints.maxWidth - 16) / 2,
            ),
            _buildStatCard(
              icon: Icons.attach_money,
              label: '总消费',
              value: data.totalAmount.toStringAsFixed(0),
              unit: '¥',
              isPrefix: true,
              width: isWide ? (constraints.maxWidth - 48) / 3 : (constraints.maxWidth - 16) / 2,
            ),
            _buildStatCard(
              icon: Icons.category_outlined,
              label: '品类数',
              value: '${data.categoryDistribution.length}',
              unit: '个',
              width: isWide ? (constraints.maxWidth - 48) / 3 : constraints.maxWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    bool isPrefix = false,
    required double width,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isPrefix)
                Text(
                  unit,
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
              Text(
                value,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (!isPrefix)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  child: Text(
                    unit,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard({
    required String title,
    String? subtitle,
    Widget? trailing,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildChartTypeToggle(StateProvider<ChartType> provider) {
    final chartType = ref.watch(provider);
    
    return SegmentedButton<ChartType>(
      segments: const [
        ButtonSegment(value: ChartType.pie, icon: Icon(Icons.pie_chart, size: 18)),
        ButtonSegment(value: ChartType.bar, icon: Icon(Icons.bar_chart, size: 18)),
      ],
      selected: {chartType},
      onSelectionChanged: (selected) {
        ref.read(provider.notifier).state = selected.first;
      },
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildPriceRangeChart(List<PriceRangeDistribution> data) {
    if (data.isEmpty) return const Center(child: Text('暂无数据'));
    
    final colorScheme = Theme.of(context).colorScheme;
    final maxPercentage = data.map((e) => e.percentage).reduce((a, b) => a > b ? a : b);

    return Column(
      children: data.map((item) {
        final widthFactor = maxPercentage > 0 ? item.percentage / maxPercentage : 0.0;
        
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  '¥${item.range}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 24,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: widthFactor.clamp(0.05, 1.0),
                      child: Container(
                        height: 24,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          '${item.percentage.toStringAsFixed(1)}%',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 50,
                child: Text(
                  '${item.count}件',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// 偏好分析 Tab
  Widget _buildPreferencesTab() {
    final preferencesAsync = ref.watch(userPreferencesProvider);

    return preferencesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _buildErrorWidget(error.toString()),
      data: (data) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.insights,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '智能偏好分析',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '基于您的购物行为生成的个性化画像',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Divider(height: 32),
                PreferencesCard(preferences: data),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 时间分析 Tab
  Widget _buildTimeAnalysisTab() {
    final timeAnalysisAsync = ref.watch(shoppingTimeAnalysisProvider);

    return timeAnalysisAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _buildErrorWidget(error.toString()),
      data: (data) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 热力图卡片
            _buildChartCard(
              title: '购物时间热力图',
              subtitle: '分析您的购物时间分布模式',
              child: ShoppingTimeHeatmap(data: data),
            ),

            const SizedBox(height: 16),

            // 小时分布柱状图
            _buildChartCard(
              title: '24小时分布',
              subtitle: '每小时购物活跃度',
              child: SizedBox(
                height: 180,
                child: HourlyDistributionChart(data: data.hourlyDistribution),
              ),
            ),
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
          Text(
            '加载失败',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => refreshAnalyticsData(ref),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  void _showExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导出购物报告'),
        content: const Text('将根据当前时间范围生成购物报告，并导出为PDF文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _exportReport();
            },
            child: const Text('导出PDF'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportReport() async {
    final timeRange = ref.read(selectedTimeRangeProvider);
    
    // 显示加载提示
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在生成报告...')),
    );

    try {
      final report = await ref.read(shoppingReportProvider(timeRange).future);
      final exportNotifier = ref.read(reportExportStateProvider.notifier);
      await exportNotifier.exportToPdf(report);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('报告已生成'),
            action: SnackBarAction(
              label: '查看',
              onPressed: () {
                // TODO: 打开PDF文件
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导出失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

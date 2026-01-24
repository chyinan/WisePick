import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'price_history_model.dart';
import 'price_history_providers.dart';
import 'price_history_service.dart';
import 'widgets/price_history_chart.dart';

/// 价格历史页面
/// 
/// 展示商品价格历史曲线、趋势分析和购买时机建议
class PriceHistoryPage extends ConsumerWidget {
  final String productId;
  final String productTitle;
  final String? productImage;
  final double? currentPrice;

  const PriceHistoryPage({
    super.key,
    required this.productId,
    required this.productTitle,
    this.productImage,
    this.currentPrice,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productInfo = ProductInfo(
      id: productId,
      title: productTitle,
      image: productImage,
    );
    
    final trendAnalysis = ref.watch(priceTrendAnalysisProvider(productInfo));
    final buyingSuggestion = ref.watch(buyingTimeSuggestionProvider(productId));
    final timeRange = ref.watch(priceHistoryTimeRangeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('价格历史'),
        actions: [
          // 时间范围选择
          PopupMenuButton<PriceHistoryTimeRange>(
            icon: const Icon(Icons.date_range),
            tooltip: '选择时间范围',
            initialValue: timeRange,
            onSelected: (value) {
              ref.read(priceHistoryTimeRangeProvider.notifier).state = value;
            },
            itemBuilder: (context) => PriceHistoryTimeRange.values
                .map((range) => PopupMenuItem(
                      value: range,
                      child: Text(range.displayName),
                    ))
                .toList(),
          ),
          // 更多操作菜单
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多操作',
            onSelected: (value) async {
              if (value == 'clear') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('清除价格历史'),
                    content: const Text('确定要清除此商品的价格历史数据吗？清除后将从头开始记录。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await PriceHistoryService().clearPriceHistory(productId);
                  ref.invalidate(priceTrendAnalysisProvider(productInfo));
                  ref.invalidate(buyingTimeSuggestionProvider(productId));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('价格历史已清除')),
                    );
                  }
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 20),
                    SizedBox(width: 8),
                    Text('清除价格历史'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 商品信息卡片
            _buildProductInfoCard(context),
            
            const SizedBox(height: 16),

            // 价格趋势分析
            trendAnalysis.when(
              loading: () => _buildLoadingCard(context),
              error: (error, stack) => _buildErrorCard(context, error.toString()),
              data: (data) => _buildTrendAnalysisSection(context, data),
            ),

            const SizedBox(height: 16),

            // 购买时机建议
            buyingSuggestion.when(
              loading: () => const SizedBox.shrink(),
              error: (error, stack) => const SizedBox.shrink(),
              data: (data) => BuyingSuggestionCard(suggestion: data),
            ),

            const SizedBox(height: 16),

            // 价格历史详情
            trendAnalysis.when(
              loading: () => const SizedBox.shrink(),
              error: (error, stack) => const SizedBox.shrink(),
              data: (data) => _buildPriceHistoryDetail(context, data),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductInfoCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // 商品图片
            if (productImage != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  productImage!,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 60,
                    height: 60,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.image_not_supported),
                  ),
                ),
              )
            else
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.shopping_bag_outlined),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    productTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (currentPrice != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '当前价格: ¥${currentPrice!.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingCard(BuildContext context) {
    return Card(
      child: Container(
        height: 300,
        padding: const EdgeInsets.all(16),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, String message) {
    return Card(
      child: Container(
        height: 200,
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 8),
              Text(
                '加载失败',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                message,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrendAnalysisSection(BuildContext context, PriceTrendAnalysis data) {
    // 如果没有价格历史数据，显示提示信息
    if (data.priceHistory.isEmpty) {
      return _buildNoDataCard(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 价格统计面板
        _buildPriceStatsPanel(context, data),
        
        const SizedBox(height: 16),

        // 价格历史图表
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '价格趋势',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    PriceTrendIndicator(
                      trend: data.trend,
                      changePercent: data.priceChangePercent,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 250,
                  child: PriceHistoryChart(
                    data: data.priceHistory,
                    highlightPrice: data.averagePrice,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '橙色线为历史平均价格 ¥${data.averagePrice.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 当没有价格历史数据时显示的提示卡片
  Widget _buildNoDataCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Card(
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.timeline,
                    size: 48,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '暂无价格历史数据',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '该商品刚加入购物车，价格历史记录将从现在开始自动收集。\n\n系统会在每次价格更新时记录数据，帮助您追踪价格波动趋势，找到最佳购买时机。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '当前价格: ¥${currentPrice?.toStringAsFixed(2) ?? '--'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPriceStatsPanel(BuildContext context, PriceTrendAnalysis data) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 500;
        final itemWidth = isWide 
            ? (constraints.maxWidth - 32) / 4 
            : (constraints.maxWidth - 16) / 2;

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildStatItem(
              context,
              icon: Icons.attach_money,
              label: '当前价格',
              value: '¥${data.currentPrice.toStringAsFixed(2)}',
              color: Theme.of(context).colorScheme.primary,
              width: itemWidth,
            ),
            _buildStatItem(
              context,
              icon: Icons.arrow_downward,
              label: '历史最低',
              value: '¥${data.lowestPrice.toStringAsFixed(2)}',
              color: Colors.green,
              width: itemWidth,
              highlight: data.isAtLow,
            ),
            _buildStatItem(
              context,
              icon: Icons.arrow_upward,
              label: '历史最高',
              value: '¥${data.highestPrice.toStringAsFixed(2)}',
              color: Colors.red,
              width: itemWidth,
              highlight: data.isAtHigh,
            ),
            _buildStatItem(
              context,
              icon: Icons.analytics_outlined,
              label: '平均价格',
              value: '¥${data.averagePrice.toStringAsFixed(2)}',
              color: Colors.orange,
              width: itemWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required double width,
    bool highlight = false,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight 
            ? color.withValues(alpha: 0.1)
            : Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: highlight 
            ? Border.all(color: color.withValues(alpha: 0.3), width: 2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: highlight ? color : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceHistoryDetail(BuildContext context, PriceTrendAnalysis data) {
    if (data.priceHistory.isEmpty) {
      return const SizedBox.shrink();
    }

    // 只显示最近10条记录
    final recentRecords = data.priceHistory.length > 10
        ? data.priceHistory.sublist(data.priceHistory.length - 10)
        : data.priceHistory;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '价格变化记录',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '最近${recentRecords.length}条',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recentRecords.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final record = recentRecords[recentRecords.length - 1 - index];
                final prevRecord = index < recentRecords.length - 1
                    ? recentRecords[recentRecords.length - 2 - index]
                    : null;
                
                double? priceChange;
                if (prevRecord != null) {
                  priceChange = record.finalPrice - prevRecord.finalPrice;
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          _formatDate(record.recordedAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          '¥${record.finalPrice.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (priceChange != null)
                        Expanded(
                          flex: 1,
                          child: Text(
                            '${priceChange >= 0 ? '+' : ''}${priceChange.toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: priceChange > 0 
                                  ? Colors.red 
                                  : priceChange < 0 
                                      ? Colors.green 
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.end,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

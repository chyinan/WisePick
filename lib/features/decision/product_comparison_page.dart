import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'decision_models.dart';
import 'decision_providers.dart';

/// 商品对比页面
/// 
/// 展示多商品对比表格、购买建议评分和替代商品推荐
class ProductComparisonPage extends ConsumerWidget {
  const ProductComparisonPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comparisonAsync = ref.watch(productComparisonProvider);
    final comparisonList = ref.watch(comparisonListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('商品对比'),
        actions: [
          if (comparisonList.isNotEmpty)
            TextButton.icon(
              onPressed: () => clearComparisonList(ref),
              icon: const Icon(Icons.clear_all),
              label: const Text('清空'),
            ),
        ],
      ),
      body: comparisonList.isEmpty
          ? _buildEmptyState(context)
          : comparisonAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => _buildErrorState(context, error.toString()),
              data: (data) => data == null
                  ? _buildEmptyState(context)
                  : _buildComparisonContent(context, ref, data),
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.compare_arrows,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无对比商品',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '在商品详情页点击"加入对比"添加商品',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String message) {
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
        ],
      ),
    );
  }

  Widget _buildComparisonContent(BuildContext context, WidgetRef ref, ProductComparison data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 推荐商品卡片
          if (data.recommendedProduct != null)
            _buildRecommendationCard(context, data.recommendedProduct!),
          
          const SizedBox(height: 16),

          // 对比表格
          _buildComparisonTable(context, ref, data),

          const SizedBox(height: 16),

          // 评分详情
          _buildScoreDetails(context, data),
        ],
      ),
    );
  }

  Widget _buildRecommendationCard(BuildContext context, ComparisonProduct product) {
    final colorScheme = Theme.of(context).colorScheme;
    final score = product.decisionScore;

    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.recommend,
                  color: colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  '推荐购买',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${score.totalScore.toStringAsFixed(0)}分',
                    style: TextStyle(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (product.imageUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      product.imageUrl!,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 60,
                        height: 60,
                        color: colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.image_not_supported),
                      ),
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '¥${product.price.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              score.reasoning,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonTable(BuildContext context, WidgetRef ref, ProductComparison data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '对比详情',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final double totalWidth = constraints.maxWidth;
                final int productCount = data.products.length;
                const double dimensionColWidth = 80.0;
                const double columnSpacing = 20.0;
                const double horizontalMargin = 10.0;

                // 计算每个商品列的可用宽度
                // 公式: 总宽 = 2*边距 + 维度列宽 + N*商品列宽 + N*列间距
                double availableWidth = totalWidth -
                    (2 * horizontalMargin) -
                    dimensionColWidth -
                    (productCount * columnSpacing);
                double productColWidth = availableWidth / productCount;

                // 最小宽度限制
                if (productColWidth < 100.0) {
                  productColWidth = 100.0;
                }

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: totalWidth),
                    child: DataTable(
                      horizontalMargin: horizontalMargin,
                      columnSpacing: columnSpacing,
                      columns: [
                        DataColumn(
                          label: SizedBox(
                            width: dimensionColWidth,
                            child: const Text('维度',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        ...data.products.map((p) => DataColumn(
                              label: SizedBox(
                                width: productColWidth,
                                child: Stack(
                                  alignment: Alignment.center,
                                  clipBehavior: Clip.none,
                                  children: [
                                    Center(
                                      child: Text(
                                        p.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    Positioned(
                                      top: -8,
                                      right: 0,
                                      child: InkWell(
                                        child: IconButton(
                                          icon:
                                              const Icon(Icons.close, size: 16),
                                          onPressed: () =>
                                              removeFromComparisonList(
                                                  ref, p.id),
                                          splashRadius: 16,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )),
                      ],
                      rows: [
                        _buildDataRow(
                            '价格',
                            data.products
                                .map((p) => '¥${p.price.toStringAsFixed(2)}')
                                .toList(),
                            _findLowestPriceIndex(data.products),
                            cellWidth: productColWidth),
                        _buildDataRow(
                          'AI评分',
                          data.products.map((p) {
                            final score = p.decisionScore.ratingScore;
                            final percentage = (score / 25 * 100).clamp(0, 100);
                            return '${percentage.toStringAsFixed(0)}%';
                          }).toList(),
                          _findHighestRatingScoreIndex(data.products),
                          labelIcon: Icons.auto_awesome,
                          onLabelPressed: () =>
                              _showAiScoreExplanation(context),
                          cellWidth: productColWidth,
                        ),
                        _buildDataRow(
                            '销量',
                            data.products
                                .map((p) => _formatSales(p.sales))
                                .toList(),
                            _findHighestSalesIndex(data.products),
                            cellWidth: productColWidth),
                        _buildDataRow(
                            '综合评分',
                            data.products
                                .map((p) =>
                                    '${p.decisionScore.totalScore.toStringAsFixed(0)}分')
                                .toList(),
                            _findHighestScoreIndex(data.products),
                            cellWidth: productColWidth),
                        _buildDataRow(
                            '平台', data.products.map((p) => p.platform).toList(),
                            null,
                            cellWidth: productColWidth),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  DataRow _buildDataRow(
    String label,
    List<String> values,
    int? highlightIndex, {
    IconData? labelIcon,
    VoidCallback? onLabelPressed,
    double? cellWidth,
  }) {
    return DataRow(
      cells: [
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
              if (labelIcon != null) ...[
                const SizedBox(width: 4),
                InkWell(
                  onTap: onLabelPressed,
                  borderRadius: BorderRadius.circular(12),
                  child: Icon(labelIcon, size: 16, color: Colors.blue),
                ),
              ],
            ],
          ),
        ),
        ...values.asMap().entries.map((entry) => DataCell(
              Container(
                width: cellWidth,
                alignment: Alignment.center,
                child: Text(
                  entry.value,
                  style: TextStyle(
                    fontWeight:
                        entry.key == highlightIndex ? FontWeight.bold : null,
                    color: entry.key == highlightIndex ? Colors.green : null,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )),
      ],
    );
  }

  void _showAiScoreExplanation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.auto_awesome, color: Colors.blue),
            SizedBox(width: 8),
            Text('AI 评分说明'),
          ],
        ),
        content: const Text(
          'AI 评分是基于商品的用户评价、好评率等数据综合计算得出的分数。\n\n'
          '我们会综合分析评价数量、好评占比以及用户的详细评论内容（如果可用），'
          '为您提供一个更客观的评分参考，避免因单一好评率失真。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('了解了'),
          ),
        ],
      ),
    );
  }

  int? _findLowestPriceIndex(List<ComparisonProduct> products) {
    if (products.isEmpty) return null;
    int index = 0;
    double lowest = products[0].price;
    for (int i = 1; i < products.length; i++) {
      if (products[i].price < lowest) {
        lowest = products[i].price;
        index = i;
      }
    }
    return index;
  }

  int? _findHighestRatingIndex(List<ComparisonProduct> products) {
    if (products.isEmpty) return null;
    int index = 0;
    double highest = products[0].rating;
    for (int i = 1; i < products.length; i++) {
      if (products[i].rating > highest) {
        highest = products[i].rating;
        index = i;
      }
    }
    return index;
  }

  int? _findHighestRatingScoreIndex(List<ComparisonProduct> products) {
    if (products.isEmpty) return null;
    int index = 0;
    double highest = products[0].decisionScore.ratingScore;
    for (int i = 1; i < products.length; i++) {
      if (products[i].decisionScore.ratingScore > highest) {
        highest = products[i].decisionScore.ratingScore;
        index = i;
      }
    }
    return index;
  }

  int? _findHighestSalesIndex(List<ComparisonProduct> products) {
    if (products.isEmpty) return null;
    int index = 0;
    int highest = products[0].sales;
    for (int i = 1; i < products.length; i++) {
      if (products[i].sales > highest) {
        highest = products[i].sales;
        index = i;
      }
    }
    return index;
  }

  int? _findHighestScoreIndex(List<ComparisonProduct> products) {
    if (products.isEmpty) return null;
    int index = 0;
    double highest = products[0].decisionScore.totalScore;
    for (int i = 1; i < products.length; i++) {
      if (products[i].decisionScore.totalScore > highest) {
        highest = products[i].decisionScore.totalScore;
        index = i;
      }
    }
    return index;
  }

  String _formatSales(int sales) {
    if (sales >= 10000) {
      return '${(sales / 10000).toStringAsFixed(1)}万+';
    }
    return '$sales';
  }

  Widget _buildScoreDetails(BuildContext context, ProductComparison data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '评分详情',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            ...data.products.map((product) => _buildProductScoreCard(context, product)),
          ],
        ),
      ),
    );
  }

  Widget _buildProductScoreCard(BuildContext context, ComparisonProduct product) {
    final score = product.decisionScore;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  product.title,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _buildScoreBadge(context, score.level),
            ],
          ),
          const SizedBox(height: 12),
          ...score.details.map((detail) => _buildScoreBar(context, detail)),
          const SizedBox(height: 8),
          Text(
            score.reasoning,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreBadge(BuildContext context, ScoreLevel level) {
    Color color;
    switch (level) {
      case ScoreLevel.excellent:
        color = Colors.green;
        break;
      case ScoreLevel.good:
        color = Colors.blue;
        break;
      case ScoreLevel.average:
        color = Colors.orange;
        break;
      case ScoreLevel.belowAverage:
      case ScoreLevel.poor:
        color = Colors.red;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        level.displayName,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildScoreBar(BuildContext context, ScoreDetail detail) {
    final colorScheme = Theme.of(context).colorScheme;
    final percentage = detail.percentage;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              detail.dimension,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: percentage.clamp(0.0, 1.0),
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: _getScoreColor(percentage),
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
              '${detail.score.toStringAsFixed(0)}/${detail.maxScore.toStringAsFixed(0)}',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Color _getScoreColor(double percentage) {
    if (percentage >= 0.8) return Colors.green;
    if (percentage >= 0.6) return Colors.blue;
    if (percentage >= 0.4) return Colors.orange;
    return Colors.red;
  }
}

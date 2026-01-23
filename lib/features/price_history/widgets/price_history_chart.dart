import 'package:flutter/material.dart';
import '../price_history_model.dart';

/// 价格历史折线图组件
/// 
/// 展示商品价格随时间的变化趋势
class PriceHistoryChart extends StatelessWidget {
  final List<PriceHistoryRecord> data;
  final double? highlightPrice;
  final bool showGrid;
  final bool showLabels;
  final Color? lineColor;
  final Color? fillColor;

  const PriceHistoryChart({
    super.key,
    required this.data,
    this.highlightPrice,
    this.showGrid = true,
    this.showLabels = true,
    this.lineColor,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return _buildEmptyState(context);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _PriceChartPainter(
            data: data,
            highlightPrice: highlightPrice,
            showGrid: showGrid,
            showLabels: showLabels,
            lineColor: lineColor ?? Theme.of(context).colorScheme.primary,
            fillColor: fillColor ?? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            textColor: Theme.of(context).colorScheme.onSurfaceVariant,
            gridColor: Theme.of(context).colorScheme.outlineVariant,
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.show_chart,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 8),
          Text(
            '暂无价格历史数据',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceChartPainter extends CustomPainter {
  final List<PriceHistoryRecord> data;
  final double? highlightPrice;
  final bool showGrid;
  final bool showLabels;
  final Color lineColor;
  final Color fillColor;
  final Color textColor;
  final Color gridColor;

  _PriceChartPainter({
    required this.data,
    this.highlightPrice,
    required this.showGrid,
    required this.showLabels,
    required this.lineColor,
    required this.fillColor,
    required this.textColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    const leftPadding = 50.0;
    const rightPadding = 16.0;
    const topPadding = 16.0;
    const bottomPadding = 30.0;

    final chartWidth = size.width - leftPadding - rightPadding;
    final chartHeight = size.height - topPadding - bottomPadding;

    final prices = data.map((r) => r.finalPrice).toList();
    final minPrice = prices.reduce((a, b) => a < b ? a : b) * 0.95;
    final maxPrice = prices.reduce((a, b) => a > b ? a : b) * 1.05;
    final priceRange = maxPrice - minPrice;

    // 绘制网格
    if (showGrid) {
      _drawGrid(canvas, size, leftPadding, topPadding, chartWidth, chartHeight, minPrice, maxPrice);
    }

    // 绘制价格曲线
    _drawPriceLine(canvas, leftPadding, topPadding, chartWidth, chartHeight, minPrice, priceRange);

    // 绘制填充区域
    _drawFillArea(canvas, leftPadding, topPadding, chartWidth, chartHeight, minPrice, priceRange, size.height - bottomPadding);

    // 绘制高亮价格线
    if (highlightPrice != null && priceRange > 0) {
      _drawHighlightLine(canvas, leftPadding, topPadding, chartWidth, chartHeight, minPrice, priceRange, highlightPrice!);
    }

    // 绘制Y轴标签
    if (showLabels) {
      _drawYAxisLabels(canvas, leftPadding, topPadding, chartHeight, minPrice, maxPrice);
      _drawXAxisLabels(canvas, leftPadding, topPadding, chartWidth, chartHeight);
    }
  }

  void _drawGrid(Canvas canvas, Size size, double leftPadding, double topPadding, 
      double chartWidth, double chartHeight, double minPrice, double maxPrice) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    // 水平线
    for (int i = 0; i <= 4; i++) {
      final y = topPadding + (chartHeight / 4) * i;
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(leftPadding + chartWidth, y),
        gridPaint,
      );
    }

    // 垂直线
    final verticalCount = data.length > 7 ? 7 : data.length;
    for (int i = 0; i <= verticalCount; i++) {
      final x = leftPadding + (chartWidth / verticalCount) * i;
      canvas.drawLine(
        Offset(x, topPadding),
        Offset(x, topPadding + chartHeight),
        gridPaint,
      );
    }
  }

  void _drawPriceLine(Canvas canvas, double leftPadding, double topPadding,
      double chartWidth, double chartHeight, double minPrice, double priceRange) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    
    for (int i = 0; i < data.length; i++) {
      final x = leftPadding + (chartWidth / (data.length - 1)) * i;
      final normalizedPrice = priceRange > 0 
          ? (data[i].finalPrice - minPrice) / priceRange 
          : 0.5;
      final y = topPadding + chartHeight - (normalizedPrice * chartHeight);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, linePaint);

    // 绘制数据点
    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < data.length; i++) {
      final x = leftPadding + (chartWidth / (data.length - 1)) * i;
      final normalizedPrice = priceRange > 0 
          ? (data[i].finalPrice - minPrice) / priceRange 
          : 0.5;
      final y = topPadding + chartHeight - (normalizedPrice * chartHeight);

      // 只在数据点较少时绘制点
      if (data.length <= 30) {
        canvas.drawCircle(Offset(x, y), 3, dotPaint);
      }
    }
  }

  void _drawFillArea(Canvas canvas, double leftPadding, double topPadding,
      double chartWidth, double chartHeight, double minPrice, double priceRange, double bottom) {
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(leftPadding, bottom);

    for (int i = 0; i < data.length; i++) {
      final x = leftPadding + (chartWidth / (data.length - 1)) * i;
      final normalizedPrice = priceRange > 0 
          ? (data[i].finalPrice - minPrice) / priceRange 
          : 0.5;
      final y = topPadding + chartHeight - (normalizedPrice * chartHeight);
      path.lineTo(x, y);
    }

    path.lineTo(leftPadding + chartWidth, bottom);
    path.close();

    canvas.drawPath(path, fillPaint);
  }

  void _drawHighlightLine(Canvas canvas, double leftPadding, double topPadding,
      double chartWidth, double chartHeight, double minPrice, double priceRange, double price) {
    final normalizedPrice = (price - minPrice) / priceRange;
    final y = topPadding + chartHeight - (normalizedPrice * chartHeight);

    final highlightPaint = Paint()
      ..color = Colors.orange
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(leftPadding, y),
      Offset(leftPadding + chartWidth, y),
      highlightPaint,
    );
  }

  void _drawYAxisLabels(Canvas canvas, double leftPadding, double topPadding,
      double chartHeight, double minPrice, double maxPrice) {
    final textStyle = TextStyle(
      color: textColor,
      fontSize: 10,
    );

    for (int i = 0; i <= 4; i++) {
      final price = minPrice + ((maxPrice - minPrice) / 4) * (4 - i);
      final y = topPadding + (chartHeight / 4) * i;

      final textSpan = TextSpan(
        text: '¥${price.toStringAsFixed(0)}',
        style: textStyle,
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(leftPadding - textPainter.width - 4, y - textPainter.height / 2),
      );
    }
  }

  void _drawXAxisLabels(Canvas canvas, double leftPadding, double topPadding,
      double chartWidth, double chartHeight) {
    if (data.isEmpty) return;

    final textStyle = TextStyle(
      color: textColor,
      fontSize: 10,
    );

    // 只显示首尾和中间的日期
    final indices = [0, data.length ~/ 2, data.length - 1];
    
    for (final i in indices) {
      if (i >= data.length) continue;
      
      final x = leftPadding + (chartWidth / (data.length - 1)) * i;
      final date = data[i].recordedAt;
      final dateStr = '${date.month}/${date.day}';

      final textSpan = TextSpan(
        text: dateStr,
        style: textStyle,
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, topPadding + chartHeight + 8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PriceChartPainter oldDelegate) {
    return data != oldDelegate.data ||
        highlightPrice != oldDelegate.highlightPrice ||
        lineColor != oldDelegate.lineColor;
  }
}

/// 价格趋势指示器
class PriceTrendIndicator extends StatelessWidget {
  final PriceTrend trend;
  final double? changePercent;

  const PriceTrendIndicator({
    super.key,
    required this.trend,
    this.changePercent,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    Color backgroundColor;
    Color textColor;
    IconData icon;

    switch (trend) {
      case PriceTrend.rising:
        backgroundColor = Colors.red.shade50;
        textColor = Colors.red.shade700;
        icon = Icons.trending_up;
        break;
      case PriceTrend.falling:
        backgroundColor = Colors.green.shade50;
        textColor = Colors.green.shade700;
        icon = Icons.trending_down;
        break;
      case PriceTrend.stable:
        backgroundColor = colorScheme.surfaceContainerHighest;
        textColor = colorScheme.onSurfaceVariant;
        icon = Icons.trending_flat;
        break;
      case PriceTrend.volatile:
        backgroundColor = Colors.orange.shade50;
        textColor = Colors.orange.shade700;
        icon = Icons.show_chart;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 4),
          Text(
            trend.displayName,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (changePercent != null) ...[
            const SizedBox(width: 4),
            Text(
              '${changePercent! >= 0 ? '+' : ''}${changePercent!.toStringAsFixed(1)}%',
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 购买建议卡片
class BuyingSuggestionCard extends StatelessWidget {
  final BuyingTimeSuggestion suggestion;

  const BuyingSuggestionCard({
    super.key,
    required this.suggestion,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    Color backgroundColor;
    Color borderColor;
    IconData icon;

    switch (suggestion.type) {
      case BuyingSuggestionType.buyNow:
        backgroundColor = Colors.green.shade50;
        borderColor = Colors.green.shade200;
        icon = Icons.check_circle_outline;
        break;
      case BuyingSuggestionType.wait:
        backgroundColor = Colors.orange.shade50;
        borderColor = Colors.orange.shade200;
        icon = Icons.schedule;
        break;
      case BuyingSuggestionType.observe:
        backgroundColor = colorScheme.surfaceContainerHighest;
        borderColor = colorScheme.outlineVariant;
        icon = Icons.visibility_outlined;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 24, color: borderColor),
              const SizedBox(width: 8),
              Text(
                suggestion.type.displayName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _buildConfidenceBadge(context, suggestion.confidence),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            suggestion.reason,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (suggestion.predictedPrice != null) ...[
            const SizedBox(height: 8),
            Text(
              '预计合理价格: ¥${suggestion.predictedPrice!.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConfidenceBadge(BuildContext context, double confidence) {
    final percent = (confidence * 100).toInt();
    Color color;
    
    if (confidence >= 0.8) {
      color = Colors.green;
    } else if (confidence >= 0.5) {
      color = Colors.orange;
    } else {
      color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '置信度 $percent%',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

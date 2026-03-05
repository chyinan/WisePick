import 'package:flutter/material.dart';

/// 显示当前价格与加入购物车时价格的差异标签
class PriceDiffLabel extends StatelessWidget {
  final double? initialCartPrice;
  final double? currentPrice;
  final bool hasCartRecord;

  const PriceDiffLabel({
    super.key,
    required this.hasCartRecord,
    required this.initialCartPrice,
    required this.currentPrice,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasCartRecord || initialCartPrice == null || currentPrice == null) {
      return const SizedBox.shrink();
    }
    if (initialCartPrice! < 0.01 || currentPrice! < 0.01) {
      return const SizedBox.shrink();
    }
    final delta = currentPrice! - initialCartPrice!;
    if (delta.abs() < 0.01) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '与加入购物车时价格一致',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    final bool cheaper = delta < 0;
    final text = cheaper
        ? '该商品比加入购物车时降价¥${delta.abs().toStringAsFixed(2)}'
        : '该商品比加入购物车时涨价¥${delta.abs().toStringAsFixed(2)}';
    final color = cheaper ? Colors.green : Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}

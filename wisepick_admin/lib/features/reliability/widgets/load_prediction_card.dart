import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

/// 负载预测卡片
class LoadPredictionCard extends StatelessWidget {
  final Map<String, dynamic> prediction;
  final VoidCallback? onRefresh;

  const LoadPredictionCard({
    super.key,
    required this.prediction,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final predictedLoad = (prediction['predictedLoad'] as num?)?.toDouble() ?? 0;
    final confidence = (prediction['confidence'] as num?)?.toDouble() ?? 0;
    final bounds = prediction['bounds'] as Map<String, dynamic>? ?? {};
    final trend = prediction['trend'] as Map<String, dynamic>? ?? {};
    final recommendedAction = prediction['recommendedAction'] as String? ?? 'none';
    final predictedTime = DateTime.tryParse(prediction['predictedTime'] ?? '');

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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.insights,
                      color: Color(0xFF8B5CF6),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '负载预测',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              if (onRefresh != null)
                IconButton(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: '刷新预测',
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildLoadGauge(predictedLoad),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildPredictionDetails(
                  predictedLoad: predictedLoad,
                  confidence: confidence,
                  bounds: bounds,
                  trend: trend,
                  predictedTime: predictedTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildRecommendation(recommendedAction, predictedLoad),
        ],
      ),
    );
  }

  Widget _buildLoadGauge(double load) {
    // 确保负载值在有效范围内，防止绘制异常
    final safeLoad = load.clamp(0.0, 1.0);
    final color = _getLoadColor(safeLoad);
    
    return Column(
      children: [
        SizedBox(
          width: 140,
          height: 140,
          child: CustomPaint(
            painter: _LoadGaugePainter(
              load: safeLoad,
              color: color,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(safeLoad * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    '预测负载',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _getLoadLabel(safeLoad),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPredictionDetails({
    required double predictedLoad,
    required double confidence,
    required Map<String, dynamic> bounds,
    required Map<String, dynamic> trend,
    DateTime? predictedTime,
  }) {
    final lowerBound = (bounds['lower'] as num?)?.toDouble() ?? 0;
    final upperBound = (bounds['upper'] as num?)?.toDouble() ?? 0;
    final direction = trend['direction'] as String? ?? 'stable';
    final slope = (trend['slope'] as num?)?.toDouble() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDetailRow(
          icon: Icons.schedule,
          label: '预测时间',
          value: predictedTime != null
              ? DateFormat('HH:mm').format(predictedTime)
              : '--:--',
        ),
        const SizedBox(height: 12),
        _buildDetailRow(
          icon: Icons.verified,
          label: '置信度',
          value: '${(confidence * 100).toStringAsFixed(0)}%',
          valueColor: confidence >= 0.8 ? Colors.green : Colors.orange,
        ),
        const SizedBox(height: 12),
        _buildDetailRow(
          icon: Icons.swap_vert,
          label: '预测范围',
          value: '${(lowerBound * 100).toStringAsFixed(0)}% - ${(upperBound * 100).toStringAsFixed(0)}%',
        ),
        const SizedBox(height: 12),
        _buildDetailRow(
          icon: _getTrendIcon(direction),
          label: '趋势',
          value: '${_getTrendLabel(direction)} (${slope >= 0 ? '+' : ''}${(slope * 100).toStringAsFixed(1)}%/min)',
          valueColor: _getTrendColor(direction),
        ),
      ],
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[400]),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor ?? const Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendation(String action, double load) {
    if (action == 'none') {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 20,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                '系统负载正常，无需采取行动',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.green,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final recommendation = _getRecommendation(action);
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: recommendation.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: recommendation.color.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: recommendation.color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              recommendation.icon,
              color: recommendation.color,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '建议: ${recommendation.title}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: recommendation.color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  recommendation.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getLoadColor(double load) {
    if (load >= 0.9) return const Color(0xFFEF4444);
    if (load >= 0.8) return const Color(0xFFF97316);
    if (load >= 0.7) return const Color(0xFFF59E0B);
    if (load >= 0.5) return const Color(0xFF3B82F6);
    return const Color(0xFF10B981);
  }

  String _getLoadLabel(double load) {
    if (load >= 0.9) return '严重过载';
    if (load >= 0.8) return '高负载';
    if (load >= 0.7) return '中高负载';
    if (load >= 0.5) return '中等负载';
    if (load >= 0.3) return '低负载';
    return '空闲';
  }

  IconData _getTrendIcon(String direction) {
    switch (direction.toLowerCase()) {
      case 'increasing':
        return Icons.trending_up;
      case 'decreasing':
        return Icons.trending_down;
      default:
        return Icons.trending_flat;
    }
  }

  String _getTrendLabel(String direction) {
    switch (direction.toLowerCase()) {
      case 'increasing':
        return '上升';
      case 'decreasing':
        return '下降';
      default:
        return '稳定';
    }
  }

  Color _getTrendColor(String direction) {
    switch (direction.toLowerCase()) {
      case 'increasing':
        return Colors.orange;
      case 'decreasing':
        return Colors.green;
      default:
        return Colors.blue;
    }
  }

  _Recommendation _getRecommendation(String action) {
    switch (action.toLowerCase()) {
      case 'emergencybrake':
        return _Recommendation(
          title: '紧急制动',
          description: '立即启用紧急限流，拒绝新请求以保护系统',
          icon: Icons.emergency,
          color: Colors.red,
        );
      case 'shedload':
        return _Recommendation(
          title: '负载卸载',
          description: '开始拒绝低优先级请求，保护核心功能',
          icon: Icons.remove_circle_outline,
          color: Colors.orange,
        );
      case 'enablethrottling':
        return _Recommendation(
          title: '启用限流',
          description: '启用请求限流以控制流量增长',
          icon: Icons.speed,
          color: Colors.amber,
        );
      case 'prewarm':
        return _Recommendation(
          title: '预热资源',
          description: '预测流量增长，建议提前预热缓存和连接池',
          icon: Icons.whatshot,
          color: Colors.blue,
        );
      default:
        return _Recommendation(
          title: '监控',
          description: '继续监控系统状态',
          icon: Icons.visibility,
          color: Colors.grey,
        );
    }
  }
}

class _Recommendation {
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  _Recommendation({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}

class _LoadGaugePainter extends CustomPainter {
  final double load;
  final Color color;

  _LoadGaugePainter({required this.load, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;

    // 背景圆弧
    final bgPaint = Paint()
      ..color = Colors.grey.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi * 0.75,
      math.pi * 1.5,
      false,
      bgPaint,
    );

    // 负载圆弧
    final loadPaint = Paint()
      ..shader = SweepGradient(
        startAngle: -math.pi * 0.75,
        endAngle: math.pi * 0.75,
        colors: [
          const Color(0xFF10B981),
          const Color(0xFFF59E0B),
          const Color(0xFFEF4444),
        ],
        stops: const [0.0, 0.5, 1.0],
        transform: GradientRotation(-math.pi * 0.75),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    final sweepAngle = load * math.pi * 1.5;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi * 0.75,
      sweepAngle,
      false,
      loadPaint,
    );

    // 指示点
    final indicatorAngle = -math.pi * 0.75 + sweepAngle;
    final indicatorPos = Offset(
      center.dx + radius * math.cos(indicatorAngle),
      center.dy + radius * math.sin(indicatorAngle),
    );

    final indicatorPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(indicatorPos, 8, indicatorPaint);

    final indicatorBorderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(indicatorPos, 8, indicatorBorderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

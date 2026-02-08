import 'package:flutter/material.dart';
import 'dart:math' as math;

/// 健康评分卡片组件
class HealthScoreCard extends StatelessWidget {
  final double score;
  final String grade;
  final int healthyServices;
  final int degradedServices;
  final int unhealthyServices;
  final List<String> criticalIssues;
  final List<String> warnings;
  final VoidCallback? onRefresh;

  const HealthScoreCard({
    super.key,
    required this.score,
    required this.grade,
    required this.healthyServices,
    required this.degradedServices,
    required this.unhealthyServices,
    this.criticalIssues = const [],
    this.warnings = const [],
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _getGradeColor(grade),
            _getGradeColor(grade).withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _getGradeColor(grade).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '系统健康度',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        score.clamp(0.0, 100.0).toStringAsFixed(0),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8, left: 4),
                        child: Text(
                          '/100',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              _buildScoreGauge(),
            ],
          ),
          const SizedBox(height: 20),
          _buildGradeBadge(),
          const SizedBox(height: 20),
          _buildServiceStats(),
          if (criticalIssues.isNotEmpty || warnings.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildIssuesList(),
          ],
        ],
      ),
    );
  }

  Widget _buildScoreGauge() {
    // 确保分数在有效范围内，防止绘制异常
    final safeScore = score.clamp(0.0, 100.0);
    
    return SizedBox(
      width: 100,
      height: 100,
      child: CustomPaint(
        painter: _ScoreGaugePainter(
          score: safeScore,
          color: Colors.white,
        ),
        child: Center(
          child: Icon(
            _getGradeIcon(grade),
            color: Colors.white,
            size: 32,
          ),
        ),
      ),
    );
  }

  Widget _buildGradeBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getGradeIcon(grade),
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            _getGradeLabel(grade),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceStats() {
    return Row(
      children: [
        _buildStatItem(
          icon: Icons.check_circle_outline,
          label: '健康',
          value: healthyServices.toString(),
          color: Colors.white,
        ),
        const SizedBox(width: 24),
        _buildStatItem(
          icon: Icons.warning_amber_outlined,
          label: '降级',
          value: degradedServices.toString(),
          color: Colors.amber[200]!,
        ),
        const SizedBox(width: 24),
        _buildStatItem(
          icon: Icons.error_outline,
          label: '异常',
          value: unhealthyServices.toString(),
          color: Colors.red[200]!,
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: color.withOpacity(0.8),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIssuesList() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (criticalIssues.isNotEmpty) ...[
            ...criticalIssues.take(2).map((issue) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.error, color: Colors.red[200], size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      issue,
                      style: TextStyle(color: Colors.red[200], fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            )),
          ],
          if (warnings.isNotEmpty) ...[
            ...warnings.take(2).map((warning) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.amber[200], size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      warning,
                      style: TextStyle(color: Colors.amber[200], fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }

  Color _getGradeColor(String grade) {
    switch (grade.toLowerCase()) {
      case 'excellent':
        return const Color(0xFF10B981);
      case 'good':
        return const Color(0xFF3B82F6);
      case 'fair':
        return const Color(0xFFF59E0B);
      case 'poor':
        return const Color(0xFFF97316);
      case 'critical':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData _getGradeIcon(String grade) {
    switch (grade.toLowerCase()) {
      case 'excellent':
        return Icons.verified;
      case 'good':
        return Icons.thumb_up;
      case 'fair':
        return Icons.trending_flat;
      case 'poor':
        return Icons.trending_down;
      case 'critical':
        return Icons.dangerous;
      default:
        return Icons.help_outline;
    }
  }

  String _getGradeLabel(String grade) {
    switch (grade.toLowerCase()) {
      case 'excellent':
        return '优秀 - 系统运行良好';
      case 'good':
        return '良好 - 轻微问题';
      case 'fair':
        return '一般 - 需要关注';
      case 'poor':
        return '较差 - 需要处理';
      case 'critical':
        return '严重 - 立即处理';
      default:
        return '未知状态';
    }
  }
}

class _ScoreGaugePainter extends CustomPainter {
  final double score;
  final Color color;

  _ScoreGaugePainter({required this.score, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    // 背景圆弧
    final bgPaint = Paint()
      ..color = color.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi * 0.75,
      math.pi * 1.5,
      false,
      bgPaint,
    );

    // 分数圆弧
    final scorePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    final sweepAngle = (score / 100) * math.pi * 1.5;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi * 0.75,
      sweepAngle,
      false,
      scorePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

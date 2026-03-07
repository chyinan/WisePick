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
    final safeScore = score.clamp(0.0, 100.0);
    final accentColor = _getGradeColor(grade);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E8E8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部：评分 + 仪表盘
          Row(
            children: [
              // 左侧：分数和等级
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '系统健康度',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          safeScore.toStringAsFixed(0),
                          style: TextStyle(
                            color: Colors.grey[850],
                            fontSize: 42,
                            fontWeight: FontWeight.bold,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '/100',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildGradeBadge(accentColor),
                  ],
                ),
              ),
              // 右侧：仪表盘
              SizedBox(
                width: 72,
                height: 72,
                child: CustomPaint(
                  painter: _ScoreGaugePainter(
                    score: safeScore,
                    activeColor: accentColor,
                    bgColor: Colors.grey[200]!,
                  ),
                  child: Center(
                    child: Icon(
                      _getGradeIcon(grade),
                      color: accentColor,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // 服务状态
          _buildServiceStats(),
          // 问题列表
          if (criticalIssues.isNotEmpty || warnings.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildIssuesList(),
          ],
        ],
      ),
    );
  }

  Widget _buildGradeBadge(Color accentColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accentColor.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_getGradeIcon(grade), color: accentColor, size: 14),
          const SizedBox(width: 6),
          Text(
            _getGradeLabel(grade),
            style: TextStyle(
              color: accentColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceStats() {
    final total = healthyServices + degradedServices + unhealthyServices;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _buildStatChip('健康', healthyServices, const Color(0xFF4CAF50),
              Icons.check_circle_rounded),
          const SizedBox(width: 12),
          _buildStatChip('降级', degradedServices, const Color(0xFFFF9800),
              Icons.warning_amber_rounded),
          const SizedBox(width: 12),
          _buildStatChip('异常', unhealthyServices, const Color(0xFFF44336),
              Icons.error_outline_rounded),
          const Spacer(),
          if (total > 0)
            SizedBox(
              width: 80,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$healthyServices/$total',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 4,
                      child: Row(
                        children: [
                          if (healthyServices > 0)
                            Expanded(
                              flex: healthyServices,
                              child: Container(color: const Color(0xFF4CAF50)),
                            ),
                          if (degradedServices > 0)
                            Expanded(
                              flex: degradedServices,
                              child: Container(color: const Color(0xFFFF9800)),
                            ),
                          if (unhealthyServices > 0)
                            Expanded(
                              flex: unhealthyServices,
                              child: Container(color: const Color(0xFFF44336)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, int value, Color color, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Text(
          '$value',
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      ],
    );
  }

  Widget _buildIssuesList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (criticalIssues.isNotEmpty)
          ...criticalIssues.take(2).map((issue) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Color(0xFFF44336), size: 15),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        issue,
                        style: const TextStyle(
                            color: Color(0xFFF44336), fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )),
        if (warnings.isNotEmpty)
          ...warnings.take(2).map((warning) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFFF9800), size: 15),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        warning,
                        style: const TextStyle(
                            color: Color(0xFFFF9800), fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  Color _getGradeColor(String grade) {
    return switch (grade.toLowerCase()) {
      'excellent' => const Color(0xFF10B981),
      'good' => const Color(0xFF3B82F6),
      'fair' => const Color(0xFFF59E0B),
      'poor' => const Color(0xFFF97316),
      'critical' => const Color(0xFFEF4444),
      _ => const Color(0xFF6B7280),
    };
  }

  IconData _getGradeIcon(String grade) {
    return switch (grade.toLowerCase()) {
      'excellent' => Icons.verified_rounded,
      'good' => Icons.thumb_up_rounded,
      'fair' => Icons.trending_flat_rounded,
      'poor' => Icons.trending_down_rounded,
      'critical' => Icons.dangerous_rounded,
      _ => Icons.help_outline_rounded,
    };
  }

  String _getGradeLabel(String grade) {
    return switch (grade.toLowerCase()) {
      'excellent' => '优秀 · 系统运行良好',
      'good' => '良好 · 轻微问题',
      'fair' => '一般 · 需要关注',
      'poor' => '较差 · 需要处理',
      'critical' => '严重 · 立即处理',
      _ => '未知状态',
    };
  }
}

class _ScoreGaugePainter extends CustomPainter {
  final double score;
  final Color activeColor;
  final Color bgColor;

  _ScoreGaugePainter({
    required this.score,
    required this.activeColor,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;

    final bgPaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi * 0.75,
      math.pi * 1.5,
      false,
      bgPaint,
    );

    final scorePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
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
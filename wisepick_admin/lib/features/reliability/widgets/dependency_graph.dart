import 'package:flutter/material.dart';
import 'dart:math' as math;

/// 服务依赖图组件
class DependencyGraph extends StatefulWidget {
  final Map<String, dynamic> graphData;
  final Function(String)? onNodeTap;

  const DependencyGraph({
    super.key,
    required this.graphData,
    this.onNodeTap,
  });

  @override
  State<DependencyGraph> createState() => _DependencyGraphState();
}

class _DependencyGraphState extends State<DependencyGraph> {
  String? _hoveredNode;
  String? _selectedNode;
  Offset _offset = Offset.zero;
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
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
              const Text(
                '服务依赖图',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              Row(
                children: [
                  _buildLegendItem('健康', const Color(0xFF10B981)),
                  const SizedBox(width: 16),
                  _buildLegendItem('降级', const Color(0xFFF59E0B)),
                  const SizedBox(width: 16),
                  _buildLegendItem('异常', const Color(0xFFEF4444)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: GestureDetector(
                  onScaleUpdate: (details) {
                    setState(() {
                      _scale = (_scale * details.scale).clamp(0.5, 2.0);
                      _offset += details.focalPointDelta;
                    });
                  },
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return CustomPaint(
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                        painter: _DependencyGraphPainter(
                          graphData: widget.graphData,
                          offset: _offset,
                          scale: _scale,
                          hoveredNode: _hoveredNode,
                          selectedNode: _selectedNode,
                        ),
                        child: _buildInteractiveLayer(constraints),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          if (_selectedNode != null) ...[
            const SizedBox(height: 12),
            _buildNodeDetails(),
          ],
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildInteractiveLayer(BoxConstraints constraints) {
    final nodes = widget.graphData['nodes'] as List? ?? [];
    
    // 安全处理空节点列表
    if (nodes.isEmpty) {
      return const SizedBox.shrink();
    }
    
    final positions = _calculateNodePositions(
      nodes.length,
      Size(constraints.maxWidth, constraints.maxHeight),
    );

    return Stack(
      children: [
        for (int i = 0; i < nodes.length; i++)
          if (i < positions.length && nodes[i] is Map<String, dynamic>)
            Positioned(
              left: (positions[i].dx + _offset.dx) * _scale - 30,
              top: (positions[i].dy + _offset.dy) * _scale - 30,
              child: GestureDetector(
                onTap: () {
                  final nodeId = (nodes[i] as Map<String, dynamic>)['id'] as String?;
                  setState(() {
                    _selectedNode = _selectedNode == nodeId ? null : nodeId;
                  });
                  if (nodeId != null) {
                    widget.onNodeTap?.call(nodeId);
                  }
                },
                child: MouseRegion(
                  onEnter: (_) {
                    setState(() {
                      _hoveredNode = (nodes[i] as Map<String, dynamic>)['id'] as String?;
                    });
                  },
                  onExit: (_) {
                    setState(() {
                      _hoveredNode = null;
                    });
                  },
                  child: Container(
                    width: 60 * _scale,
                    height: 60 * _scale,
                    color: Colors.transparent,
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildNodeDetails() {
    final nodes = widget.graphData['nodes'] as List? ?? [];
    
    // 安全查找节点
    Map<String, dynamic>? node;
    for (final n in nodes) {
      if (n is Map<String, dynamic> && n['id'] == _selectedNode) {
        node = n;
        break;
      }
    }

    if (node == null) return const SizedBox.shrink();

    final metrics = node['metrics'] as Map<String, dynamic>? ?? {};
    // 修复运算符优先级 bug: 先计算 errorRate，再乘以 100
    final errorRate = (metrics['errorRate'] as num?)?.toDouble() ?? 0;
    final errorRatePercent = (errorRate * 100).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _getStatusColor(node['status'] as String? ?? 'unknown'),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatNodeName(node['label'] as String? ?? node['id'] as String? ?? ''),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '状态: ${_getStatusLabel(node['status'] as String? ?? 'unknown')}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          _buildMetricChip(
            '错误率',
            '$errorRatePercent%',
          ),
          const SizedBox(width: 12),
          _buildMetricChip(
            '延迟',
            '${(metrics['latencyMs'] as num?)?.toStringAsFixed(0) ?? '0'}ms',
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  List<Offset> _calculateNodePositions(int nodeCount, Size size) {
    final positions = <Offset>[];
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final radius = math.min(size.width, size.height) * 0.35;

    for (int i = 0; i < nodeCount; i++) {
      final angle = (2 * math.pi * i / nodeCount) - math.pi / 2;
      positions.add(Offset(
        centerX + radius * math.cos(angle),
        centerY + radius * math.sin(angle),
      ));
    }

    return positions;
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'healthy':
        return const Color(0xFF10B981);
      case 'degraded':
        return const Color(0xFFF59E0B);
      case 'unhealthy':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF6B7280);
    }
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'healthy':
        return '健康';
      case 'degraded':
        return '降级';
      case 'unhealthy':
        return '异常';
      default:
        return '未知';
    }
  }

  String _formatNodeName(String name) {
    return name
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1)}'
            : '')
        .join(' ');
  }
}

class _DependencyGraphPainter extends CustomPainter {
  final Map<String, dynamic> graphData;
  final Offset offset;
  final double scale;
  final String? hoveredNode;
  final String? selectedNode;

  _DependencyGraphPainter({
    required this.graphData,
    required this.offset,
    required this.scale,
    this.hoveredNode,
    this.selectedNode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final nodes = graphData['nodes'] as List? ?? [];
    final edges = graphData['edges'] as List? ?? [];

    if (nodes.isEmpty) return;

    final positions = _calculateNodePositions(nodes.length, size);
    final nodeIdToIndex = <String, int>{};
    for (int i = 0; i < nodes.length; i++) {
      final nodeId = nodes[i]['id'] as String?;
      if (nodeId != null) {
        nodeIdToIndex[nodeId] = i;
      }
    }

    // 绘制边
    for (final edge in edges) {
      final sourceId = edge['source'] as String?;
      final targetId = edge['target'] as String?;
      if (sourceId == null || targetId == null) continue;

      final sourceIndex = nodeIdToIndex[sourceId];
      final targetIndex = nodeIdToIndex[targetId];
      if (sourceIndex == null || targetIndex == null) continue;

      final start = (positions[sourceIndex] + offset) * scale;
      final end = (positions[targetIndex] + offset) * scale;

      final isHighlighted = sourceId == selectedNode || 
                           targetId == selectedNode ||
                           sourceId == hoveredNode ||
                           targetId == hoveredNode;

      final edgePaint = Paint()
        ..color = isHighlighted 
            ? const Color(0xFF6366F1).withOpacity(0.8)
            : Colors.grey.withOpacity(0.3)
        ..strokeWidth = isHighlighted ? 2.5 : 1.5
        ..style = PaintingStyle.stroke;

      // 绘制带箭头的线
      _drawArrowLine(canvas, start, end, edgePaint);
    }

    // 绘制节点
    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node is! Map<String, dynamic>) continue;
      
      final position = (positions[i] + offset) * scale;
      final nodeId = node['id'] as String?;
      final status = node['status'] as String? ?? 'unknown';
      final label = node['label'] as String? ?? nodeId ?? '';

      final isHovered = nodeId == hoveredNode;
      final isSelected = nodeId == selectedNode;

      _drawNode(
        canvas,
        position,
        label,
        status,
        isHovered: isHovered,
        isSelected: isSelected,
      );
    }
  }

  void _drawArrowLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    // 计算方向
    final direction = (end - start);
    final length = direction.distance;
    if (length == 0) return;

    final normalized = direction / length;
    
    // 调整起点和终点以避开节点
    final nodeRadius = 25.0 * scale;
    final adjustedStart = start + normalized * nodeRadius;
    final adjustedEnd = end - normalized * nodeRadius;

    // 绘制线
    canvas.drawLine(adjustedStart, adjustedEnd, paint);

    // 绘制箭头
    final arrowSize = 8.0 * scale;
    final arrowAngle = math.pi / 6;
    
    final arrowPoint1 = adjustedEnd - Offset(
      normalized.dx * arrowSize * math.cos(arrowAngle) - 
          normalized.dy * arrowSize * math.sin(arrowAngle),
      normalized.dy * arrowSize * math.cos(arrowAngle) + 
          normalized.dx * arrowSize * math.sin(arrowAngle),
    );
    
    final arrowPoint2 = adjustedEnd - Offset(
      normalized.dx * arrowSize * math.cos(-arrowAngle) - 
          normalized.dy * arrowSize * math.sin(-arrowAngle),
      normalized.dy * arrowSize * math.cos(-arrowAngle) + 
          normalized.dx * arrowSize * math.sin(-arrowAngle),
    );

    final arrowPath = Path()
      ..moveTo(adjustedEnd.dx, adjustedEnd.dy)
      ..lineTo(arrowPoint1.dx, arrowPoint1.dy)
      ..lineTo(arrowPoint2.dx, arrowPoint2.dy)
      ..close();

    canvas.drawPath(arrowPath, paint..style = PaintingStyle.fill);
  }

  void _drawNode(
    Canvas canvas,
    Offset position,
    String label,
    String status, {
    bool isHovered = false,
    bool isSelected = false,
  }) {
    final radius = (isHovered || isSelected ? 28.0 : 25.0) * scale;
    final color = _getStatusColor(status);

    // 绘制阴影
    if (isHovered || isSelected) {
      final shadowPaint = Paint()
        ..color = color.withOpacity(0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * scale);
      canvas.drawCircle(position, radius + 5, shadowPaint);
    }

    // 绘制外圈
    final outerPaint = Paint()
      ..color = isSelected ? const Color(0xFF6366F1) : color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (isSelected ? 3 : 2) * scale;
    canvas.drawCircle(position, radius, outerPaint);

    // 绘制内圈
    final innerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(position, radius - 2 * scale, innerPaint);

    // 绘制状态指示点
    final statusPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(position, 6 * scale, statusPaint);

    // 绘制标签
    final textPainter = TextPainter(
      text: TextSpan(
        text: _formatLabel(label),
        style: TextStyle(
          color: const Color(0xFF1E293B),
          fontSize: 10 * scale,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: 80 * scale);
    textPainter.paint(
      canvas,
      Offset(
        position.dx - textPainter.width / 2,
        position.dy + radius + 8 * scale,
      ),
    );
  }

  List<Offset> _calculateNodePositions(int nodeCount, Size size) {
    final positions = <Offset>[];
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final radius = math.min(size.width, size.height) * 0.35;

    for (int i = 0; i < nodeCount; i++) {
      final angle = (2 * math.pi * i / nodeCount) - math.pi / 2;
      positions.add(Offset(
        centerX + radius * math.cos(angle),
        centerY + radius * math.sin(angle),
      ));
    }

    return positions;
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'healthy':
        return const Color(0xFF10B981);
      case 'degraded':
        return const Color(0xFFF59E0B);
      case 'unhealthy':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF6B7280);
    }
  }

  String _formatLabel(String label) {
    final parts = label.replaceAll('_', ' ').split(' ');
    if (parts.length > 2) {
      return '${parts[0]}\n${parts.sublist(1).join(' ')}';
    }
    return label.replaceAll('_', '\n');
  }

  @override
  bool shouldRepaint(covariant _DependencyGraphPainter oldDelegate) {
    return oldDelegate.graphData != graphData ||
           oldDelegate.offset != offset ||
           oldDelegate.scale != scale ||
           oldDelegate.hoveredNode != hoveredNode ||
           oldDelegate.selectedNode != selectedNode;
  }
}

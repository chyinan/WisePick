import 'package:flutter/material.dart';

/// 服务状态卡片
class ServiceCard extends StatelessWidget {
  final String name;
  final String status;
  final double successRate;
  final double avgLatencyMs;
  final double p99LatencyMs;
  final int requestsPerMinute;
  final String circuitBreakerState;
  final String degradationLevel;
  final Map<String, dynamic>? sloStatus;
  final VoidCallback? onTap;

  const ServiceCard({
    super.key,
    required this.name,
    required this.status,
    required this.successRate,
    required this.avgLatencyMs,
    required this.p99LatencyMs,
    required this.requestsPerMinute,
    required this.circuitBreakerState,
    required this.degradationLevel,
    this.sloStatus,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _getStatusColor(status).withOpacity(0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildMetrics(),
              const SizedBox(height: 12),
              _buildStatusBadges(),
              if (sloStatus != null) ...[
                const SizedBox(height: 12),
                _buildSloStatus(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: _getStatusColor(status),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _getStatusColor(status).withOpacity(0.4),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _formatServiceName(name),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
        ),
        _buildStatusChip(),
      ],
    );
  }

  Widget _buildStatusChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _getStatusColor(status).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _getStatusLabel(status),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _getStatusColor(status),
        ),
      ),
    );
  }

  Widget _buildMetrics() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricItem(
            icon: Icons.check_circle_outline,
            label: '成功率',
            value: '${(successRate * 100).toStringAsFixed(1)}%',
            color: successRate >= 0.99 ? Colors.green : Colors.orange,
          ),
        ),
        Expanded(
          child: _buildMetricItem(
            icon: Icons.speed,
            label: '平均延迟',
            value: '${avgLatencyMs.toStringAsFixed(0)}ms',
            color: avgLatencyMs < 200 ? Colors.green : Colors.orange,
          ),
        ),
        Expanded(
          child: _buildMetricItem(
            icon: Icons.trending_up,
            label: 'P99延迟',
            value: '${p99LatencyMs.toStringAsFixed(0)}ms',
            color: p99LatencyMs < 500 ? Colors.green : Colors.orange,
          ),
        ),
        Expanded(
          child: _buildMetricItem(
            icon: Icons.data_usage,
            label: 'RPM',
            value: requestsPerMinute.toString(),
            color: Colors.blue,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color.withOpacity(0.7)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
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
    );
  }

  Widget _buildStatusBadges() {
    return Row(
      children: [
        _buildBadge(
          icon: _getCircuitBreakerIcon(circuitBreakerState),
          label: '断路器: ${_getCircuitBreakerLabel(circuitBreakerState)}',
          color: _getCircuitBreakerColor(circuitBreakerState),
        ),
        const SizedBox(width: 8),
        _buildBadge(
          icon: Icons.shield_outlined,
          label: _getDegradationLabel(degradationLevel),
          color: _getDegradationColor(degradationLevel),
        ),
      ],
    );
  }

  Widget _buildBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSloStatus() {
    final availability = sloStatus?['availability'] as Map<String, dynamic>?;
    final latency = sloStatus?['latency'] as Map<String, dynamic>?;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSloItem(
              label: 'SLO 可用性',
              target: availability?['target'] ?? 0.999,
              current: availability?['current'] ?? 0,
              met: availability?['met'] ?? false,
            ),
          ),
          Container(
            width: 1,
            height: 30,
            color: Colors.grey[300],
          ),
          Expanded(
            child: _buildSloItem(
              label: 'SLO 延迟',
              target: latency?['targetMs']?.toDouble() ?? 500,
              current: latency?['currentP99Ms']?.toDouble() ?? 0,
              met: latency?['met'] ?? false,
              isLatency: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSloItem({
    required String label,
    required double target,
    required double current,
    required bool met,
    bool isLatency = false,
  }) {
    String targetStr, currentStr;
    if (isLatency) {
      targetStr = '${target.toStringAsFixed(0)}ms';
      currentStr = '${current.toStringAsFixed(0)}ms';
    } else {
      targetStr = '${(target * 100).toStringAsFixed(2)}%';
      currentStr = '${(current * 100).toStringAsFixed(2)}%';
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              met ? Icons.check_circle : Icons.warning,
              size: 14,
              color: met ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          currentStr,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: met ? Colors.green : Colors.orange,
          ),
        ),
        Text(
          '目标: $targetStr',
          style: TextStyle(
            fontSize: 9,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
  }

  String _formatServiceName(String name) {
    return name
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1)}'
            : '')
        .join(' ');
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

  IconData _getCircuitBreakerIcon(String state) {
    switch (state.toLowerCase()) {
      case 'closed':
        return Icons.check_circle_outline;
      case 'open':
        return Icons.block;
      case 'halfopen':
        return Icons.pending;
      default:
        return Icons.help_outline;
    }
  }

  String _getCircuitBreakerLabel(String state) {
    switch (state.toLowerCase()) {
      case 'closed':
        return '关闭';
      case 'open':
        return '打开';
      case 'halfopen':
        return '半开';
      default:
        return '未知';
    }
  }

  Color _getCircuitBreakerColor(String state) {
    switch (state.toLowerCase()) {
      case 'closed':
        return Colors.green;
      case 'open':
        return Colors.red;
      case 'halfopen':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _getDegradationLabel(String level) {
    switch (level.toLowerCase()) {
      case 'normal':
        return '正常';
      case 'caution':
        return '注意';
      case 'warning':
        return '警告';
      case 'critical':
        return '严重';
      default:
        return '未知';
    }
  }

  Color _getDegradationColor(String level) {
    switch (level.toLowerCase()) {
      case 'normal':
        return Colors.green;
      case 'caution':
        return Colors.blue;
      case 'warning':
        return Colors.orange;
      case 'critical':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

/// 服务列表组件
class ServiceList extends StatelessWidget {
  final List<Map<String, dynamic>> services;
  final Function(String)? onServiceTap;

  const ServiceList({
    super.key,
    required this.services,
    this.onServiceTap,
  });

  @override
  Widget build(BuildContext context) {
    if (services.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.dns_outlined, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              '暂无服务数据',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        mainAxisExtent: 260,
      ),
      itemCount: services.length,
      itemBuilder: (context, index) {
        final service = services[index];
        final metrics = service['metrics'] as Map<String, dynamic>? ?? {};
        final slo = service['slo'] as Map<String, dynamic>?;

        return ServiceCard(
          name: service['name'] ?? 'unknown',
          status: service['status'] ?? 'unknown',
          successRate: (metrics['successRate'] as num?)?.toDouble() ?? 0,
          avgLatencyMs: (metrics['avgLatencyMs'] as num?)?.toDouble() ?? 0,
          p99LatencyMs: (metrics['p99LatencyMs'] as num?)?.toDouble() ?? 0,
          requestsPerMinute: (metrics['requestsPerMinute'] as num?)?.toInt() ?? 0,
          circuitBreakerState: service['circuitBreaker'] ?? 'unknown',
          degradationLevel: service['degradation'] ?? 'unknown',
          sloStatus: slo,
          onTap: onServiceTap != null
              ? () => onServiceTap!(service['name'] ?? '')
              : null,
        );
      },
    );
  }
}

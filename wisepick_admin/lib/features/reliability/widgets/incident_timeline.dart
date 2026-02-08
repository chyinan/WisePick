import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// 事件时间线组件
class IncidentTimeline extends StatelessWidget {
  final List<Map<String, dynamic>> events;
  final String title;
  final VoidCallback? onViewAll;

  const IncidentTimeline({
    super.key,
    required this.events,
    this.title = '事件时间线',
    this.onViewAll,
  });

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
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              if (onViewAll != null)
                TextButton(
                  onPressed: onViewAll,
                  child: const Text('查看全部'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (events.isEmpty)
            _buildEmptyState()
          else
            _buildTimeline(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: Colors.green[300],
            ),
            const SizedBox(height: 12),
            Text(
              '系统运行正常，暂无事件',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final isLast = index == events.length - 1;
        return _TimelineItem(
          event: event,
          isLast: isLast,
        );
      },
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final Map<String, dynamic> event;
  final bool isLast;

  const _TimelineItem({
    required this.event,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final timestamp = DateTime.tryParse(event['time'] ?? event['timestamp'] ?? '');
    final severity = event['severity'] as String? ?? 'info';
    final eventText = event['event'] ?? event['description'] ?? '';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 时间线
          SizedBox(
            width: 60,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _getSeverityColor(severity),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _getSeverityColor(severity).withOpacity(0.4),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Colors.grey[200],
                    ),
                  ),
              ],
            ),
          ),
          // 内容
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildSeverityBadge(severity),
                      const SizedBox(width: 8),
                      if (timestamp != null)
                        Text(
                          DateFormat('HH:mm:ss').format(timestamp),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    eventText,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  if (timestamp != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('yyyy-MM-dd').format(timestamp),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeverityBadge(String severity) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _getSeverityColor(severity).withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _getSeverityLabel(severity),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: _getSeverityColor(severity),
        ),
      ),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return const Color(0xFFEF4444);
      case 'error':
        return const Color(0xFFF97316);
      case 'warning':
        return const Color(0xFFF59E0B);
      case 'info':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFF6B7280);
    }
  }

  String _getSeverityLabel(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return '严重';
      case 'error':
        return '错误';
      case 'warning':
        return '警告';
      case 'info':
        return '信息';
      default:
        return '未知';
    }
  }
}

/// 告警列表组件
class AlertList extends StatelessWidget {
  final List<Map<String, dynamic>> alerts;
  final Function(String)? onAcknowledge;
  final VoidCallback? onViewAll;

  const AlertList({
    super.key,
    required this.alerts,
    this.onAcknowledge,
    this.onViewAll,
  });

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
              Row(
                children: [
                  const Text(
                    '活跃告警',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (alerts.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${alerts.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.red[700],
                        ),
                      ),
                    ),
                ],
              ),
              if (onViewAll != null)
                TextButton(
                  onPressed: onViewAll,
                  child: const Text('查看全部'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (alerts.isEmpty)
            _buildEmptyState()
          else
            _buildAlertList(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.notifications_off_outlined,
              size: 40,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 8),
            Text(
              '暂无活跃告警',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: alerts.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final alert = alerts[index];
        return _AlertItem(
          alert: alert,
          onAcknowledge: onAcknowledge,
        );
      },
    );
  }
}

class _AlertItem extends StatelessWidget {
  final Map<String, dynamic> alert;
  final Function(String)? onAcknowledge;

  const _AlertItem({
    required this.alert,
    this.onAcknowledge,
  });

  @override
  Widget build(BuildContext context) {
    final severity = alert['severity'] as String? ?? 'info';
    final title = alert['title'] as String? ?? '';
    final description = alert['description'] as String? ?? '';
    final timestamp = DateTime.tryParse(alert['timestamp'] ?? '');
    final acknowledged = alert['acknowledged'] as bool? ?? false;
    final alertId = alert['id'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _getSeverityColor(severity).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getSeverityIcon(severity),
              size: 20,
              color: _getSeverityColor(severity),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    _buildSeverityBadge(severity),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (timestamp != null)
                      Text(
                        DateFormat('MM-dd HH:mm').format(timestamp),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[400],
                        ),
                      ),
                    const Spacer(),
                    if (!acknowledged && onAcknowledge != null)
                      TextButton.icon(
                        onPressed: () => onAcknowledge!(alertId),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('确认'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeverityBadge(String severity) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _getSeverityColor(severity).withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _getSeverityLabel(severity),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: _getSeverityColor(severity),
        ),
      ),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return const Color(0xFFEF4444);
      case 'error':
        return const Color(0xFFF97316);
      case 'warning':
        return const Color(0xFFF59E0B);
      case 'info':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData _getSeverityIcon(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Icons.error;
      case 'error':
        return Icons.warning;
      case 'warning':
        return Icons.info;
      case 'info':
        return Icons.notifications;
      default:
        return Icons.help;
    }
  }

  String _getSeverityLabel(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return '严重';
      case 'error':
        return '错误';
      case 'warning':
        return '警告';
      case 'info':
        return '信息';
      default:
        return '未知';
    }
  }
}

/// 自愈动作历史组件
class SelfHealingActionsCard extends StatelessWidget {
  final List<Map<String, dynamic>> actions;
  final VoidCallback? onViewAll;

  const SelfHealingActionsCard({
    super.key,
    required this.actions,
    this.onViewAll,
  });

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
              Row(
                children: [
                  const Icon(
                    Icons.auto_fix_high,
                    size: 20,
                    color: Color(0xFF6366F1),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '自愈动作',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
              if (onViewAll != null)
                TextButton(
                  onPressed: onViewAll,
                  child: const Text('查看全部'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (actions.isEmpty)
            _buildEmptyState()
          else
            _buildActionList(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.healing,
              size: 40,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 8),
            Text(
              '暂无自愈动作记录',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      itemBuilder: (context, index) {
        final action = actions[index];
        final type = action['type'] as String? ?? '';
        final service = action['service'] as String? ?? '';
        final timestamp = DateTime.tryParse(action['timestamp'] ?? '');
        final success = action['success'] as bool? ?? false;
        final description = action['description'] as String? ?? '';

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: success
                      ? Colors.green.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  success ? Icons.check_circle : Icons.cancel,
                  size: 18,
                  color: success ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      description.isNotEmpty ? description : _formatActionType(type),
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      service,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              if (timestamp != null)
                Text(
                  DateFormat('HH:mm').format(timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[400],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _formatActionType(String type) {
    return type
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1)}'
            : '')
        .join(' ');
  }
}

import 'package:flutter/material.dart';

/// 混沌工程控制面板
class ChaosControlPanel extends StatelessWidget {
  final bool chaosEnabled;
  final bool experimentRunning;
  final String? currentExperimentId;
  final String? currentExperimentName;
  final List<Map<String, dynamic>> experiments;
  final VoidCallback? onEnableChaos;
  final VoidCallback? onDisableChaos;
  final Function(String)? onStartExperiment;
  final VoidCallback? onStopExperiment;

  const ChaosControlPanel({
    super.key,
    required this.chaosEnabled,
    required this.experimentRunning,
    this.currentExperimentId,
    this.currentExperimentName,
    this.experiments = const [],
    this.onEnableChaos,
    this.onDisableChaos,
    this.onStartExperiment,
    this.onStopExperiment,
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
          _buildHeader(),
          const SizedBox(height: 20),
          _buildStatusCard(),
          const SizedBox(height: 20),
          _buildExperimentList(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.bug_report,
                color: Color(0xFF6366F1),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '混沌工程',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                Text(
                  '测试系统弹性和容错能力',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ),
        _buildMainSwitch(),
      ],
    );
  }

  Widget _buildMainSwitch() {
    return Container(
      decoration: BoxDecoration(
        color: chaosEnabled
            ? const Color(0xFFDCFCE7)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chaosEnabled)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                '已启用',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.green[700],
                ),
              ),
            ),
          Switch(
            value: chaosEnabled,
            onChanged: (value) {
              if (value) {
                onEnableChaos?.call();
              } else {
                onDisableChaos?.call();
              }
            },
            activeColor: Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    if (!chaosEnabled) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: Colors.grey[400],
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '混沌工程已禁用。启用后可以运行故障注入实验来测试系统弹性。',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (experimentRunning) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.orange.withOpacity(0.1),
              Colors.red.withOpacity(0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.warning_amber,
                color: Colors.orange,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '实验进行中',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentExperimentName ?? currentExperimentId ?? '未知实验',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: onStopExperiment,
              icon: const Icon(Icons.stop, size: 18),
              label: const Text('停止'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle,
            color: Colors.green[600],
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '混沌工程已就绪。选择下方实验开始测试。',
              style: TextStyle(
                color: Colors.green[700],
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExperimentList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '可用实验',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 12),
        if (experiments.isEmpty)
          _buildEmptyExperiments()
        else
          ...experiments.map((exp) => _buildExperimentCard(exp)),
      ],
    );
  }

  Widget _buildEmptyExperiments() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.science_outlined,
              size: 40,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 8),
            Text(
              '暂无可用实验',
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

  Widget _buildExperimentCard(Map<String, dynamic> experiment) {
    final id = experiment['id'] as String? ?? '';
    final name = experiment['name'] as String? ?? '';
    final description = experiment['description'] as String? ?? '';
    final faults = experiment['faults'] as List? ?? [];
    final isRunning = currentExperimentId == id;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isRunning
            ? Colors.orange.withOpacity(0.05)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRunning
              ? Colors.orange.withOpacity(0.3)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.science,
                  size: 16,
                  color: Color(0xFF6366F1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              if (!experimentRunning && chaosEnabled)
                ElevatedButton(
                  onPressed: () => onStartExperiment?.call(id),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('运行', style: TextStyle(fontSize: 12)),
                ),
              if (isRunning)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '运行中',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
          if (faults.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: faults.map((fault) {
                final type = fault['type'] as String? ?? '';
                final probability = fault['probability'] as num? ?? 0;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getFaultColor(type).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getFaultIcon(type),
                        size: 12,
                        color: _getFaultColor(type),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_getFaultLabel(type)} ${(probability * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 10,
                          color: _getFaultColor(type),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Color _getFaultColor(String type) {
    switch (type.toLowerCase()) {
      case 'latency':
        return Colors.orange;
      case 'error':
        return Colors.red;
      case 'timeout':
        return Colors.purple;
      case 'resource':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getFaultIcon(String type) {
    switch (type.toLowerCase()) {
      case 'latency':
        return Icons.timer;
      case 'error':
        return Icons.error_outline;
      case 'timeout':
        return Icons.hourglass_empty;
      case 'resource':
        return Icons.memory;
      default:
        return Icons.bug_report;
    }
  }

  String _getFaultLabel(String type) {
    switch (type.toLowerCase()) {
      case 'latency':
        return '延迟注入';
      case 'error':
        return '错误注入';
      case 'timeout':
        return '超时注入';
      case 'resource':
        return '资源压力';
      default:
        return type;
    }
  }
}

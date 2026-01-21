import 'package:flutter/material.dart';
import '../services/sync/conflict_resolver.dart';

/// 冲突解决对话框
/// 当自动解决失败时，让用户选择如何处理冲突
class ConflictResolutionDialog extends StatefulWidget {
  final List<SyncConflict<Map<String, dynamic>>> conflicts;
  final String title;

  const ConflictResolutionDialog({
    super.key,
    required this.conflicts,
    this.title = '数据冲突',
  });

  /// 显示对话框并返回用户选择的解决方案
  static Future<Map<String, ConflictResolutionStrategy>?> show(
    BuildContext context, {
    required List<SyncConflict<Map<String, dynamic>>> conflicts,
    String title = '数据冲突',
  }) async {
    return showDialog<Map<String, ConflictResolutionStrategy>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ConflictResolutionDialog(
        conflicts: conflicts,
        title: title,
      ),
    );
  }

  @override
  State<ConflictResolutionDialog> createState() => _ConflictResolutionDialogState();
}

class _ConflictResolutionDialogState extends State<ConflictResolutionDialog> {
  final Map<String, ConflictResolutionStrategy> _selections = {};

  @override
  void initState() {
    super.initState();
    // 初始化为推荐的解决方案
    for (final conflict in widget.conflicts) {
      _selections[conflict.id] = conflict.recommendedResolution;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Text(widget.title),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '检测到 ${widget.conflicts.length} 个数据冲突，请选择如何处理：',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.conflicts.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final conflict = widget.conflicts[index];
                  return _buildConflictItem(conflict, theme);
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消同步'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selections),
          child: const Text('应用选择'),
        ),
      ],
    );
  }

  Widget _buildConflictItem(SyncConflict<Map<String, dynamic>> conflict, ThemeData theme) {
    final itemName = _getItemName(conflict);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_getConflictIcon(conflict.type), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  itemName,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _getConflictDescription(conflict),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _buildResolutionOptions(conflict, theme),
        ],
      ),
    );
  }

  Widget _buildResolutionOptions(SyncConflict<Map<String, dynamic>> conflict, ThemeData theme) {
    return Wrap(
      spacing: 8,
      children: [
        _buildOptionChip(
          conflict.id,
          ConflictResolutionStrategy.keepLocal,
          '保留本地',
          Icons.phone_android,
          theme,
        ),
        _buildOptionChip(
          conflict.id,
          ConflictResolutionStrategy.keepServer,
          '使用云端',
          Icons.cloud,
          theme,
        ),
        if (conflict.type == ConflictType.bothModified)
          _buildOptionChip(
            conflict.id,
            ConflictResolutionStrategy.merge,
            '合并',
            Icons.merge,
            theme,
          ),
      ],
    );
  }

  Widget _buildOptionChip(
    String conflictId,
    ConflictResolutionStrategy strategy,
    String label,
    IconData icon,
    ThemeData theme,
  ) {
    final isSelected = _selections[conflictId] == strategy;
    
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selections[conflictId] = strategy;
          });
        }
      },
    );
  }

  String _getItemName(SyncConflict<Map<String, dynamic>> conflict) {
    final local = conflict.localData;
    final server = conflict.serverData;
    
    // 尝试获取商品标题
    final title = local?['title'] ?? server?['title'] ?? 
                  local?['name'] ?? server?['name'] ??
                  '未知项目';
    return title.toString();
  }

  IconData _getConflictIcon(ConflictType type) {
    switch (type) {
      case ConflictType.bothAdded:
        return Icons.add_circle_outline;
      case ConflictType.bothModified:
        return Icons.edit_outlined;
      case ConflictType.deleteVsModify:
        return Icons.delete_outline;
      case ConflictType.versionMismatch:
        return Icons.sync_problem;
    }
  }

  String _getConflictDescription(SyncConflict<Map<String, dynamic>> conflict) {
    switch (conflict.type) {
      case ConflictType.bothAdded:
        return '本地和云端都添加了此项目';
      case ConflictType.bothModified:
        return '本地和云端都修改了此项目';
      case ConflictType.deleteVsModify:
        final localDeleted = conflict.localData?['is_deleted'] == true;
        return localDeleted 
            ? '本地已删除，但云端有修改' 
            : '云端已删除，但本地有修改';
      case ConflictType.versionMismatch:
        return '版本不一致，云端版本: ${conflict.serverVersion}';
    }
  }
}

/// 冲突解决结果提示
class ConflictResolutionSnackBar {
  static void show(
    BuildContext context, {
    required int autoResolvedCount,
    required int userResolvedCount,
  }) {
    final total = autoResolvedCount + userResolvedCount;
    if (total == 0) return;

    String message;
    if (userResolvedCount == 0) {
      message = '已自动解决 $autoResolvedCount 个冲突';
    } else if (autoResolvedCount == 0) {
      message = '已解决 $userResolvedCount 个冲突';
    } else {
      message = '已解决 $total 个冲突（自动 $autoResolvedCount，手动 $userResolvedCount）';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

/// 简化的冲突提示组件（用于设置页等位置）
class ConflictWarningBanner extends StatelessWidget {
  final int conflictCount;
  final VoidCallback? onResolve;

  const ConflictWarningBanner({
    super.key,
    required this.conflictCount,
    this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    if (conflictCount == 0) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    
    return MaterialBanner(
      backgroundColor: theme.colorScheme.errorContainer,
      leading: Icon(
        Icons.warning_amber_rounded,
        color: theme.colorScheme.error,
      ),
      content: Text(
        '检测到 $conflictCount 个数据冲突需要处理',
        style: TextStyle(color: theme.colorScheme.onErrorContainer),
      ),
      actions: [
        TextButton(
          onPressed: onResolve,
          child: const Text('立即处理'),
        ),
      ],
    );
  }
}

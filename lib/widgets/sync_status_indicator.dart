import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/sync/sync_manager.dart';
import '../../features/auth/auth_providers.dart';

/// 同步状态指示器组件
class SyncStatusIndicator extends ConsumerWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggedIn = ref.watch(isLoggedInProvider);
    
    if (!isLoggedIn) {
      return const SizedBox.shrink();
    }

    final syncState = ref.watch(syncManagerProvider);
    final theme = Theme.of(context);

    return Card(
      child: Column(
        children: [
          // 同步状态行
          ListTile(
            leading: _buildStatusIcon(syncState, theme),
            title: const Text('数据同步'),
            subtitle: _buildStatusText(syncState),
            trailing: _buildSyncButton(context, ref, syncState),
          ),
          // 详细状态（可选）
          if (syncState.isSyncing || 
              syncState.cartError != null || 
              syncState.conversationError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _buildDetailedStatus(syncState, theme),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(SyncState state, ThemeData theme) {
    if (state.isSyncing) {
      return SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: theme.colorScheme.primary,
        ),
      );
    }

    // 离线状态
    if (state.cartStatus == SyncStatus.offline || 
        state.conversationStatus == SyncStatus.offline) {
      return Stack(
        children: [
          Icon(
            Icons.cloud_off,
            color: theme.colorScheme.outline,
          ),
          if (state.hasPendingChanges)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      );
    }

    if (state.cartError != null || state.conversationError != null) {
      return Icon(
        Icons.sync_problem,
        color: theme.colorScheme.error,
      );
    }

    if (state.cartStatus == SyncStatus.success || 
        state.conversationStatus == SyncStatus.success) {
      return Icon(
        Icons.cloud_done,
        color: theme.colorScheme.primary,
      );
    }

    // 有待同步的变更
    if (state.hasPendingChanges) {
      return Stack(
        children: [
          Icon(
            Icons.cloud_upload_outlined,
            color: theme.colorScheme.tertiary,
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiary,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${state.pendingCartChanges + state.pendingConversationChanges}',
                style: TextStyle(
                  fontSize: 8,
                  color: theme.colorScheme.onTertiary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Icon(
      Icons.cloud_outlined,
      color: theme.colorScheme.onSurfaceVariant,
    );
  }

  Widget _buildStatusText(SyncState state) {
    if (state.isSyncing) {
      if (state.cartStatus == SyncStatus.syncing) {
        return const Text('正在同步购物车...');
      }
      if (state.conversationStatus == SyncStatus.syncing) {
        return const Text('正在同步聊天记录...');
      }
      return const Text('正在同步...');
    }

    // 离线状态
    if (state.cartStatus == SyncStatus.offline || 
        state.conversationStatus == SyncStatus.offline) {
      final pendingCount = state.pendingCartChanges + state.pendingConversationChanges;
      if (pendingCount > 0) {
        return Text(
          '离线模式 · $pendingCount 项待同步',
          style: const TextStyle(color: Colors.orange),
        );
      }
      return const Text(
        '离线模式',
        style: TextStyle(color: Colors.orange),
      );
    }

    if (state.cartError != null || state.conversationError != null) {
      return Text(
        '同步失败',
        style: TextStyle(color: Colors.red.shade700),
      );
    }

    // 有待同步的变更
    if (state.hasPendingChanges) {
      final pendingCount = state.pendingCartChanges + state.pendingConversationChanges;
      return Text('$pendingCount 项待同步');
    }

    // 显示上次同步时间
    final lastSync = state.lastCartSync ?? state.lastConversationSync;
    if (lastSync != null) {
      final diff = DateTime.now().difference(lastSync);
      String timeText;
      if (diff.inMinutes < 1) {
        timeText = '刚刚';
      } else if (diff.inMinutes < 60) {
        timeText = '${diff.inMinutes}分钟前';
      } else if (diff.inHours < 24) {
        timeText = '${diff.inHours}小时前';
      } else {
        timeText = '${diff.inDays}天前';
      }
      return Text('上次同步: $timeText');
    }

    return const Text('点击同步数据到云端');
  }

  Widget? _buildSyncButton(BuildContext context, WidgetRef ref, SyncState state) {
    if (state.isSyncing) {
      return null; // 同步中不显示按钮
    }

    return IconButton(
      icon: const Icon(Icons.sync),
      tooltip: '立即同步',
      onPressed: () async {
        final syncManager = ref.read(syncManagerProvider.notifier);
        await syncManager.syncAll();
        
        // 显示同步结果
        if (context.mounted) {
          final newState = ref.read(syncManagerProvider);
          if (newState.cartError != null || newState.conversationError != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('同步失败: ${newState.cartError ?? newState.conversationError}'),
                backgroundColor: Colors.red,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('同步完成'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      },
    );
  }

  Widget _buildDetailedStatus(SyncState state, ThemeData theme) {
    final items = <Widget>[];

    if (state.cartStatus == SyncStatus.syncing) {
      items.add(_buildDetailItem(
        Icons.shopping_cart_outlined,
        '购物车',
        '同步中...',
        theme.colorScheme.primary,
      ));
    } else if (state.cartError != null) {
      items.add(_buildDetailItem(
        Icons.shopping_cart_outlined,
        '购物车',
        state.cartError!,
        theme.colorScheme.error,
      ));
    }

    if (state.conversationStatus == SyncStatus.syncing) {
      items.add(_buildDetailItem(
        Icons.chat_outlined,
        '聊天记录',
        '同步中...',
        theme.colorScheme.primary,
      ));
    } else if (state.conversationError != null) {
      items.add(_buildDetailItem(
        Icons.chat_outlined,
        '聊天记录',
        state.conversationError!,
        theme.colorScheme.error,
      ));
    }

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: items,
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String status, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              color: color,
            ),
          ),
          Expanded(
            child: Text(
              status,
              style: TextStyle(
                fontSize: 12,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 紧凑版同步状态指示器（用于 AppBar 等位置）
class CompactSyncIndicator extends ConsumerWidget {
  const CompactSyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggedIn = ref.watch(isLoggedInProvider);
    
    if (!isLoggedIn) {
      return const SizedBox.shrink();
    }

    final syncState = ref.watch(syncManagerProvider);
    final theme = Theme.of(context);

    if (syncState.isSyncing) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary,
          ),
        ),
      );
    }

    if (syncState.cartError != null || syncState.conversationError != null) {
      return IconButton(
        icon: Icon(
          Icons.sync_problem,
          color: theme.colorScheme.error,
          size: 20,
        ),
        tooltip: '同步失败，点击重试',
        onPressed: () {
          ref.read(syncManagerProvider.notifier).syncAll();
        },
      );
    }

    return const SizedBox.shrink();
  }
}

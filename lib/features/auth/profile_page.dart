import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_providers.dart';
import 'user_model.dart';

/// 用户资料页面
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  @override
  void initState() {
    super.initState();
    // 刷新用户信息
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authStateProvider.notifier).refreshUser();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authStateProvider);
    final user = authState.user;
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('我的账号')),
        body: const Center(child: Text('请先登录')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的账号'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () =>
                ref.read(authStateProvider.notifier).refreshUser(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 48 : 16,
            vertical: 24,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 用户头像和基本信息卡片
                  _UserInfoCard(user: user),
                  const SizedBox(height: 24),

                  // 账号操作
                  _buildSectionTitle(theme, '账号设置'),
                  const SizedBox(height: 12),
                  _buildSettingsCard(theme, [
                    _SettingsTile(
                      icon: Icons.edit_outlined,
                      title: '编辑资料',
                      onTap: () => _showEditProfileDialog(user),
                    ),
                    _SettingsTile(
                      icon: Icons.lock_outlined,
                      title: '修改密码',
                      onTap: () => _showChangePasswordDialog(),
                    ),
                    _SettingsTile(
                      icon: Icons.devices_outlined,
                      title: '登录设备',
                      onTap: () => _showSessionsDialog(),
                    ),
                  ]),
                  const SizedBox(height: 24),

                  // 账号信息
                  _buildSectionTitle(theme, '账号信息'),
                  const SizedBox(height: 12),
                  _buildInfoCard(theme, user),
                  const SizedBox(height: 32),

                  // 登出按钮
                  OutlinedButton.icon(
                    onPressed: () => _confirmLogout(),
                    icon: const Icon(Icons.logout),
                    label: const Text('退出登录'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(color: theme.colorScheme.error),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 登出所有设备
                  TextButton(
                    onPressed: () => _confirmLogoutAll(),
                    child: Text(
                      '从所有设备登出',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildSettingsCard(ThemeData theme, List<_SettingsTile> tiles) {
    return Card(
      child: Column(
        children: tiles.map((tile) {
          final isLast = tiles.indexOf(tile) == tiles.length - 1;
          return Column(
            children: [
              ListTile(
                leading: Icon(tile.icon, color: theme.colorScheme.primary),
                title: Text(tile.title),
                trailing: const Icon(Icons.chevron_right),
                onTap: tile.onTap,
              ),
              if (!isLast)
                Divider(
                  height: 1,
                  indent: 56,
                  color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme, User user) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _InfoRow(label: '邮箱', value: user.email),
            const Divider(),
            _InfoRow(
              label: '注册时间',
              value: user.createdAt != null 
                  ? _formatDate(user.createdAt!) 
                  : '未知',
            ),
            const Divider(),
            _InfoRow(
              label: '上次登录',
              value: user.lastLoginAt != null 
                  ? _formatDate(user.lastLoginAt!) 
                  : '未知',
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  /// 显示编辑资料对话框
  void _showEditProfileDialog(User user) {
    final nicknameController = TextEditingController(text: user.nickname);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑资料'),
        content: TextField(
          controller: nicknameController,
          decoration: const InputDecoration(
            labelText: '昵称',
            hintText: '请输入昵称',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final success = await ref.read(authStateProvider.notifier).updateProfile(
                    nickname: nicknameController.text.trim(),
                  );
              if (success && mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('资料更新成功')),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 显示修改密码对话框
  void _showChangePasswordDialog() {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改密码'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '当前密码',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '新密码',
                  helperText: '至少8位，包含字母和数字',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '确认新密码',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (newPasswordController.text != confirmPasswordController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('两次输入的密码不一致')),
                );
                return;
              }

              final success = await ref.read(authStateProvider.notifier).changePassword(
                    oldPassword: oldPasswordController.text,
                    newPassword: newPasswordController.text,
                  );

              if (success && mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('密码修改成功')),
                );
              }
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  /// 显示登录设备对话框
  void _showSessionsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => const _SessionsDialog(),
    );
  }

  /// 确认登出
  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认退出'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authStateProvider.notifier).logout();
              if (mounted) {
                Navigator.of(context).pop(); // 返回上一页
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  /// 确认从所有设备登出
  void _confirmLogoutAll() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认退出所有设备'),
        content: const Text('确定要从所有设备退出登录吗？这将使所有设备上的登录状态失效。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authStateProvider.notifier).logoutAll();
              if (mounted) {
                Navigator.of(context).pop(); // 返回上一页
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('退出所有设备'),
          ),
        ],
      ),
    );
  }
}

/// 用户信息卡片
class _UserInfoCard extends StatelessWidget {
  final User user;

  const _UserInfoCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // 头像
            CircleAvatar(
              radius: 48,
              backgroundColor: theme.colorScheme.primaryContainer,
              backgroundImage:
                  user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
              child: user.avatarUrl == null
                  ? Text(
                      _getInitials(user),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 16),

            // 昵称
            Text(
              user.nickname ?? user.email.split('@').first,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),

            // 邮箱
            Text(
              user.email,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getInitials(User user) {
    if (user.nickname != null && user.nickname!.isNotEmpty) {
      return user.nickname![0].toUpperCase();
    }
    return user.email[0].toUpperCase();
  }
}

/// 设置项
class _SettingsTile {
  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.onTap,
  });
}

/// 信息行
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

/// 登录设备对话框
class _SessionsDialog extends ConsumerWidget {
  const _SessionsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sessionsAsync = ref.watch(userSessionsProvider);

    return AlertDialog(
      title: const Text('登录设备'),
      content: SizedBox(
        width: double.maxFinite,
        child: sessionsAsync.when(
          data: (sessions) {
            if (sessions.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无登录设备'),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              itemCount: sessions.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (ctx, index) {
                final session = sessions[index];
                return ListTile(
                  leading: Icon(
                    _getDeviceIcon(session.deviceType),
                    color: session.isCurrentDevice
                        ? theme.colorScheme.primary
                        : null,
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          session.deviceName ?? '未知设备',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (session.isCurrentDevice) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '当前设备',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '上次活动: ${_formatLastActive(session.lastActiveAt)}',
                    style: theme.textTheme.bodySmall,
                  ),
                );
              },
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('加载失败: $e'),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  IconData _getDeviceIcon(String? deviceType) {
    switch (deviceType?.toLowerCase()) {
      case 'android':
        return Icons.phone_android;
      case 'ios':
        return Icons.phone_iphone;
      case 'macos':
      case 'windows':
      case 'linux':
        return Icons.laptop;
      case 'web':
        return Icons.language;
      default:
        return Icons.devices;
    }
  }

  String _formatLastActive(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) {
      return '刚刚';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}小时前';
    } else if (diff.inDays < 30) {
      return '${diff.inDays}天前';
    } else {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }
}

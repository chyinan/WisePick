import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import 'settings_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with SingleTickerProviderStateMixin {
  final _service = SettingsService(ApiClient());
  late TabController _tabController;

  Map<String, dynamic>? _settings;
  List<Map<String, dynamic>> _sessions = [];
  int _sessionsTotal = 0;
  int _sessionsPage = 1;
  int _sessionsTotalPages = 1;
  bool _isLoading = true;
  bool _isLoadingSessions = false;
  String? _error;
  bool _activeOnly = true;

  // 修改密码表单
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  void _log(String message, {bool isError = false}) {
    final prefix = isError ? '❌ Settings' : '⚙️ Settings';
    developer.log('$prefix: $message', name: 'SettingsPage');
  }
  
  // 安全地从 Map 获取值
  String _safeGetString(Map<String, dynamic>? map, String key, [String defaultValue = '-']) {
    final value = map?[key];
    if (value == null) return defaultValue;
    return value.toString();
  }

  T? _safeGetNested<T>(Map<String, dynamic>? map, List<String> keys) {
    if (map == null) return null;
    dynamic current = map;
    for (final key in keys) {
      if (current is! Map<String, dynamic>) return null;
      current = current[key];
      if (current == null) return null;
    }
    return current is T ? current : null;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSettings();
    _loadSessions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changeAdminPassword() async {
    final oldPwd = _oldPasswordController.text.trim();
    final newPwd = _newPasswordController.text.trim();
    final confirmPwd = _confirmPasswordController.text.trim();

    if (oldPwd.isEmpty || newPwd.isEmpty || confirmPwd.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写所有密码字段'), backgroundColor: Colors.orange),
      );
      return;
    }

    if (newPwd.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('新密码长度不能少于8位'), backgroundColor: Colors.orange),
      );
      return;
    }

    if (newPwd != confirmPwd) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('两次输入的新密码不一致'), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      await _service.changeAdminPassword(
        oldPassword: oldPwd,
        newPassword: newPwd,
      );
      if (mounted) {
        _oldPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('密码修改成功'), backgroundColor: Color(0xFF10B981)),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _log('Loading settings...');
      final settings = await _service.getSettings();
      if (mounted) {
        setState(() {
          _settings = settings;
          _isLoading = false;
        });
        _log('Settings loaded successfully');
      }
    } on ApiException catch (e) {
      _log('Failed to load settings (API): ${e.message}', isError: true);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.message;
        });
      }
    } catch (e) {
      _log('Failed to load settings (unexpected): $e', isError: true);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '加载设置失败，请稍后重试';
        });
      }
    }
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoadingSessions = true);

    try {
      _log('Loading sessions (page: $_sessionsPage, activeOnly: $_activeOnly)');
      final result = await _service.getSessions(
        page: _sessionsPage,
        activeOnly: _activeOnly,
      );
      if (mounted) {
        setState(() {
          _sessions = List<Map<String, dynamic>>.from(result['sessions'] ?? []);
          _sessionsTotal = (result['total'] as num?)?.toInt() ?? 0;
          // 确保 totalPages 至少为 1，避免显示 "1/0"
          _sessionsTotalPages = ((result['totalPages'] as num?)?.toInt() ?? 1).clamp(1, 10000);
          _isLoadingSessions = false;
        });
        _log('Loaded ${_sessions.length} sessions');
      }
    } on ApiException catch (e) {
      _log('Failed to load sessions (API): ${e.message}', isError: true);
      if (mounted) {
        setState(() => _isLoadingSessions = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载会话失败: ${e.message}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      _log('Failed to load sessions (unexpected): $e', isError: true);
      if (mounted) {
        setState(() => _isLoadingSessions = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加载会话失败，请稍后重试'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteSession(Map<String, dynamic> session) async {
    final sessionId = session['id']?.toString();
    final deviceName = _safeGetString(session, 'deviceName', '未知设备');
    
    if (sessionId == null || sessionId.isEmpty) {
      _log('Cannot delete session: missing ID', isError: true);
      return;
    }
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('强制下线'),
        content: Text('确定要强制下线设备"$deviceName"吗？用户将需要重新登录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('强制下线'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        _log('Deleting session: $sessionId');
        await _service.deleteSession(sessionId);
        _loadSessions();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已强制下线'), backgroundColor: Colors.green),
          );
        }
      } on ApiException catch (e) {
        _log('Failed to delete session (API): ${e.message}', isError: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('操作失败: ${e.message}'), backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        _log('Failed to delete session (unexpected): $e', isError: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('操作失败，请稍后重试'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab 栏
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF6366F1),
            labelColor: const Color(0xFF6366F1),
            unselectedLabelColor: Colors.grey[600],
            tabs: const [
              Tab(icon: Icon(Icons.settings), text: '系统配置'),
              Tab(icon: Icon(Icons.devices), text: '在线设备'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Tab 内容
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSettingsTab(),
              _buildSessionsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadSettings,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_settings == null) {
      return const Center(child: Text('无配置数据'));
    }

    // 使用安全方式提取嵌套值
    final serverHost = _safeGetNested<String>(_settings, ['server', 'host']) ?? '-';
    final serverPort = _safeGetNested(_settings, ['server', 'port'])?.toString() ?? '-';
    final dbHost = _safeGetNested<String>(_settings, ['database', 'host']) ?? '-';
    final dbPort = _safeGetNested(_settings, ['database', 'port'])?.toString() ?? '-';
    final dbName = _safeGetNested<String>(_settings, ['database', 'name']) ?? '-';
    final dbStatus = _safeGetNested<String>(_settings, ['database', 'status']);
    
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSettingsSection(
            title: '服务器配置',
            icon: Icons.dns_rounded,
            children: [
              _buildSettingItem('监听地址', serverHost),
              _buildSettingItem('端口', serverPort),
            ],
          ),
          const SizedBox(height: 20),
          _buildSettingsSection(
            title: '数据库配置',
            icon: Icons.storage_rounded,
            color: const Color(0xFF10B981),
            children: [
              _buildSettingItem('数据库主机', dbHost),
              _buildSettingItem('端口', dbPort),
              _buildSettingItem('数据库名', dbName),
              _buildSettingItem(
                '连接状态',
                dbStatus == 'connected' ? '已连接' : '断开',
                valueColor: dbStatus == 'connected'
                    ? const Color(0xFF10B981)
                    : Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildChangePasswordSection(),
        ],
      ),
    );
  }

  Widget _buildSettingsSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
    Color color = const Color(0xFF6366F1),
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey[600]),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: valueColor ?? const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChangePasswordSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.lock_reset_rounded, color: Color(0xFFEF4444), size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '管理员密码',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '定期更换密码有助于保障后台安全',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _showChangePasswordDialog,
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text('修改密码'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
                side: const BorderSide(color: Color(0xFFEF4444)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog() {
    _oldPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ChangePasswordDialog(
        oldController: _oldPasswordController,
        newController: _newPasswordController,
        confirmController: _confirmPasswordController,
        onSubmit: (navigator) async {
          await _changeAdminPassword();
          if (_oldPasswordController.text.isEmpty) {
            navigator.pop();
          }
        },
      ),
    );
  }

  Widget _buildSessionsTab() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 头部
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.devices_rounded, color: Color(0xFF6366F1)),
                const SizedBox(width: 12),
                const Text(
                  '设备会话管理',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const Spacer(),
                // 筛选
                FilterChip(
                  label: const Text('仅显示在线'),
                  selected: _activeOnly,
                  onSelected: (selected) {
                    setState(() {
                      _activeOnly = selected;
                      _sessionsPage = 1;
                    });
                    _loadSessions();
                  },
                  selectedColor: const Color(0xFF6366F1).withOpacity(0.1),
                  checkmarkColor: const Color(0xFF6366F1),
                ),
                const SizedBox(width: 12),
                Text(
                  '共 $_sessionsTotal 个',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: _loadSessions,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: '刷新',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 列表
          Expanded(
            child: _isLoadingSessions
                ? const Center(child: CircularProgressIndicator())
                : _sessions.isEmpty
                    ? _buildEmptySessions()
                    : _buildSessionsList(),
          ),
          // 分页
          if (_sessionsTotalPages > 1) _buildSessionsPagination(),
        ],
      ),
    );
  }

  Widget _buildSessionsList() {
    return ListView.separated(
      itemCount: _sessions.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final session = _sessions[index];
        return _buildSessionItem(session);
      },
    );
  }

  Widget _buildSessionItem(Map<String, dynamic> session) {
    final isActive = session['isActive'] == true;
    final deviceType = _safeGetString(session, 'deviceType', 'unknown');
    final deviceName = _safeGetString(session, 'deviceName', '未知设备');
    final userNickname = _safeGetString(session, 'userNickname', '未知用户');
    final userEmail = _safeGetString(session, 'userEmail', '');
    final ipAddress = _safeGetString(session, 'ipAddress', '-');
    final lastActiveAt = _safeGetString(session, 'lastActiveAt', '');

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF10B981).withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getDeviceIcon(deviceType),
              color: isActive ? const Color(0xFF10B981) : Colors.grey,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      deviceName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF10B981).withOpacity(0.1)
                            : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isActive ? '在线' : '离线',
                        style: TextStyle(
                          fontSize: 11,
                          color: isActive ? const Color(0xFF10B981) : Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$userNickname ($userEmail)',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 2),
                Text(
                  'IP: $ipAddress • 最后活跃: ${_formatDateTime(lastActiveAt)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          if (isActive)
            TextButton.icon(
              onPressed: () => _deleteSession(session),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('强制下线'),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptySessions() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.devices_other, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _activeOnly ? '当前没有在线设备' : '暂无会话记录',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionsPagination() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _sessionsPage > 1
                ? () {
                    setState(() => _sessionsPage--);
                    _loadSessions();
                  }
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          const SizedBox(width: 8),
          Text('$_sessionsPage / $_sessionsTotalPages'),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _sessionsPage < _sessionsTotalPages
                ? () {
                    setState(() => _sessionsPage++);
                    _loadSessions();
                  }
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  IconData _getDeviceIcon(String deviceType) {
    switch (deviceType.toLowerCase()) {
      case 'ios':
      case 'iphone':
        return Icons.phone_iphone;
      case 'android':
        return Icons.phone_android;
      case 'windows':
        return Icons.desktop_windows;
      case 'macos':
      case 'mac':
        return Icons.laptop_mac;
      case 'linux':
        return Icons.computer;
      case 'web':
        return Icons.language;
      default:
        return Icons.devices_other;
    }
  }

  String _formatDateTime(String dateStr) {
    if (dateStr.isEmpty) return '-';
    final parsed = DateTime.tryParse(dateStr);
    if (parsed == null) return '-';
    // 统一转换为本地时间，确保与 DateTime.now() 比较准确
    final date = parsed.toLocal();
    final now = DateTime.now();
    final diff = now.difference(date);
    
    // 防止负数时间差（时钟偏差或服务器时间超前）
    if (diff.isNegative) return '刚刚';
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  final TextEditingController oldController;
  final TextEditingController newController;
  final TextEditingController confirmController;
  final Future<void> Function(NavigatorState navigator) onSubmit;

  const _ChangePasswordDialog({
    required this.oldController,
    required this.newController,
    required this.confirmController,
    required this.onSubmit,
  });

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  bool _oldVisible = false;
  bool _newVisible = false;
  bool _confirmVisible = false;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.lock_reset_rounded, color: Color(0xFFEF4444), size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '修改管理员密码',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '请先验证原密码后再设置新密码',
                        style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _loading ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
            const SizedBox(height: 28),
            // 原密码
            _buildField(
              controller: widget.oldController,
              label: '原密码',
              visible: _oldVisible,
              onToggle: () => setState(() => _oldVisible = !_oldVisible),
            ),
            const SizedBox(height: 16),
            // 分隔线
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('设置新密码', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),
            // 新密码
            _buildField(
              controller: widget.newController,
              label: '新密码（至少 8 位）',
              visible: _newVisible,
              onToggle: () => setState(() => _newVisible = !_newVisible),
            ),
            const SizedBox(height: 16),
            // 确认新密码
            _buildField(
              controller: widget.confirmController,
              label: '确认新密码',
              visible: _confirmVisible,
              onToggle: () => setState(() => _confirmVisible = !_confirmVisible),
            ),
            const SizedBox(height: 28),
            // 按钮
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _loading ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _submit,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: Text(_loading ? '保存中...' : '确认修改'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required bool visible,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: !visible,
      enabled: !_loading,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        suffixIcon: IconButton(
          icon: Icon(visible ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
          onPressed: onToggle,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Future<void> _submit() async {
    final navigator = Navigator.of(context);
    setState(() => _loading = true);
    await widget.onSubmit(navigator);
    if (mounted) setState(() => _loading = false);
  }
}

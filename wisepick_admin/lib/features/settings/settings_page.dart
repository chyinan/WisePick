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
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final settings = await _service.getSettings();
      if (mounted) {
        setState(() {
          _settings = settings;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoadingSessions = true);

    try {
      final result = await _service.getSessions(
        page: _sessionsPage,
        activeOnly: _activeOnly,
      );
      if (mounted) {
        setState(() {
          _sessions = result['sessions'];
          _sessionsTotal = result['total'];
          _sessionsTotalPages = result['totalPages'];
          _isLoadingSessions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSessions = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载会话失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteSession(Map<String, dynamic> session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('强制下线'),
        content: Text('确定要强制下线设备"${session['deviceName']}"吗？用户将需要重新登录。'),
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
        await _service.deleteSession(session['id']);
        _loadSessions();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已强制下线'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('操作失败: $e'), backgroundColor: Colors.red),
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

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSettingsSection(
            title: '服务器配置',
            icon: Icons.dns_rounded,
            children: [
              _buildSettingItem('监听地址', _settings!['server']?['host'] ?? '-'),
              _buildSettingItem('端口', _settings!['server']?['port'] ?? '-'),
            ],
          ),
          const SizedBox(height: 20),
          _buildSettingsSection(
            title: '数据库配置',
            icon: Icons.storage_rounded,
            color: const Color(0xFF10B981),
            children: [
              _buildSettingItem('数据库主机', _settings!['database']?['host'] ?? '-'),
              _buildSettingItem('端口', _settings!['database']?['port'] ?? '-'),
              _buildSettingItem('数据库名', _settings!['database']?['name'] ?? '-'),
              _buildSettingItem(
                '连接状态',
                _settings!['database']?['status'] == 'connected' ? '已连接' : '断开',
                valueColor: _settings!['database']?['status'] == 'connected'
                    ? const Color(0xFF10B981)
                    : Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildSettingsSection(
            title: 'AI 配置',
            icon: Icons.psychology_rounded,
            color: const Color(0xFF8B5CF6),
            children: [
              _buildSettingItem('AI 服务商', _settings!['ai']?['provider'] ?? '-'),
              _buildSettingItem('模型', _settings!['ai']?['model'] ?? '-'),
              _buildSettingItem('API 地址', _settings!['ai']?['baseUrl'] ?? '-'),
              _buildSettingItem(
                'API Key',
                _settings!['ai']?['hasApiKey'] == true ? '已配置' : '未配置',
                valueColor: _settings!['ai']?['hasApiKey'] == true
                    ? const Color(0xFF10B981)
                    : Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildSettingsSection(
            title: '京东配置',
            icon: Icons.shopping_bag_rounded,
            color: const Color(0xFFE52B2B),
            children: [
              _buildSettingItem(
                'Cookie 状态',
                _settings!['jd']?['hasCookie'] == true ? '已配置' : '未配置',
                valueColor: _settings!['jd']?['hasCookie'] == true
                    ? const Color(0xFF10B981)
                    : Colors.orange,
              ),
              _buildSettingItem('Cookie 来源', _settings!['jd']?['cookieSource'] ?? '-'),
            ],
          ),
          const SizedBox(height: 20),
          _buildSettingsSection(
            title: '功能开关',
            icon: Icons.toggle_on_rounded,
            color: const Color(0xFFF59E0B),
            children: [
              _buildSettingItem(
                '邮箱验证',
                _settings!['features']?['emailVerification'] == true ? '开启' : '关闭',
                valueColor: _settings!['features']?['emailVerification'] == true
                    ? const Color(0xFF10B981)
                    : Colors.grey,
              ),
              _buildSettingItem(
                '请求限流',
                _settings!['features']?['rateLimit'] == true ? '开启' : '关闭',
                valueColor: _settings!['features']?['rateLimit'] == true
                    ? const Color(0xFF10B981)
                    : Colors.grey,
              ),
            ],
          ),
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
    final deviceType = session['deviceType'] ?? 'unknown';

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
                      session['deviceName'] ?? '未知设备',
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
                  '${session['userNickname']} (${session['userEmail']})',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 2),
                Text(
                  'IP: ${session['ipAddress'] ?? '-'} • 最后活跃: ${_formatDateTime(session['lastActiveAt'])}',
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

  String _formatDateTime(String? dateStr) {
    if (dateStr == null) return '-';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

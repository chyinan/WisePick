import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/login_page.dart';
import '../users/users_page.dart';
import '../cart/cart_page.dart';
import '../conversations/conversations_page.dart';
import '../settings/settings_page.dart';
import '../reliability/reliability_page.dart';
import 'dashboard_service.dart';
import 'widgets/stats_dashboard.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final ApiClient _apiClient;
  late final DashboardService _service;
  late final AuthService _authService;
  
  void _log(String message, {bool isError = false}) {
    final prefix = isError ? '❌ Dashboard' : '📊 Dashboard';
    developer.log('$prefix: $message', name: 'DashboardPage');
  }
  
  /// 安全地将 dynamic 转换为 `List<Map<String, dynamic>>`
  List<Map<String, dynamic>> _safeParseList(dynamic data) {
    if (data == null) return [];
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((item) => item is Map<String, dynamic> 
            ? item 
            : Map<String, dynamic>.from(item))
        .toList();
  }
  
  /// 安全地将 dynamic 转换为 `Map<String, dynamic>`
  Map<String, dynamic> _safeParseMap(dynamic data) {
    if (data == null) return {};
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }
  
  Map<String, dynamic>? _userStats;
  Map<String, dynamic>? _systemStats;
  List<Map<String, dynamic>>? _recentUsers;
  List<Map<String, dynamic>>? _chartData;
  bool _isLoading = true;
  String? _error;
  DateTime? _lastRefresh;
  int _selectedNavIndex = 0;
  
  /// 防止并发加载的锁标志
  bool _isLoadingInProgress = false;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _service = DashboardService(_apiClient);
    _authService = AuthService(_apiClient);
    
    // 连接全局 401 未授权回调，触发自动登出
    _apiClient.onUnauthorized = _handleUnauthorized;
    
    _loadData();
  }
  
  /// 处理 401 未授权错误，执行全局登出
  void _handleUnauthorized() {
    _log('Received 401 unauthorized, triggering logout');
    // 使用 Future.microtask 避免在请求处理中直接导航
    Future.microtask(() async {
      if (!mounted) return;
      await _authService.logout();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    });
  }

  Future<void> _loadData() async {
    // 防止并发请求
    if (_isLoadingInProgress) {
      _log('Skipping load: another load is already in progress');
      return;
    }
    
    _isLoadingInProgress = true;
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _log('Loading dashboard data...');
      // 并行加载所有数据
      final results = await Future.wait([
        _service.getUserStats(),
        _service.getSystemStats(),
        _service.getRecentUsers().catchError((e) {
          _log('Failed to load recent users: $e', isError: true);
          return <Map<String, dynamic>>[];
        }),
        _service.getActivityChart().catchError((e) {
          _log('Failed to load activity chart: $e', isError: true);
          return <Map<String, dynamic>>[];
        }),
      ]);

      if (mounted) {
        setState(() {
          _userStats = _safeParseMap(results[0]);
          _systemStats = _safeParseMap(results[1]);
          _recentUsers = _safeParseList(results[2]);
          _chartData = _safeParseList(results[3]);
          _isLoading = false;
          _lastRefresh = DateTime.now();
        });
        _log('Dashboard data loaded successfully');
      }
    } on ApiException catch (e) {
      _log('Dashboard loading failed (API): ${e.message}', isError: true);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.message;
        });
      }
    } catch (e) {
      _log('Dashboard loading failed (unexpected): $e', isError: true);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '加载数据失败，请稍后重试';
        });
      }
    } finally {
      _isLoadingInProgress = false;
    }
  }

  @override
  void dispose() {
    // 清理 onUnauthorized 回调，避免在 widget 销毁后被调用。
    // 
    // 由于 ApiClient 是单例，多个页面可能设置此回调。
    // 通过检查引用相等性确保只清除本实例设置的回调，
    // 避免意外清除其他页面的回调（边界情况防护）。
    if (_apiClient.onUnauthorized == _handleUnauthorized) {
      _apiClient.onUnauthorized = null;
    }
    super.dispose();
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Row(
        children: [
          // 侧边栏
          _buildSidebar(context),
          // 主内容区
          Expanded(
            child: Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: _buildContent(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
      ),
      child: Column(
        children: [
          // Logo区域
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.shopping_bag_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WisePick',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '管理后台',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 导航菜单
          _buildNavItem(
            icon: Icons.dashboard_rounded,
            label: '数据概览',
            index: 0,
          ),
          _buildNavItem(
            icon: Icons.people_rounded,
            label: '用户管理',
            index: 1,
          ),
          _buildNavItem(
            icon: Icons.shopping_cart_rounded,
            label: '购物车数据',
            index: 2,
          ),
          _buildNavItem(
            icon: Icons.chat_rounded,
            label: '会话记录',
            index: 3,
          ),
          _buildNavItem(
            icon: Icons.settings_rounded,
            label: '系统设置',
            index: 4,
          ),
          
          // 分隔线
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Divider(color: Colors.white.withOpacity(0.1)),
          ),
          
          // 可靠性监控
          _buildNavItem(
            icon: Icons.monitor_heart_rounded,
            label: '可靠性监控',
            index: 5,
          ),
          
          const Spacer(),
          
          // 底部信息
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF334155),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _systemStats != null 
                            ? const Color(0xFF10B981) 
                            : const Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _systemStats != null ? '系统运行正常' : '加载中...',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                if (_lastRefresh != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '更新于 ${_lastRefresh!.hour}:${_lastRefresh!.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // 退出按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: TextButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('退出登录'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF94A3B8),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isActive = _selectedNavIndex == index;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: isActive ? const Color(0xFF6366F1).withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () {
            setState(() => _selectedNavIndex = index);
            if (index == 0) _loadData();
          },
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isActive ? const Color(0xFF6366F1) : const Color(0xFF94A3B8),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: isActive ? const Color(0xFF6366F1) : const Color(0xFF94A3B8),
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _currentPageTitle {
    switch (_selectedNavIndex) {
      case 0: return '数据概览';
      case 1: return '用户管理';
      case 2: return '购物车数据';
      case 3: return '会话记录';
      case 4: return '系统设置';
      case 5: return '可靠性监控';
      default: return '管理后台';
    }
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _currentPageTitle,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '欢迎回来，管理员',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const Spacer(),
          // 刷新按钮
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              onPressed: _isLoading ? null : _loadData,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              tooltip: '刷新数据',
            ),
          ),
          const SizedBox(width: 12),
          // 管理员头像
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.admin_panel_settings_rounded,
                color: Color(0xFF6366F1),
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    // 根据导航索引显示不同内容
    switch (_selectedNavIndex) {
      case 1: // 用户管理
        return const Padding(
          padding: EdgeInsets.all(32),
          child: UsersPage(),
        );
      case 2: // 购物车数据
        return const Padding(
          padding: EdgeInsets.all(32),
          child: CartPage(),
        );
      case 3: // 会话记录
        return const Padding(
          padding: EdgeInsets.all(32),
          child: ConversationsPage(),
        );
      case 4: // 系统设置
        return const Padding(
          padding: EdgeInsets.all(32),
          child: SettingsPage(),
        );
      case 5: // 可靠性监控
        return const ReliabilityPage();
      default: // 数据概览
        return _buildDashboardContent();
    }
  }

  Widget _buildDashboardContent() {
    if (_isLoading && _userStats == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('加载数据中...'),
          ],
        ),
      );
    }

    if (_error != null && _userStats == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              '加载失败',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: StatsDashboard(
        userStats: _userStats ?? {},
        systemStats: _systemStats ?? {},
        recentUsers: _recentUsers,
        chartData: _chartData,
      ),
    );
  }
}

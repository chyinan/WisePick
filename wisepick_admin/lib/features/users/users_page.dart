import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import 'users_service.dart';

/// 用户管理页面
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  late final UsersService _service;

  List<Map<String, dynamic>> _users = [];
  int _total = 0;
  int _currentPage = 1;
  int _totalPages = 1;
  bool _isLoading = true;
  String? _error;
  
  /// 防止并发加载的锁标志
  bool _isLoadingInProgress = false;

  @override
  void initState() {
    super.initState();
    _service = UsersService(ApiClient());
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;
    
    // 防止并发请求
    if (_isLoadingInProgress) return;
    _isLoadingInProgress = true;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _service.getUsers(page: _currentPage);
      if (!mounted) {
        _isLoadingInProgress = false;
        return;
      }

      setState(() {
        _users = _safeGetList(result, 'users');
        _total = _safeGetInt(result, 'total', 0);
        _totalPages = _safeGetInt(result, 'totalPages', 1).clamp(1, 10000);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        _isLoadingInProgress = false;
        return;
      }

      setState(() {
        _isLoading = false;
        _error = _formatErrorMessage(e);
      });
    } finally {
      _isLoadingInProgress = false;
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final userId = _safeGetString(user, 'id');
    if (userId.isEmpty) {
      _showError('无效的用户 ID');
      return;
    }

    final userEmail = _safeGetString(user, 'email', '未知用户');

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除用户 $userEmail 吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _service.deleteUser(userId);
      if (!mounted) return;

      _showSuccess('用户已删除');
      _loadUsers();
    } catch (e) {
      if (!mounted) return;
      _showError('删除失败: ${_formatErrorMessage(e)}');
    }
  }

  Future<void> _editUser(Map<String, dynamic> user) async {
    final userId = _safeGetString(user, 'id');
    if (userId.isEmpty) {
      _showError('无效的用户 ID');
      return;
    }

    final emailController = TextEditingController(
      text: _safeGetString(user, 'email'),
    );
    final nicknameController = TextEditingController(
      text: _safeGetString(user, 'nickname'),
    );

    try {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _EditUserDialog(
          emailController: emailController,
          nicknameController: nicknameController,
        ),
      );

      if (result == null || !mounted) return;

      await _service.updateUser(userId, result);
      if (!mounted) return;

      _showSuccess('用户信息已更新');
      _loadUsers();
    } catch (e) {
      if (!mounted) return;
      _showError('更新失败: ${_formatErrorMessage(e)}');
    } finally {
      emailController.dispose();
      nicknameController.dispose();
    }
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  String _formatErrorMessage(dynamic error) {
    if (error is ApiException) {
      return error.message;
    }
    final str = error.toString();
    // 移除 "Exception: " 前缀
    if (str.startsWith('Exception: ')) {
      return str.substring(11);
    }
    return str;
  }

  List<Map<String, dynamic>> _safeGetList(
    Map<String, dynamic> data,
    String key,
  ) {
    final value = data[key];
    if (value == null) return [];
    if (value is List) {
      // 先过滤出所有 Map 类型，再转换为 Map<String, dynamic>
      // 避免 whereType<Map<String, dynamic>> 过滤掉 Map<dynamic, dynamic>
      return value
          .whereType<Map>()
          .map((item) => item is Map<String, dynamic>
              ? item
              : Map<String, dynamic>.from(item))
          .toList();
    }
    return [];
  }

  int _safeGetInt(Map<String, dynamic> data, String key, int defaultValue) {
    final value = data[key];
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  String _safeGetString(Map<String, dynamic> data, String key, [String defaultValue = '']) {
    final value = data[key];
    if (value == null) return defaultValue;
    return value.toString();
  }

  String _getAvatarInitial(String email) {
    if (email.isEmpty) return '?';
    final firstChar = email[0].toUpperCase();
    // 确保是有效字符
    if (RegExp(r'[A-Z0-9]').hasMatch(firstChar)) {
      return firstChar;
    }
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.people_rounded,
                size: 20,
                color: Color(0xFF6366F1),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '用户管理',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1E293B),
              ),
            ),
            const Spacer(),
            Text(
              '共 $_total 位用户',
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(width: 16),
            IconButton(
              onPressed: _loadUsers,
              icon: _isLoading 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // 用户列表
        Expanded(
          child: _isLoading && _users.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _users.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                          const SizedBox(height: 16),
                          Text('加载失败: $_error'),
                          const SizedBox(height: 16),
                          FilledButton(onPressed: _loadUsers, child: const Text('重试')),
                        ],
                      ),
                    )
                  : _buildUserTable(),
        ),

        // 分页
        if (_totalPages > 1)
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _currentPage > 1
                      ? () {
                          setState(() => _currentPage--);
                          _loadUsers();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                for (final page in _getVisiblePageNumbers())
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: page == -1
                        ? const Text('...', style: TextStyle(color: Color(0xFF64748B)))
                        : _buildPageButton(page),
                  ),
                IconButton(
                  onPressed: _currentPage < _totalPages
                      ? () {
                          setState(() => _currentPage++);
                          _loadUsers();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 计算应该显示的页码列表
  /// 返回页码列表，-1 表示省略号
  List<int> _getVisiblePageNumbers() {
    const int maxVisible = 7; // 最多显示的按钮数（包括省略号）
    
    if (_totalPages <= maxVisible) {
      return List.generate(_totalPages, (i) => i + 1);
    }
    
    final List<int> pages = [];
    
    // 始终显示第一页
    pages.add(1);
    
    // 计算中间显示范围
    int start = _currentPage - 1;
    int end = _currentPage + 1;
    
    // 调整范围确保不超出边界
    if (start <= 2) {
      start = 2;
      end = 4;
    }
    if (end >= _totalPages - 1) {
      end = _totalPages - 1;
      start = _totalPages - 3;
    }
    
    // 如果起始位置离第一页有间隔，添加省略号
    if (start > 2) {
      pages.add(-1); // -1 表示省略号
    }
    
    // 添加中间页码
    for (int i = start; i <= end; i++) {
      if (i > 1 && i < _totalPages) {
        pages.add(i);
      }
    }
    
    // 如果结束位置离最后一页有间隔，添加省略号
    if (end < _totalPages - 1) {
      pages.add(-1);
    }
    
    // 始终显示最后一页
    pages.add(_totalPages);
    
    return pages;
  }

  Widget _buildPageButton(int page) {
    final isActive = page == _currentPage;
    return Material(
      color: isActive ? const Color(0xFF6366F1) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          setState(() => _currentPage = page);
          _loadUsers();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Text(
            '$page',
            style: TextStyle(
              color: isActive ? Colors.white : const Color(0xFF64748B),
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          // 表头
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('邮箱', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF64748B)))),
                Expanded(flex: 2, child: Text('昵称', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF64748B)))),
                Expanded(flex: 2, child: Text('注册时间', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF64748B)))),
                Expanded(flex: 1, child: Text('状态', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF64748B)))),
                SizedBox(width: 100, child: Text('操作', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF64748B)))),
              ],
            ),
          ),
          // 列表
          Expanded(
            child: ListView.builder(
              itemCount: _users.length,
              itemBuilder: (context, index) => _buildUserRow(_users[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserRow(Map<String, dynamic> user) {
    final createdAt = _safeGetString(user, 'createdAt');
    String formattedDate = '未知';
    if (createdAt.isNotEmpty) {
      final date = DateTime.tryParse(createdAt);
      if (date != null) {
        formattedDate = '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} '
            '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }
    }

    final isVerified = user['emailVerified'] == true;
    final status = _safeGetString(user, 'status', 'active');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF6366F1).withOpacity(0.1),
                  child: Text(
                    _getAvatarInitial(_safeGetString(user, 'email')),
                    style: const TextStyle(
                      color: Color(0xFF6366F1),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _safeGetString(user, 'email', '未知邮箱'),
                        style: const TextStyle(color: Color(0xFF1E293B)),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Builder(
                        builder: (context) {
                          final lastLogin = _safeGetString(user, 'lastLoginAt');
                          if (lastLogin.isEmpty) return const SizedBox.shrink();
                          return Text(
                            '最近登录: ${_formatLastLogin(lastLogin)}',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _safeGetString(user, 'nickname', '未设置'),
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              formattedDate,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          Expanded(
            flex: 1,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isVerified 
                        ? const Color(0xFF10B981).withOpacity(0.1)
                        : const Color(0xFFF59E0B).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isVerified ? '已验证' : '未验证',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isVerified 
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF59E0B),
                    ),
                  ),
                ),
                if (status != 'active') ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      status == 'suspended' ? '已暂停' : status,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 100,
            child: Row(
              children: [
                IconButton(
                  onPressed: () => _editUser(user),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  tooltip: '编辑',
                  color: const Color(0xFF6366F1),
                ),
                IconButton(
                  onPressed: () => _deleteUser(user),
                  icon: const Icon(Icons.delete_rounded, size: 18),
                  tooltip: '删除',
                  color: Colors.red,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatLastLogin(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '从未';

    final date = DateTime.tryParse(dateStr);
    if (date == null) return '未知';

    final now = DateTime.now();
    final diff = now.difference(date);

    // 防止负数时间差（时钟偏差）
    if (diff.isNegative) return '刚刚';

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';

    // 安全格式化日期
    return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }
}

/// 编辑用户对话框
class _EditUserDialog extends StatelessWidget {
  final TextEditingController emailController;
  final TextEditingController nicknameController;

  const _EditUserDialog({
    required this.emailController,
    required this.nicknameController,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑用户'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: '邮箱',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nicknameController,
              decoration: const InputDecoration(
                labelText: '昵称',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final email = emailController.text.trim();
            final nickname = nicknameController.text.trim();

            if (email.isEmpty) {
              return; // 不允许空邮箱
            }

            Navigator.pop(context, {
              'email': email,
              'nickname': nickname,
            });
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

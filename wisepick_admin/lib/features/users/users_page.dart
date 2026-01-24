import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import 'users_service.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final _service = UsersService(ApiClient());
  
  List<Map<String, dynamic>> _users = [];
  int _total = 0;
  int _currentPage = 1;
  int _totalPages = 1;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _service.getUsers(page: _currentPage);
      if (mounted) {
        setState(() {
          _users = result['users'];
          _total = result['total'];
          _totalPages = result['totalPages'];
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

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除用户 ${user['email']} 吗？此操作不可恢复。'),
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

    if (confirmed == true) {
      try {
        await _service.deleteUser(user['id']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('用户已删除'), backgroundColor: Colors.green),
          );
          _loadUsers();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _editUser(Map<String, dynamic> user) async {
    final emailController = TextEditingController(text: user['email']);
    final nicknameController = TextEditingController(text: user['nickname']);
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context, {
              'email': emailController.text,
              'nickname': nicknameController.text,
            }),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        await _service.updateUser(user['id'], result);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('用户信息已更新'), backgroundColor: Colors.green),
          );
          _loadUsers();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('更新失败: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
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
                for (int i = 1; i <= _totalPages && i <= 5; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _buildPageButton(i),
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
    final createdAt = user['createdAt'] as String?;
    String formattedDate = '未知';
    if (createdAt != null) {
      final date = DateTime.tryParse(createdAt);
      if (date != null) {
        formattedDate = '${date.year}/${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
      }
    }

    final isVerified = user['emailVerified'] == true;
    final status = user['status'] ?? 'active';

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
                    (user['email'] as String?)?.substring(0, 1).toUpperCase() ?? '?',
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
                        user['email'] as String? ?? '',
                        style: const TextStyle(color: Color(0xFF1E293B)),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (user['lastLoginAt'] != null)
                        Text(
                          '最近登录: ${_formatLastLogin(user['lastLoginAt'])}',
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
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
              user['nickname'] as String? ?? '未设置',
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
    if (dateStr == null) return '从未';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return '未知';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${date.month}/${date.day}';
  }
}

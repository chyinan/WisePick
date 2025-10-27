import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/chat/chat_providers.dart';
import '../features/chat/conversation_model.dart';
import 'user_settings_page.dart';
// import '../features/chat/chat_service.dart';

/// 侧边菜单：展示会话列表并支持新建会话
class HomeDrawer extends ConsumerStatefulWidget {
  const HomeDrawer({super.key});

  @override
  ConsumerState<HomeDrawer> createState() => _HomeDrawerState();
}

class _HomeDrawerState extends ConsumerState<HomeDrawer> {
  final List<ConversationModel> _conversations = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isMultiSelect = false;
  final Set<String> _selectedIds = <String>{};

  List<ConversationModel> get _filteredConversations {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _conversations;
    return _conversations.where((c) => c.title.toLowerCase().contains(q)).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    try {
      final repo = ref.read(conversationRepositoryProvider);
      final list = await repo.listConversations();
      setState(() {
        _conversations.clear();
        _conversations.addAll(list);
      });
    } catch (_) {}
  }

  Future<void> _newConversation() async {
    // 使用 ChatStateNotifier 创建并直接切换到新会话（会保存到仓库），然后关闭抽屉进入聊天界面
    final notifier = ref.read(chatStateNotifierProvider.notifier);
    await notifier.createNewConversation();
    // 刷新本地列表（从仓库重新加载），并立即关闭抽屉以展示新会话
    try {
      final repo = ref.read(conversationRepositoryProvider);
      final list = await repo.listConversations();
      setState(() {
        _conversations.clear();
        _conversations.addAll(list);
      });
    } catch (_) {}
    Navigator.of(context).pop();
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) _selectedIds.remove(id);
      else _selectedIds.add(id);
    });
  }

  Future<void> _exitMultiSelect() async {
    setState(() {
      _isMultiSelect = false;
      _selectedIds.clear();
    });
  }

  Future<void> _bulkDelete() async {
    if (_selectedIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除所选会话'),
        content: Text('确定要删除已选的 ${_selectedIds.length} 个会话吗？此操作无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    final notifier = ref.read(chatStateNotifierProvider.notifier);
    for (final id in List<String>.from(_selectedIds)) {
      await notifier.deleteConversationById(id);
    }
    // reload list
    try {
      final repo = ref.read(conversationRepositoryProvider);
      final list = await repo.listConversations();
      setState(() {
        _conversations.clear();
        _conversations.addAll(list);
        _isMultiSelect = false;
        _selectedIds.clear();
      });
    } catch (_) {
      setState(() {
        _isMultiSelect = false;
        _selectedIds.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              title: Text('对话列表', style: Theme.of(context).textTheme.titleMedium),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(_isMultiSelect ? Icons.close : Icons.delete_outline, color: Theme.of(context).colorScheme.primary),
                    onPressed: () {
                      setState(() {
                        if (_isMultiSelect) {
                          _exitMultiSelect();
                        } else {
                          _isMultiSelect = true;
                        }
                      });
                    },
                    tooltip: _isMultiSelect ? '取消多选' : '批量删除',
                  ),
                  IconButton(onPressed: _newConversation, icon: Icon(Icons.add, color: Theme.of(context).colorScheme.primary)),
                ],
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(hintText: '搜索会话标题', prefixIcon: const Icon(Icons.search)),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredConversations.length,
                itemBuilder: (ctx, idx) {
                  final c = _filteredConversations[idx];
                  final selected = _selectedIds.contains(c.id);
                  return ListTile(
                    leading: _isMultiSelect ? Checkbox(value: selected, onChanged: (_) => _toggleSelect(c.id)) : null,
                    title: Text(c.title, style: Theme.of(context).textTheme.bodyMedium),
                    subtitle: Text('${c.messages.length} 条消息', style: Theme.of(context).textTheme.bodySmall),
                    onTap: () {
                      if (_isMultiSelect) {
                        _toggleSelect(c.id);
                        return;
                      }
                      // 通知 ChatPage 切换会话
                      final notifier = ref.read(chatStateNotifierProvider.notifier);
                      notifier.loadConversation(c);
                      Navigator.of(context).pop();
                    },
                  );
                },
              ),
            ),
            const Divider(),
            // 将设置入口填满宽度，去掉右侧多余间隙，使用内容内边距控制左右间距
            ListTile(
              contentPadding: const EdgeInsetsDirectional.only(start: 12, end: 0),
              leading: Icon(Icons.settings, color: Theme.of(context).colorScheme.primary),
              title: const Text('API设置'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UserSettingsPage()));
              },
            ),
            if (_isMultiSelect)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(child: Text('已选 ${_selectedIds.length} 项')),
                    TextButton(onPressed: _selectedIds.isEmpty ? null : _bulkDelete, child: const Text('删除')),
                    const SizedBox(width: 8),
                    TextButton(onPressed: _exitMultiSelect, child: const Text('取消')),
                  ],
                ),
              )
          ],
        ),
      ),
    );
  }
}


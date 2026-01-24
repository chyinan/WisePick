import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import 'conversations_service.dart';

class ConversationsPage extends StatefulWidget {
  const ConversationsPage({super.key});

  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  final _service = ConversationsService(ApiClient());

  List<Map<String, dynamic>> _conversations = [];
  int _total = 0;
  int _currentPage = 1;
  int _totalPages = 1;
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _selectedConversation;
  List<Map<String, dynamic>>? _messages;
  bool _isLoadingMessages = false;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _service.getConversations(page: _currentPage);
      if (mounted) {
        setState(() {
          _conversations = result['conversations'];
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

  Future<void> _loadMessages(Map<String, dynamic> conversation) async {
    setState(() {
      _selectedConversation = conversation;
      _isLoadingMessages = true;
      _messages = null;
    });

    try {
      final result = await _service.getMessages(conversation['id']);
      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(result['messages'] ?? []);
          _isLoadingMessages = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMessages = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载消息失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteConversation(Map<String, dynamic> conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除会话"${conversation['title']}"吗？所有消息也将被删除。'),
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
        await _service.deleteConversation(conversation['id']);
        if (_selectedConversation?['id'] == conversation['id']) {
          setState(() {
            _selectedConversation = null;
            _messages = null;
          });
        }
        _loadConversations();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('会话已删除'), backgroundColor: Colors.green),
          );
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

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 会话列表
        SizedBox(
          width: 400,
          child: _buildConversationsList(),
        ),
        const SizedBox(width: 24),
        // 消息详情
        Expanded(
          child: _buildMessagesPanel(),
        ),
      ],
    );
  }

  Widget _buildConversationsList() {
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
          // 表头
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.chat_rounded, color: Color(0xFF6366F1)),
                const SizedBox(width: 12),
                const Text(
                  '会话记录',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const Spacer(),
                Text(
                  '共 $_total 条',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _loadConversations,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: '刷新',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 列表
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : _conversations.isEmpty
                        ? _buildEmpty()
                        : ListView.separated(
                            itemCount: _conversations.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final conv = _conversations[index];
                              final isSelected = _selectedConversation?['id'] == conv['id'];
                              return _buildConversationItem(conv, isSelected);
                            },
                          ),
          ),
          // 分页
          if (_totalPages > 1) _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildConversationItem(Map<String, dynamic> conv, bool isSelected) {
    return Material(
      color: isSelected ? const Color(0xFF6366F1).withOpacity(0.08) : Colors.transparent,
      child: InkWell(
        onTap: () => _loadMessages(conv),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF6366F1)
                      : const Color(0xFF6366F1).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.chat_bubble_outline,
                  color: isSelected ? Colors.white : const Color(0xFF6366F1),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conv['title'] ?? '新对话',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${conv['userNickname']} • ${conv['messageCount']} 条消息',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    if (conv['lastMessage'] != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        conv['lastMessage'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatDate(conv['updatedAt']),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 8),
                  IconButton(
                    onPressed: () => _deleteConversation(conv),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: Colors.grey[400],
                    tooltip: '删除',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesPanel() {
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
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                const Icon(Icons.message_rounded, color: Color(0xFF6366F1)),
                const SizedBox(width: 12),
                Expanded(
                  child: _selectedConversation != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedConversation!['title'] ?? '新对话',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            Text(
                              '${_selectedConversation!['userNickname']} (${_selectedConversation!['userEmail']})',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        )
                      : const Text(
                          '消息详情',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                ),
              ],
            ),
          ),
          // 消息列表
          Expanded(
            child: _selectedConversation == null
                ? _buildSelectPrompt()
                : _isLoadingMessages
                    ? const Center(child: CircularProgressIndicator())
                    : _messages == null || _messages!.isEmpty
                        ? _buildNoMessages()
                        : _buildMessagesList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _messages!.length,
      itemBuilder: (context, index) {
        final msg = _messages![index];
        final isUser = msg['role'] == 'user';
        return _buildMessageBubble(msg, isUser);
      },
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isUser) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.smart_toy, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF6366F1) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    msg['content'] ?? '',
                    style: TextStyle(
                      color: isUser ? Colors.white : const Color(0xFF1E293B),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatTime(msg['createdAt']),
                    style: TextStyle(
                      fontSize: 10,
                      color: isUser ? Colors.white60 : Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 12),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 18),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectPrompt() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '选择一个会话查看详情',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildNoMessages() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '暂无消息',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _currentPage > 1
                ? () {
                    setState(() => _currentPage--);
                    _loadConversations();
                  }
                : null,
            icon: const Icon(Icons.chevron_left, size: 20),
          ),
          Text('$_currentPage / $_totalPages', style: const TextStyle(fontSize: 12)),
          IconButton(
            onPressed: _currentPage < _totalPages
                ? () {
                    setState(() => _currentPage++);
                    _loadConversations();
                  }
                : null,
            icon: const Icon(Icons.chevron_right, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loadConversations,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_outlined, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('暂无会话记录', style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '-';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    return '${date.month}/${date.day}';
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return '';
    return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

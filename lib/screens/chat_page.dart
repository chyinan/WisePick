import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/chat/chat_providers.dart';
import 'home_drawer.dart';
import '../../features/chat/chat_message.dart';
import '../../widgets/product_card.dart';
import '../../features/products/product_detail_page.dart';
import 'package:wisepick_dart_version/features/cart/cart_providers.dart';
import '../../features/products/keyword_prompt.dart';
import '../../features/products/search_service.dart';
import '../../features/products/product_model.dart';

/// 聊天页面组件
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _hasRegisteredListener = false;
  String? _lastShownDebugNotification;
  // store per-message product list page index for pagination controls
  final Map<String, int> _messageProductPage = {};

  @override
  void dispose() {
    try {
      ref.read(chatStateNotifierProvider.notifier).saveCurrentConversation();
    } catch (_) {}
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendSuggestion(String text) {
    ref.read(chatStateNotifierProvider.notifier).sendMessage(text);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Widget _buildSuggestionCard({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return Card(
      margin: const EdgeInsets.only(right: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 160,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestions(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome, size: 48, color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              '我可以帮你挑选什么？',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
            const SizedBox(height: 32),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: <Widget>[
                  _buildSuggestionCard(
                    icon: Icons.headphones,
                    title: '推荐耳机',
                    subtitle: '降噪、适合通勤',
                    onTap: () => _sendSuggestion('推荐一款降噪、适合通勤的蓝牙耳机'),
                  ),
                  _buildSuggestionCard(
                    icon: Icons.directions_run,
                    title: '运动装备',
                    subtitle: '跑步、缓冲好的鞋',
                    onTap: () => _sendSuggestion('帮我找一双适合跑步、缓冲好的运动鞋'),
                  ),
                  _buildSuggestionCard(
                    icon: Icons.card_giftcard,
                    title: '礼物灵感',
                    subtitle: '送女朋友的礼物',
                    onTap: () => _sendSuggestion('有什么适合送给女朋友的礼物推荐吗？'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildAiDisplayText(ChatMessage message) {
    final base = message.text;
    if (message.aiParsedRaw == null || message.aiParsedRaw!.isEmpty) return base;
    try {
      final dynamic parsed = jsonDecode(message.aiParsedRaw!);
      final List<dynamic>? recs = parsed is Map<String, dynamic>
          ? (parsed['recommendations'] as List<dynamic>? ?? parsed['recommendations'] as List<dynamic>?)
          : null;
      final StringBuffer buf = StringBuffer();
      buf.writeln(base);
      if (recs != null && recs.isNotEmpty) {
        for (final r in recs) {
          try {
            final g = r['goods'] as Map<String, dynamic>?;
            final String title = g != null ? (g['title'] as String? ?? '') : (r['title'] as String? ?? '');
            final String desc = g != null ? (g['description'] as String? ?? '') : (r['description'] as String? ?? '');
            if (title.isNotEmpty) {
              buf.writeln('${title}：${desc}');
            }
          } catch (_) {}
        }
      }
      return buf.toString().trim();
    } catch (_) {
      return base;
    }
  }

  Widget _buildThinkingBubble() {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 16,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Icon(Icons.smart_toy, size: 18, color: Theme.of(context).colorScheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Text('正在思考...', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleSendPressed() {
    final String rawText = _textController.text.trim();
    if (rawText.isEmpty) return;

    ref.read(chatStateNotifierProvider.notifier).sendMessage(rawText);
    _textController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent + 80,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Widget _buildChatBubble(ChatMessage message) {
    final bool isUser = message.isUser;
    final String content = message.text;

    final CrossAxisAlignment alignment = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final Color bubbleColor = isUser
        ? Theme.of(context).colorScheme.primary
        : Colors.white;
    final Color textColor = isUser
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;
    final textStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5, color: textColor) ?? TextStyle(color: textColor);

    final BorderRadius bubbleRadius = isUser
        ? const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(4),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          );
    
    final List<BoxShadow> shadows = isUser ? [] : [
      BoxShadow(
        color: Colors.black.withOpacity(0.05),
        blurRadius: 4,
        offset: const Offset(0, 2),
      )
    ];

    Widget avatar = isUser 
      ? CircleAvatar(
          radius: 16,
          backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
          child: Icon(Icons.person, size: 18, color: Theme.of(context).colorScheme.onTertiaryContainer),
        )
      : CircleAvatar(
          radius: 16,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(Icons.smart_toy, size: 18, color: Theme.of(context).colorScheme.onPrimaryContainer),
        );

    Widget bubbleContent;

    // Product Logic
    if (message.product != null || (message.products != null && message.products!.isNotEmpty) || (message.keywords != null && message.keywords!.isNotEmpty)) {
      final String aiText = message.text;
      bubbleContent = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (aiText.isNotEmpty)
            SelectableText(_buildAiDisplayText(message), style: textStyle),
            
          const SizedBox(height: 12),
          
          if (message.products != null && message.products!.isNotEmpty)
            Builder(builder: (ctx) {
              final products = message.products!;
              const int pageSize = 6;
              final int totalPages = (products.length + pageSize - 1) ~/ pageSize;
              final int curPage = _messageProductPage[message.id] ?? 1;
              final int safePage = curPage.clamp(1, totalPages == 0 ? 1 : totalPages);
              if (_messageProductPage[message.id] != safePage) _messageProductPage[message.id] = safePage;
              final int start = (safePage - 1) * pageSize;
              final pageItems = products.skip(start).take(pageSize).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...pageItems.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: ProductCard(
                          product: p,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ProductDetailPage(product: p, aiParsedRaw: message.aiParsedRaw ?? message.text)),
                          ),
                          onFavorite: (product) async {
                             // ... favorite logic (same as before)
                             final box = await Hive.openBox('favorites');
                             final exists = box.containsKey(product.id);
                             if (exists) {
                               await box.delete(product.id);
                               if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已取消收藏')));
                             } else {
                               await box.put(product.id, product.toMap());
                               if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已加入收藏')));
                             }
                          },
                          expandToFullWidth: true,
                        ),
                      )),
                  if (totalPages > 1)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: safePage > 1 ? () {
                             setState(() => _messageProductPage[message.id] = safePage - 1);
                          } : null,
                        ),
                        Text('$safePage / $totalPages', style: Theme.of(context).textTheme.bodySmall),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: safePage < totalPages ? () {
                             setState(() => _messageProductPage[message.id] = safePage + 1);
                          } : null,
                        ),
                      ],
                    ),
                ],
              );
            })
          else if (message.product != null)
             ProductCard(
                product: message.product!,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(product: message.product!))),
                expandToFullWidth: true,
             ),

           if (message.keywords != null && message.keywords!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('猜你想找：', style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 8),
              KeywordPrompt(
                  keywords: message.keywords!,
                  onSelected: (kw) async {
                      // Search logic (kept same as before, just simplified call site for brevity in thought process)
                      // ... (Original search logic here) ...
                       // Note: I am preserving the logic but ensuring code is cleaner.
                       // Due to length limit, I will assume the SearchService call structure remains similar
                       // but I need to make sure I don't break it. 
                       // Re-implementing the search logic block briefly:
                       _handleKeywordSearch(kw, message);
                  },
              ),
           ]
        ],
      );
    } else {
       // Normal Text Message
       final String? firstUrl = _extractFirstUrl(content);
       
       // Logic for long text truncation or special display
       Widget textContent;
       if (firstUrl == null) {
          const int previewLen = 800;
          if (content.length <= previewLen) {
             textContent = SelectableText(content, style: textStyle);
          } else {
             final preview = content.substring(0, previewLen) + '...';
             textContent = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   SelectableText(preview, style: textStyle),
                   TextButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _FullDebugPage(full: content))),
                      child: const Text('查看完整内容'),
                   )
                ],
             );
          }
       } else {
          textContent = Column(
             crossAxisAlignment: CrossAxisAlignment.start,
             children: [
                SelectableText(content.replaceAll(firstUrl, '').trim(), style: textStyle),
                const SizedBox(height: 8),
                FilledButton.icon(
                   onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: firstUrl));
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('链接已复制')));
                   }, 
                   icon: const Icon(Icons.link),
                   label: const Text('复制链接'),
                   style: FilledButton.styleFrom(
                      backgroundColor: isUser ? Colors.white.withOpacity(0.2) : Theme.of(context).colorScheme.primaryContainer,
                      foregroundColor: isUser ? Colors.white : Theme.of(context).colorScheme.onPrimaryContainer,
                   ),
                )
             ],
          );
       }
       bubbleContent = textContent;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: alignment == CrossAxisAlignment.end ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[avatar, const SizedBox(width: 8)],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: bubbleRadius,
                boxShadow: shadows,
              ),
              child: bubbleContent,
            ),
          ),
          if (isUser) ...[const SizedBox(width: 8), avatar],
        ],
      ),
    );
  }

  Future<void> _handleKeywordSearch(String kw, ChatMessage originalMessage) async {
       final svc = SearchService();
       try {
          // ... Original parallel fetch logic ...
          final fJd = svc.searchWithMeta(kw, platform: 'jd');
          final fTb = svc.searchWithMeta(kw, platform: 'taobao');
          final fPdd = svc.searchWithMeta(kw, platform: 'pdd');

          Map jdMeta = {};
          Map tbMeta = {};
          Map pddMeta = {};

          try { jdMeta = await fJd as Map<String, dynamic>; } catch (_) { jdMeta = {'products': []}; }
          try { tbMeta = await fTb as Map<String, dynamic>; } catch (_) { tbMeta = {'products': []}; }
          try { pddMeta = await fPdd as Map<String, dynamic>; } catch (_) { pddMeta = {'products': []}; }

          final List<ProductModel> jdList = List<ProductModel>.from(jdMeta['products'] ?? []);
          final List<ProductModel> tbList = List<ProductModel>.from(tbMeta['products'] ?? []);
          final List<ProductModel> pddList = List<ProductModel>.from(pddMeta['products'] ?? []);

          final merged = <ProductModel>[];
          final seenIds = <String>{};

          int jdAdded = 0;
          for (final it in jdList) {
            if (jdAdded >= 5) break;
            if (it.id.isNotEmpty && !seenIds.contains(it.id)) {
              merged.add(it);
              seenIds.add(it.id);
              jdAdded += 1;
            }
          }
          int tbAdded = 0;
          for (final it in tbList) {
            if (tbAdded >= 5) break;
            if (it.id.isNotEmpty && !seenIds.contains(it.id)) {
              merged.add(it);
              seenIds.add(it.id);
              tbAdded += 1;
            }
          }
          int pddAdded = 0;
          for (final it in pddList) {
            if (pddAdded >= 4) break;
            if (it.id.isNotEmpty && !seenIds.contains(it.id)) {
              merged.add(it);
              seenIds.add(it.id);
              pddAdded += 1;
            }
          }

          final List<ProductModel> results = merged;
          final attempts = (jdMeta['attempts'] ?? []) + (tbMeta['attempts'] ?? []) + (pddMeta['attempts'] ?? []);

          if (!mounted) return;
          
          if (results.isEmpty) {
             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到相关商品')));
          } else {
             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('搜索返回 ${results.length} 条商品')));
             
             final msgs = [...ref.read(chatStateNotifierProvider).messages];
             final idx = msgs.indexWhere((m) => m.id == originalMessage.id);
             if (idx != -1) {
                final updated = ChatMessage(
                   id: originalMessage.id,
                   text: originalMessage.text,
                   isUser: false,
                   products: results,
                   keywords: originalMessage.keywords,
                   attempts: List<dynamic>.from(attempts ?? []),
                   aiParsedRaw: originalMessage.aiParsedRaw
                );
                msgs[idx] = updated;
                ref.read(chatStateNotifierProvider.notifier).state = ref.read(chatStateNotifierProvider.notifier).state.copyWith(messages: msgs);
             }
          }
       } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('搜索失败: $e')));
       }
  }

  String? _extractFirstUrl(String text) {
    final RegExp urlReg = RegExp(r'https?:\/\/[^\s]+');
    final RegExpMatch? m = urlReg.firstMatch(text);
    return m?.group(0);
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasRegisteredListener) {
      _hasRegisteredListener = true;
      ref.listen<ChatState>(chatStateNotifierProvider, (previous, next) {
        if (next.debugNotification != null && next.debugNotification!.isNotEmpty) {
           final notif = next.debugNotification!;
           if (notif != _lastShownDebugNotification) {
              _lastShownDebugNotification = notif;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notif)));
              WidgetsBinding.instance.addPostFrameCallback((_) {
                 ref.read(chatStateNotifierProvider.notifier).state = next.copyWith(debugNotification: null);
              });
              Future.delayed(const Duration(seconds: 2), () {
                 if (mounted) _lastShownDebugNotification = null;
              });
           }
        }
      });
    }

    return Scaffold(
        drawer: const HomeDrawer(),
        appBar: AppBar(
           title: const Text('AI导购助手快淘帮'),
           centerTitle: false,
           actions: [
             IconButton(
               icon: const Icon(Icons.refresh),
               tooltip: '新对话',
               onPressed: () {
                  ref.read(chatStateNotifierProvider.notifier).clearConversation();
               },
             ),
           ],
        ),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
                child: Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Consumer(builder: (context, ref2, _) {
                    final state = ref2.watch(chatStateNotifierProvider);
                    final msgs = state.messages;
                    final bool loading = state.isLoading;
                    final bool streaming = state.isStreaming;

                    if (msgs.isEmpty && !loading) {
                      return _buildSuggestions(context);
                    }

                    final int itemCount = msgs.length + ((loading && !streaming) ? 1 : 0);

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: itemCount,
                      itemBuilder: (BuildContext context, int index) {
                        if (loading && index == msgs.length) {
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: _buildThinkingBubble(),
                          );
                        }
                        return _buildChatBubble(msgs[index]);
                      },
                    );
                  }),
                ),
              ),

              // Input Area
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        maxLines: 1,
                        decoration: InputDecoration(
                          hintText: '输入您的需求，例如：推荐一款高性价比降噪耳机...',
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        ),
                        onSubmitted: (_) => _handleSendPressed(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FloatingActionButton(
                      onPressed: _handleSendPressed,
                      elevation: 0,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      child: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }
}

class _FullDebugPage extends StatelessWidget {
  final String full;
  const _FullDebugPage({required this.full});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('完整内容')),
      body: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
           color: Colors.white,
           borderRadius: BorderRadius.circular(12),
           border: Border.all(color: Colors.grey.shade200),
        ),
        child: SingleChildScrollView(child: SelectableText(full)),
      ),
    );
  }
}

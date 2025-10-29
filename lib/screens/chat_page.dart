// ignore_for_file: unused_element

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

/// 聊天页面组件（从 main.dart 拆分出来）
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
    // autosave current conversation when widget is disposed
    try {
      ref.read(chatStateNotifierProvider.notifier).saveCurrentConversation();
    } catch (_) {}
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // 新增：当用户点击建议时，发送消息
  void _sendSuggestion(String text) {
    ref.read(chatStateNotifierProvider.notifier).sendMessage(text);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  // 新增：构建单个建议卡片
  Widget _buildSuggestionCard({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    // 使用 SizedBox 设定固定宽度，避免被 Expanded 拉伸
    return SizedBox(
      width: 140, // 为卡片设置一个合适的固定宽度
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
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

  // 新增：构建建议区域的整体布局
  Widget _buildSuggestions(BuildContext context) {
    // 使用 Column 将建议推到底部，避免在 Expanded 中被拉伸
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // 为滚动视图的左右添加内边距
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: <Widget>[
              _buildSuggestionCard(
                title: '推荐一款耳机',
                subtitle: '降噪、适合通勤',
                onTap: () => _sendSuggestion('推荐一款降噪、适合通勤的蓝牙耳机'),
              ),
              const SizedBox(width: 12),
              _buildSuggestionCard(
                title: '寻找运动鞋',
                subtitle: '适合跑步、缓冲好',
                onTap: () => _sendSuggestion('帮我找一双适合跑步、缓冲好的运动鞋'),
              ),
              const SizedBox(width: 12),
              _buildSuggestionCard(
                title: '有什么礼物推荐',
                subtitle: '送女朋友的礼物',
                onTap: () => _sendSuggestion('有什么适合送给女朋友的礼物推荐吗？'),
              ),
            ],
          ),
        ),
        // 预留一些空间，避免紧贴输入框
        const SizedBox(height: 24),
      ],
    );
  }

  // 构建 AI 展示文本：若消息包含结构化 aiParsedRaw 并包含 recommendations，则在原始文本下追加每条商品的描述
  String _buildAiDisplayText(ChatMessage message) {
    final base = message.text;
    if (message.aiParsedRaw == null || message.aiParsedRaw!.isEmpty) return base;
    try {
      final dynamic parsed = jsonDecode(message.aiParsedRaw!);
      // 支持两种字段命名：recommendations 或 recommendations
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  /// 思考中的占位气泡（带简单动效）
  Widget _buildThinkingBubble() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 8,
                  height: 8,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Text('正在思考中...', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
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

    // 通过 provider 发送消息；provider 会负责向 AI 请求回复并更新 state
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
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final Color textColor = isUser
        ? Theme.of(context).colorScheme.onPrimaryContainer
        : Theme.of(context).colorScheme.onSurface;
    final textStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.3, color: textColor) ?? TextStyle(color: textColor);

    final BorderRadius bubbleRadius = isUser
        ? const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
            bottomLeft: Radius.circular(12),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
            bottomRight: Radius.circular(12),
          );

    // 如果消息包含 product 或 products 列表，则先展示 AI 的文字说明（如果存在），再展示 ProductCard
    if (message.product != null || (message.products != null && message.products!.isNotEmpty) || (message.keywords != null && message.keywords!.isNotEmpty)) {
      final String aiText = message.text;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        child: Column(
          crossAxisAlignment: alignment,
          children: <Widget>[
            // 先展示 AI 的文本输出（如：分析与推荐理由），支持选择与复制
            if (aiText.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 显示给用户的文本（可能经过格式化）
                    Expanded(child: SelectableText(_buildAiDisplayText(message), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface))),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '复制',
                      onPressed: () async {
                        // 根据设置决定复制展示文本还是复制 AI 的完整原始返回
                        final settingsBox = await Hive.openBox('settings');
                        final bool copyFull = settingsBox.get('copy_full_return') as bool? ?? false;
                        final String toCopy = copyFull ? (message.aiParsedRaw ?? aiText) : _buildAiDisplayText(message);
                        await Clipboard.setData(ClipboardData(text: toCopy));
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(copyFull ? '已复制完整返回内容' : '已复制AI返回内容')));
                      },
                      icon: const Icon(Icons.copy),
                    ),
                  ],
                ),
              ),
            if (message.products != null && message.products!.isNotEmpty) ...[
              // Paginated product list per message: show a page of items and pagination controls
              Builder(builder: (ctx) {
                final products = message.products!;
                const int pageSize = 6; // items per page
                final int totalPages = (products.length + pageSize - 1) ~/ pageSize;
                final int curPage = _messageProductPage[message.id] ?? 1;
                final int safePage = curPage.clamp(1, totalPages == 0 ? 1 : totalPages);
                // ensure stored value is within bounds
                if (_messageProductPage[message.id] != safePage) _messageProductPage[message.id] = safePage;
                final int start = (safePage - 1) * pageSize;
                final pageItems = products.skip(start).take(pageSize).toList();

                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // product cards for current page
                  ...pageItems.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                          child: ProductCard(
                          product: p,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ProductDetailPage(product: p, aiParsedRaw: message.aiParsedRaw ?? message.text)),
                          ),
                          onFavorite: (product) async {
                            final box = await Hive.openBox('favorites');
                            final exists = box.containsKey(product.id);
                            if (exists) {
                              await box.delete(product.id);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已取消收藏')));
                            } else {
                              await box.put(product.id, product.toMap());
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已加入收藏')));
                            }
                          },
                          expandToFullWidth: true,
                        ),
                      )),

                  // pagination controls row
                  if (totalPages > 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 分页按钮行：上一页、页码、下一页（靠右）
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: safePage > 1
                                    ? () {
                                        setState(() {
                                          _messageProductPage[message.id] = safePage - 1;
                                        });
                                        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                                      }
                                    : null,
                                child: const Text('上一页'),
                              ),
                              const SizedBox(width: 8),
                              Text('第${safePage}/${totalPages}页', style: Theme.of(context).textTheme.bodyMedium),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: safePage < totalPages
                                    ? () {
                                        setState(() {
                                          _messageProductPage[message.id] = safePage + 1;
                                        });
                                        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                                      }
                                    : null,
                                child: const Text('下一页'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // 单独一行显示淡色注释，移动设备友好
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4.0),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceVariant,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '商品搜索结果为官方平台返回，本软件不保证精准',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ]);
              }),
            ]
            else if (message.product != null)
              ProductCard(
                product: message.product!,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ProductDetailPage(product: message.product!)),
                ),
                onFavorite: (product) async {
                  final box = await Hive.openBox('favorites');
                  final exists = box.containsKey(product.id);
                  if (exists) {
                    await box.delete(product.id);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已取消收藏')));
                  } else {
                    await box.put(product.id, product.toMap());
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已加入收藏')));
                  }
                },
                expandToFullWidth: true,
              ),
            // 如果 AI 返回关键词建议，展示 标签 + KeywordPrompt
            if (message.keywords != null && message.keywords!.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'AI智能搜索推荐：',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: KeywordPrompt(
                  keywords: message.keywords!,
                  onSelected: (kw) async {
                    // 点击后调用后端搜索并把结果插入到当前消息（替换关键词提示）
                    // 为确保包含拼多多结果，向后端明确传递 platform=pdd
                    final svc = SearchService();
                    try {
                      // 并行获取 JD、Taobao、PDD，各平台单独请求以便后续合并和优先级控制
                      final fJd = svc.searchWithMeta(kw, platform: 'jd');
                      final fTb = svc.searchWithMeta(kw, platform: 'taobao');
                      final fPdd = svc.searchWithMeta(kw, platform: 'pdd');

                      Map jdMeta = {};
                      Map tbMeta = {};
                      Map pddMeta = {};

                      try {
                        jdMeta = await fJd as Map<String, dynamic>;
                      } catch (_) {
                        jdMeta = {'products': []};
                      }
                      try {
                        tbMeta = await fTb as Map<String, dynamic>;
                      } catch (_) {
                        tbMeta = {'products': []};
                      }
                      try {
                        pddMeta = await fPdd as Map<String, dynamic>;
                      } catch (_) {
                        pddMeta = {'products': []};
                      }

                      final List<ProductModel> jdList = List<ProductModel>.from(jdMeta['products'] ?? []);
                      final List<ProductModel> tbList = List<ProductModel>.from(tbMeta['products'] ?? []);
                      final List<ProductModel> pddList = List<ProductModel>.from(pddMeta['products'] ?? []);

                      // 合并：优先 JD -> Taobao -> PDD（但 PDD 最多展示 4 个，且去重）
                      final merged = <ProductModel>[];
                      final seenIds = <String>{};

                      int jdAdded = 0;
                      for (final it in jdList) {
                        if (jdAdded >= 5) break; // JD 最多 5 个
                        if (it.id.isNotEmpty && !seenIds.contains(it.id)) {
                          merged.add(it);
                          seenIds.add(it.id);
                          jdAdded += 1;
                        }
                      }
                      int tbAdded = 0;
                      for (final it in tbList) {
                        if (tbAdded >= 5) break; // Taobao 最多 5 个
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
                      if (results.isEmpty) {
                        if (!mounted) return;
                        // transient notification only; do not append a failure line to the chat bubble
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到相关商品')));
                        // keep keywords and attempts in message metadata but avoid modifying visible text
                        final msgs = [...ref.read(chatStateNotifierProvider).messages];
                        final idx = msgs.indexWhere((m) => m.id == message.id);
                        if (idx != -1) {
                          final updated = ChatMessage(
                              id: message.id,
                              text: message.text,
                              isUser: false,
                              products: results,
                              keywords: message.keywords,
                              attempts: List<dynamic>.from(attempts ?? []));
                          msgs[idx] = updated;
                          ref.read(chatStateNotifierProvider.notifier).state = ref.read(chatStateNotifierProvider.notifier).state.copyWith(messages: msgs);
                        }
                      } else {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('搜索返回 ${results.length} 条商品')));
                        // 将当前消息替换为包含 products 的消息，同时保留 keywords
                        final msgs = [...ref.read(chatStateNotifierProvider).messages];
                        final idx = msgs.indexWhere((m) => m.id == message.id);
                        if (idx != -1) {
                          final updated = ChatMessage(
                              id: message.id,
                              text: message.text,
                              isUser: false,
                              products: results,
                              keywords: message.keywords,
                              attempts: List<dynamic>.from(attempts ?? []),
                              aiParsedRaw: message.aiParsedRaw);
                          msgs[idx] = updated;
                          final notifier = ref.read(chatStateNotifierProvider.notifier);
                          notifier.state = notifier.state.copyWith(messages: msgs);
                          // persist the updated conversation so product list and aiParsedRaw survive navigation
                          try {
                            await notifier.saveCurrentConversation();
                          } catch (_) {}
                        }
                      }
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('搜索失败：${e.toString()}')));
                    }
                  },
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              _formatTimestamp(message.timestamp),
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    // 普通文本消息
    final String? firstUrl = _extractFirstUrl(content);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      child: Column(
        crossAxisAlignment: alignment,
        children: <Widget>[
          Container(
            constraints: const BoxConstraints(maxWidth: 520),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: bubbleRadius,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: firstUrl == null
                ? (() {
                    const int previewLen = 800;
                    // 对超长文本只渲染预览，避免一次性渲染超长单行导致布局卡顿
                    if (content.length <= previewLen) {
                      return SelectableText(content, style: textStyle);
                    }
                    final preview = content.substring(0, previewLen) + '\n\n[调试内容已截断，点击展开查看完整内容]';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SelectableText(preview, style: textStyle),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            TextButton(
                              onPressed: () {
                                if (!mounted) return;
                                Navigator.of(context).push(MaterialPageRoute(builder: (_) => _FullDebugPage(full: content)));
                              },
                              child: const Text('展开'),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: '复制全部',
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: content));
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制完整返回信息')));
                              },
                              icon: const Icon(Icons.copy),
                            ),
                          ],
                        ),
                      ],
                    );
                  })()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SelectableText(content.replaceAll(firstUrl, '').trim(), style: textStyle),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          ElevatedButton.icon(
                          onPressed: () async {
                              String copyUrl = firstUrl;
                              try {
                                final box = await Hive.openBox('settings');
                                final String? tpl = box.get('affiliate_api') as String?;
                                if (tpl != null && tpl.isNotEmpty && copyUrl.isNotEmpty) {
                                  if (tpl.contains('{url}')) {
                                    copyUrl = tpl.replaceAll('{url}', Uri.encodeComponent(copyUrl));
                                  } else if (tpl.contains('{{url}}')) {
                                    copyUrl = tpl.replaceAll('{{url}}', Uri.encodeComponent(copyUrl));
                                  } else {
                                    if (tpl.contains('?')) {
                                      copyUrl = '$tpl&url=${Uri.encodeComponent(copyUrl)}';
                                    } else {
                                      copyUrl = '$tpl?url=${Uri.encodeComponent(copyUrl)}';
                                    }
                                  }
                                }
                              } catch (_) {}
                              await Clipboard.setData(ClipboardData(text: copyUrl));
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('下单链接已复制，打开浏览器完成下单')));
                            },
                icon: const Icon(Icons.shopping_cart_checkout),
                            label: Text('去下单', style: Theme.of(context).textTheme.labelLarge),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: '复制链接',
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: firstUrl));
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('链接已复制到剪贴板')));
                            },
                            icon: const Icon(Icons.copy),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatTimestamp(message.timestamp),
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          // 如果消息发送失败，显示重试按钮
          if (message.failed && message.retryForText != null)
            TextButton.icon(
              onPressed: () => _retryMessage(message),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  void _retryMessage(ChatMessage failedMessage) {
    final String? original = failedMessage.retryForText;
    if (original == null) return;
    // set state by sending the original text again (notifier will append and persist)
    ref.read(chatStateNotifierProvider.notifier).sendMessage(original);
  }

  /// 从文本中提取第一个 URL（若存在），返回 null 表示未找到
  String? _extractFirstUrl(String text) {
    final RegExp urlReg = RegExp(r'https?:\/\/[^\s]+');
    final RegExpMatch? m = urlReg.firstMatch(text);
    return m?.group(0);
  }

  // 保留时间格式化函数，可能在未来消息模型中使用
  String _formatTimestamp(DateTime timestamp) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(timestamp.hour)}:${twoDigits(timestamp.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    // 注册一次性的 state 监听器（避免在每次 build 时重复注册）
    if (!_hasRegisteredListener) {
      _hasRegisteredListener = true;
      ref.listen<ChatState>(chatStateNotifierProvider, (previous, next) {
      if (next.debugNotification != null && next.debugNotification!.isNotEmpty) {
        // 防止重复每秒弹出：只有当通知内容与上一次不同且距离上次显示超过 2 秒时才显示
        final notif = next.debugNotification!;
        final shouldShow = notif != _lastShownDebugNotification;
        if (shouldShow) {
          _lastShownDebugNotification = notif;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notif)));
          // 异步清空通知字段，避免在 listener 中同步修改 provider 导致重入
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              final notifier = ref.read(chatStateNotifierProvider.notifier);
              notifier.state = notifier.state.copyWith(debugNotification: null);
            } catch (_) {}
          });
          // 2 秒后允许再次显示同样的通知
          Future.delayed(const Duration(seconds: 2), () {
            try {
              if (mounted) _lastShownDebugNotification = null;
            } catch (_) {}
          });
        }
      }
      // debugFullResponse 由 UI 层显示为固定复制条，listener 不再弹窗或自动清除，避免重入或卡顿
      });
    }
    return Scaffold(
        drawer: const HomeDrawer(),
        appBar: AppBar(
          title: Text('快淘帮', style: Theme.of(context).textTheme.titleMedium),
          centerTitle: true,
          leading: Builder(
            builder: (ctx) => IconButton(
              icon: Icon(Icons.menu, color: Theme.of(context).colorScheme.onSurface),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
              tooltip: '对话列表',
            ),
          ),
          // autosave is enabled; manual save button removed
        ),
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
                child: Container(
                  color: Theme.of(context).colorScheme.surface,
                  child: Consumer(builder: (context, ref2, _) {
                    final state = ref2.watch(chatStateNotifierProvider);
                    final msgs = state.messages;
                    final bool loading = state.isLoading;
                    final bool streaming = state.isStreaming;

                    // 当聊天记录为空且不在加载时，显示建议
                    if (msgs.isEmpty && !loading) {
                      return _buildSuggestions(context);
                    }

                    // only show the generic thinking bubble when not streaming and loading is true
                    final int itemCount = msgs.length + ((loading && !streaming) ? 1 : 0);

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: itemCount,
                      itemBuilder: (BuildContext context, int index) {
                        // 如果是 loading 占位（放在末尾）
                        if (loading && index == msgs.length) {
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: _buildThinkingBubble(),
                          );
                        }

                        final ChatMessage message = msgs[index];
                        return Align(
                          alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
                          child: _buildChatBubble(message),
                        );
                      },
                    );
                  }),
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                color: Theme.of(context).colorScheme.surface,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 150),
                        child: TextField(
                          controller: _textController,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          decoration: InputDecoration(
                            hintText: '请输入你的需求',
                            border: const OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(12)),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Theme.of(context).inputDecorationTheme.fillColor ?? Theme.of(context).colorScheme.surfaceContainerHighest,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          onSubmitted: (_) => _handleSendPressed(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: Theme.of(context).colorScheme.primary,
                      shape: const CircleBorder(),
                      child: IconButton(
                        onPressed: _handleSendPressed,
                        icon: Icon(Icons.send, color: Theme.of(context).colorScheme.onPrimary),
                      ),
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

/// 独立页面用于显示完整调试文本，放在新的路由以避免对主页面造成渲染压力
class _FullDebugPage extends StatelessWidget {
  final String full;
  const _FullDebugPage({required this.full});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('完整 AI 返回')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: SelectableText(full),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: full));
          if (!Navigator.of(context).mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制完整返回信息到剪贴板')));
        },
        label: const Text('复制全部'),
        icon: const Icon(Icons.copy),
      ),
    );
  }
}


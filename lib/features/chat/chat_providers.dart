import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/api_client.dart';
import 'chat_service.dart';
import 'conversation_model.dart';
import 'chat_message.dart';
import '../products/product_model.dart';
import 'conversation_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'dart:convert'; // Added for jsonDecode
import 'dart:async';

/// 提供 ChatService 的 Provider
final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService(client: ApiClient());
});

/// 聊天状态（结构化消息列表）
class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final bool isStreaming;
  final String? currentConversationId;
  final String? currentConversationTitle;
  // 用于在 UI 端触发一次性提示（例如复制完整返回到剪贴板后显示提示）
  final String? debugNotification;
  // debug 模式下，provider 将完整返回文本放到这里，由 UI 层负责写入剪贴板
  final String? debugFullResponse;
  // 如果为 true 表示标题已由 AI 明确提取并锁定，不会被自动生成逻辑覆盖
  final bool isTitleLocked;

  ChatState({List<ChatMessage>? messages, this.isLoading = false, this.isStreaming = false, this.currentConversationId, this.currentConversationTitle, this.debugNotification, this.debugFullResponse, this.isTitleLocked = false}) : messages = messages ?? <ChatMessage>[];

  ChatState copyWith({List<ChatMessage>? messages, bool? isLoading, bool? isStreaming, String? currentConversationId, String? currentConversationTitle, String? debugNotification, String? debugFullResponse, bool? isTitleLocked}) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isStreaming: isStreaming ?? this.isStreaming,
      currentConversationId: currentConversationId ?? this.currentConversationId,
      currentConversationTitle: currentConversationTitle ?? this.currentConversationTitle,
      debugNotification: debugNotification ?? this.debugNotification,
      debugFullResponse: debugFullResponse ?? this.debugFullResponse,
      isTitleLocked: isTitleLocked ?? this.isTitleLocked,
    );
  }
}

/// 使用 StateNotifier 管理聊天状态（结构化消息）
class ChatStateNotifier extends StateNotifier<ChatState> {
  final ChatService service;
  final Ref _ref;

  ChatStateNotifier({required this.service, required Ref ref}) : _ref = ref, super(ChatState());

  /// 发送用户消息并请求 AI 推荐（AI 回复可能包含 ProductModel 信息）
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    // Ensure there is a conversation id so the conversation is persisted
    // when sending messages from places that didn't explicitly create a
    // conversation (e.g. home suggestion chips).
    if (state.currentConversationId == null) {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      state = state.copyWith(currentConversationId: id, currentConversationTitle: '新对话');
      try {
        final repo = _ref.read(conversationRepositoryProvider);
        final conv = ConversationModel(id: id, title: '新对话', messages: []);
        await repo.saveConversation(conv);
      } catch (_) {}
    }

    // 添加用户消息结构体
    final userMsg = ChatMessage(id: DateTime.now().microsecondsSinceEpoch.toString(), text: text, isUser: true);
    state = state.copyWith(messages: [...state.messages, userMsg]);

    // 发起 AI 请求：使用流式时设置 isStreaming 并保持 isLoading=true（显示“正在思考中...”动效）
    state = state.copyWith(isStreaming: true, isLoading: true);
    // We'll try to stream the AI reply (incremental updates). If streaming, replace the loading bubble with a placeholder message
    ChatMessage placeholder = ChatMessage(id: DateTime.now().microsecondsSinceEpoch.toString(), text: '', isUser: false);
    // keep the generic loading bubble visible while adding the placeholder for incremental updates
    state = state.copyWith(isLoading: true, isStreaming: true, messages: [...state.messages, placeholder]);

    String buffer = '';
    bool failed = false;
    // Throttle helpers to avoid updating state too frequently during streaming
    Timer? pendingUpdateTimer;
    List<ChatMessage>? latestScheduledMsgs;
    DateTime lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    // cache keywords extracted during streaming so we can preserve them if final parse
    // does not produce explicit keywords
    List<String> streamingKeywordsCache = [];

    void scheduleMessagesUpdate(List<ChatMessage> msgs) {
      final now = DateTime.now();
      if (now.difference(lastUpdate) >= const Duration(milliseconds: 100)) {
        state = state.copyWith(messages: msgs);
        lastUpdate = now;
      } else {
        latestScheduledMsgs = msgs;
        pendingUpdateTimer?.cancel();
        pendingUpdateTimer = Timer(const Duration(milliseconds: 100), () {
          try {
            state = state.copyWith(messages: latestScheduledMsgs ?? msgs);
          } catch (_) {}
          lastUpdate = DateTime.now();
          pendingUpdateTimer = null;
        });
      }
    }
    // Quick extraction of candidate keywords from partial AI text (streaming)
    List<String> quickExtractKeywords(String text) {
      try {
        final kws = <String>[];
        // Try nested goods.title first
        final goodsTitleReg = RegExp(r'"goods"\s*:\s*\{[^}]*"title"\s*:\s*"([^"]+)"', multiLine: true);
        for (final m in goodsTitleReg.allMatches(text)) {
          final s = m.group(1)?.trim();
          if (s != null && s.isNotEmpty && !kws.contains(s)) {
            kws.add(s);
            if (kws.length >= 6) return kws;
          }
        }
        // Fallback: generic title fields
        final titleReg = RegExp(r'"title"\s*:\s*"([^"]{3,120})"', multiLine: true);
        for (final m in titleReg.allMatches(text)) {
          final s = m.group(1)?.trim();
          if (s != null && s.isNotEmpty && !kws.contains(s)) {
            kws.add(s);
            if (kws.length >= 6) return kws;
          }
        }
        return kws;
      } catch (_) {
        return <String>[];
      }
    }

    // Derive concise keywords from a parsedMap recommendations list
    List<String> deriveKeywordsFromParsedMap(Map<String, dynamic>? pm) {
      final out = <String>[];
      if (pm == null) return out;
      try {
        if (pm.containsKey('keywords') && pm['keywords'] is List) {
          for (final k in (pm['keywords'] as List)) {
            if (k is String) {
              final s = k.trim();
              if (s.isNotEmpty && !out.contains(s)) out.add(s);
              if (out.length >= 6) return out;
            }
          }
        }
      } catch (_) {}

      try {
        if (pm.containsKey('recommendations') && pm['recommendations'] is List) {
          for (final rec in (pm['recommendations'] as List)) {
            try {
              if (rec is Map<String, dynamic>) {
                String? s;
                if (rec.containsKey('goods') && rec['goods'] is Map && rec['goods']['title'] is String) {
                  s = (rec['goods']['title'] as String).trim();
                }
                if ((s == null || s.isEmpty) && rec.containsKey('title') && rec['title'] is String) {
                  s = (rec['title'] as String).trim();
                }
                if (s != null && s.isNotEmpty) {
                  if (!out.contains(s)) out.add(s);
                }
              } else if (rec is String) {
                final s = rec.trim();
                if (s.isNotEmpty && !out.contains(s)) out.add(s);
              }
            } catch (_) {}
            if (out.length >= 6) break;
          }
        }
      } catch (_) {}

      return out;
    }
    try {
      // Decide whether to include title instruction in the messages: only include on first user message in a conversation
      bool includeTitleInstruction = false;
      try {
        if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
        // If this is the first user message in current conversation (no previous AI replies), include title instruction
        includeTitleInstruction = state.messages.where((m) => !m.isUser).isEmpty;
      } catch (_) {}

      final stream = await service.getAiReplyStream(text /* messages built inside service */, includeTitleInstruction: includeTitleInstruction);
      String pending = '';
      // flush when encountering sentence end punctuation or when pending grows too large
      const int pendingFlushThreshold = 60;
      await for (final chunk in stream) {
        pending += chunk;
        // find last sentence-ending punctuation
        final punctuationIdx = () {
          for (int i = pending.length - 1; i >= 0; i--) {
            final c = pending[i];
            if (c == '。' || c == '？' || c == '！' || c == '?' || c == '!' || c == '.' || c == '\n') return i;
          }
          return -1;
        }();

        int flushLen = 0;
        if (punctuationIdx >= 0) {
          flushLen = punctuationIdx + 1;
        } else if (pending.length > pendingFlushThreshold) {
          flushLen = pendingFlushThreshold;
        }

          if (flushLen > 0) {
          final toFlush = pending.substring(0, flushLen);
          buffer += toFlush;
          pending = pending.substring(flushLen);
          // update last message with flushed buffer plus remaining pending as ephemeral
          final displayed = buffer + pending;
          final msgs = [...state.messages];
          final lastIdx = msgs.length - 1;
          final kw = quickExtractKeywords(displayed);
          if (kw.isNotEmpty) streamingKeywordsCache = kw;
          final updated = ChatMessage(id: msgs[lastIdx].id, text: displayed, isUser: false, keywords: kw);
          msgs[lastIdx] = updated;
          scheduleMessagesUpdate(msgs);
        } else {
          // if nothing to flush yet, optionally update ephemeral preview every few chars to show typing
          if (pending.length % 20 == 0) {
            final displayed = buffer + pending;
            final msgs = [...state.messages];
            final lastIdx = msgs.length - 1;
            final kw = quickExtractKeywords(displayed);
            if (kw.isNotEmpty) streamingKeywordsCache = kw;
            final updated = ChatMessage(id: msgs[lastIdx].id, text: displayed, isUser: false, keywords: kw);
            msgs[lastIdx] = updated;
            scheduleMessagesUpdate(msgs);
          }
        }
      }
      // stream done: flush remaining pending
      if (pending.isNotEmpty) {
        buffer += pending;
        pending = '';
        final msgs = [...state.messages];
        final lastIdx = msgs.length - 1;
        final finalKw = quickExtractKeywords(buffer);
        if (finalKw.isNotEmpty) streamingKeywordsCache = finalKw;
        msgs[lastIdx] = ChatMessage(id: msgs[lastIdx].id, text: buffer, isUser: false, keywords: finalKw);
        // ensure any pending timer is flushed and apply final streaming update
        pendingUpdateTimer?.cancel();
        if (latestScheduledMsgs != null) {
          state = state.copyWith(messages: latestScheduledMsgs!);
        }
        state = state.copyWith(messages: msgs);
      }

      // 标题提取逻辑已移至解析 metaText 之后以便同时从 buffer 与 metaText 中查找

      // streaming completed; if buffer empty treat as failure
      if (buffer.trim().isEmpty) {
        failed = true;
        buffer = 'AI 未返回内容，请重试。';
      }
    } catch (e) {
      failed = true;
      buffer = 'AI 服务调用失败：${e.toString()}';
      // update last message with error text and clear streaming flag
      final msgs = [...state.messages];
      final lastIdx = msgs.length - 1;
      msgs[lastIdx] = ChatMessage(id: msgs[lastIdx].id, text: buffer, isUser: false, failed: true, retryForText: text);
      state = state.copyWith(isStreaming: false, messages: msgs);
    }

    // After streaming finishes (or failed), attempt to parse buffer for product link
    ChatMessage finalMsg;
    try {
      // Remove debug prefix if present
      var cleaned = buffer;
      const prefix = '原始AI返回(JSON)：';
      if (cleaned.startsWith(prefix)) {
        final idx = cleaned.indexOf('\n\n');
        if (idx >= 0) cleaned = cleaned.substring(idx + 2);
      }

      // Try to robustly extract the first JSON object from the cleaned string
      Map<String, dynamic>? parsedMap;
      try {
        // strip common debug prefixes
        const prefix1 = '原始AI返回(JSON)：';
        const prefix2 = '原始请求(JSON)：';
        if (cleaned.startsWith(prefix1)) {
          final idx = cleaned.indexOf('\n\n');
          if (idx >= 0) cleaned = cleaned.substring(idx + 2);
        } else if (cleaned.startsWith(prefix2)) {
          final idx = cleaned.indexOf('\n\n');
          if (idx >= 0) cleaned = cleaned.substring(idx + 2);
        }

        // Try to find a JSON object that contains 'recommendations'. Scan multiple '{' starts.
        final starts = <int>[];
        for (int i = 0; i < cleaned.length; i++) {
          if (cleaned[i] == '{') starts.add(i);
        }
        for (final startIdx in starts) {
          int depth = 0;
          bool inString = false;
          bool escape = false;
          int endIdx = -1;
          for (int i = startIdx; i < cleaned.length; i++) {
            final ch = cleaned[i];
            if (escape) { escape = false; continue; }
            if (ch == '\\') { escape = true; continue; }
            if (ch == '"') { inString = !inString; continue; }
            if (inString) continue;
            if (ch == '{') depth++; else if (ch == '}') depth--;
            if (depth == 0) { endIdx = i; break; }
          }
          if (endIdx != -1) {
            final jsonSub = cleaned.substring(startIdx, endIdx + 1);
            try {
              final dynamic parsed = jsonDecode(jsonSub);
              if (parsed is Map<String, dynamic>) {
                // prefer an object that contains recommendations
                if (parsed.containsKey('recommendations')) {
                  parsedMap = parsed;
                  break;
                }
                // otherwise keep the first parsed object as fallback
                parsedMap ??= parsed;
              }
            } catch (_) {
              // ignore parse errors for this span and try next start
            }
          }
        }
      } catch (_) {
        parsedMap = null;
      }

      // 额外尝试：有些模型会在 JSON 之后直接追加一段 `title: ...`（可能没有换行），
      // 优先从最原始的 cleaned 文本中提取这种紧贴 JSON 的标题并立即锁定为会话标题。
      try {
        if (parsedMap == null) {
          final afterJsonTitleReg = RegExp(r'(?im)\}\s*(?:title|标题)\s*[:：]\s*([^\n\{\r]+)');
          final m = afterJsonTitleReg.firstMatch(cleaned);
          if (m != null) {
            String inlineTitle = m.group(1)!.trim().replaceAll('"', '');
            if (inlineTitle.isNotEmpty) {
              if (inlineTitle.length > 15) inlineTitle = inlineTitle.substring(0, 15);
              try {
                // 从 cleaned 与 buffer 中移除该 title 片段，避免显示在消息体中
                cleaned = cleaned.replaceAll(afterJsonTitleReg, '}');
                try {
                  final metaReg = RegExp(r'(?im)(?:title|标题)\s*[:：]\s*[^\n\{\r]+');
                  buffer = buffer.replaceAll(metaReg, '');
                } catch (_) {}

                final currentId = state.currentConversationId;
                if (currentId == null) {
                  final newId = DateTime.now().microsecondsSinceEpoch.toString();
                  state = state.copyWith(currentConversationId: newId, currentConversationTitle: inlineTitle, isTitleLocked: true);
                  try {
                    // persist asynchronously to avoid blocking the streaming/parse flow
                    saveCurrentConversation().catchError((_) {});
                  } catch (_) {}
                } else {
                  state = state.copyWith(currentConversationTitle: inlineTitle, isTitleLocked: true);
                  try {
                    // persist asynchronously to avoid blocking the streaming/parse flow
                    saveCurrentConversation().catchError((_) {});
                  } catch (_) {}
                }
              } catch (_) {}
            }
          }
        }
      } catch (_) {}

      // Prepare parse diagnostics (do not mutate buffer). We'll prepend to metaText only when debug is enabled.
      String parseDiagnostic = '';
      try {
        if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
        final box = Hive.box('settings');
        final bool debug = box.get('debug_ai_response') as bool? ?? false;
        if (debug) {
          if (parsedMap == null) {
            parseDiagnostic = 'PARSE_STATUS:FAILED';
          } else {
            parseDiagnostic = 'PARSE_STATUS:OK KEYS:' + parsedMap.keys.join(',');
          }
          // Prepend to buffer for UI visibility (only in debug)
          buffer = parseDiagnostic + '\n' + buffer;
        }
      } catch (_) {}

      if (parsedMap != null && parsedMap.containsKey('recommendations')) {
        final recs = (parsedMap['recommendations'] as List<dynamic>);
        final products = <ProductModel>[];
        // Do NOT convert AI recommendation items into product cards immediately.
        // Instead, only populate products if the AI returned a concrete `products` list
        // (which contains full product data). Otherwise we'll show keyword buttons
        // derived from `recommendations` and let the user tap to trigger a backend search.
        if (parsedMap.containsKey('products') && parsedMap['products'] is List) {
          for (final item in (parsedMap['products'] as List)) {
          if (item is Map<String, dynamic>) {
              try {
                products.add(ProductModel.fromMap(item));
              } catch (_) {}
            }
          }
        }
        // Build metaText: show 'analysis' always if present; show raw meta only when debug is enabled
        String metaText = '';
        try {
          if (parsedMap.containsKey('analysis')) {
            final a = parsedMap['analysis'] as String?;
            if (a != null && a.trim().isNotEmpty) {
              metaText = a + '\n\n';
            }
          }
        } catch (_) {}
        // If debug flag enabled, append a short parsed-summary for quick verification
        try {
          if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
          final box = Hive.box('settings');
          final bool debug = box.get('debug_ai_response') as bool? ?? false;
        if (debug) {
            final summaries = products.map((p) => '${p.title} (¥${p.price.toStringAsFixed(0)})').toList();
            final summaryLine = '解析到 ${products.length} 个商品：' + summaries.join(' ; ');
            metaText = summaryLine + '\n\n' + metaText;
            // Also add detailed parse diagnostics to help debugging when cards do not render
            try {
              final keys = parsedMap.keys.join(',');
              metaText = 'PARSE_KEYS:' + keys + '\n' + metaText;
              if (parsedMap.containsKey('recommendations')) {
                final first = (parsedMap['recommendations'] as List).isNotEmpty ? (parsedMap['recommendations'] as List)[0] : null;
                if (first != null && first is Map<String, dynamic>) {
                  final firstKeys = first.keys.join(',');
                  metaText = metaText + '\nFIRST_REC_KEYS:' + firstKeys;
                }
              }
            } catch (_) {}
          }
        } catch (_) {}

        // Ensure debug-only lines are removed when debug mode is off
            try {
              if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
              final box2 = Hive.box('settings');
              final bool debugFlag = box2.get('debug_ai_response') as bool? ?? false;
              // 如果 debugFlag 为 true，我们不移除 debug-only 行，并准备把完整数据通过 state 传给 UI 以便在那里执行剪贴板写入（更可靠）
              if (debugFlag) {
                // 通过 debugNotification 提示 UI 有完整返回可复制；仅把 AI 的原始返回（cleaned buffer）放到 state.debugFullResponse，避免过长的解析信息导致 UI 卡顿
                final full = buffer;
                state = state.copyWith(debugNotification: '已复制完整返回信息', debugFullResponse: full);
              } else {
                metaText = metaText.split('\n').where((line) => !line.startsWith('PARSE_') && !line.startsWith('FIRST_REC_KEYS:') && !line.startsWith('PARSE_KEYS:') && !line.startsWith('解析到 ') && !line.trim().startsWith('{query')).join('\n');
                buffer = buffer.split('\n').where((line) => !line.startsWith('PARSE_') && !line.contains('原始AI返回(JSON)') && !line.contains('原始请求(JSON)：') && !line.trim().startsWith('{query')).join('\n');
              }
            } catch (_) {}

        // If debug flag is enabled, prefer to show only the AI's cleaned buffer as the message
        String finalText = metaText.trim();
        try {
          if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
          final boxDbg2 = Hive.box('settings');
          final bool dbg2 = boxDbg2.get('debug_ai_response') as bool? ?? false;
          if (dbg2) {
            finalText = buffer.trim();
          }
        } catch (_) {}
        // Try to extract suggestion keywords from parsedMap (if present)
        List<String>? keywordsList;
        try {
          if (parsedMap.containsKey('keywords') && parsedMap['keywords'] is List) {
            keywordsList = (parsedMap['keywords'] as List).whereType<String>().toList();
          } else if (parsedMap.containsKey('recommendations') && parsedMap['recommendations'] is List) {
            // Collect (keyword, rating) pairs so we can sort by rating if provided
            final tmpPairs = <Map<String, dynamic>>[];
            for (final rec in parsedMap['recommendations']) {
              String? candidate;
              double rating = 0.0;
              if (rec is Map<String, dynamic>) {
                // Prefer nested goods.title
                try {
                  if (rec.containsKey('goods') && rec['goods'] is Map && (rec['goods']['title'] is String)) {
                    candidate = (rec['goods']['title'] as String);
                  }
                } catch (_) {}
                // Fallbacks
                if (candidate == null) {
                  candidate = (rec['keyword'] ?? rec['title'] ?? rec['name'])?.toString();
                }
                // rating may be under rec['rating'] or rec['score']
                try {
                  final r = rec['rating'] ?? rec['score'];
                  if (r is num) rating = (r as num).toDouble();
                } catch (_) {}
              } else if (rec is String) {
                candidate = rec;
              }

              if (candidate != null) {
                // clean candidate
                candidate = candidate.trim();
                // remove surrounding ASCII quotes and Unicode smart quotes by iterative trimming
                try {
                  String s = candidate;
                  while (s.isNotEmpty) {
                    final first = s.codeUnitAt(0);
                    if (first == 0x27 || first == 0x22 || first == 0x201C || first == 0x201D) {
                      s = s.substring(1);
                      continue;
                    }
                    break;
                  }
                  while (s.isNotEmpty) {
                    final last = s.codeUnitAt(s.length - 1);
                    if (last == 0x27 || last == 0x22 || last == 0x201C || last == 0x201D) {
                      s = s.substring(0, s.length - 1);
                      continue;
                    }
                    break;
                  }
                  candidate = s;
                } catch (_) {}
                if (candidate != null && candidate.isNotEmpty) tmpPairs.add({'kw': candidate, 'rating': rating});
              }
              if (tmpPairs.length >= 12) break; // collect a few more to allow de-dup & sort
            }
            if (tmpPairs.isNotEmpty) {
              // sort by rating desc then keep unique keywords preserving order
              tmpPairs.sort((a, b) => (b['rating'] as double).compareTo(a['rating'] as double));
              final seen = <String>{};
              final tmp = <String>[];
              for (final p in tmpPairs) {
                final s = (p['kw'] as String).trim();
                if (!seen.contains(s)) {
                  seen.add(s);
                  tmp.add(s);
                }
                if (tmp.length >= 6) break;
              }
              if (tmp.isNotEmpty) keywordsList = tmp;
            }
          }
        } catch (_) {
          keywordsList = null;
        }

        // Fallback: if no keywords extracted, derive concise keywords from recommendations
        try {
          if ((keywordsList == null || keywordsList.isEmpty) && parsedMap.containsKey('recommendations') && parsedMap['recommendations'] is List) {
            final cand = <String>[];
            for (final rec in parsedMap['recommendations']) {
              String? k;
              try {
                if (rec is Map<String, dynamic>) {
                  if (rec.containsKey('goods') && rec['goods'] is Map && rec['goods']['title'] is String) {
                    k = (rec['goods']['title'] as String).trim();
                  } else if (rec.containsKey('title') && rec['title'] is String) {
                    k = (rec['title'] as String).trim();
                  }
                } else if (rec is String) {
                  k = rec.trim();
                }
              } catch (_) {}
              if (k != null && k.isNotEmpty) {
                // simple cleaning
                k = k.replaceAll(RegExp(r'^\W+|\W+\$'), '');
                if (k.isNotEmpty && !cand.contains(k)) cand.add(k);
              }
              if (cand.length >= 6) break;
            }
            if (cand.isNotEmpty) keywordsList = cand;
          }
        } catch (_) {}

        // If parsing produced no keywords, fall back to streaming cache or derive from parsedMap
        if ((keywordsList == null || keywordsList.isEmpty)) {
          try {
            if (streamingKeywordsCache.isNotEmpty) {
              keywordsList = streamingKeywordsCache;
            } else {
              final derived = deriveKeywordsFromParsedMap(parsedMap);
              if (derived.isNotEmpty) keywordsList = derived;
            }
          } catch (_) {}
        }

        finalMsg = ChatMessage(id: DateTime.now().microsecondsSinceEpoch.toString(), text: finalText, isUser: false, products: products, keywords: keywordsList, aiParsedRaw: parsedMap != null ? jsonEncode(parsedMap) : null, failed: failed, retryForText: failed ? text : null);
        // 尝试优先从 parsedMap 中读取显式标题（如果 AI 以结构化字段返回 title），否则回退到在 metaText 与 buffer 中匹配 'title/标题:' 形式
        try {
          String? extracted;
          // 1) parsedMap 优先
          try {
            if (parsedMap != null) {
              // 1a) top-level title fields
              if (parsedMap.containsKey('title') && parsedMap['title'] is String && (parsedMap['title'] as String).trim().isNotEmpty) {
                extracted = (parsedMap['title'] as String).trim();
              } else if (parsedMap.containsKey('conversation_title') && parsedMap['conversation_title'] is String && (parsedMap['conversation_title'] as String).trim().isNotEmpty) {
                extracted = (parsedMap['conversation_title'] as String).trim();
              } else if (parsedMap.containsKey('conversationTitle') && parsedMap['conversationTitle'] is String && (parsedMap['conversationTitle'] as String).trim().isNotEmpty) {
                extracted = (parsedMap['conversationTitle'] as String).trim();
              }

              // 1b) some responses put the title inside a `meta` object
              try {
                if ((extracted == null || extracted.trim().isEmpty) && parsedMap.containsKey('meta') && parsedMap['meta'] is Map<String, dynamic>) {
                  final meta = parsedMap['meta'] as Map<String, dynamic>;
                  if (meta.containsKey('title') && meta['title'] is String && (meta['title'] as String).trim().isNotEmpty) {
                    extracted = (meta['title'] as String).trim();
                  } else if (meta.containsKey('conversation_title') && meta['conversation_title'] is String && (meta['conversation_title'] as String).trim().isNotEmpty) {
                    extracted = (meta['conversation_title'] as String).trim();
                  } else if (meta.containsKey('conversationTitle') && meta['conversationTitle'] is String && (meta['conversationTitle'] as String).trim().isNotEmpty) {
                    extracted = (meta['conversationTitle'] as String).trim();
                  }
                }
              } catch (_) {}
            }
          } catch (_) {}

          // 2) 回退到文本正则匹配
          // 先做一个简单直接的查找：如果返回文本中任何位置包含 `title:` 或 `标题：` 字段，优先提取该字段的值并作为标题
          try {
            if (extracted == null || extracted.trim().isEmpty) {
              final combinedForTitle = (cleaned + '\n' + metaText + '\n' + buffer).trim();
              final titleFieldReg = RegExp(r'(?im)(?:title|标题)\s*[:：]\s*(.+?)(?=\r?\n|$)');
              final titleMatches = titleFieldReg.allMatches(combinedForTitle).toList();
              if (titleMatches.isNotEmpty) {
                final last = titleMatches.last;
                extracted = last.group(1)!.trim().replaceAll('"', '').replaceAll('\n', ' ');
              }
            }
          } catch (_) {}

          if (extracted == null || extracted.trim().isEmpty) {
            try {
              // 先尝试在最原始的 cleaned 文本中查找（cleaned 变量包含流式合并后的原始文本）
              final cleanedTitleReg = RegExp(r'(?im)(?:title|标题)\s*[:：]\s*([^\n\{]+)');
              final cleanedMatches = cleanedTitleReg.allMatches(cleaned).toList();
              if (cleanedMatches.isNotEmpty) {
                final last = cleanedMatches.last;
                extracted = last.group(1)!.trim().replaceAll('"', '').replaceAll('\n', ' ');
              }
            } catch (_) {}

            if (extracted == null || extracted.trim().isEmpty) {
              try {
                // 再尝试在 buffer 中查找紧随 JSON 后的 title 行
                final rawTitleReg = RegExp(r'(?im)(?:title|标题)\s*[:：]\s*([^\n\{]+)');
                final rawMatches = rawTitleReg.allMatches(buffer).toList();
                if (rawMatches.isNotEmpty) {
                  final last = rawMatches.last;
                  extracted = last.group(1)!.trim().replaceAll('"', '').replaceAll('\n', ' ');
                }
              } catch (_) {}
            }

            if (extracted == null || extracted.trim().isEmpty) {
              final combined = (metaText + '\n' + buffer).trim();
              // 最后在 metaText+buffer 中做宽松匹配，允许在行中或行尾出现 title
              final regTitle = RegExp(r'(?im)(?:title|标题)\s*[:：]\s*(.+?)\s*(?=(\n|\r|\{|$))');
              final matchesTitle = regTitle.allMatches(combined).toList();
              if (matchesTitle.isNotEmpty) {
                final last = matchesTitle.last;
                extracted = last.group(1)!.trim().replaceAll('"', '').replaceAll('\n', ' ');
              }
            }
          }

          if (extracted != null && extracted.trim().isNotEmpty) {
            var finalTitle = extracted.trim();
            if (finalTitle.length > 15) finalTitle = finalTitle.substring(0, 15);
            // remove any matching title lines from metaText/buffer to avoid duplicate display
            try {
              final metaReg = RegExp(r'(?im)(?:title|标题)\s*[:：]\s*.+?\s*(?:\n|\r|$)');
              metaText = metaText.replaceAll(metaReg, '');
              buffer = buffer.replaceAll(metaReg, '');
            } catch (_) {}

            try {
              final currentId = state.currentConversationId;
              // 如果开启 debug 标志，准备把完整返回复制到剪贴板并在 UI 触发提示
              bool copied = false;
              String? fullDebug;
              try {
                if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
                final box = Hive.box('settings');
                final bool debug = box.get('debug_ai_response') as bool? ?? false;
                if (debug) {
                  final full = 'PARSED_MAP:\n' + (parsedMap != null ? jsonEncode(parsedMap) : '{}') + '\n\nCLEANED_BUFFER:\n' + buffer + '\n\nMETA_TEXT:\n' + metaText;
                  // 不直接在 provider 写入剪贴板（可能在非 UI 线程导致问题），改为把完整文本放到 state.debugFullResponse，由 UI 层负责写入剪贴板并弹窗
                  fullDebug = full;
                  copied = true;
                }
              } catch (_) {}

                if (currentId == null) {
                final newId = DateTime.now().microsecondsSinceEpoch.toString();
                state = state.copyWith(currentConversationId: newId, currentConversationTitle: finalTitle, debugNotification: copied ? '已复制完整返回信息' : null, debugFullResponse: copied ? fullDebug : null, isTitleLocked: true);
                try {
                  // persist asynchronously to avoid blocking the streaming/parse flow
                  saveCurrentConversation().catchError((_) {});
                } catch (_) {}
              } else {
                state = state.copyWith(currentConversationTitle: finalTitle, debugNotification: copied ? '已复制完整返回信息' : null, debugFullResponse: copied ? fullDebug : null, isTitleLocked: true);
                try {
                  // persist asynchronously to avoid blocking the streaming/parse flow
                  saveCurrentConversation().catchError((_) {});
                } catch (_) {}
              }
            } catch (_) {}
          }
        } catch (_) {}
      } else {
        finalMsg = ChatMessage(id: DateTime.now().microsecondsSinceEpoch.toString(), text: buffer.trim(), isUser: false, aiParsedRaw: null, failed: failed, retryForText: failed ? text : null);
      }

      // 如果开启 debug，避免在消息气泡中渲染超长的原始 JSON 导致 UI 卡顿，截断展示并确保完整内容已通过 debugFullResponse 传给 UI 以便复制
      try {
        if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
        final boxDbg = Hive.box('settings');
        final bool dbg = boxDbg.get('debug_ai_response') as bool? ?? false;
        if (dbg && finalMsg.text.length > 1500) {
          final preview = finalMsg.text.substring(0, 1500) + '\n\n[调试内容已截断，已复制完整返回到剪贴板]';
          finalMsg = ChatMessage(id: finalMsg.id, text: preview, isUser: finalMsg.isUser, product: finalMsg.product, products: finalMsg.products, aiParsedRaw: finalMsg.aiParsedRaw, failed: finalMsg.failed, retryForText: finalMsg.retryForText, timestamp: finalMsg.timestamp);
        }
      } catch (_) {}
    } catch (_) {
      finalMsg = ChatMessage(id: DateTime.now().microsecondsSinceEpoch.toString(), text: buffer.trim(), isUser: false, failed: failed, retryForText: failed ? text : null);
    }

    // Before replacing placeholder, ensure we strip debug-only lines from all messages in memory
    String sanitize(String t) {
      try {
        return t.split('\n').where((line) {
          final s = line.trimLeft();
          if (s.startsWith('PARSE_')) return false;
          if (s.startsWith('FIRST_REC_KEYS:')) return false;
          if (s.startsWith('PARSE_KEYS:')) return false;
          if (s.startsWith('解析到 ')) return false;
          if (s.contains('原始请求(JSON)')) return false;
          if (s.contains('原始AI返回(JSON)')) return false;
          if (s.trimLeft().startsWith('{query')) return false;
          return true;
        }).join('\n');
      } catch (_) {
        return t;
      }
    }

    try {
      if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
      final box = Hive.box('settings');
      final bool debugFlag = box.get('debug_ai_response') as bool? ?? false;
      if (!debugFlag) {
        final cleanMsgs = state.messages.map((m) {
          final cleaned = sanitize(m.text);
          return ChatMessage(
              id: m.id,
              text: cleaned,
              isUser: m.isUser,
              product: m.product,
              products: m.products,
              keywords: m.keywords,
              attempts: m.attempts,
              aiParsedRaw: m.aiParsedRaw,
              failed: m.failed,
              retryForText: m.retryForText,
              timestamp: m.timestamp);
        }).toList();
        // replace current state's messages with cleaned versions before inserting finalMsg
        state = state.copyWith(messages: cleanMsgs);
        // also sanitize finalMsg text
        finalMsg = ChatMessage(
            id: finalMsg.id,
            text: sanitize(finalMsg.text),
            isUser: finalMsg.isUser,
            product: finalMsg.product,
            products: finalMsg.products,
            keywords: finalMsg.keywords,
            attempts: finalMsg.attempts,
            aiParsedRaw: finalMsg.aiParsedRaw,
            failed: finalMsg.failed,
            retryForText: finalMsg.retryForText,
            timestamp: finalMsg.timestamp);
      }
    } catch (_) {}

    // replace placeholder with final message and stop loading
    final msgs = [...state.messages];
    if (msgs.isNotEmpty) {
      msgs[msgs.length - 1] = finalMsg;
      state = state.copyWith(isLoading: false, isStreaming: false, messages: msgs);
    } else {
      state = state.copyWith(isLoading: false, isStreaming: false, messages: [finalMsg]);
    }

    // If conversation title is still the default placeholder, try to auto-generate
    // a title from analysis or first product and persist it.
    try {
      // 已禁用自动根据消息首行生成会话标题的逻辑。
      // 如果没有从 parsedMap 或显式字段提取到标题，则保持当前标题不变（通常为 '新对话'）。
    } catch (_) {}

    // persist conversation after adding AI message
    try {
      // persist asynchronously to avoid blocking UI after adding AI message
      saveCurrentConversation().catchError((_) {});
    } catch (_) {}
  }

  /// Create a new conversation and set as current
  Future<void> createNewConversation() async {
    // Do NOT call AI here. Create a new conversation with a placeholder title.
    // The actual AI-generated title will be created when the user sends the first message
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final placeholderTitle = '新对话';
    state = state.copyWith(messages: [], currentConversationId: id, currentConversationTitle: placeholderTitle);
    // persist
    final repo = _ref.read(conversationRepositoryProvider);
    final conv = ConversationModel(id: id, title: placeholderTitle, messages: []);
    await repo.saveConversation(conv);
  }

  /// Save or update current conversation to repository
  Future<void> saveCurrentConversation() async {
    final id = state.currentConversationId;
    final title = state.currentConversationTitle ?? '对话';
    if (id == null) return;
    final repo = _ref.read(conversationRepositoryProvider);
    final conv = ConversationModel(id: id, title: title, messages: state.messages);
    await repo.saveConversation(conv);
  }

  /// Load a conversation
  /// 加载一个会话的消息到当前聊天状态（用于在 UI 中切换会话）
  void loadConversation(ConversationModel conv) {
    state = state.copyWith(messages: [...conv.messages], isLoading: false, currentConversationId: conv.id, currentConversationTitle: conv.title);
  }

  Future<void> deleteConversationById(String id) async {
    final repo = _ref.read(conversationRepositoryProvider);
    await repo.deleteConversation(id);
    // if current conversation is deleted, clear state
    if (state.currentConversationId == id) {
      state = ChatState();
    }
  }
}

/// Provider 用于创建 ChatStateNotifier
final chatStateNotifierProvider = StateNotifierProvider<ChatStateNotifier, ChatState>((ref) {
  final svc = ref.watch(chatServiceProvider);
  return ChatStateNotifier(service: svc, ref: ref);
});

/// Conversation repository provider
final conversationRepositoryProvider = Provider<ConversationRepository>((ref) => ConversationRepository());


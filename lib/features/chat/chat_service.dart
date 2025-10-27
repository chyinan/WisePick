// 保留以便后续扩展 HTTP 实现，但当前 mock 实现不需要 dio
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import '../../services/ai_prompt_service.dart';

/// ChatService 负责与 OpenAI（或 mock）交互，返回聊天回复文本或结构化推荐
class ChatService {
  final ApiClient apiClient;

  ChatService({ApiClient? client}) : apiClient = client ?? ApiClient();

  /// 调用本地代理或 OpenAI 兼容接口，返回文本回复（不处理流式响应）
  Future<String> getAiReply(String prompt, {bool includeTitleInstruction = false}) async {
    // Allow using a local mock AI response for offline/debugging. When enabled via
    // Hive settings key `use_mock_ai`, return a canned JSON-like reply to avoid
    // calling external APIs (helps during development to save cost).
    try {
      if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
      final box = Hive.box('settings');
      final bool useMock = box.get('use_mock_ai') as bool? ?? false;
      if (useMock) {
        // small delay to simulate network latency
        await Future.delayed(const Duration(milliseconds: 200));
        return _mockResponseString();
      }
    } catch (_) {}

    // Decide whether to call OpenAI directly (if user saved API key) or use local proxy
    final localKey = await _localApiKey();
    final useDirect = localKey != null;
    // read optional base url and model from settings
    String baseUrl = 'https://api.openai.com';
    String model = 'gpt-3.5-turbo';
    try {
      if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
      final box = Hive.box('settings');
      final b = box.get('openai_base') as String?;
      final m = box.get('openai_model') as String?;
      if (b != null && b.trim().isNotEmpty) baseUrl = b.trim();
      if (m != null && m.trim().isNotEmpty) model = m.trim();
    } catch (_) {}
    String url;
    if (useDirect) {
      final baseTrimmed = baseUrl.trim();
      // remove only trailing slashes while preserving scheme (e.g. https://)
      final baseNoTrailing = baseTrimmed.replaceAll(RegExp(r'/+$'), '');
      if (RegExp(r'/v1$', caseSensitive: false).hasMatch(baseNoTrailing)) {
        url = '$baseNoTrailing/chat/completions';
      } else {
        url = '$baseNoTrailing/v1/chat/completions';
      }
    } else {
      // resolve backend base saved in settings if present
      String backend = 'http://localhost:8080';
      try {
        if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
        final box = Hive.box('settings');
        final String? b = box.get('backend_base') as String?;
        if (b != null && b.trim().isNotEmpty) backend = b.trim();
        else backend = const String.fromEnvironment('BACKEND_BASE', defaultValue: 'http://localhost:8080');
      } catch (_) {}
      final baseNoTrailing = backend.replaceAll(RegExp(r'/+$'), '');
      url = '$baseNoTrailing/v1/chat/completions';
    }
    // Check settings flag: if embed_prompts is disabled, send a lightweight user-only message
    bool embedPrompts = true;
    try {
      if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
      final box = Hive.box('settings');
      final b = box.get('embed_prompts') as bool?;
      if (b != null) embedPrompts = b;
    } catch (_) {}

    final dynamic messages = AiPromptService.buildMessages(userProfile: ' ', context: ' ', userQuestion: prompt, includeTitleInstruction: includeTitleInstruction);

    // Read max_tokens setting (string): 'unlimited' means omit the field so upstream can use model's max
    int? maxTokens;
    try {
      final box = Hive.box('settings');
      final String? t = box.get('max_tokens') as String?;
      if (t != null && t != 'unlimited') maxTokens = int.tryParse(t);
    } catch (_) {}

    final requestBody = {
      'model': model,
      'messages': messages,
      if (maxTokens != null) 'max_tokens': maxTokens,
    };

    try {
      // If calling upstream directly, include Authorization header with localKey
      final headers = useDirect ? {'Authorization': 'Bearer $localKey', 'Content-Type': 'application/json'} : {'Content-Type': 'application/json'};
      // Allow long-running responses when max_tokens is unlimited; raise receiveTimeout
      // Do a longer timeout by temporarily adjusting the dio instance when max_tokens is unlimited.
      final useLongTimeout = (requestBody['max_tokens'] == null);
      Response resp;
      if (useLongTimeout) {
        final oldReceive = apiClient.dio.options.receiveTimeout;
        try {
          apiClient.dio.options.receiveTimeout = const Duration(minutes: 5);
          resp = await apiClient.post(url, data: requestBody, headers: headers);
        } finally {
          apiClient.dio.options.receiveTimeout = oldReceive;
        }
      } else {
        resp = await apiClient.post(url, data: requestBody, headers: headers);
      }
      if (resp.statusCode != 200) {
        throw Exception('AI proxy returned status ${resp.statusCode}');
      }
      final Map<String, dynamic> body = Map<String, dynamic>.from(resp.data);
      // 尝试按照 OpenAI 的响应结构读取第一个 assistant 消息
      final choices = body['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return '';
      final message = choices[0]['message'] as Map<String, dynamic>?;
      String result = '';
      if (message != null && message['content'] != null) {
        result = message['content'] as String;
      } else {
        // 备选：某些兼容实现可能直接在 choices[n].text
        final text = choices[0]['text'] as String?;
        result = text ?? '';
      }

      // If debug flag enabled in settings, prepend full raw JSON response for inspection
      try {
        if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
        final box = Hive.box('settings');
        final bool debug = box.get('debug_ai_response') as bool? ?? false;
        if (debug) {
          final raw = jsonEncode(body);
          result = '原始AI返回(JSON)：$raw\n\n' + result;
        }
      } catch (_) {}

      // If embedding was enabled but model returned empty content, retry once without embedding
      try {
        if (embedPrompts && result.trim().isEmpty) {
          final fallbackBody = {
            'model': model,
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
            'max_tokens': 300
          };
          final fallbackResp = await apiClient.post(url, data: fallbackBody, headers: headers);
          if (fallbackResp.statusCode == 200) {
            final Map<String, dynamic> fb = Map<String, dynamic>.from(fallbackResp.data);
            final fbChoices = fb['choices'] as List<dynamic>?;
            if (fbChoices != null && fbChoices.isNotEmpty) {
              final fbMessage = fbChoices[0]['message'] as Map<String, dynamic>?;
              String fbResult = '';
              if (fbMessage != null && fbMessage['content'] != null) {
                fbResult = fbMessage['content'] as String;
              } else {
                fbResult = fbChoices[0]['text'] as String? ?? '';
              }
              // prepend raw fb JSON if debug
              try {
                final box = Hive.box('settings');
                final bool debug = box.get('debug_ai_response') as bool? ?? false;
                if (debug) {
                  fbResult = '原始AI返回(JSON)(回退)：${jsonEncode(fb)}\n\n' + fbResult;
                }
              } catch (_) {}

              if (fbResult.trim().isNotEmpty) return fbResult;
            }
          }
        }
      } catch (_) {
        // ignore fallback errors and continue returning original result
      }

      return result;
    } catch (e) {
      // 在错误情况下回退为简单提示
      return 'AI 服务调用失败：${e.toString()}';
    }
  }

  /// 使用流式响应（stream: true）从代理获取增量回复，返回每个增量文本的 Stream
  /// 注意：上游可能以 SSE 风格（`data: {...}\n\n`）发送数据，本函数简单解析 `data: ` 行并抽取 delta 内容。
  Future<Stream<String>> getAiReplyStream(String prompt, {bool includeTitleInstruction = false}) async {
    final localKey = await _localApiKey();
    final useDirect = localKey != null;
    // read optional base and model
    String baseUrl = 'https://api.openai.com';
    String model = 'gpt-3.5-turbo';
    try {
      if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
      final box = Hive.box('settings');
      final b = box.get('openai_base') as String?;
      final m = box.get('openai_model') as String?;
      if (b != null && b.trim().isNotEmpty) baseUrl = b.trim();
      if (m != null && m.trim().isNotEmpty) model = m.trim();
    } catch (_) {}
    String url;
    if (useDirect) {
      final baseTrimmed = baseUrl.trim();
      final baseNoTrailing = baseTrimmed.replaceAll(RegExp(r'/+$'), '');
      if (RegExp(r'/v1$', caseSensitive: false).hasMatch(baseNoTrailing)) {
        url = '$baseNoTrailing/chat/completions';
      } else {
        url = '$baseNoTrailing/v1/chat/completions';
      }
    } else {
      url = 'http://localhost:8080/v1/chat/completions';
    }
    // Build messages consistent with non-streaming API and respect embed/debug/max_tokens settings
    bool embedPrompts = true;
    bool debugOutgoing = false;
    int? maxTokens;
    try {
      if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
      final box = Hive.box('settings');
      final b = box.get('embed_prompts') as bool?;
      if (b != null) embedPrompts = b;
      debugOutgoing = box.get('debug_ai_response') as bool? ?? false;
      final String? t = box.get('max_tokens') as String?;
      if (t != null && t != 'unlimited') maxTokens = int.tryParse(t);
    } catch (_) {}

    final dynamic messages = embedPrompts
        ? AiPromptService.buildMessages(userProfile: ' ', context: ' ', userQuestion: prompt, includeTitleInstruction: includeTitleInstruction)
        : [
            {'role': 'user', 'content': prompt}
          ];

    final requestBody = {
      'model': model,
      'messages': messages,
      'stream': true,
      if (maxTokens != null) 'max_tokens': maxTokens,
    };

    // If mock mode enabled, return a simulated streaming response composed of
    // small text chunks so the UI streaming logic behaves the same as with a
    // real upstream.
    try {
      if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
      final box = Hive.box('settings');
      final bool useMock = box.get('use_mock_ai') as bool? ?? false;
      if (useMock) {
        final controllerMock = StreamController<String>();
        final content = _mockResponseString();
        // emit in small chunks to mimic streaming
        Future(() async {
          const int chunkSize = 40;
          for (int i = 0; i < content.length; i += chunkSize) {
            final end = (i + chunkSize < content.length) ? i + chunkSize : content.length;
            controllerMock.add(content.substring(i, end));
            await Future.delayed(const Duration(milliseconds: 80));
          }
          controllerMock.close();
        });
        return controllerMock.stream;
      }
    } catch (_) {}

    final controller = StreamController<String>();
    try {
      final headers = useDirect ? {'Authorization': 'Bearer $localKey', 'Content-Type': 'application/json'} : {'Content-Type': 'application/json'};
      // If max_tokens is unlimited (null), extend receiveTimeout to avoid truncation
      final useLongTimeout = (requestBody['max_tokens'] == null);
      Response resp;
      if (useLongTimeout) {
        final oldReceive = apiClient.dio.options.receiveTimeout;
        try {
          apiClient.dio.options.receiveTimeout = const Duration(minutes: 5);
          try {
            resp = await apiClient.post(url, data: requestBody, headers: headers, responseType: ResponseType.stream);
          } on DioException catch (e) {
            final controllerErr = StreamController<String>();
            if (e.response?.statusCode == 429) {
              controllerErr.add('AI streaming error: 请求过多 (429)，请稍后重试。');
            } else {
              controllerErr.add('AI streaming error: ${e.toString()}');
            }
            controllerErr.close();
            return controllerErr.stream;
          }
        } finally {
          apiClient.dio.options.receiveTimeout = oldReceive;
        }
      } else {
        try {
          resp = await apiClient.post(url, data: requestBody, headers: headers, responseType: ResponseType.stream);
        } on DioException catch (e) {
          final controllerErr = StreamController<String>();
          if (e.response?.statusCode == 429) {
            controllerErr.add('AI streaming error: 请求过多 (429)，请稍后重试。');
          } else {
            controllerErr.add('AI streaming error: ${e.toString()}');
          }
          controllerErr.close();
          return controllerErr.stream;
        }
      }

      // If debug outgoing enabled, emit the outgoing request body first
      if (debugOutgoing) {
        try {
          controller.add('原始请求(JSON)：' + jsonEncode(requestBody));
        } catch (_) {}
      }

      // resp.data may be a Stream<List<int>> or a Dio ResponseBody with .stream
      late final Stream<List<int>> rawStream;
      if (resp.data is Stream<List<int>>) {
        rawStream = resp.data as Stream<List<int>>;
      } else if (resp.data is ResponseBody) {
        rawStream = (resp.data as ResponseBody).stream as Stream<List<int>>;
      } else {
        try {
          rawStream = (resp.data as dynamic).stream as Stream<List<int>>;
        } catch (e) {
          throw Exception('Unexpected streaming response type: ${resp.data.runtimeType}');
        }
      }

      final decoded = rawStream.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());

      decoded.listen((line) {
        var l = line.trimRight();
        if (l.startsWith('data:')) l = l.substring(5).trimLeft();
        if (l.isEmpty || l == '[DONE]') return;
        try {
          final m = jsonDecode(l);
          if (m is Map<String, dynamic>) {
            final choices = m['choices'] as List<dynamic>?;
            if (choices != null && choices.isNotEmpty) {
              final first = choices[0] as Map<String, dynamic>;
              final delta = first['delta'] as Map<String, dynamic>?;
              if (delta != null && delta['content'] != null) {
                controller.add(delta['content'] as String);
                return;
              }
              final message = first['message'] as Map<String, dynamic>?;
              if (message != null && message['content'] != null) {
                controller.add(message['content'] as String);
                return;
              }
              final text = first['text'] as String?;
              if (text != null) {
                controller.add(text);
                return;
              }
            }
          }
        } catch (_) {
          // not JSON, fallthrough to emit raw
        }
        controller.add(l);
      }, onError: (e) {
        controller.add('AI streaming error: ${e.toString()}');
        controller.close();
      }, onDone: () {
        controller.close();
      }, cancelOnError: true);

      return controller.stream;
    } catch (e) {
      controller.add('AI streaming error: ${e.toString()}');
      controller.close();
      return controller.stream;
    }
  }

  /// 使用 AI 为会话生成一个简短描述作为会话标题（mock 实现）
  Future<String> generateConversationTitle(String firstUserMsg) async {
    // Try to use AI to generate a concise (<=15 char) title in Chinese. Fallback to a simple truncation if AI fails.
    try {
      final prompt = '请为以下用户消息生成一个不超过15个汉字的会话标题（仅标题，中文）：\n"${firstUserMsg}"';
      final reply = await getAiReply(prompt);
      if (reply.trim().isNotEmpty) {
        // take first line and trim to 15 chars
        final line = reply.split('\n').first.trim();
        final clean = line.replaceAll(RegExp(r'[\r\n"]'), '').trim();
        return clean.length <= 15 ? clean : '${clean.substring(0, 15)}';
      }
    } catch (_) {}

    // Fallback: simple truncation
    final t = firstUserMsg.replaceAll(RegExp(r"\s+"), ' ').trim();
    final short = t.length > 12 ? '${t.substring(0, 12)}...' : t;
    return short.isNotEmpty ? short : '对话';
  }

  /// 尝试从 Hive 设置中读取用户保存的 OpenAI API Key
  Future<String?> _localApiKey() async {
    try {
      if (!Hive.isBoxOpen('settings')) {
        await Hive.openBox('settings');
      }
      final box = Hive.box('settings');
      final v = box.get('openai_api') as String?;
      if (v != null && v.trim().isNotEmpty) return v.trim();
    } catch (_) {}

    // Fallback to compile-time config when set
    if (Config.openAiApiKey != 'YOUR_OPENAI_API_KEY' && Config.openAiApiKey.isNotEmpty) return Config.openAiApiKey;
    return null;
  }

  /// 返回用于本地 mock 的完整 assistant 响应字符串（包含结构化 JSON + 最后一行 title）
  String _mockResponseString() {
    final Map<String, dynamic> obj = {
      'analysis': '你预算约800元，建议优先考虑带耳放的一体机或纯DAC+外置耳放的组合：前者方便直推耳机，后者扩展性更好。以下为针对不同需求的具体型号示例。',
      'title': '800元USB DAC推荐',
      'recommendations': [
        {
          'goods': {
            'title': 'TOPPING DX1 USB DAC/耳放',
            'description': '带耳放且价格贴近800，适合直推耳机'
          },
          'rating': 4.7,
          'platform': 'jd',
          'price': 649.0,
          'imageUrl': 'https://picsum.photos/seed/dx1/800/600',
          'link': 'https://search.jd.com/Search?keyword=TOPPING%20DX1',
          'tags': ['USB DAC', '耳放', '桌面']
        },
        {
          'goods': {
            'title': 'SMSL C100 桌面USB DAC',
            'description': '纯DAC多输入，扩展性好，适合接外置耳放/有源音箱'
          },
          'rating': 4.5,
          'platform': 'jd',
          'price': 759.0,
          'imageUrl': 'https://picsum.photos/seed/smslc100/800/600',
          'link': 'https://search.jd.com/Search?keyword=SMSL%20C100',
          'tags': ['USB DAC', '多输入', '桌面']
        },
        {
          'goods': {
            'title': 'TOPPING D10s 纯USB DAC',
            'description': '纯解码稳健，预算可覆盖，适合追求纯音质'
          },
          'rating': 4.6,
          'platform': 'jd',
          'price': 799.0,
          'imageUrl': 'https://picsum.photos/seed/d10s/800/600',
          'link': 'https://search.jd.com/Search?keyword=TOPPING%20D10s',
          'tags': ['USB DAC', '纯解码', '桌面']
        },
        {
          'goods': {
            'title': 'FiiO 飞傲 K3 (2021) USB DAC/耳放',
            'description': '体积小，便携办公友好，同时具备耳放功能'
          },
          'rating': 4.4,
          'platform': 'jd',
          'price': 579.0,
          'imageUrl': 'https://picsum.photos/seed/fiok3/800/600',
          'link': 'https://search.jd.com/Search?keyword=FiiO%20K3%202021',
          'tags': ['USB DAC', '便携', '耳放']
        }
      ],
      'meta': {
        'query': '需要800左右的USB DAC.',
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'reason': '800元内高性价比',
        'count': 4,
        'title': '800元USB DAC推荐'
      }
    };

    return jsonEncode(obj) + '\n' + 'title: 800元USB DAC推荐';
  }
}


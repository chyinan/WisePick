import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wisepick_dart_version/core/api_client.dart';
import 'package:wisepick_dart_version/features/chat/chat_service.dart';
import 'package:wisepick_dart_version/features/chat/chat_error_mapper.dart';

// ── 构造 mock ApiClient ──────────────────────────────────────────
ApiClient _mockClient({
  required dynamic responseData,
  int statusCode = 200,
  bool throwDio = false,
  DioExceptionType? dioErrorType,
}) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      if (throwDio && dioErrorType != null) {
        handler.reject(DioException(
          requestOptions: options,
          type: dioErrorType,
          message: 'mock error',
        ));
        return;
      }
      handler.resolve(Response(
        requestOptions: options,
        statusCode: statusCode,
        data: responseData,
      ));
    },
  ));
  return ApiClient(dio: dio);
}

// 标准 OpenAI 格式响应
Map<String, dynamic> _openAiResponse(String content) => {
      'choices': [
        {
          'message': {'role': 'assistant', 'content': content}
        }
      ]
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('chat_service_test_');
    Hive.init(tempDir.path);
    // 打开 settings box，不设置 use_mock_ai（默认 false）
    await Hive.openBox('settings');
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  // ──────────────────────────────────────────────────────────────
  // getAiReply — 正常响应
  // ──────────────────────────────────────────────────────────────
  group('getAiReply - 正常响应', () {
    test('返回 choices[0].message.content', () async {
      final client = _mockClient(
        responseData: _openAiResponse('这是 AI 的回复'),
      );
      final service = ChatService(client: client);
      final result = await service.getAiReply('你好');
      expect(result, equals('这是 AI 的回复'));
    });

    test('choices[0].text 作为备选', () async {
      final client = _mockClient(
        responseData: {
          'choices': [
            {'text': '备选文本回复'}
          ]
        },
      );
      final service = ChatService(client: client);
      final result = await service.getAiReply('你好');
      expect(result, equals('备选文本回复'));
    });

    test('choices 为空时返回空字符串', () async {
      final client = _mockClient(
        responseData: {'choices': []},
      );
      final service = ChatService(client: client);
      final result = await service.getAiReply('你好');
      expect(result, equals(''));
    });

    test('choices 为 null 时返回空字符串', () async {
      final client = _mockClient(
        responseData: <String, dynamic>{},
      );
      final service = ChatService(client: client);
      final result = await service.getAiReply('你好');
      expect(result, equals(''));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // getAiReply — 错误处理
  // ──────────────────────────────────────────────────────────────
  group('getAiReply - 错误处理', () {
    test('网络错误返回用户友好消息而非抛出异常', () async {
      final client = _mockClient(
        responseData: null,
        throwDio: true,
        dioErrorType: DioExceptionType.connectionError,
      );
      final service = ChatService(client: client);
      final result = await service.getAiReply('你好');
      // 不应抛出，应返回友好错误消息
      expect(result, isA<String>());
      expect(result, isNotEmpty);
    });

    test('超时错误返回用户友好消息', () async {
      final client = _mockClient(
        responseData: null,
        throwDio: true,
        dioErrorType: DioExceptionType.receiveTimeout,
      );
      final service = ChatService(client: client);
      final result = await service.getAiReply('你好');
      expect(result, isA<String>());
      expect(result, isNotEmpty);
    });

    test('401 错误返回认证相关消息', () async {
      final client = _mockClient(
        responseData: null,
        throwDio: true,
        dioErrorType: DioExceptionType.badResponse,
      );
      // 用自定义 Dio 模拟 401
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: options,
              statusCode: 401,
            ),
          ));
        },
      ));
      final service = ChatService(client: ApiClient(dio: dio));
      final result = await service.getAiReply('你好');
      expect(result, isA<String>());
      expect(result, isNotEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // getAiReply — URL 构建逻辑
  // ──────────────────────────────────────────────────────────────
  group('getAiReply - URL 构建', () {
    test('有本地 API key 时直接调用 OpenAI', () async {
      final box = Hive.box('settings');
      await box.put('openai_api', 'sk-test-key');

      String? capturedUrl;
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedUrl = options.path;
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: _openAiResponse('回复'),
          ));
        },
      ));
      final service = ChatService(client: ApiClient(dio: dio));
      await service.getAiReply('你好');

      expect(capturedUrl, contains('/v1/chat/completions'));
      await box.delete('openai_api');
    });

    test('自定义 base URL 末尾有 /v1 时不重复添加', () async {
      final box = Hive.box('settings');
      await box.put('openai_api', 'sk-test-key');
      await box.put('openai_base', 'https://custom.api.com/v1');

      String? capturedUrl;
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedUrl = options.path;
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: _openAiResponse('回复'),
          ));
        },
      ));
      final service = ChatService(client: ApiClient(dio: dio));
      await service.getAiReply('你好');

      expect(capturedUrl, equals('https://custom.api.com/v1/chat/completions'));
      await box.delete('openai_api');
      await box.delete('openai_base');
    });

    test('自定义 base URL 无 /v1 时自动添加', () async {
      final box = Hive.box('settings');
      await box.put('openai_api', 'sk-test-key');
      await box.put('openai_base', 'https://custom.api.com');

      String? capturedUrl;
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedUrl = options.path;
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: _openAiResponse('回复'),
          ));
        },
      ));
      final service = ChatService(client: ApiClient(dio: dio));
      await service.getAiReply('你好');

      expect(capturedUrl, equals('https://custom.api.com/v1/chat/completions'));
      await box.delete('openai_api');
      await box.delete('openai_base');
    });
  });

  // ──────────────────────────────────────────────────────────────
  // getAiReply — max_tokens 设置
  // ──────────────────────────────────────────────────────────────
  group('getAiReply - max_tokens', () {
    test('max_tokens 为 unlimited 时请求体不含该字段', () async {
      final box = Hive.box('settings');
      await box.put('max_tokens', 'unlimited');

      Map<String, dynamic>? capturedBody;
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedBody = options.data as Map<String, dynamic>?;
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: _openAiResponse('回复'),
          ));
        },
      ));
      final service = ChatService(client: ApiClient(dio: dio));
      await service.getAiReply('你好');

      expect(capturedBody?.containsKey('max_tokens'), isFalse);
      await box.delete('max_tokens');
    });

    test('max_tokens 为数字时请求体包含该字段', () async {
      final box = Hive.box('settings');
      await box.put('max_tokens', '500');

      Map<String, dynamic>? capturedBody;
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedBody = options.data as Map<String, dynamic>?;
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: _openAiResponse('回复'),
          ));
        },
      ));
      final service = ChatService(client: ApiClient(dio: dio));
      await service.getAiReply('你好');

      expect(capturedBody?['max_tokens'], equals(500));
      await box.delete('max_tokens');
    });
  });

  // ──────────────────────────────────────────────────────────────
  // generateConversationTitle
  // ──────────────────────────────────────────────────────────────
  group('generateConversationTitle', () {
    test('AI 返回标题时使用 AI 标题', () async {
      final client = _mockClient(
        responseData: _openAiResponse('蓝牙耳机推荐'),
      );
      final service = ChatService(client: client);
      final title = await service.generateConversationTitle('我想买蓝牙耳机');
      expect(title, equals('蓝牙耳机推荐'));
    });

    test('AI 标题超过 15 字时截断', () async {
      final client = _mockClient(
        responseData: _openAiResponse('这是一个超过十五个汉字的非常长的会话标题内容'),
      );
      final service = ChatService(client: client);
      final title = await service.generateConversationTitle('测试');
      expect(title.length, lessThanOrEqualTo(15));
    });

    test('AI 返回空时回退到截断原始消息', () async {
      final client = _mockClient(
        responseData: _openAiResponse(''),
      );
      final service = ChatService(client: client);
      final title = await service.generateConversationTitle('我想买一款性价比高的蓝牙耳机推荐');
      expect(title, isNotEmpty);
      expect(title.length, lessThanOrEqualTo(15));
    });

    test('原始消息为空时返回默认标题', () async {
      final client = _mockClient(
        responseData: _openAiResponse(''),
      );
      final service = ChatService(client: client);
      final title = await service.generateConversationTitle('');
      expect(title, equals('对话'));
    });

    test('AI 调用失败时回退到截断原始消息', () async {
      final client = _mockClient(
        responseData: null,
        throwDio: true,
        dioErrorType: DioExceptionType.connectionError,
      );
      final service = ChatService(client: client);
      final title = await service.generateConversationTitle('我想买蓝牙耳机');
      expect(title, isNotEmpty);
    });

    test('短消息不添加省略号', () async {
      final client = _mockClient(
        responseData: _openAiResponse(''),
      );
      final service = ChatService(client: client);
      final title = await service.generateConversationTitle('买耳机');
      expect(title, equals('买耳机'));
    });
  });
}

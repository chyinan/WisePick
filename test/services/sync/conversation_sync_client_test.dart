import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wisepick_dart_version/features/auth/token_manager.dart';
import 'package:wisepick_dart_version/services/sync/conversation_sync_client.dart';

class _FakeTokenManager extends TokenManager {
  final bool _loggedIn;
  final String? _token;

  _FakeTokenManager({bool loggedIn = false, String? token})
      : _loggedIn = loggedIn,
        _token = token,
        super.forTesting();

  @override
  bool get isLoggedIn => _loggedIn;

  @override
  String? get accessToken => _token;
}

Dio _mockDio({
  required dynamic responseData,
  int statusCode = 200,
  DioExceptionType? errorType,
  int? errorStatusCode,
}) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      if (errorType != null) {
        handler.reject(DioException(
          requestOptions: options,
          type: errorType,
          response: errorStatusCode != null
              ? Response(requestOptions: options, statusCode: errorStatusCode)
              : null,
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
  return dio;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('conv_sync_client_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('sync_meta');
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  // ──────────────────────────────────────────────────────────────
  // ConversationChange
  // ──────────────────────────────────────────────────────────────
  group('ConversationChange', () {
    test('toJson 只序列化非 null 字段', () {
      final c = ConversationChange(clientId: 'conv1');
      final json = c.toJson();
      expect(json['client_id'], equals('conv1'));
      expect(json['is_deleted'], isFalse);
      expect(json.containsKey('title'), isFalse);
      expect(json.containsKey('created_at'), isFalse);
    });

    test('toJson 序列化所有字段', () {
      final now = DateTime(2024, 1, 1, 10, 0, 0);
      final c = ConversationChange(
        clientId: 'conv1',
        title: '测试会话',
        isDeleted: true,
        localVersion: 3,
        createdAt: now,
        updatedAt: now,
      );
      final json = c.toJson();
      expect(json['title'], equals('测试会话'));
      expect(json['is_deleted'], isTrue);
      expect(json['local_version'], equals(3));
      expect(json['created_at'], equals(now.toIso8601String()));
    });

    test('fromJson 正确解析', () {
      final json = {
        'client_id': 'conv1',
        'title': '会话标题',
        'is_deleted': false,
        'local_version': 2,
        'created_at': '2024-01-01T10:00:00.000',
        'updated_at': '2024-01-01T11:00:00.000',
      };
      final c = ConversationChange.fromJson(json);
      expect(c.clientId, equals('conv1'));
      expect(c.title, equals('会话标题'));
      expect(c.isDeleted, isFalse);
      expect(c.localVersion, equals(2));
      expect(c.createdAt, isNotNull);
    });

    test('fromJson 缺失字段使用默认值', () {
      final c = ConversationChange.fromJson({'client_id': 'conv1'});
      expect(c.isDeleted, isFalse);
      expect(c.localVersion, equals(0));
      expect(c.title, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // MessageChange
  // ──────────────────────────────────────────────────────────────
  group('MessageChange', () {
    test('toJson 只序列化非 null 字段', () {
      final m = MessageChange(
        conversationClientId: 'conv1',
        clientId: 'msg1',
        role: 'user',
        content: '你好',
      );
      final json = m.toJson();
      expect(json['conversation_client_id'], equals('conv1'));
      expect(json['client_id'], equals('msg1'));
      expect(json['role'], equals('user'));
      expect(json['content'], equals('你好'));
      expect(json['failed'], isFalse);
      expect(json.containsKey('products'), isFalse);
      expect(json.containsKey('keywords'), isFalse);
      expect(json.containsKey('ai_parsed_raw'), isFalse);
    });

    test('toJson 序列化可选字段', () {
      final m = MessageChange(
        conversationClientId: 'conv1',
        clientId: 'msg1',
        role: 'assistant',
        content: '推荐商品',
        products: [
          {'id': 'p1', 'title': '商品1'}
        ],
        keywords: ['耳机', '蓝牙'],
        aiParsedRaw: '{"recommendations":[]}',
        failed: true,
        retryForText: '原始文本',
      );
      final json = m.toJson();
      expect(json['products'], isNotNull);
      expect(json['keywords'], equals(['耳机', '蓝牙']));
      expect(json['ai_parsed_raw'], equals('{"recommendations":[]}'));
      expect(json['failed'], isTrue);
      expect(json['retry_for_text'], equals('原始文本'));
    });

    test('fromJson 正确解析', () {
      final json = {
        'conversation_client_id': 'conv1',
        'client_id': 'msg1',
        'role': 'user',
        'content': '你好',
        'failed': false,
        'local_version': 1,
        'keywords': ['耳机'],
        'created_at': '2024-01-01T10:00:00.000',
      };
      final m = MessageChange.fromJson(json);
      expect(m.conversationClientId, equals('conv1'));
      expect(m.clientId, equals('msg1'));
      expect(m.role, equals('user'));
      expect(m.keywords, equals(['耳机']));
      expect(m.localVersion, equals(1));
      expect(m.createdAt, isNotNull);
    });

    test('fromJson 缺失字段使用默认值', () {
      final m = MessageChange.fromJson({
        'conversation_client_id': 'conv1',
        'client_id': 'msg1',
        'role': 'user',
        'content': '你好',
      });
      expect(m.failed, isFalse);
      expect(m.localVersion, equals(0));
      expect(m.products, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // ConversationSyncResponse
  // ──────────────────────────────────────────────────────────────
  group('ConversationSyncResponse', () {
    test('fromJson 正确解析', () {
      final json = {
        'success': true,
        'current_version': 8,
        'conversations': [
          {'client_id': 'conv1', 'title': '会话1'}
        ],
        'messages': [
          {'client_id': 'msg1', 'content': '你好'}
        ],
        'deleted_conversation_ids': ['conv2'],
        'message': '同步成功',
      };
      final resp = ConversationSyncResponse.fromJson(json);
      expect(resp.success, isTrue);
      expect(resp.currentVersion, equals(8));
      expect(resp.conversations.length, equals(1));
      expect(resp.messages.length, equals(1));
      expect(resp.deletedConversationIds, equals(['conv2']));
    });

    test('fromJson 缺失字段使用默认值', () {
      final resp = ConversationSyncResponse.fromJson({});
      expect(resp.success, isFalse);
      expect(resp.currentVersion, equals(0));
      expect(resp.conversations, isEmpty);
      expect(resp.messages, isEmpty);
      expect(resp.deletedConversationIds, isEmpty);
    });

    test('error 工厂方法', () {
      final resp = ConversationSyncResponse.error('同步失败');
      expect(resp.success, isFalse);
      expect(resp.message, equals('同步失败'));
      expect(resp.conversations, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // ConversationSyncClient — 本地存储
  // ──────────────────────────────────────────────────────────────
  group('ConversationSyncClient - 本地存储', () {
    late ConversationSyncClient client;

    setUp(() {
      client = ConversationSyncClient(
        dio: _mockDio(responseData: {}),
        tokenManager: _FakeTokenManager(),
      );
    });

    test('getLocalSyncVersion 初始为 0', () async {
      expect(await client.getLocalSyncVersion(), equals(0));
    });

    test('saveLocalSyncVersion / getLocalSyncVersion 读写', () async {
      await client.saveLocalSyncVersion(15);
      expect(await client.getLocalSyncVersion(), equals(15));
    });

    test('getPendingConversationChanges 初始为空', () async {
      expect(await client.getPendingConversationChanges(), isEmpty);
    });

    test('addPendingConversationChange 添加新变更', () async {
      await client.addPendingConversationChange({'client_id': 'conv1', 'title': '会话1'});
      final changes = await client.getPendingConversationChanges();
      expect(changes.length, equals(1));
      expect(changes[0]['client_id'], equals('conv1'));
    });

    test('addPendingConversationChange 相同 client_id 时更新', () async {
      await client.addPendingConversationChange({'client_id': 'conv1', 'title': '旧标题'});
      await client.addPendingConversationChange({'client_id': 'conv1', 'title': '新标题'});
      final changes = await client.getPendingConversationChanges();
      expect(changes.length, equals(1));
      expect(changes[0]['title'], equals('新标题'));
    });

    test('getPendingMessageChanges 初始为空', () async {
      expect(await client.getPendingMessageChanges(), isEmpty);
    });

    test('addPendingMessageChange 添加新消息变更', () async {
      await client.addPendingMessageChange({'client_id': 'msg1', 'content': '你好'});
      final changes = await client.getPendingMessageChanges();
      expect(changes.length, equals(1));
      expect(changes[0]['client_id'], equals('msg1'));
    });

    test('addPendingMessageChange 相同 client_id 时更新', () async {
      await client.addPendingMessageChange({'client_id': 'msg1', 'content': '旧内容'});
      await client.addPendingMessageChange({'client_id': 'msg1', 'content': '新内容'});
      final changes = await client.getPendingMessageChanges();
      expect(changes.length, equals(1));
      expect(changes[0]['content'], equals('新内容'));
    });

    test('clearPendingChanges 清空两个队列', () async {
      await client.addPendingConversationChange({'client_id': 'conv1'});
      await client.addPendingMessageChange({'client_id': 'msg1'});
      await client.clearPendingChanges();
      expect(await client.getPendingConversationChanges(), isEmpty);
      expect(await client.getPendingMessageChanges(), isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // ConversationSyncClient — sync
  // ──────────────────────────────────────────────────────────────
  group('ConversationSyncClient - sync', () {
    test('未登录时返回 error', () async {
      final client = ConversationSyncClient(
        dio: _mockDio(responseData: {}),
        tokenManager: _FakeTokenManager(loggedIn: false),
      );
      final result = await client.sync();
      expect(result.success, isFalse);
      expect(result.message, contains('未登录'));
    });

    test('成功时返回 success=true、更新版本号、清空 pending', () async {
      final client = ConversationSyncClient(
        dio: _mockDio(responseData: {
          'success': true,
          'current_version': 5,
          'conversations': [],
          'messages': [],
          'deleted_conversation_ids': [],
        }),
        tokenManager: _FakeTokenManager(loggedIn: true, token: 'test-token'),
      );
      await client.addPendingConversationChange({'client_id': 'conv1'});
      final result = await client.sync();
      expect(result.success, isTrue);
      expect(result.currentVersion, equals(5));
      expect(await client.getLocalSyncVersion(), equals(5));
      expect(await client.getPendingConversationChanges(), isEmpty);
    });

    test('服务器返回 401 时返回认证失败消息', () async {
      final client = ConversationSyncClient(
        dio: _mockDio(
          responseData: null,
          errorType: DioExceptionType.badResponse,
          errorStatusCode: 401,
        ),
        tokenManager: _FakeTokenManager(loggedIn: true, token: 'test-token'),
      );
      final result = await client.sync();
      expect(result.success, isFalse);
      expect(result.message, contains('认证'));
    });

    test('传入 changes 参数时合并到请求', () async {
      Map<String, dynamic>? capturedBody;
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedBody = jsonDecode(options.data as String) as Map<String, dynamic>;
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'success': true,
              'current_version': 1,
              'conversations': [],
              'messages': [],
              'deleted_conversation_ids': [],
            },
          ));
        },
      ));
      final client = ConversationSyncClient(
        dio: dio,
        tokenManager: _FakeTokenManager(loggedIn: true, token: 'test-token'),
      );
      await client.sync(
        conversationChanges: [
          ConversationChange(clientId: 'conv1', title: '测试会话'),
        ],
        messageChanges: [
          MessageChange(
            conversationClientId: 'conv1',
            clientId: 'msg1',
            role: 'user',
            content: '你好',
          ),
        ],
      );
      final convChanges = capturedBody!['conversation_changes'] as List;
      final msgChanges = capturedBody!['message_changes'] as List;
      expect(convChanges.length, equals(1));
      expect(msgChanges.length, equals(1));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // ConversationSyncClient — getCloudConversations
  // ──────────────────────────────────────────────────────────────
  group('ConversationSyncClient - getCloudConversations', () {
    test('未登录时返回 error', () async {
      final client = ConversationSyncClient(
        dio: _mockDio(responseData: {}),
        tokenManager: _FakeTokenManager(loggedIn: false),
      );
      final result = await client.getCloudConversations();
      expect(result.success, isFalse);
    });

    test('成功时返回 conversations', () async {
      final client = ConversationSyncClient(
        dio: _mockDio(responseData: {
          'success': true,
          'current_version': 3,
          'conversations': [
            {'client_id': 'conv1', 'title': '会话1'}
          ],
        }),
        tokenManager: _FakeTokenManager(loggedIn: true, token: 'test-token'),
      );
      final result = await client.getCloudConversations();
      expect(result.success, isTrue);
      expect(result.conversations.length, equals(1));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // ConversationSyncClient — getCloudMessages
  // ──────────────────────────────────────────────────────────────
  group('ConversationSyncClient - getCloudMessages', () {
    test('未登录时返回空列表', () async {
      final client = ConversationSyncClient(
        dio: _mockDio(responseData: {}),
        tokenManager: _FakeTokenManager(loggedIn: false),
      );
      expect(await client.getCloudMessages('conv1'), isEmpty);
    });

    test('成功时返回消息列表', () async {
      final client = ConversationSyncClient(
        dio: _mockDio(responseData: {
          'success': true,
          'messages': [
            {'client_id': 'msg1', 'content': '你好'}
          ],
        }),
        tokenManager: _FakeTokenManager(loggedIn: true, token: 'test-token'),
      );
      final messages = await client.getCloudMessages('conv1');
      expect(messages.length, equals(1));
      expect(messages[0]['client_id'], equals('msg1'));
    });

    test('请求失败时返回空列表', () async {
      final client = ConversationSyncClient(
        dio: _mockDio(
          responseData: null,
          errorType: DioExceptionType.connectionError,
        ),
        tokenManager: _FakeTokenManager(loggedIn: true, token: 'test-token'),
      );
      expect(await client.getCloudMessages('conv1'), isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // ConversationSyncClient — getCloudVersion
  // ──────────────────────────────────────────────────────────────
  group('ConversationSyncClient - getCloudVersion', () {
    test('未登录时返回 0', () async {
      final client = ConversationSyncClient(
        dio: _mockDio(responseData: {}),
        tokenManager: _FakeTokenManager(loggedIn: false),
      );
      expect(await client.getCloudVersion(), equals(0));
    });

    test('成功时返回版本号', () async {
      final client = ConversationSyncClient(
        dio: _mockDio(responseData: {'current_version': 12}),
        tokenManager: _FakeTokenManager(loggedIn: true, token: 'test-token'),
      );
      expect(await client.getCloudVersion(), equals(12));
    });

    test('请求失败时返回 0', () async {
      final client = ConversationSyncClient(
        dio: _mockDio(
          responseData: null,
          errorType: DioExceptionType.connectionError,
        ),
        tokenManager: _FakeTokenManager(loggedIn: true, token: 'test-token'),
      );
      expect(await client.getCloudVersion(), equals(0));
    });
  });
}

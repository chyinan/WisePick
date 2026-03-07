import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wisepick_dart_version/features/chat/conversation_model.dart';
import 'package:wisepick_dart_version/features/chat/chat_message.dart';
import 'package:wisepick_dart_version/features/chat/conversation_repository.dart';

ConversationModel _makeConv({
  String id = 'conv1',
  String title = '测试会话',
  List<ChatMessage>? messages,
  DateTime? timestamp,
}) {
  return ConversationModel(
    id: id,
    title: title,
    messages: messages ?? [],
    timestamp: timestamp,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ConversationRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('conv_repo_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('conversations');
    repo = ConversationRepository();
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  // ──────────────────────────────────────────────────────────────
  // listConversations
  // ──────────────────────────────────────────────────────────────
  group('listConversations', () {
    test('空 box 返回空列表', () async {
      expect(await repo.listConversations(), isEmpty);
    });

    test('保存后能列出', () async {
      await repo.saveConversation(_makeConv(id: 'c1', title: '会话1'));
      final list = await repo.listConversations();
      expect(list.length, equals(1));
      expect(list[0].id, equals('c1'));
    });

    test('多条会话按 timestamp 降序排列', () async {
      final now = DateTime.now();
      await repo.saveConversation(_makeConv(
        id: 'old',
        title: '旧会话',
        timestamp: now.subtract(const Duration(hours: 2)),
      ));
      await repo.saveConversation(_makeConv(
        id: 'new',
        title: '新会话',
        timestamp: now,
      ));
      final list = await repo.listConversations();
      expect(list[0].id, equals('new'));
      expect(list[1].id, equals('old'));
    });

    test('跳过损坏的条目不抛出异常', () async {
      // 直接写入非 Map 数据模拟损坏
      final box = await Hive.openBox('conversations');
      await box.put('bad_key', 'not_a_map');
      await repo.saveConversation(_makeConv(id: 'good'));
      final list = await repo.listConversations();
      // 只返回有效条目
      expect(list.length, equals(1));
      expect(list[0].id, equals('good'));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // getConversation
  // ──────────────────────────────────────────────────────────────
  group('getConversation', () {
    test('不存在时返回 null', () async {
      expect(await repo.getConversation('nonexistent'), isNull);
    });

    test('保存后能按 id 获取', () async {
      await repo.saveConversation(_makeConv(id: 'c1', title: '会话1'));
      final conv = await repo.getConversation('c1');
      expect(conv, isNotNull);
      expect(conv!.title, equals('会话1'));
    });

    test('获取正确的 id，不返回其他会话', () async {
      await repo.saveConversation(_makeConv(id: 'c1', title: '会话1'));
      await repo.saveConversation(_makeConv(id: 'c2', title: '会话2'));
      final conv = await repo.getConversation('c2');
      expect(conv!.title, equals('会话2'));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // saveConversation
  // ──────────────────────────────────────────────────────────────
  group('saveConversation', () {
    test('保存新会话', () async {
      await repo.saveConversation(_makeConv(id: 'c1', title: '新会话'));
      expect(await repo.getConversation('c1'), isNotNull);
    });

    test('覆盖同 id 的旧会话', () async {
      await repo.saveConversation(_makeConv(id: 'c1', title: '旧标题'));
      await repo.saveConversation(_makeConv(id: 'c1', title: '新标题'));
      final conv = await repo.getConversation('c1');
      expect(conv!.title, equals('新标题'));
    });

    test('保存后 listConversations 数量正确', () async {
      await repo.saveConversation(_makeConv(id: 'c1'));
      await repo.saveConversation(_makeConv(id: 'c2'));
      await repo.saveConversation(_makeConv(id: 'c3'));
      expect((await repo.listConversations()).length, equals(3));
    });

    test('保存含消息的会话后能正确还原', () async {
      final msg = ChatMessage(
        id: 'msg1',
        text: '你好',
        isUser: true,
        timestamp: DateTime(2024, 1, 1),
      );
      await repo.saveConversation(_makeConv(id: 'c1', messages: [msg]));
      final conv = await repo.getConversation('c1');
      expect(conv!.messages.length, equals(1));
      expect(conv.messages[0].text, equals('你好'));
      expect(conv.messages[0].isUser, isTrue);
    });

    test('保存时过滤 PARSE_ 调试标记', () async {
      final msg = ChatMessage(
        id: 'msg1',
        text: '正常内容\nPARSE_DEBUG: 调试信息\n其他内容',
        isUser: false,
        timestamp: DateTime(2024, 1, 1),
      );
      await repo.saveConversation(_makeConv(id: 'c1', messages: [msg]));
      final conv = await repo.getConversation('c1');
      expect(conv!.messages[0].text, isNot(contains('PARSE_DEBUG')));
      expect(conv.messages[0].text, contains('正常内容'));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // deleteConversation
  // ──────────────────────────────────────────────────────────────
  group('deleteConversation', () {
    test('删除后 getConversation 返回 null', () async {
      await repo.saveConversation(_makeConv(id: 'c1'));
      await repo.deleteConversation('c1');
      expect(await repo.getConversation('c1'), isNull);
    });

    test('删除后 listConversations 不包含该会话', () async {
      await repo.saveConversation(_makeConv(id: 'c1'));
      await repo.saveConversation(_makeConv(id: 'c2'));
      await repo.deleteConversation('c1');
      final list = await repo.listConversations();
      expect(list.length, equals(1));
      expect(list[0].id, equals('c2'));
    });

    test('删除不存在的 id 不抛出异常', () async {
      await expectLater(repo.deleteConversation('nonexistent'), completes);
    });

    test('删除一个不影响其他会话', () async {
      await repo.saveConversation(_makeConv(id: 'c1', title: '保留'));
      await repo.saveConversation(_makeConv(id: 'c2', title: '删除'));
      await repo.deleteConversation('c2');
      final conv = await repo.getConversation('c1');
      expect(conv!.title, equals('保留'));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // 数据持久化（关闭再打开 box）
  // ──────────────────────────────────────────────────────────────
  group('数据持久化', () {
    test('关闭再打开 box 后数据仍存在', () async {
      await repo.saveConversation(_makeConv(id: 'persist', title: '持久化测试'));
      await Hive.close();
      Hive.init(tempDir.path);
      await Hive.openBox('conversations');
      repo = ConversationRepository();
      final conv = await repo.getConversation('persist');
      expect(conv, isNotNull);
      expect(conv!.title, equals('持久化测试'));
    });
  });
}

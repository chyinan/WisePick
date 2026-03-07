import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wisepick_dart_version/services/sync/offline_sync_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late OfflineSyncQueue queue;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('offline_sync_queue_test_');
    Hive.init(tempDir.path);
    queue = OfflineSyncQueue();
    await queue.init();
  });

  tearDown(() async {
    await queue.dispose();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  // ──────────────────────────────────────────────────────────────
  // 初始状态
  // ──────────────────────────────────────────────────────────────
  group('初始状态', () {
    test('初始化后无待同步变更', () {
      expect(queue.hasPendingChanges, isFalse);
    });

    test('初始购物车变更数量为 0', () {
      expect(queue.pendingCartChangesCount, equals(0));
    });

    test('初始会话变更数量为 0', () {
      expect(queue.pendingConversationChangesCount, equals(0));
    });

    test('getCartChanges 返回空列表', () {
      expect(queue.getCartChanges(), isEmpty);
    });

    test('getConversationChanges 返回空列表', () {
      expect(queue.getConversationChanges(), isEmpty);
    });

    test('getMessageChanges 返回空列表', () {
      expect(queue.getMessageChanges(), isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // 添加购物车变更
  // ──────────────────────────────────────────────────────────────
  group('addCartChange', () {
    test('添加后 hasPendingChanges 为 true', () async {
      await queue.addCartChange({'id': 'item1', 'qty': 2});
      expect(queue.hasPendingChanges, isTrue);
    });

    test('添加后 pendingCartChangesCount 增加', () async {
      await queue.addCartChange({'id': 'item1', 'qty': 2});
      await queue.addCartChange({'id': 'item2', 'qty': 1});
      expect(queue.pendingCartChangesCount, equals(2));
    });

    test('getCartChanges 返回正确数据', () async {
      await queue.addCartChange({'id': 'item1', 'qty': 3, 'action': 'add'});
      final changes = queue.getCartChanges();
      expect(changes.length, equals(1));
      expect(changes[0]['id'], equals('item1'));
      expect(changes[0]['qty'], equals(3));
      expect(changes[0]['action'], equals('add'));
    });

    test('自动添加 queued_at 时间戳', () async {
      await queue.addCartChange({'id': 'item1'});
      final changes = queue.getCartChanges();
      expect(changes[0].containsKey('queued_at'), isTrue);
      // 验证是合法的 ISO8601 时间戳
      expect(DateTime.tryParse(changes[0]['queued_at'] as String), isNotNull);
    });

    test('不修改调用方传入的 map（防御性拷贝）', () async {
      final original = {'id': 'item1', 'qty': 1};
      await queue.addCartChange(original);
      // 原始 map 不应被修改（不含 queued_at）
      expect(original.containsKey('queued_at'), isFalse);
    });

    test('多次添加保留所有变更', () async {
      for (var i = 0; i < 5; i++) {
        await queue.addCartChange({'id': 'item$i', 'qty': i + 1});
      }
      expect(queue.pendingCartChangesCount, equals(5));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // 添加会话变更
  // ──────────────────────────────────────────────────────────────
  group('addConversationChange', () {
    test('添加后 hasPendingChanges 为 true', () async {
      await queue.addConversationChange({'id': 'conv1', 'action': 'update'});
      expect(queue.hasPendingChanges, isTrue);
    });

    test('pendingConversationChangesCount 正确计数', () async {
      await queue.addConversationChange({'id': 'conv1'});
      await queue.addConversationChange({'id': 'conv2'});
      expect(queue.pendingConversationChangesCount, equals(2));
    });

    test('getConversationChanges 返回正确数据', () async {
      await queue.addConversationChange({'id': 'conv1', 'title': '测试会话'});
      final changes = queue.getConversationChanges();
      expect(changes[0]['id'], equals('conv1'));
      expect(changes[0]['title'], equals('测试会话'));
    });

    test('自动添加 queued_at 时间戳', () async {
      await queue.addConversationChange({'id': 'conv1'});
      final changes = queue.getConversationChanges();
      expect(changes[0].containsKey('queued_at'), isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // 添加消息变更
  // ──────────────────────────────────────────────────────────────
  group('addMessageChange', () {
    test('添加后 hasPendingChanges 为 true', () async {
      await queue.addMessageChange({'id': 'msg1', 'content': '你好'});
      expect(queue.hasPendingChanges, isTrue);
    });

    test('getMessageChanges 返回正确数据', () async {
      await queue.addMessageChange({'id': 'msg1', 'content': '你好', 'conv_id': 'conv1'});
      final changes = queue.getMessageChanges();
      expect(changes.length, equals(1));
      expect(changes[0]['content'], equals('你好'));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // 清空操作
  // ──────────────────────────────────────────────────────────────
  group('清空操作', () {
    test('clearCartChanges 清空购物车队列', () async {
      await queue.addCartChange({'id': 'item1'});
      await queue.addCartChange({'id': 'item2'});
      await queue.clearCartChanges();
      expect(queue.pendingCartChangesCount, equals(0));
      expect(queue.getCartChanges(), isEmpty);
    });

    test('clearConversationChanges 清空会话队列', () async {
      await queue.addConversationChange({'id': 'conv1'});
      await queue.clearConversationChanges();
      expect(queue.pendingConversationChangesCount, equals(0));
    });

    test('clearMessageChanges 清空消息队列', () async {
      await queue.addMessageChange({'id': 'msg1'});
      await queue.clearMessageChanges();
      expect(queue.getMessageChanges(), isEmpty);
    });

    test('clearAll 清空所有队列', () async {
      await queue.addCartChange({'id': 'item1'});
      await queue.addConversationChange({'id': 'conv1'});
      await queue.addMessageChange({'id': 'msg1'});
      await queue.clearAll();
      expect(queue.hasPendingChanges, isFalse);
      expect(queue.pendingCartChangesCount, equals(0));
      expect(queue.pendingConversationChangesCount, equals(0));
    });

    test('clearCartChanges 不影响会话队列', () async {
      await queue.addCartChange({'id': 'item1'});
      await queue.addConversationChange({'id': 'conv1'});
      await queue.clearCartChanges();
      expect(queue.pendingCartChangesCount, equals(0));
      expect(queue.pendingConversationChangesCount, equals(1));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // hasPendingChanges 综合判断
  // ──────────────────────────────────────────────────────────────
  group('hasPendingChanges', () {
    test('只有购物车变更时为 true', () async {
      await queue.addCartChange({'id': 'item1'});
      expect(queue.hasPendingChanges, isTrue);
    });

    test('只有会话变更时为 true', () async {
      await queue.addConversationChange({'id': 'conv1'});
      expect(queue.hasPendingChanges, isTrue);
    });

    test('只有消息变更时为 true', () async {
      await queue.addMessageChange({'id': 'msg1'});
      expect(queue.hasPendingChanges, isTrue);
    });

    test('全部清空后为 false', () async {
      await queue.addCartChange({'id': 'item1'});
      await queue.addConversationChange({'id': 'conv1'});
      await queue.clearAll();
      expect(queue.hasPendingChanges, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // 重复初始化保护
  // ──────────────────────────────────────────────────────────────
  group('重复初始化', () {
    test('多次调用 init 不崩溃', () async {
      await queue.init();
      await queue.init();
      await queue.init();
      // 仍然可以正常使用
      await queue.addCartChange({'id': 'item1'});
      expect(queue.pendingCartChangesCount, equals(1));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // onNetworkRestored 回调
  // ──────────────────────────────────────────────────────────────
  group('onNetworkRestored', () {
    test('可以设置回调而不崩溃', () {
      var called = false;
      queue.onNetworkRestored = () {
        called = true;
      };
      // 回调已注册，不会立即触发
      expect(called, isFalse);
    });
  });
}

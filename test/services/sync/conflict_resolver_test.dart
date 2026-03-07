import 'package:flutter_test/flutter_test.dart';
import 'package:wisepick_dart_version/services/sync/conflict_resolver.dart';

void main() {
  // ──────────────────────────────────────────────────────────────
  // SyncConflict.recommendedResolution
  // ──────────────────────────────────────────────────────────────
  group('SyncConflict.recommendedResolution', () {
    test('bothAdded → merge', () {
      final c = SyncConflict<String>(id: '1', type: ConflictType.bothAdded);
      expect(c.recommendedResolution, ConflictResolutionStrategy.merge);
    });

    test('bothModified → lastWriteWins', () {
      final c = SyncConflict<String>(id: '1', type: ConflictType.bothModified);
      expect(c.recommendedResolution, ConflictResolutionStrategy.lastWriteWins);
    });

    test('deleteVsModify → keepLocal', () {
      final c = SyncConflict<String>(id: '1', type: ConflictType.deleteVsModify);
      expect(c.recommendedResolution, ConflictResolutionStrategy.keepLocal);
    });

    test('versionMismatch → keepServer', () {
      final c = SyncConflict<String>(id: '1', type: ConflictType.versionMismatch);
      expect(c.recommendedResolution, ConflictResolutionStrategy.keepServer);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // SyncConflict.resolveWith
  // ──────────────────────────────────────────────────────────────
  group('SyncConflict.resolveWith', () {
    test('keepLocal 返回本地数据', () {
      final c = SyncConflict<String>(
        id: '1',
        type: ConflictType.bothModified,
        localData: 'local',
        serverData: 'server',
      );
      expect(c.resolveWith(ConflictResolutionStrategy.keepLocal), equals('local'));
    });

    test('keepServer 返回服务器数据', () {
      final c = SyncConflict<String>(
        id: '1',
        type: ConflictType.bothModified,
        localData: 'local',
        serverData: 'server',
      );
      expect(c.resolveWith(ConflictResolutionStrategy.keepServer), equals('server'));
    });

    test('lastWriteWins - 本地更新时返回本地', () {
      final now = DateTime.now();
      final c = SyncConflict<String>(
        id: '1',
        type: ConflictType.bothModified,
        localData: 'local',
        serverData: 'server',
        localModifiedAt: now,
        serverModifiedAt: now.subtract(const Duration(minutes: 5)),
      );
      expect(c.resolveWith(ConflictResolutionStrategy.lastWriteWins), equals('local'));
    });

    test('lastWriteWins - 服务器更新时返回服务器', () {
      final now = DateTime.now();
      final c = SyncConflict<String>(
        id: '1',
        type: ConflictType.bothModified,
        localData: 'local',
        serverData: 'server',
        localModifiedAt: now.subtract(const Duration(minutes: 5)),
        serverModifiedAt: now,
      );
      expect(c.resolveWith(ConflictResolutionStrategy.lastWriteWins), equals('server'));
    });

    test('lastWriteWins - 本地时间为 null 时返回服务器', () {
      final c = SyncConflict<String>(
        id: '1',
        type: ConflictType.bothModified,
        localData: 'local',
        serverData: 'server',
        localModifiedAt: null,
        serverModifiedAt: DateTime.now(),
      );
      expect(c.resolveWith(ConflictResolutionStrategy.lastWriteWins), equals('server'));
    });

    test('lastWriteWins - 服务器时间为 null 时返回本地', () {
      final c = SyncConflict<String>(
        id: '1',
        type: ConflictType.bothModified,
        localData: 'local',
        serverData: 'server',
        localModifiedAt: DateTime.now(),
        serverModifiedAt: null,
      );
      expect(c.resolveWith(ConflictResolutionStrategy.lastWriteWins), equals('local'));
    });

    test('merge 返回 null（需外部处理）', () {
      final c = SyncConflict<String>(
        id: '1',
        type: ConflictType.bothAdded,
        localData: 'local',
        serverData: 'server',
      );
      expect(c.resolveWith(ConflictResolutionStrategy.merge), isNull);
    });

    test('askUser 返回 null（需外部处理）', () {
      final c = SyncConflict<String>(
        id: '1',
        type: ConflictType.bothModified,
        localData: 'local',
        serverData: 'server',
      );
      expect(c.resolveWith(ConflictResolutionStrategy.askUser), isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // CartItemConflict.merge
  // ──────────────────────────────────────────────────────────────
  group('CartItemConflict.merge', () {
    test('数量取较大值', () {
      final c = CartItemConflict(
        id: 'item1',
        type: ConflictType.bothModified,
        localData: {'id': 'item1', 'qty': 5},
        serverData: {'id': 'item1', 'qty': 3},
      );
      final result = c.merge();
      expect(result!['qty'], equals(5));
    });

    test('服务器数量更大时取服务器', () {
      final c = CartItemConflict(
        id: 'item1',
        type: ConflictType.bothModified,
        localData: {'id': 'item1', 'qty': 2},
        serverData: {'id': 'item1', 'qty': 8},
      );
      final result = c.merge();
      expect(result!['qty'], equals(8));
    });

    test('本地有 notes 时保留本地 notes', () {
      final c = CartItemConflict(
        id: 'item1',
        type: ConflictType.bothModified,
        localData: {'id': 'item1', 'qty': 1, 'notes': '生日礼物'},
        serverData: {'id': 'item1', 'qty': 1},
      );
      final result = c.merge();
      expect(result!['notes'], equals('生日礼物'));
    });

    test('本地数据为 null 时返回服务器数据', () {
      final c = CartItemConflict(
        id: 'item1',
        type: ConflictType.bothModified,
        localData: null,
        serverData: {'id': 'item1', 'qty': 3},
      );
      expect(c.merge(), equals({'id': 'item1', 'qty': 3}));
    });

    test('服务器数据为 null 时返回本地数据', () {
      final c = CartItemConflict(
        id: 'item1',
        type: ConflictType.bothModified,
        localData: {'id': 'item1', 'qty': 2},
        serverData: null,
      );
      expect(c.merge(), equals({'id': 'item1', 'qty': 2}));
    });

    test('resolveWith(merge) 调用 merge()', () {
      final c = CartItemConflict(
        id: 'item1',
        type: ConflictType.bothModified,
        localData: {'id': 'item1', 'qty': 5},
        serverData: {'id': 'item1', 'qty': 3},
      );
      final result = c.resolveWith(ConflictResolutionStrategy.merge);
      expect(result!['qty'], equals(5));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // ConversationConflict.merge
  // ──────────────────────────────────────────────────────────────
  group('ConversationConflict.merge', () {
    test('合并消息去重并按时间排序', () {
      final c = ConversationConflict(
        id: 'conv1',
        type: ConflictType.bothModified,
        localData: {'id': 'conv1', 'title': '本地标题'},
        serverData: {'id': 'conv1', 'title': '服务器标题'},
        localMessages: [
          {'client_id': 'msg1', 'content': '消息1', 'created_at': '2024-01-01T10:00:00Z'},
          {'client_id': 'msg2', 'content': '消息2', 'created_at': '2024-01-01T10:05:00Z'},
        ],
        serverMessages: [
          {'client_id': 'msg2', 'content': '消息2（服务器版）', 'created_at': '2024-01-01T10:05:00Z'},
          {'client_id': 'msg3', 'content': '消息3', 'created_at': '2024-01-01T10:10:00Z'},
        ],
      );
      final result = c.merge()!;
      final messages = result['messages'] as List;

      // 3 条唯一消息（msg2 服务器版覆盖本地版）
      expect(messages.length, equals(3));
      // 按时间排序
      expect(messages[0]['client_id'], equals('msg1'));
      expect(messages[1]['client_id'], equals('msg2'));
      expect(messages[2]['client_id'], equals('msg3'));
      // msg2 使用服务器版本
      expect(messages[1]['content'], equals('消息2（服务器版）'));
    });

    test('本地更新时使用本地标题', () {
      final now = DateTime.now();
      final c = ConversationConflict(
        id: 'conv1',
        type: ConflictType.bothModified,
        localData: {'id': 'conv1', 'title': '本地新标题'},
        serverData: {'id': 'conv1', 'title': '服务器旧标题'},
        localModifiedAt: now,
        serverModifiedAt: now.subtract(const Duration(hours: 1)),
      );
      final result = c.merge()!;
      expect(result['title'], equals('本地新标题'));
    });

    test('服务器更新时使用服务器标题', () {
      final now = DateTime.now();
      final c = ConversationConflict(
        id: 'conv1',
        type: ConflictType.bothModified,
        localData: {'id': 'conv1', 'title': '本地旧标题'},
        serverData: {'id': 'conv1', 'title': '服务器新标题'},
        localModifiedAt: now.subtract(const Duration(hours: 1)),
        serverModifiedAt: now,
      );
      final result = c.merge()!;
      expect(result['title'], equals('服务器新标题'));
    });

    test('本地数据为 null 时返回服务器数据', () {
      final c = ConversationConflict(
        id: 'conv1',
        type: ConflictType.bothModified,
        localData: null,
        serverData: {'id': 'conv1', 'title': '服务器'},
      );
      expect(c.merge(), equals({'id': 'conv1', 'title': '服务器'}));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // CartConflictResolver
  // ──────────────────────────────────────────────────────────────
  group('CartConflictResolver', () {
    late CartConflictResolver resolver;

    setUp(() {
      resolver = CartConflictResolver();
    });

    test('只在本地存在的项保留', () {
      final result = resolver.resolveConflicts(
        localItems: [
          {'id': 'item1', 'qty': 2}
        ],
        serverItems: [],
      );
      expect(result.resolvedItems.length, equals(1));
      expect(result.resolvedItems[0]['id'], equals('item1'));
    });

    test('只在服务器存在的项保留', () {
      final result = resolver.resolveConflicts(
        localItems: [],
        serverItems: [
          {'id': 'item2', 'qty': 3}
        ],
      );
      expect(result.resolvedItems.length, equals(1));
      expect(result.resolvedItems[0]['id'], equals('item2'));
    });

    test('两边都删除的项被丢弃', () {
      final result = resolver.resolveConflicts(
        localItems: [
          {'id': 'item1', 'qty': 1, 'is_deleted': true}
        ],
        serverItems: [
          {'id': 'item1', 'qty': 1, 'is_deleted': true}
        ],
      );
      expect(result.resolvedItems, isEmpty);
    });

    test('本地删除、服务器修改 → 保留服务器版本', () {
      final result = resolver.resolveConflicts(
        localItems: [
          {'id': 'item1', 'qty': 1, 'is_deleted': true}
        ],
        serverItems: [
          {'id': 'item1', 'qty': 5}
        ],
      );
      expect(result.resolvedItems.length, equals(1));
      expect(result.resolvedItems[0]['qty'], equals(5));
      expect(result.autoResolvedCount, equals(1));
    });

    test('服务器删除、本地修改 → 保留本地版本', () {
      final result = resolver.resolveConflicts(
        localItems: [
          {'id': 'item1', 'qty': 3}
        ],
        serverItems: [
          {'id': 'item1', 'qty': 1, 'is_deleted': true}
        ],
      );
      expect(result.resolvedItems.length, equals(1));
      expect(result.resolvedItems[0]['qty'], equals(3));
    });

    test('两边都修改时默认使用 merge 策略（数量取较大值）', () {
      final result = resolver.resolveConflicts(
        localItems: [
          {'id': 'item1', 'qty': 5}
        ],
        serverItems: [
          {'id': 'item1', 'qty': 3}
        ],
      );
      expect(result.resolvedItems.length, equals(1));
      expect(result.resolvedItems[0]['qty'], equals(5));
      expect(result.autoResolvedCount, equals(1));
    });

    test('allResolved 在无未解决冲突时为 true', () {
      final result = resolver.resolveConflicts(
        localItems: [
          {'id': 'item1', 'qty': 2}
        ],
        serverItems: [
          {'id': 'item1', 'qty': 4}
        ],
      );
      expect(result.allResolved, isTrue);
      expect(result.hasUnresolvedConflicts, isFalse);
    });

    test('多个商品混合场景', () {
      final result = resolver.resolveConflicts(
        localItems: [
          {'id': 'a', 'qty': 1},
          {'id': 'b', 'qty': 2, 'is_deleted': true},
          {'id': 'c', 'qty': 3},
        ],
        serverItems: [
          {'id': 'a', 'qty': 4},
          {'id': 'b', 'qty': 2},
          {'id': 'd', 'qty': 1},
        ],
      );
      // a: merge → qty=4, b: 本地删除服务器保留 → qty=2, c: 只本地, d: 只服务器
      expect(result.resolvedItems.length, equals(4));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // ConversationConflictResolver
  // ──────────────────────────────────────────────────────────────
  group('ConversationConflictResolver', () {
    late ConversationConflictResolver resolver;

    setUp(() {
      resolver = ConversationConflictResolver();
    });

    test('只在本地存在的会话保留', () {
      final result = resolver.resolveConflicts(
        localConversations: [
          {'id': 'conv1', 'title': '本地会话'}
        ],
        serverConversations: [],
      );
      expect(result.resolvedItems.length, equals(1));
    });

    test('只在服务器存在的会话保留', () {
      final result = resolver.resolveConflicts(
        localConversations: [],
        serverConversations: [
          {'id': 'conv1', 'title': '服务器会话'}
        ],
      );
      expect(result.resolvedItems.length, equals(1));
    });

    test('两边都有的会话自动合并消息', () {
      final result = resolver.resolveConflicts(
        localConversations: [
          {
            'id': 'conv1',
            'title': '会话',
            'messages': [
              {'client_id': 'msg1', 'content': '你好', 'created_at': '2024-01-01T10:00:00Z'}
            ],
          }
        ],
        serverConversations: [
          {
            'id': 'conv1',
            'title': '会话',
            'messages': [
              {'client_id': 'msg2', 'content': '世界', 'created_at': '2024-01-01T10:01:00Z'}
            ],
          }
        ],
      );
      expect(result.resolvedItems.length, equals(1));
      expect(result.autoResolvedCount, equals(1));
      final messages = result.resolvedItems[0]['messages'] as List;
      expect(messages.length, equals(2));
    });

    test('使用 client_id 或 id 作为消息唯一键', () {
      final result = resolver.resolveConflicts(
        localConversations: [
          {
            'id': 'conv1',
            'title': '会话',
            'messages': [
              {'id': 'server-msg-1', 'content': '本地版', 'created_at': '2024-01-01T10:00:00Z'}
            ],
          }
        ],
        serverConversations: [
          {
            'id': 'conv1',
            'title': '会话',
            'messages': [
              {'id': 'server-msg-1', 'content': '服务器版', 'created_at': '2024-01-01T10:00:00Z'}
            ],
          }
        ],
      );
      final messages = result.resolvedItems[0]['messages'] as List;
      // 服务器版覆盖本地版
      expect(messages.length, equals(1));
      expect(messages[0]['content'], equals('服务器版'));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // ConflictResolutionResult
  // ──────────────────────────────────────────────────────────────
  group('ConflictResolutionResult', () {
    test('hasUnresolvedConflicts 在有未解决冲突时为 true', () {
      final conflict = SyncConflict<String>(
        id: '1',
        type: ConflictType.bothModified,
      );
      final result = ConflictResolutionResult<String>(
        resolvedItems: [],
        unresolvedConflicts: [conflict],
        autoResolvedCount: 0,
        userResolvedCount: 0,
      );
      expect(result.hasUnresolvedConflicts, isTrue);
      expect(result.allResolved, isFalse);
    });

    test('allResolved 在无未解决冲突时为 true', () {
      final result = ConflictResolutionResult<String>(
        resolvedItems: ['item'],
        unresolvedConflicts: [],
        autoResolvedCount: 1,
        userResolvedCount: 0,
      );
      expect(result.allResolved, isTrue);
    });
  });
}

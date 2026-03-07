import 'package:flutter_test/flutter_test.dart';
import 'package:wisepick_dart_version/services/sync/sync_manager.dart';

void main() {
  // ──────────────────────────────────────────────────────────────
  // SyncState 默认值
  // ──────────────────────────────────────────────────────────────
  group('SyncState 默认值', () {
    test('默认状态全部为 idle', () {
      const s = SyncState();
      expect(s.cartStatus, SyncStatus.idle);
      expect(s.conversationStatus, SyncStatus.idle);
    });

    test('默认错误信息为 null', () {
      const s = SyncState();
      expect(s.cartError, isNull);
      expect(s.conversationError, isNull);
    });

    test('默认待同步数量为 0', () {
      const s = SyncState();
      expect(s.pendingCartChanges, equals(0));
      expect(s.pendingConversationChanges, equals(0));
    });

    test('默认重试次数为 0', () {
      const s = SyncState();
      expect(s.cartRetryCount, equals(0));
      expect(s.conversationRetryCount, equals(0));
    });

    test('默认上次同步时间为 null', () {
      const s = SyncState();
      expect(s.lastCartSync, isNull);
      expect(s.lastConversationSync, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // SyncState.isSyncing
  // ──────────────────────────────────────────────────────────────
  group('SyncState.isSyncing', () {
    test('购物车同步中时为 true', () {
      const s = SyncState(cartStatus: SyncStatus.syncing);
      expect(s.isSyncing, isTrue);
    });

    test('会话同步中时为 true', () {
      const s = SyncState(conversationStatus: SyncStatus.syncing);
      expect(s.isSyncing, isTrue);
    });

    test('两者都同步中时为 true', () {
      const s = SyncState(
        cartStatus: SyncStatus.syncing,
        conversationStatus: SyncStatus.syncing,
      );
      expect(s.isSyncing, isTrue);
    });

    test('idle 状态时为 false', () {
      const s = SyncState();
      expect(s.isSyncing, isFalse);
    });

    test('success 状态时为 false', () {
      const s = SyncState(
        cartStatus: SyncStatus.success,
        conversationStatus: SyncStatus.success,
      );
      expect(s.isSyncing, isFalse);
    });

    test('error 状态时为 false', () {
      const s = SyncState(
        cartStatus: SyncStatus.error,
        conversationStatus: SyncStatus.error,
      );
      expect(s.isSyncing, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // SyncState.hasPendingChanges
  // ──────────────────────────────────────────────────────────────
  group('SyncState.hasPendingChanges', () {
    test('有购物车待同步时为 true', () {
      const s = SyncState(pendingCartChanges: 3);
      expect(s.hasPendingChanges, isTrue);
    });

    test('有会话待同步时为 true', () {
      const s = SyncState(pendingConversationChanges: 1);
      expect(s.hasPendingChanges, isTrue);
    });

    test('两者都有待同步时为 true', () {
      const s = SyncState(pendingCartChanges: 2, pendingConversationChanges: 5);
      expect(s.hasPendingChanges, isTrue);
    });

    test('两者都为 0 时为 false', () {
      const s = SyncState();
      expect(s.hasPendingChanges, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // SyncState.copyWith
  // ──────────────────────────────────────────────────────────────
  group('SyncState.copyWith', () {
    test('更新 cartStatus', () {
      const s = SyncState();
      final updated = s.copyWith(cartStatus: SyncStatus.syncing);
      expect(updated.cartStatus, SyncStatus.syncing);
      expect(updated.conversationStatus, SyncStatus.idle); // 未变
    });

    test('更新 conversationStatus', () {
      const s = SyncState();
      final updated = s.copyWith(conversationStatus: SyncStatus.success);
      expect(updated.conversationStatus, SyncStatus.success);
      expect(updated.cartStatus, SyncStatus.idle); // 未变
    });

    test('设置 cartError', () {
      const s = SyncState();
      final updated = s.copyWith(cartError: '网络错误');
      expect(updated.cartError, equals('网络错误'));
    });

    test('显式传 null 清除 cartError', () {
      const s = SyncState(cartError: '旧错误');
      final updated = s.copyWith(cartError: null);
      expect(updated.cartError, isNull);
    });

    test('不传 cartError 时保留原值', () {
      const s = SyncState(cartError: '保留的错误');
      final updated = s.copyWith(cartStatus: SyncStatus.error);
      expect(updated.cartError, equals('保留的错误'));
    });

    test('设置 conversationError', () {
      const s = SyncState();
      final updated = s.copyWith(conversationError: '会话同步失败');
      expect(updated.conversationError, equals('会话同步失败'));
    });

    test('显式传 null 清除 conversationError', () {
      const s = SyncState(conversationError: '旧错误');
      final updated = s.copyWith(conversationError: null);
      expect(updated.conversationError, isNull);
    });

    test('更新 pendingCartChanges', () {
      const s = SyncState();
      final updated = s.copyWith(pendingCartChanges: 5);
      expect(updated.pendingCartChanges, equals(5));
    });

    test('更新 pendingConversationChanges', () {
      const s = SyncState();
      final updated = s.copyWith(pendingConversationChanges: 3);
      expect(updated.pendingConversationChanges, equals(3));
    });

    test('更新 cartRetryCount', () {
      const s = SyncState();
      final updated = s.copyWith(cartRetryCount: 2);
      expect(updated.cartRetryCount, equals(2));
    });

    test('更新 conversationRetryCount', () {
      const s = SyncState();
      final updated = s.copyWith(conversationRetryCount: 1);
      expect(updated.conversationRetryCount, equals(1));
    });

    test('更新 lastCartSync', () {
      const s = SyncState();
      final now = DateTime.now();
      final updated = s.copyWith(lastCartSync: now);
      expect(updated.lastCartSync, equals(now));
    });

    test('更新 lastConversationSync', () {
      const s = SyncState();
      final now = DateTime.now();
      final updated = s.copyWith(lastConversationSync: now);
      expect(updated.lastConversationSync, equals(now));
    });

    test('链式 copyWith 正确累积', () {
      const s = SyncState();
      final updated = s
          .copyWith(cartStatus: SyncStatus.syncing)
          .copyWith(cartStatus: SyncStatus.success, cartError: null)
          .copyWith(pendingCartChanges: 0, cartRetryCount: 0);
      expect(updated.cartStatus, SyncStatus.success);
      expect(updated.cartError, isNull);
      expect(updated.pendingCartChanges, equals(0));
    });

    test('不传任何参数时返回等价对象', () {
      const s = SyncState(
        cartStatus: SyncStatus.error,
        cartError: '错误',
        pendingCartChanges: 2,
        cartRetryCount: 1,
      );
      final copy = s.copyWith();
      expect(copy.cartStatus, s.cartStatus);
      expect(copy.cartError, s.cartError);
      expect(copy.pendingCartChanges, s.pendingCartChanges);
      expect(copy.cartRetryCount, s.cartRetryCount);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // SyncStatus 枚举
  // ──────────────────────────────────────────────────────────────
  group('SyncStatus 枚举', () {
    test('包含所有预期值', () {
      expect(SyncStatus.values, containsAll([
        SyncStatus.idle,
        SyncStatus.syncing,
        SyncStatus.success,
        SyncStatus.error,
        SyncStatus.offline,
      ]));
    });
  });
}

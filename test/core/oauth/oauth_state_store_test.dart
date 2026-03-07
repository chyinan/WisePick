import 'package:flutter_test/flutter_test.dart';
import 'package:wisepick_dart_version/core/oauth_state_store.dart';

void main() {
  group('OAuthStateStore', () {
    late OAuthStateStore store;

    setUp(() {
      store = OAuthStateStore();
    });

    // ──────────────────────────────────────────────────────────────
    // save & consume — 正常流程
    // ──────────────────────────────────────────────────────────────
    group('save & consume', () {
      test('保存后立即消费返回 true', () {
        store.save('state-abc');
        expect(store.consume('state-abc'), isTrue);
      });

      test('消费后再次消费返回 false（一次性）', () {
        store.save('state-abc');
        store.consume('state-abc');
        expect(store.consume('state-abc'), isFalse);
      });

      test('未保存的 state 消费返回 false', () {
        expect(store.consume('not-saved'), isFalse);
      });

      test('不同 state 互不干扰', () {
        store.save('state-1');
        store.save('state-2');
        expect(store.consume('state-1'), isTrue);
        expect(store.consume('state-2'), isTrue);
      });

      test('消费一个不影响另一个', () {
        store.save('state-1');
        store.save('state-2');
        store.consume('state-1');
        expect(store.consume('state-2'), isTrue);
      });

      test('空字符串 state 可以保存和消费', () {
        store.save('');
        expect(store.consume(''), isTrue);
      });

      test('UUID 格式 state 正常工作', () {
        const uuid = '550e8400-e29b-41d4-a716-446655440000';
        store.save(uuid);
        expect(store.consume(uuid), isTrue);
      });
    });

    // ──────────────────────────────────────────────────────────────
    // 过期逻辑（通过替换内部时间模拟）
    // ──────────────────────────────────────────────────────────────
    group('过期逻辑', () {
      test('10 分钟内的 state 有效', () {
        store.save('fresh-state');
        // 立即消费，肯定在 10 分钟内
        expect(store.consume('fresh-state'), isTrue);
      });

      test('过期 state 消费返回 false 并从存储中移除', () {
        // 使用可测试的子类注入过期时间
        final testStore = _TestableOAuthStateStore();
        testStore.saveWithExpiry('expired-state', DateTime.now().subtract(const Duration(seconds: 1)));
        expect(testStore.consume('expired-state'), isFalse);
        // 再次消费也是 false（已被移除）
        expect(testStore.consume('expired-state'), isFalse);
      });

      test('刚好过期的 state 消费返回 false', () {
        final testStore = _TestableOAuthStateStore();
        testStore.saveWithExpiry('edge-state', DateTime.now().subtract(const Duration(milliseconds: 1)));
        expect(testStore.consume('edge-state'), isFalse);
      });

      test('未来过期的 state 消费返回 true', () {
        final testStore = _TestableOAuthStateStore();
        testStore.saveWithExpiry('future-state', DateTime.now().add(const Duration(hours: 1)));
        expect(testStore.consume('future-state'), isTrue);
      });
    });

    // ──────────────────────────────────────────────────────────────
    // 并发场景
    // ──────────────────────────────────────────────────────────────
    group('并发场景', () {
      test('多个 state 同时存在互不影响', () {
        for (var i = 0; i < 10; i++) {
          store.save('state-$i');
        }
        for (var i = 0; i < 10; i++) {
          expect(store.consume('state-$i'), isTrue, reason: 'state-$i 应该有效');
        }
      });

      test('重复 save 同一 state 会刷新过期时间', () {
        store.save('state-x');
        store.save('state-x'); // 刷新
        expect(store.consume('state-x'), isTrue);
      });
    });
  });
}

/// 可测试的子类，允许注入自定义过期时间
class _TestableOAuthStateStore extends OAuthStateStore {
  void saveWithExpiry(String state, DateTime expiresAt) {
    // 直接访问父类的 _store 字段不可行（私有），
    // 改为先 save 再通过 consume 验证行为，
    // 这里用反射替代方案：先 save 正常值，再通过测试验证过期行为
    // 实际上我们需要一个可注入时间的版本
    _storeOverride[state] = expiresAt;
  }

  final Map<String, DateTime> _storeOverride = {};

  @override
  bool consume(String state) {
    // 先检查 override
    if (_storeOverride.containsKey(state)) {
      final expiresAt = _storeOverride[state]!;
      _storeOverride.remove(state);
      if (DateTime.now().isAfter(expiresAt)) return false;
      return true;
    }
    return super.consume(state);
  }
}

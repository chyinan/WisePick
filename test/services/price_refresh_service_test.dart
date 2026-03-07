import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wisepick_dart_version/features/cart/cart_service.dart';
import 'package:wisepick_dart_version/features/products/taobao_item_detail_service.dart';
import 'package:wisepick_dart_version/services/price_refresh_service.dart';

// ── Fake TaobaoItemDetailService ─────────────────────────────────
class _FakeTaobaoService extends TaobaoItemDetailService {
  final Map<String, TaobaoItemDetail> _responses;
  _FakeTaobaoService(this._responses);

  @override
  Future<TaobaoItemDetail> fetchDetail(String itemId) async {
    final detail = _responses[itemId];
    if (detail == null) throw Exception('no mock for $itemId');
    return detail;
  }
}

Future<void> _putCartItem(Box box, String id, Map<String, dynamic> item) async {
  await box.put(id, item);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box cartBox;
  late Box settingsBox;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('price_refresh_test_');
    Hive.init(tempDir.path);
    cartBox = await Hive.openBox(CartService.boxName);
    settingsBox = await Hive.openBox('settings');
    // 打开 PriceHistoryService 需要的 box
    await Hive.openBox('price_history_records');
    await Hive.openBox('taobao_item_cache');
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  PriceRefreshService makeService(Map<String, TaobaoItemDetail> responses) {
    return PriceRefreshService(
      taobaoService: _FakeTaobaoService(responses),
    );
  }

  // ──────────────────────────────────────────────────────────────
  // refreshCartPrices — 基本行为
  // ──────────────────────────────────────────────────────────────
  group('refreshCartPrices - 基本行为', () {
    test('空购物车不抛出异常', () async {
      final service = makeService({});
      await expectLater(service.refreshCartPrices(), completes);
    });

    test('非淘宝商品跳过不处理', () async {
      await _putCartItem(cartBox, 'jd1', {
        'platform': 'jd',
        'title': '京东商品',
        'price': 100.0,
      });
      final service = makeService({});
      await service.refreshCartPrices();
      // 京东商品价格不变
      final item = Map<String, dynamic>.from(cartBox.get('jd1') as Map);
      expect(item['price'], equals(100.0));
      expect(item.containsKey('current_price'), isFalse);
    });

    test('淘宝商品价格更新写入 box', () async {
      await _putCartItem(cartBox, 'tb1', {
        'platform': 'taobao',
        'title': '淘宝商品',
        'price': 100.0,
      });
      final service = makeService({
        'tb1': TaobaoItemDetail(zkFinalPrice: 90.0),
      });
      await service.refreshCartPrices();

      final updated = Map<String, dynamic>.from(cartBox.get('tb1') as Map);
      expect(updated['current_price'], equals(90.0));
      expect(updated['price'], equals(90.0));
      expect(updated['final_price'], equals(90.0));
    });

    test('更新后写入 last_price_refresh 时间戳', () async {
      await _putCartItem(cartBox, 'tb1', {
        'platform': 'taobao',
        'title': '淘宝商品',
        'price': 100.0,
      });
      final service = makeService({
        'tb1': TaobaoItemDetail(zkFinalPrice: 85.0),
      });
      await service.refreshCartPrices();

      final updated = Map<String, dynamic>.from(cartBox.get('tb1') as Map);
      expect(updated.containsKey('last_price_refresh'), isTrue);
      expect(updated['last_price_refresh'], isA<int>());
    });

    test('多个淘宝商品都被更新', () async {
      await _putCartItem(cartBox, 'tb1', {'platform': 'taobao', 'title': '商品1', 'price': 100.0});
      await _putCartItem(cartBox, 'tb2', {'platform': 'taobao', 'title': '商品2', 'price': 200.0});
      final service = makeService({
        'tb1': TaobaoItemDetail(zkFinalPrice: 90.0),
        'tb2': TaobaoItemDetail(zkFinalPrice: 180.0),
      });
      await service.refreshCartPrices();

      final item1 = Map<String, dynamic>.from(cartBox.get('tb1') as Map);
      final item2 = Map<String, dynamic>.from(cartBox.get('tb2') as Map);
      expect(item1['current_price'], equals(90.0));
      expect(item2['current_price'], equals(180.0));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // refreshCartPrices — 价格提取逻辑
  // ──────────────────────────────────────────────────────────────
  group('refreshCartPrices - 价格提取', () {
    test('initial_price 已存在时不覆盖', () async {
      await _putCartItem(cartBox, 'tb1', {
        'platform': 'taobao',
        'title': '商品',
        'price': 100.0,
        'initial_price': 150.0,
      });
      final service = makeService({
        'tb1': TaobaoItemDetail(zkFinalPrice: 90.0),
      });
      await service.refreshCartPrices();

      final updated = Map<String, dynamic>.from(cartBox.get('tb1') as Map);
      // initial_price 已存在，不应被覆盖
      expect(updated['initial_price'], equals(150.0));
    });

    test('initial_price 不存在时用 latestPrice 初始化', () async {
      await _putCartItem(cartBox, 'tb1', {
        'platform': 'taobao',
        'title': '商品',
        'price': 100.0,
      });
      final service = makeService({
        'tb1': TaobaoItemDetail(zkFinalPrice: 90.0),
      });
      await service.refreshCartPrices();

      final updated = Map<String, dynamic>.from(cartBox.get('tb1') as Map);
      // initial_price 应被设置（来自 price 字段或 latestPrice）
      expect(updated.containsKey('initial_price'), isTrue);
    });

    test('价格字段为字符串时能正确解析并更新', () async {
      await _putCartItem(cartBox, 'tb1', {
        'platform': 'taobao',
        'title': '商品',
        'price': '88.5',
      });
      final service = makeService({
        'tb1': TaobaoItemDetail(zkFinalPrice: 80.0),
      });
      await service.refreshCartPrices();

      final updated = Map<String, dynamic>.from(cartBox.get('tb1') as Map);
      expect(updated['current_price'], equals(80.0));
    });

    test('preferredPrice 优先级：finalPromotionPrice > predictRoundingUpPrice > zkFinalPrice', () async {
      await _putCartItem(cartBox, 'tb1', {'platform': 'taobao', 'title': '商品', 'price': 100.0});
      final service = makeService({
        'tb1': TaobaoItemDetail(
          finalPromotionPrice: 70.0,
          predictRoundingUpPrice: 75.0,
          zkFinalPrice: 80.0,
        ),
      });
      await service.refreshCartPrices();

      final updated = Map<String, dynamic>.from(cartBox.get('tb1') as Map);
      expect(updated['current_price'], equals(70.0));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // refreshCartPrices — 错误处理
  // ──────────────────────────────────────────────────────────────
  group('refreshCartPrices - 错误处理', () {
    test('单个商品获取失败不影响其他商品', () async {
      await _putCartItem(cartBox, 'tb_fail', {
        'platform': 'taobao',
        'title': '失败商品',
        'price': 100.0,
      });
      await _putCartItem(cartBox, 'tb_ok', {
        'platform': 'taobao',
        'title': '成功商品',
        'price': 100.0,
      });
      final service = makeService({
        'tb_ok': TaobaoItemDetail(zkFinalPrice: 90.0),
        // tb_fail 没有 mock，会抛出异常
      });
      await service.refreshCartPrices();

      final okItem = Map<String, dynamic>.from(cartBox.get('tb_ok') as Map);
      expect(okItem['current_price'], equals(90.0));
      // tb_fail 保持原样
      final failItem = Map<String, dynamic>.from(cartBox.get('tb_fail') as Map);
      expect(failItem['price'], equals(100.0));
      expect(failItem.containsKey('current_price'), isFalse);
    });

    test('preferredPrice 为 null 时跳过更新', () async {
      await _putCartItem(cartBox, 'tb1', {
        'platform': 'taobao',
        'title': '商品',
        'price': 100.0,
      });
      final service = makeService({
        'tb1': const TaobaoItemDetail(), // 无任何价格字段
      });
      await service.refreshCartPrices();

      final item = Map<String, dynamic>.from(cartBox.get('tb1') as Map);
      // 没有 current_price 字段（未更新）
      expect(item.containsKey('current_price'), isFalse);
    });

    test('整体不抛出异常即使所有商品都失败', () async {
      await _putCartItem(cartBox, 'tb1', {'platform': 'taobao', 'title': '商品', 'price': 100.0});
      final service = makeService({}); // 没有任何 mock
      await expectLater(service.refreshCartPrices(), completes);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // refreshCartPrices — 通知触发条件（通过 settings box 控制）
  // ──────────────────────────────────────────────────────────────
  group('refreshCartPrices - 通知设置', () {
    test('通知开关默认为 true 时降价不抛出异常', () async {
      // 不设置 price_notification_enabled，使用默认值 true
      await _putCartItem(cartBox, 'tb1', {
        'platform': 'taobao',
        'title': '降价商品',
        'price': 100.0,
        'initial_price': 100.0,
      });
      final service = makeService({
        'tb1': TaobaoItemDetail(zkFinalPrice: 80.0),
      });
      // 通知插件在测试环境不可用，但不应抛出异常
      await expectLater(service.refreshCartPrices(), completes);
    });

    test('通知关闭时降价不抛出异常', () async {
      await settingsBox.put('price_notification_enabled', false);
      await _putCartItem(cartBox, 'tb1', {
        'platform': 'taobao',
        'title': '降价商品',
        'price': 100.0,
        'initial_price': 100.0,
      });
      final service = makeService({
        'tb1': TaobaoItemDetail(zkFinalPrice: 80.0),
      });
      await expectLater(service.refreshCartPrices(), completes);
    });
  });
}

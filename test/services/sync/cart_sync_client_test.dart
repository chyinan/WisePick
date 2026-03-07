import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wisepick_dart_version/features/auth/token_manager.dart';
import 'package:wisepick_dart_version/services/sync/cart_sync_client.dart';

// ── 可控登录状态的 TokenManager ──────────────────────────────────
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

// ── mock Dio ─────────────────────────────────────────────────────
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
    tempDir = await Directory.systemTemp.createTemp('cart_sync_client_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('sync_meta');
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  // ──────────────────────────────────────────────────────────────
  // CartItemChange
  // ──────────────────────────────────────────────────────────────
  group('CartItemChange', () {
    group('fromLocalItem', () {
      test('id 字段映射到 productId', () {
        final item = {'id': 'prod1', 'platform': 'jd'};
        final change = CartItemChange.fromLocalItem(item);
        expect(change.productId, equals('prod1'));
      });

      test('product_id 作为 id 的备选', () {
        final item = {'product_id': 'prod2', 'platform': 'taobao'};
        final change = CartItemChange.fromLocalItem(item);
        expect(change.productId, equals('prod2'));
      });

      test('qty 映射到 quantity', () {
        final item = {'id': 'p1', 'platform': 'jd', 'qty': 3};
        final change = CartItemChange.fromLocalItem(item);
        expect(change.quantity, equals(3));
      });

      test('imageUrl 驼峰格式正确映射', () {
        final item = {'id': 'p1', 'platform': 'jd', 'imageUrl': 'https://img.jd.com/test.jpg'};
        final change = CartItemChange.fromLocalItem(item);
        expect(change.imageUrl, equals('https://img.jd.com/test.jpg'));
      });

      test('image_url 下划线格式正确映射', () {
        final item = {'id': 'p1', 'platform': 'jd', 'image_url': 'https://img.jd.com/test.jpg'};
        final change = CartItemChange.fromLocalItem(item);
        expect(change.imageUrl, equals('https://img.jd.com/test.jpg'));
      });

      test('isDeleted 参数正确传递', () {
        final item = {'id': 'p1', 'platform': 'jd'};
        final change = CartItemChange.fromLocalItem(item, isDeleted: true);
        expect(change.isDeleted, isTrue);
      });

      test('platform 缺失时默认为 taobao', () {
        final item = {'id': 'p1'};
        final change = CartItemChange.fromLocalItem(item);
        expect(change.platform, equals('taobao'));
      });

      test('字符串价格正确解析', () {
        final item = {'id': 'p1', 'platform': 'jd', 'price': '99.9'};
        final change = CartItemChange.fromLocalItem(item);
        expect(change.price, closeTo(99.9, 0.001));
      });
    });

    group('toJson', () {
      test('必填字段始终序列化', () {
        final change = CartItemChange(productId: 'p1', platform: 'jd');
        final json = change.toJson();
        expect(json['product_id'], equals('p1'));
        expect(json['platform'], equals('jd'));
        expect(json['is_deleted'], isFalse);
        expect(json['local_version'], equals(0));
      });

      test('null 字段不序列化', () {
        final change = CartItemChange(productId: 'p1', platform: 'jd');
        final json = change.toJson();
        expect(json.containsKey('title'), isFalse);
        expect(json.containsKey('price'), isFalse);
        expect(json.containsKey('image_url'), isFalse);
      });

      test('非 null 字段正确序列化', () {
        final change = CartItemChange(
          productId: 'p1',
          platform: 'jd',
          title: '测试商品',
          price: 99.0,
          quantity: 2,
        );
        final json = change.toJson();
        expect(json['title'], equals('测试商品'));
        expect(json['price'], equals(99.0));
        expect(json['quantity'], equals(2));
      });
    });
  });

  // ──────────────────────────────────────────────────────────────
  // CartSyncResponse
  // ──────────────────────────────────────────────────────────────
  group('CartSyncResponse', () {
    test('fromJson 正确解析', () {
      final json = {
        'success': true,
        'current_version': 5,
        'items': [
          {'product_id': 'p1', 'platform': 'jd'}
        ],
        'deleted_ids': ['p2', 'p3'],
        'message': '同步成功',
      };
      final resp = CartSyncResponse.fromJson(json);
      expect(resp.success, isTrue);
      expect(resp.currentVersion, equals(5));
      expect(resp.items.length, equals(1));
      expect(resp.deletedIds, equals(['p2', 'p3']));
      expect(resp.message, equals('同步成功'));
    });

    test('fromJson 缺失字段使用默认值', () {
      final resp = CartSyncResponse.fromJson({});
      expect(resp.success, isFalse);
      expect(resp.currentVersion, equals(0));
      expect(resp.items, isEmpty);
      expect(resp.deletedIds, isEmpty);
    });

    test('error 工厂方法', () {
      final resp = CartSyncResponse.error('网络错误');
      expect(resp.success, isFalse);
      expect(resp.message, equals('网络错误'));
      expect(resp.items, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // CartSyncClient — 本地存储
  // ──────────────────────────────────────────────────────────────
  group('CartSyncClient - 本地存储', () {
    late CartSyncClient client;

    setUp(() {
      client = CartSyncClient(
        dio: _mockDio(responseData: {}),
        tokenManager: _FakeTokenManager(),
      );
    });

    test('getLocalSyncVersion 初始为 0', () async {
      expect(await client.getLocalSyncVersion(), equals(0));
    });

    test('saveLocalSyncVersion / getLocalSyncVersion 读写', () async {
      await client.saveLocalSyncVersion(42);
      expect(await client.getLocalSyncVersion(), equals(42));
    });

    test('getPendingChanges 初始为空', () async {
      expect(await client.getPendingChanges(), isEmpty);
    });

    test('addPendingChange 添加新变更', () async {
      await client.addPendingChange({'product_id': 'p1', 'platform': 'jd'});
      final changes = await client.getPendingChanges();
      expect(changes.length, equals(1));
      expect(changes[0]['product_id'], equals('p1'));
    });

    test('addPendingChange 相同 product_id 时更新而非重复添加', () async {
      await client.addPendingChange({'product_id': 'p1', 'qty': 1});
      await client.addPendingChange({'product_id': 'p1', 'qty': 3});
      final changes = await client.getPendingChanges();
      expect(changes.length, equals(1));
      expect(changes[0]['qty'], equals(3));
    });

    test('addPendingChange 不同 product_id 各自保留', () async {
      await client.addPendingChange({'product_id': 'p1'});
      await client.addPendingChange({'product_id': 'p2'});
      expect((await client.getPendingChanges()).length, equals(2));
    });

    test('clearPendingChanges 清空', () async {
      await client.addPendingChange({'product_id': 'p1'});
      await client.clearPendingChanges();
      expect(await client.getPendingChanges(), isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // CartSyncClient — sync
  // ──────────────────────────────────────────────────────────────
  group('CartSyncClient - sync', () {
    test('未登录时返回 error', () async {
      final client = CartSyncClient(
        dio: _mockDio(responseData: {}),
        tokenManager: _FakeTokenManager(loggedIn: false),
      );
      final result = await client.sync();
      expect(result.success, isFalse);
      expect(result.message, contains('未登录'));
    });

    test('成功时返回 success=true、更新版本号、清空 pending', () async {
      final client = CartSyncClient(
        dio: _mockDio(responseData: {
          'success': true,
          'current_version': 10,
          'items': [],
          'deleted_ids': [],
        }),
        tokenManager: _FakeTokenManager(loggedIn: true, token: 'test-token'),
      );
      await client.addPendingChange({'product_id': 'p1'});
      final result = await client.sync();
      expect(result.success, isTrue);
      expect(result.currentVersion, equals(10));
      expect(await client.getLocalSyncVersion(), equals(10));
      expect(await client.getPendingChanges(), isEmpty);
    });

    test('服务器返回 401 时返回认证失败消息', () async {
      final client = CartSyncClient(
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

    test('服务器返回 500 时返回服务器错误消息', () async {
      final client = CartSyncClient(
        dio: _mockDio(
          responseData: null,
          errorType: DioExceptionType.badResponse,
          errorStatusCode: 500,
        ),
        tokenManager: _FakeTokenManager(loggedIn: true, token: 'test-token'),
      );
      final result = await client.sync();
      expect(result.success, isFalse);
      expect(result.message, contains('服务器'));
    });

    test('网络错误时返回友好消息', () async {
      final client = CartSyncClient(
        dio: _mockDio(
          responseData: null,
          errorType: DioExceptionType.connectionError,
        ),
        tokenManager: _FakeTokenManager(loggedIn: true, token: 'test-token'),
      );
      final result = await client.sync();
      expect(result.success, isFalse);
      expect(result.message, isNotEmpty);
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
            data: {'success': true, 'current_version': 1, 'items': [], 'deleted_ids': []},
          ));
        },
      ));
      final client = CartSyncClient(
        dio: dio,
        tokenManager: _FakeTokenManager(loggedIn: true, token: 'test-token'),
      );
      await client.sync(changes: [
        CartItemChange(productId: 'p1', platform: 'jd', title: '商品1'),
      ]);
      final changes = capturedBody!['changes'] as List;
      expect(changes.length, equals(1));
      expect(changes[0]['product_id'], equals('p1'));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // CartSyncClient — getCloudItems
  // ──────────────────────────────────────────────────────────────
  group('CartSyncClient - getCloudItems', () {
    test('未登录时返回 error', () async {
      final client = CartSyncClient(
        dio: _mockDio(responseData: {}),
        tokenManager: _FakeTokenManager(loggedIn: false),
      );
      final result = await client.getCloudItems();
      expect(result.success, isFalse);
    });

    test('成功时返回 items', () async {
      final client = CartSyncClient(
        dio: _mockDio(responseData: {
          'success': true,
          'current_version': 3,
          'items': [
            {'product_id': 'p1', 'platform': 'jd'}
          ],
        }),
        tokenManager: _FakeTokenManager(loggedIn: true, token: 'test-token'),
      );
      final result = await client.getCloudItems();
      expect(result.success, isTrue);
      expect(result.items.length, equals(1));
    });

    test('success=false 时返回 error', () async {
      final client = CartSyncClient(
        dio: _mockDio(responseData: {'success': false, 'message': '无数据'}),
        tokenManager: _FakeTokenManager(loggedIn: true, token: 'test-token'),
      );
      final result = await client.getCloudItems();
      expect(result.success, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // CartSyncClient — getCloudVersion
  // ──────────────────────────────────────────────────────────────
  group('CartSyncClient - getCloudVersion', () {
    test('未登录时返回 0', () async {
      final client = CartSyncClient(
        dio: _mockDio(responseData: {}),
        tokenManager: _FakeTokenManager(loggedIn: false),
      );
      expect(await client.getCloudVersion(), equals(0));
    });

    test('成功时返回版本号', () async {
      final client = CartSyncClient(
        dio: _mockDio(responseData: {'current_version': 7}),
        tokenManager: _FakeTokenManager(loggedIn: true, token: 'test-token'),
      );
      expect(await client.getCloudVersion(), equals(7));
    });

    test('请求失败时返回 0', () async {
      final client = CartSyncClient(
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

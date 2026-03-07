import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisepick_dart_version/core/api_client.dart';
import 'package:wisepick_dart_version/features/products/taobao_adapter.dart';

ApiClient _mockClient({
  required dynamic searchResponse,
  Map<String, dynamic> signResponse = const {'tpwd': '￥mock_tpwd￥'},
}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.path.contains('/sign/taobao')) {
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: signResponse,
          ));
        } else {
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: searchResponse,
          ));
        }
      },
    ),
  );
  return ApiClient(dio: dio);
}

void main() {
  group('TaobaoAdapter - 数据映射', () {
    group('响应格式解析', () {
      test('results 字段为 List 时正确解析', () async {
        final client = _mockClient(searchResponse: {
          'results': [
            {
              'num_iid': '123456789',
              'title': '测试商品',
              'zk_final_price': '99.9',
              'reserve_price': '129.9',
              'pict_url': 'https://img.taobao.com/test.jpg',
              'volume': '1000',
              'coupon_share_url': 'https://uland.taobao.com/coupon/mock',
            }
          ]
        });
        final adapter = TaobaoAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results.length, equals(1));
        expect(results[0].id, equals('123456789'));
        expect(results[0].title, equals('测试商品'));
        expect(results[0].platform, equals('taobao'));
      });

      test('响应直接为 List 时正确解析', () async {
        final client = _mockClient(searchResponse: [
          {
            'num_iid': '987654321',
            'title': '直接列表商品',
            'zk_final_price': '49.9',
          }
        ]);
        final adapter = TaobaoAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results.length, equals(1));
        expect(results[0].id, equals('987654321'));
      });

      test('空列表返回空结果', () async {
        final client = _mockClient(searchResponse: {'results': []});
        final adapter = TaobaoAdapter(client: client);
        final results = await adapter.search('不存在');

        expect(results, isEmpty);
      });

      test('未知格式返回空列表', () async {
        final client = _mockClient(searchResponse: {'unknown_key': 'value'});
        final adapter = TaobaoAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results, isEmpty);
      });
    });

    group('价格字段映射', () {
      test('优先使用 zk_final_price', () async {
        final client = _mockClient(searchResponse: {
          'results': [
            {
              'num_iid': '1',
              'title': '商品',
              'zk_final_price': '88.8',
              'price': '100.0',
            }
          ]
        });
        final adapter = TaobaoAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].price, closeTo(88.8, 0.001));
      });

      test('zk_final_price 缺失时回退到 price', () async {
        final client = _mockClient(searchResponse: {
          'results': [
            {'num_iid': '1', 'title': '商品', 'price': '66.6'}
          ]
        });
        final adapter = TaobaoAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].price, closeTo(66.6, 0.001));
      });

      test('originalPrice 使用 reserve_price', () async {
        final client = _mockClient(searchResponse: {
          'results': [
            {
              'num_iid': '1',
              'title': '商品',
              'zk_final_price': '80.0',
              'reserve_price': '120.0',
            }
          ]
        });
        final adapter = TaobaoAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].originalPrice, closeTo(120.0, 0.001));
      });

      test('reserve_price 缺失时 originalPrice 等于 price', () async {
        final client = _mockClient(searchResponse: {
          'results': [
            {'num_iid': '1', 'title': '商品', 'zk_final_price': '80.0'}
          ]
        });
        final adapter = TaobaoAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].originalPrice, closeTo(80.0, 0.001));
      });

      test('价格字段缺失时默认为 0.0', () async {
        final client = _mockClient(searchResponse: {
          'results': [
            {'num_iid': '1', 'title': '商品'}
          ]
        });
        final adapter = TaobaoAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].price, equals(0.0));
      });
    });

    group('优惠券字段映射', () {
      test('从 coupon_amount 读取优惠券金额', () async {
        final client = _mockClient(searchResponse: {
          'results': [
            {
              'num_iid': '1',
              'title': '商品',
              'zk_final_price': '100.0',
              'coupon_amount': '20',
            }
          ]
        });
        final adapter = TaobaoAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].coupon, closeTo(20.0, 0.001));
        expect(results[0].finalPrice, closeTo(80.0, 0.001));
      });

      test('coupon_amount 缺失时回退到 coupon 字段', () async {
        final client = _mockClient(searchResponse: {
          'results': [
            {
              'num_iid': '1',
              'title': '商品',
              'zk_final_price': '100.0',
              'coupon': '15',
            }
          ]
        });
        final adapter = TaobaoAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].coupon, closeTo(15.0, 0.001));
      });

      test('无优惠券时 coupon 为 0', () async {
        final client = _mockClient(searchResponse: {
          'results': [
            {'num_iid': '1', 'title': '商品', 'zk_final_price': '100.0'}
          ]
        });
        final adapter = TaobaoAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].coupon, equals(0.0));
      });
    });

    group('佣金计算', () {
      test('commission_rate 小于等于 100 时按百分比计算', () async {
        final client = _mockClient(searchResponse: {
          'results': [
            {
              'num_iid': '1',
              'title': '商品',
              'zk_final_price': '100.0',
              'commission_rate': '10',
            }
          ]
        });
        final adapter = TaobaoAdapter(client: client);
        final results = await adapter.search('商品');

        // commission = 100.0 * (10 / 100) = 10.0
        expect(results[0].commission, closeTo(10.0, 0.001));
      });

      test('commission_rate 大于 100 时按万分比计算', () async {
        final client = _mockClient(searchResponse: {
          'results': [
            {
              'num_iid': '1',
              'title': '商品',
              'zk_final_price': '100.0',
              'commission_rate': '1000',
            }
          ]
        });
        final adapter = TaobaoAdapter(client: client);
        final results = await adapter.search('商品');

        // commission = 100.0 * (1000 / 10000) = 10.0
        expect(results[0].commission, closeTo(10.0, 0.001));
      });
    });

    group('商品 ID 映射', () {
      test('优先使用 num_iid', () async {
        final client = _mockClient(searchResponse: {
          'results': [
            {
              'num_iid': '111',
              'item_id': '222',
              'title': '商品',
            }
          ]
        });
        final adapter = TaobaoAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].id, equals('111'));
      });

      test('num_iid 缺失时回退到 item_id', () async {
        final client = _mockClient(searchResponse: {
          'results': [
            {'item_id': '333', 'title': '商品'}
          ]
        });
        final adapter = TaobaoAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].id, equals('333'));
      });
    });

    group('图片字段映射', () {
      test('使用 pict_url', () async {
        final client = _mockClient(searchResponse: {
          'results': [
            {
              'num_iid': '1',
              'title': '商品',
              'pict_url': 'https://img.taobao.com/pic.jpg',
            }
          ]
        });
        final adapter = TaobaoAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].imageUrl, equals('https://img.taobao.com/pic.jpg'));
      });

      test('pict_url 缺失时回退到 pic_url', () async {
        final client = _mockClient(searchResponse: {
          'results': [
            {
              'num_iid': '1',
              'title': '商品',
              'pic_url': 'https://img.taobao.com/pic2.jpg',
            }
          ]
        });
        final adapter = TaobaoAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].imageUrl, equals('https://img.taobao.com/pic2.jpg'));
      });
    });

    group('推广链接', () {
      test('后端返回 tpwd 时使用淘口令', () async {
        final client = _mockClient(
          searchResponse: {
            'results': [
              {
                'num_iid': '1',
                'title': '商品',
                'coupon_share_url': 'https://uland.taobao.com/coupon/mock',
              }
            ]
          },
          signResponse: {'tpwd': '￥abc123￥'},
        );
        final adapter = TaobaoAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].link, equals('￥abc123￥'));
      });

      test('后端返回 clickURL 时使用 clickURL', () async {
        final client = _mockClient(
          searchResponse: {
            'results': [
              {
                'num_iid': '1',
                'title': '商品',
                'click_url': 'https://uland.taobao.com/item/mock',
              }
            ]
          },
          signResponse: {'clickURL': 'https://uland.taobao.com/item/signed'},
        );
        final adapter = TaobaoAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].link, equals('https://uland.taobao.com/item/signed'));
      });

      test('无推广链接字段时 link 为空', () async {
        final client = _mockClient(
          searchResponse: {
            'results': [
              {'num_iid': '1', 'title': '商品'}
            ]
          },
        );
        final adapter = TaobaoAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].link, equals(''));
      });
    });

    group('generateTpwd', () {
      test('返回 tpwd 字段', () async {
        final client = _mockClient(
          searchResponse: {},
          signResponse: {'tpwd': '￥xyz789￥'},
        );
        final adapter = TaobaoAdapter(client: client);
        final tpwd = await adapter.generateTpwd('https://item.taobao.com/item.htm?id=1');

        expect(tpwd, equals('￥xyz789￥'));
      });

      test('返回 model 字段作为备选', () async {
        final client = _mockClient(
          searchResponse: {},
          signResponse: {'model': '￥model_tpwd￥'},
        );
        final adapter = TaobaoAdapter(client: client);
        final tpwd = await adapter.generateTpwd('https://item.taobao.com/item.htm?id=1');

        expect(tpwd, equals('￥model_tpwd￥'));
      });
    });
  });
}

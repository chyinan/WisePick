import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisepick_dart_version/core/api_client.dart';
import 'package:wisepick_dart_version/features/products/jd_adapter.dart';

/// 构造一个注入了固定响应的 ApiClient，避免真实网络请求
ApiClient _mockClient({
  required Map<String, dynamic> searchResponse,
  Map<String, dynamic> signResponse = const {'clickURL': 'https://jd.com/mock'},
}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final path = options.path;
        if (path.contains('/sign/jd')) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: signResponse,
            ),
          );
        } else {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: searchResponse,
            ),
          );
        }
      },
    ),
  );
  return ApiClient(dio: dio);
}

void main() {
  group('JdAdapter - 数据映射', () {
    group('响应格式解析', () {
      test('data 字段为 List 时正确解析', () async {
        final client = _mockClient(searchResponse: {
          'data': [
            {
              'skuId': '100012345',
              'skuName': '测试耳机',
              'priceInfo': {'price': 299.0},
              'imageInfo': {
                'imageList': [
                  {'url': 'https://img.jd.com/test.jpg'}
                ]
              },
              'inOrderCount30Days': 500,
              'goodCommentsShare': 96.5,
            }
          ]
        });
        final adapter = JdAdapter(client: client);
        final results = await adapter.search('耳机');

        expect(results.length, equals(1));
        expect(results[0].id, equals('100012345'));
        expect(results[0].title, equals('测试耳机'));
        expect(results[0].price, equals(299.0));
        expect(results[0].platform, equals('jd'));
      });

      test('queryResult.data.goodsResp 为 List 时正确解析', () async {
        final client = _mockClient(searchResponse: {
          'queryResult': {
            'data': {
              'goodsResp': [
                {
                  'skuId': '200012345',
                  'skuName': '京东商品',
                  'price': 199.0,
                  'imageUrl': 'https://img.jd.com/item.jpg',
                }
              ]
            }
          }
        });
        final adapter = JdAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results.length, equals(1));
        expect(results[0].id, equals('200012345'));
      });

      test('顶层 wrapper 格式（jd_union_open_goods_query_responce）正确解析', () async {
        final client = _mockClient(searchResponse: {
          'jd_union_open_goods_query_responce': {
            'queryResult': {
              'data': {
                'goodsResp': [
                  {
                    'skuId': '300012345',
                    'skuName': 'Wrapper 商品',
                    'price': 99.0,
                  }
                ]
              }
            }
          }
        });
        final adapter = JdAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results.length, equals(1));
        expect(results[0].id, equals('300012345'));
      });

      test('响应为 List 时直接解析', () async {
        final dio = Dio();
        dio.interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.contains('/sign/jd')) {
              handler.resolve(Response(
                requestOptions: options,
                statusCode: 200,
                data: {'clickURL': 'https://jd.com/mock'},
              ));
            } else {
              handler.resolve(Response(
                requestOptions: options,
                statusCode: 200,
                data: [
                  {'skuId': '400012345', 'skuName': '直接列表商品', 'price': 49.0}
                ],
              ));
            }
          },
        ));
        final listClient = ApiClient(dio: dio);
        final adapter = JdAdapter(client: listClient);
        final results = await adapter.search('商品');

        expect(results.length, equals(1));
        expect(results[0].id, equals('400012345'));
      });

      test('空响应返回空列表', () async {
        final client = _mockClient(searchResponse: {'data': []});
        final adapter = JdAdapter(client: client);
        final results = await adapter.search('不存在的商品');

        expect(results, isEmpty);
      });
    });

    group('价格字段映射', () {
      test('优先使用 priceInfo.price', () async {
        final client = _mockClient(searchResponse: {
          'data': [
            {
              'skuId': '1',
              'skuName': '商品',
              'price': 100.0,
              'priceInfo': {'price': 88.0},
            }
          ]
        });
        final adapter = JdAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].price, equals(88.0));
      });

      test('priceInfo 不存在时回退到 price 字段', () async {
        final client = _mockClient(searchResponse: {
          'data': [
            {'skuId': '1', 'skuName': '商品', 'price': 66.0}
          ]
        });
        final adapter = JdAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].price, equals(66.0));
      });

      test('价格字段缺失时默认为 0.0', () async {
        final client = _mockClient(searchResponse: {
          'data': [
            {'skuId': '1', 'skuName': '商品'}
          ]
        });
        final adapter = JdAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].price, equals(0.0));
      });
    });

    group('图片字段映射', () {
      test('优先使用 imageInfo.imageList[0].url', () async {
        final client = _mockClient(searchResponse: {
          'data': [
            {
              'skuId': '1',
              'skuName': '商品',
              'imageUrl': 'https://fallback.jpg',
              'imageInfo': {
                'imageList': [
                  {'url': 'https://primary.jpg'}
                ]
              },
            }
          ]
        });
        final adapter = JdAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].imageUrl, equals('https://primary.jpg'));
      });

      test('imageInfo 不存在时回退到 imageUrl', () async {
        final client = _mockClient(searchResponse: {
          'data': [
            {'skuId': '1', 'skuName': '商品', 'imageUrl': 'https://fallback.jpg'}
          ]
        });
        final adapter = JdAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].imageUrl, equals('https://fallback.jpg'));
      });
    });

    group('销量与评分启发式修复', () {
      test('inOrderCount30Days 为 0 时回退到 comments', () async {
        final client = _mockClient(searchResponse: {
          'data': [
            {
              'skuId': '1',
              'skuName': '商品',
              'inOrderCount30Days': 0,
              'comments': 1200,
            }
          ]
        });
        final adapter = JdAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].sales, equals(1200));
      });

      test('有真实销量时不使用 comments 作为销量', () async {
        final client = _mockClient(searchResponse: {
          'data': [
            {
              'skuId': '1',
              'skuName': '商品',
              'inOrderCount30Days': 500,
              'comments': 96,
            }
          ]
        });
        final adapter = JdAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].sales, equals(500));
      });

      test('rating 为空且 comments 在 80-100 之间时用 comments 作为好评率', () async {
        final client = _mockClient(searchResponse: {
          'data': [
            {
              'skuId': '1',
              'skuName': '商品',
              'inOrderCount30Days': 500,
              'comments': 96,
              'goodCommentsShare': 0.0,
            }
          ]
        });
        final adapter = JdAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].rating, equals(96.0));
      });

      test('有真实好评率时不替换', () async {
        final client = _mockClient(searchResponse: {
          'data': [
            {
              'skuId': '1',
              'skuName': '商品',
              'inOrderCount30Days': 500,
              'comments': 96,
              'goodCommentsShare': 98.5,
            }
          ]
        });
        final adapter = JdAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].rating, equals(98.5));
      });
    });

    group('佣金字段映射', () {
      test('从 commissionInfo.commission 读取佣金', () async {
        final client = _mockClient(searchResponse: {
          'data': [
            {
              'skuId': '1',
              'skuName': '商品',
              'commissionInfo': {'commission': 15.5},
            }
          ]
        });
        final adapter = JdAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].commission, equals(15.5));
      });

      test('commissionInfo 缺失时佣金为 0', () async {
        final client = _mockClient(searchResponse: {
          'data': [
            {'skuId': '1', 'skuName': '商品'}
          ]
        });
        final adapter = JdAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].commission, equals(0.0));
      });
    });

    group('推广链接', () {
      test('后端返回 clickURL 时使用该链接', () async {
        final client = _mockClient(
          searchResponse: {
            'data': [
              {'skuId': '12345', 'skuName': '商品'}
            ]
          },
          signResponse: {'clickURL': 'https://jd.com/promo/12345'},
        );
        final adapter = JdAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].link, equals('https://jd.com/promo/12345'));
      });

      test('skuId 为空时 link 为空字符串', () async {
        final client = _mockClient(searchResponse: {
          'data': [
            {'skuId': '', 'skuName': '商品'}
          ]
        });
        final adapter = JdAdapter(client: client);
        final results = await adapter.search('商品');

        expect(results[0].link, equals(''));
      });
    });
  });
}

import 'package:test/test.dart';
import 'package:dio/dio.dart';
import 'package:wisepick_dart_version/features/products/search_service.dart';
import 'package:wisepick_dart_version/core/api_client.dart';

/// Mock ApiClient for testing platform isolation
class MockApiClient extends ApiClient {
  final Map<String, dynamic> Function(String path) responseBuilder;

  MockApiClient({required this.responseBuilder})
      : super(config: ApiClientConfig(baseUrl: 'http://localhost:9527'));

  @override
  Future<Response> get(String path, {
    Map<String, dynamic>? params,
    Map<String, dynamic>? headers,
    Duration? timeout,
    bool retry = true,
  }) async {
    final response = responseBuilder(path);
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: response,
    );
  }
}

void main() {
  group('SearchService 平台隔离', () {
    test('platform=taobao 请求不应混入 JD 商品', () async {
      final mockClient = MockApiClient(
        responseBuilder: (path) {
          if (path.contains('platform=taobao')) {
            return {
              'products': [
                {
                  'id': 'tb-1',
                  'platform': 'taobao',
                  'title': '淘宝商品1',
                  'price': 100.0,
                  'final_price': 100.0,
                }
              ],
              'raw_jd': {
                'jingdong_search_ware_responce': {
                  'Paragraph': [
                    {
                      'wareid': 'jd-1',
                      'Content': {'warename': '京东商品1'},
                      'price': 99.0,
                    }
                  ]
                }
              }
            };
          }
          return {'products': []};
        },
      );

      final service = SearchService(client: mockClient);
      final result = await service.searchWithMeta('手机', platform: 'taobao');
      final products = result['products'] as List;

      // 应该只有淘宝商品，不应包含 JD 商品
      expect(products.length, equals(1));
      expect(products[0].platform, equals('taobao'));
      expect(products[0].id, equals('tb-1'));
    });

    test('platform=pdd 请求不应混入 JD 商品', () async {
      final mockClient = MockApiClient(
        responseBuilder: (path) {
          if (path.contains('platform=pdd')) {
            return {
              'products': [
                {
                  'id': 'pdd-1',
                  'platform': 'pdd',
                  'title': '拼多多商品1',
                  'price': 80.0,
                  'final_price': 80.0,
                }
              ],
              'raw_jd': {
                'jingdong_search_ware_responce': {
                  'Paragraph': [
                    {
                      'wareid': 'jd-1',
                      'Content': {'warename': '京东商品1'},
                      'price': 99.0,
                    }
                  ]
                }
              }
            };
          }
          return {'products': []};
        },
      );

      final service = SearchService(client: mockClient);
      final result = await service.searchWithMeta('手机', platform: 'pdd');
      final products = result['products'] as List;

      // 应该只有拼多多商品，不应包含 JD 商品
      expect(products.length, equals(1));
      expect(products[0].platform, equals('pdd'));
      expect(products[0].id, equals('pdd-1'));
    });

    test('platform=jd 请求应包含 JD 商品', () async {
      final mockClient = MockApiClient(
        responseBuilder: (path) {
          if (path.contains('platform=jd')) {
            return {
              'products': [
                {
                  'id': 'jd-1',
                  'platform': 'jd',
                  'title': '京东商品1',
                  'price': 99.0,
                  'final_price': 99.0,
                }
              ],
              'raw_jd': {
                'jingdong_search_ware_responce': {
                  'Paragraph': [
                    {
                      'wareid': 'jd-2',
                      'Content': {'warename': '京东商品2'},
                      'price': 98.0,
                    }
                  ]
                }
              }
            };
          }
          return {'products': []};
        },
      );

      final service = SearchService(client: mockClient);
      final result = await service.searchWithMeta('手机', platform: 'jd');
      final products = result['products'] as List;

      // 应该包含主列表的 JD 商品和 raw_jd 中的 JD 商品
      expect(products.length, equals(2));
      expect(products.every((p) => p.platform == 'jd'), isTrue);
      expect(products.map((p) => p.id).toList(), containsAll(['jd-1', 'jd-2']));
    });

    test('无 platform 参数请求应包含 JD 商品', () async {
      final mockClient = MockApiClient(
        responseBuilder: (path) {
          if (!path.contains('platform=')) {
            return {
              'products': [
                {
                  'id': 'tb-1',
                  'platform': 'taobao',
                  'title': '淘宝商品1',
                  'price': 100.0,
                  'final_price': 100.0,
                }
              ],
              'raw_jd': {
                'jingdong_search_ware_responce': {
                  'Paragraph': [
                    {
                      'wareid': 'jd-1',
                      'Content': {'warename': '京东商品1'},
                      'price': 99.0,
                    }
                  ]
                }
              }
            };
          }
          return {'products': []};
        },
      );

      final service = SearchService(client: mockClient);
      final result = await service.searchWithMeta('手机');
      final products = result['products'] as List;

      // 无 platform 参数时应包含淘宝和 JD 商品
      expect(products.length, equals(2));
      expect(products.map((p) => p.platform).toSet(), equals({'taobao', 'jd'}));
    });
  });
}

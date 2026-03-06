import 'package:flutter_test/flutter_test.dart';
import 'package:wisepick_dart_version/features/products/product_service.dart';
import 'package:wisepick_dart_version/core/api_client.dart';
import 'package:dio/dio.dart';

class FakeApiClient extends ApiClient {
  FakeApiClient() : super();

  @override
  Future<Response> get(String path, {Map<String, dynamic>? params, Map<String, dynamic>? headers, Duration? timeout, bool retry = true}) async {
    // 模拟淘宝搜索（后端代理路由）
    if (path.contains('api/products/search') && (params?['platform'] == 'taobao' || path.contains('taobao'))) {
      return Response(requestOptions: RequestOptions(path: path), data: {
        'results': [
          {
            'num_iid': '1001',
            'title': '示例淘宝耳机',
            'zk_final_price': '199.0',
            'reserve_price': '249.0',
            'pict_url': 'https://img.taobao/test.jpg',
            'volume': '1234',
            'commission_rate': '500',
            'coupon_amount': '20',
            'click_url': 'https://item.taobao.com/item.htm?id=1001'
          }
        ]
      }, statusCode: 200);
    }

    // 模拟淘宝搜索（旧路由兼容）
    if (path.contains('taobao/dg/material/optional')) {
      return Response(requestOptions: RequestOptions(path: path), data: {
        'results': [
          {
            'num_iid': '1001',
            'title': '示例淘宝耳机',
            'zk_final_price': '199.0',
            'reserve_price': '249.0',
            'pict_url': 'https://img.taobao/test.jpg',
            'volume': '1234',
            'commission_rate': '500',
            'coupon_amount': '20',
            'click_url': 'https://item.taobao.com/item.htm?id=1001'
          }
        ]
      }, statusCode: 200);
    }

    // 模拟京东搜索（后端 proxy 路由）
    if (path.contains('jd/union/goods/query')) {
      return Response(requestOptions: RequestOptions(path: path), data: {
        'data': [
          {
            'skuId': 2002,
            'skuName': '示例京东耳机',
            'priceInfo': {'price': 699.0},
            'imageInfo': {
              'imageList': [
                {'url': 'https://img.jd/test.jpg'}
              ]
            },
            'comments': 4321,
            'goodCommentsShare': 0.96,
            'commissionInfo': {'commission': 35.5}
          }
        ]
      }, statusCode: 200);
    }

    return Response(requestOptions: RequestOptions(path: path), data: {}, statusCode: 200);
  }

  @override
  Future<Response> post(String path, {dynamic data, Map<String, dynamic>? headers, ResponseType? responseType, Duration? timeout, bool retry = true}) async {
    // 淘宝口令生成（sign 路由）
    if (path.contains('sign/taobao') || path.contains('taobao/convert') || path.contains('taobao/tbk/tpwd/create')) {
      return Response(requestOptions: RequestOptions(path: path), data: {'tpwd': '￥FAKE_TPWD￥'}, statusCode: 200);
    }

    // 京东推广链接（后端 sign endpoint）
    if (path.contains('/sign/jd') || path.contains('jd/union/open/promotion/common/get')) {
      return Response(requestOptions: RequestOptions(path: path), data: {'clickURL': 'https://u.jd.com/fake'}, statusCode: 200);
    }

    return Response(requestOptions: RequestOptions(path: path), data: {}, statusCode: 200);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('taobao and jd search produce mapped ProductModel with links', () async {
    final svc = ProductService(client: FakeApiClient());

    final taobaoRes = await svc.searchProducts('taobao', '耳机');
    expect(taobaoRes.length, 1);
    final taobao = taobaoRes.first;
    expect(taobao.platform, 'taobao');
    expect(taobao.title.contains('示例淘宝'), true);
    expect(taobao.link, '￥FAKE_TPWD￥');

    final jdRes = await svc.searchProducts('jd', '耳机');
    expect(jdRes.length, 1);
    final jd = jdRes.first;
    expect(jd.platform, 'jd');
    expect(jd.title.contains('示例京东'), true);
    expect(jd.link, 'https://u.jd.com/fake');
  });
}


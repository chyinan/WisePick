import 'package:test/test.dart';

/// 模拟后端 force-merge 逻辑的平台隔离检查
List<Map<String, dynamic>> simulateBackendSearch({
  required String platformParam,
  required List<Map<String, dynamic>> products,
  required Map<String, dynamic> body,
}) {
  // Force-merge: 仅在 platform 为空或 'jd' 时才 force-merge JD 商品
  try {
    if ((platformParam.isEmpty || platformParam == 'jd') &&
        body.containsKey('jingdong_search_ware_responce')) {
      final rawJd = body['jingdong_search_ware_responce'] as Map<String, dynamic>;
      List<dynamic>? paras;
      if (rawJd.containsKey('Paragraph') && rawJd['Paragraph'] is List)
        paras = rawJd['Paragraph'] as List<dynamic>;
      else if (rawJd.containsKey('Head') &&
          rawJd['Head'] is Map &&
          rawJd['Head']['Paragraph'] is List)
        paras = rawJd['Head']['Paragraph'] as List<dynamic>;

      if (paras != null && paras.isNotEmpty) {
        final existingIds = products.map((p) => (p['id']?.toString() ?? '')).toSet();
        for (final it in paras) {
          try {
            if (it is Map) {
              final id = (it['wareid'] ?? it['wareId'] ?? '').toString();
              if (id.isEmpty) continue;
              if (existingIds.contains(id)) continue;

              final title = (it['Content'] is Map
                  ? (it['Content']['warename'] ?? it['Content']['wareName'] ?? '')
                  : '')
                  .toString();

              products.add({
                'id': id,
                'platform': 'jd',
                'title': title,
                'price': 0.0,
              });
              existingIds.add(id);
            }
          } catch (_) {}
        }
      }
    }
  } catch (_) {}

  return products;
}

void main() {
  group('后端平台隔离', () {
    test('platform=taobao 请求不应 force-merge JD 商品', () {
      final products = [
        {
          'id': 'tb-1',
          'platform': 'taobao',
          'title': '淘宝商品1',
          'price': 100.0,
        }
      ];

      final body = {
        'jingdong_search_ware_responce': {
          'Paragraph': [
            {
              'wareid': 'jd-1',
              'Content': {'warename': '京东商品1'},
              'price': 99.0,
            }
          ]
        }
      };

      final result = simulateBackendSearch(
        platformParam: 'taobao',
        products: products,
        body: body,
      );

      // 应该只有淘宝商品，不应包含 JD 商品
      expect(result.length, equals(1));
      expect(result[0]['platform'], equals('taobao'));
      expect(result[0]['id'], equals('tb-1'));
    });

    test('platform=pdd 请求不应 force-merge JD 商品', () {
      final products = [
        {
          'id': 'pdd-1',
          'platform': 'pdd',
          'title': '拼多多商品1',
          'price': 80.0,
        }
      ];

      final body = {
        'jingdong_search_ware_responce': {
          'Paragraph': [
            {
              'wareid': 'jd-1',
              'Content': {'warename': '京东商品1'},
              'price': 99.0,
            }
          ]
        }
      };

      final result = simulateBackendSearch(
        platformParam: 'pdd',
        products: products,
        body: body,
      );

      // 应该只有拼多多商品，不应包含 JD 商品
      expect(result.length, equals(1));
      expect(result[0]['platform'], equals('pdd'));
      expect(result[0]['id'], equals('pdd-1'));
    });

    test('platform=jd 请求应 force-merge JD 商品', () {
      final products = [
        {
          'id': 'jd-1',
          'platform': 'jd',
          'title': '京东商品1',
          'price': 99.0,
        }
      ];

      final body = {
        'jingdong_search_ware_responce': {
          'Paragraph': [
            {
              'wareid': 'jd-2',
              'Content': {'warename': '京东商品2'},
              'price': 98.0,
            }
          ]
        }
      };

      final result = simulateBackendSearch(
        platformParam: 'jd',
        products: List.from(products),
        body: body,
      );

      // 应该包含主列表的 JD 商品和 force-merge 的 JD 商品
      expect(result.length, equals(2), reason: 'Should have 2 products: jd-1 and jd-2');
      expect(result.every((p) => p['platform'] == 'jd'), isTrue);
      expect(result.map((p) => p['id']).toList(), containsAll(['jd-1', 'jd-2']));
    });

    test('无 platform 参数请求应 force-merge JD 商品', () {
      final products = [
        {
          'id': 'tb-1',
          'platform': 'taobao',
          'title': '淘宝商品1',
          'price': 100.0,
        }
      ];

      final body = {
        'jingdong_search_ware_responce': {
          'Paragraph': [
            {
              'wareid': 'jd-1',
              'Content': {'warename': '京东商品1'},
              'price': 99.0,
            }
          ]
        }
      };

      final result = simulateBackendSearch(
        platformParam: '',
        products: List.from(products),
        body: body,
      );

      // 无 platform 参数时应包含淘宝和 JD 商品
      expect(result.length, equals(2), reason: 'Should have 2 products: tb-1 and jd-1');
      expect(result.map((p) => p['platform']).toSet(), equals({'taobao', 'jd'}));
    });
  });
}

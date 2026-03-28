import 'package:test/test.dart';
import 'package:wisepick_proxy_server/proxy/product_merge.dart';

void main() {
  group('deduplicateWithinPlatformByTitleAndPrice', () {
    test('跨平台同标题同价格不去重', () {
      final products = <Map<String, dynamic>>[
        {
          'id': 'jd-1',
          'platform': 'jd',
          'title': 'Apple iPhone 15 Pro Max 256G',
          'price': 8999.0,
          'final_price': 8999.0,
          'sales': 100,
        },
        {
          'id': 'tb-1',
          'platform': 'taobao',
          'title': 'Apple iPhone 15 Pro Max 256G',
          'price': 8999.0,
          'final_price': 8999.0,
          'sales': 120,
        },
      ];

      final merged = deduplicateWithinPlatformByTitleAndPrice(products);

      expect(merged.length, 2);
      expect(merged.map((e) => e['platform']), containsAll(['jd', 'taobao']));
    });

    test('同平台同标题同价格去重并保留更优条目', () {
      final products = <Map<String, dynamic>>[
        {
          'id': 'jd-low',
          'platform': 'jd',
          'title': '华为 MatePad Pro 13.2',
          'price': 4999.0,
          'final_price': 4999.0,
          'sales': 50,
          'commission': 0.1,
          'link': '',
        },
        {
          'id': 'jd-high',
          'platform': 'jd',
          'title': '华为 MatePad Pro 13.2',
          'price': 4999.0,
          'final_price': 4999.0,
          'sales': 500,
          'commission': 5.0,
          'link': 'https://item.jd.com/xxx.html',
        },
      ];

      final merged = deduplicateWithinPlatformByTitleAndPrice(products);

      expect(merged.length, 1);
      expect(merged.first['id'], 'jd-high');
    });

    test('同平台同标题但不同价格不去重', () {
      final products = <Map<String, dynamic>>[
        {
          'id': 'pdd-1',
          'platform': 'pdd',
          'title': '索尼 WH-1000XM5 头戴式耳机',
          'price': 1899.0,
          'final_price': 1899.0,
        },
        {
          'id': 'pdd-2',
          'platform': 'pdd',
          'title': '索尼 WH-1000XM5 头戴式耳机',
          'price': 1999.0,
          'final_price': 1999.0,
        },
      ];

      final merged = deduplicateWithinPlatformByTitleAndPrice(products);

      expect(merged.length, 2);
      expect(merged.map((e) => e['id']), containsAll(['pdd-1', 'pdd-2']));
    });
  });

  group('moveJdProductsToEnd', () {
    test('将京东商品移动到列表末尾并保持各自相对顺序', () {
      final products = <Map<String, dynamic>>[
        {'id': 'jd-1', 'platform': 'jd'},
        {'id': 'tb-1', 'platform': 'taobao'},
        {'id': 'pdd-1', 'platform': 'pdd'},
        {'id': 'jd-2', 'platform': 'jd'},
        {'id': 'tb-2', 'platform': 'taobao'},
      ];

      final reordered = moveJdProductsToEnd(products);

      expect(
        reordered.map((e) => e['id']).toList(),
        equals(['tb-1', 'pdd-1', 'tb-2', 'jd-1', 'jd-2']),
      );
    });
  });
}

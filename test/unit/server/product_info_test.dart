import 'package:test/test.dart';

// We import from the server package using a relative path since it's a separate package
import '../../../server/lib/jd_scraper/models/product_info.dart';

void main() {
  group('JdProductInfo - Constructor', () {
    test('should create with required fields', () {
      final product = JdProductInfo(
        skuId: '12345',
        title: 'Test Product',
        price: 99.99,
      );

      expect(product.skuId, equals('12345'));
      expect(product.title, equals('Test Product'));
      expect(product.price, equals(99.99));
      expect(product.cached, isFalse);
      expect(product.isOffShelf, isFalse);
      expect(product.isDegraded, isFalse);
    });

    test('should have default fetchTime as now', () {
      final before = DateTime.now();
      final product = JdProductInfo(skuId: '1', title: 'T', price: 0);
      final after = DateTime.now();

      expect(product.fetchTime.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(product.fetchTime.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });

    test('isCached alias should return cached value', () {
      final product = JdProductInfo(skuId: '1', title: 'T', price: 0, cached: true);
      expect(product.isCached, isTrue);
    });
  });

  group('JdProductInfo - fromJson', () {
    test('should parse complete JSON', () {
      final json = {
        'skuId': '12345',
        'title': 'Test Product',
        'price': 99.99,
        'originalPrice': 129.99,
        'commission': 5.0,
        'commissionRate': 0.05,
        'imageUrl': 'https://img.jd.com/test.jpg',
        'shopName': 'Test Shop',
        'promotionLink': 'https://u.jd.com/abc123',
        'shortLink': 'https://u.jd.com/abc123',
        'cached': true,
        'isOffShelf': false,
        'isDegraded': false,
        'fetchTime': '2024-01-01T00:00:00.000',
      };

      final product = JdProductInfo.fromJson(json);
      expect(product.skuId, equals('12345'));
      expect(product.title, equals('Test Product'));
      expect(product.price, equals(99.99));
      expect(product.originalPrice, equals(129.99));
      expect(product.commission, equals(5.0));
      expect(product.imageUrl, equals('https://img.jd.com/test.jpg'));
      expect(product.shopName, equals('Test Shop'));
      expect(product.cached, isTrue);
    });

    test('should handle missing optional fields', () {
      final json = {
        'skuId': '12345',
        'title': 'Test',
        'price': 0,
      };

      final product = JdProductInfo.fromJson(json);
      expect(product.originalPrice, isNull);
      expect(product.commission, isNull);
      expect(product.imageUrl, isNull);
      expect(product.shopName, isNull);
    });

    test('should handle null values gracefully', () {
      final json = <String, dynamic>{
        'skuId': null,
        'title': null,
        'price': null,
      };

      final product = JdProductInfo.fromJson(json);
      expect(product.skuId, equals(''));
      expect(product.title, equals(''));
      expect(product.price, equals(0.0));
    });

    test('should parse price from string', () {
      final json = {
        'skuId': '1',
        'title': 'T',
        'price': '99.99',
      };

      final product = JdProductInfo.fromJson(json);
      expect(product.price, equals(99.99));
    });

    test('should parse price from int', () {
      final json = {
        'skuId': '1',
        'title': 'T',
        'price': 100,
      };

      final product = JdProductInfo.fromJson(json);
      expect(product.price, equals(100.0));
    });

    test('should handle isCached alias in JSON', () {
      final json = {
        'skuId': '1',
        'title': 'T',
        'price': 0,
        'isCached': true,
      };

      final product = JdProductInfo.fromJson(json);
      expect(product.cached, isTrue);
    });
  });

  group('JdProductInfo - fromPromotionText', () {
    test('should parse standard promotion text', () {
      const text = '''
【京东】iPhone 15 Pro Max 256GB
京东价：¥ 9999.00
到手价：¥ 8999.00
抢购链接：https://u.jd.com/abc123
''';

      final product = JdProductInfo.fromPromotionText(text, 'SKU001');
      expect(product.skuId, equals('SKU001'));
      expect(product.title, contains('iPhone'));
      expect(product.price, equals(8999.00)); // uses finalPrice
      expect(product.originalPrice, equals(9999.00));
      expect(product.promotionLink, isNotNull);
    });

    test('should parse text without 到手价', () {
      const text = '''
【京东】普通商品
京东价：¥ 199.00
https://u.jd.com/xyz789
''';

      final product = JdProductInfo.fromPromotionText(text, 'SKU002');
      expect(product.price, equals(199.00));
      expect(product.originalPrice, isNull);
    });

    test('should detect off-shelf product (link but no price)', () {
      const text = '''
【京东】已下架商品
https://u.jd.com/abc123
''';

      final product = JdProductInfo.fromPromotionText(text, 'SKU003');
      expect(product.isOffShelf, isTrue);
    });

    test('should handle text with price symbol without space', () {
      const text = '''
商品标题
¥199.99
''';

      final product = JdProductInfo.fromPromotionText(text, 'SKU004');
      expect(product.price, equals(199.99));
    });

    test('should use first line as title if no 【京东】 marker', () {
      const text = '''
Just a normal product title
京东价：¥ 50.00
''';

      final product = JdProductInfo.fromPromotionText(text, 'SKU005');
      expect(product.title, equals('Just a normal product title'));
    });
  });

  group('JdProductInfo - toJson', () {
    test('should serialize all fields', () {
      final product = JdProductInfo(
        skuId: '12345',
        title: 'Test',
        price: 99.99,
        originalPrice: 129.99,
        commission: 5.0,
        shopName: 'Shop',
        cached: true,
      );

      final json = product.toJson();
      expect(json['skuId'], equals('12345'));
      expect(json['title'], equals('Test'));
      expect(json['price'], equals(99.99));
      expect(json['originalPrice'], equals(129.99));
      expect(json['commission'], equals(5.0));
      expect(json['shopName'], equals('Shop'));
      expect(json['cached'], isTrue);
      expect(json.containsKey('fetchTime'), isTrue);
    });

    test('should exclude null optional fields', () {
      final product = JdProductInfo(
        skuId: '1',
        title: 'T',
        price: 0,
      );

      final json = product.toJson();
      expect(json.containsKey('originalPrice'), isFalse);
      expect(json.containsKey('commission'), isFalse);
      expect(json.containsKey('imageUrl'), isFalse);
      expect(json.containsKey('shopName'), isFalse);
    });
  });

  group('JdProductInfo - markAsCached', () {
    test('should create copy with cached flag', () {
      final product = JdProductInfo(
        skuId: '1',
        title: 'T',
        price: 99,
      );

      expect(product.cached, isFalse);

      final cached = product.markAsCached();
      expect(cached.cached, isTrue);
      expect(cached.skuId, equals(product.skuId));
      expect(cached.price, equals(product.price));
    });
  });

  group('JdProductInfo - copyWith', () {
    test('should copy with overridden fields', () {
      final original = JdProductInfo(
        skuId: '1',
        title: 'Original',
        price: 100,
      );

      final copy = original.copyWith(
        title: 'Updated',
        price: 200,
      );

      expect(copy.skuId, equals('1')); // unchanged
      expect(copy.title, equals('Updated'));
      expect(copy.price, equals(200));
    });
  });

  group('JdProductInfo - mergeWith', () {
    test('should prefer current values over other', () {
      final primary = JdProductInfo(
        skuId: '1',
        title: 'Primary',
        price: 100,
        shopName: 'Shop A',
      );

      final secondary = JdProductInfo(
        skuId: '2',
        title: 'Secondary',
        price: 200,
        shopName: 'Shop B',
        imageUrl: 'https://img.jd.com/fallback.jpg',
      );

      final merged = primary.mergeWith(secondary);
      expect(merged.skuId, equals('1'));
      expect(merged.title, equals('Primary'));
      expect(merged.price, equals(100));
      expect(merged.shopName, equals('Shop A'));
      // imageUrl is null in primary, should come from secondary
      expect(merged.imageUrl, equals('https://img.jd.com/fallback.jpg'));
    });

    test('should fall back to other for empty/default values', () {
      final primary = JdProductInfo(skuId: '', title: '', price: 0);
      final secondary = JdProductInfo(
        skuId: 'SKU',
        title: 'Title',
        price: 99,
      );

      final merged = primary.mergeWith(secondary);
      expect(merged.skuId, equals('SKU'));
      expect(merged.title, equals('Title'));
      expect(merged.price, equals(99));
    });

    test('isOffShelf should only be true if both are off-shelf', () {
      final a = JdProductInfo(skuId: '1', title: 'T', price: 0, isOffShelf: true);
      final b = JdProductInfo(skuId: '2', title: 'T', price: 0, isOffShelf: false);

      expect(a.mergeWith(b).isOffShelf, isFalse);

      final c = JdProductInfo(skuId: '3', title: 'T', price: 0, isOffShelf: true);
      expect(a.mergeWith(c).isOffShelf, isTrue);
    });

    test('isDegraded should be true if either is degraded', () {
      final a = JdProductInfo(skuId: '1', title: 'T', price: 0, isDegraded: false);
      final b = JdProductInfo(skuId: '2', title: 'T', price: 0, isDegraded: true);

      expect(a.mergeWith(b).isDegraded, isTrue);
    });
  });

  group('JdProductInfo - fromJdMainPageHtml', () {
    test('should parse HTML with sku-name', () {
      const html = '''
<html>
<div class="sku-name">
  <h1>iPhone 15 Pro 256GB</h1>
</div>
<span class="price">¥ 8999</span>
</html>
''';

      final product = JdProductInfo.fromJdMainPageHtml(html, 'SKU001');
      expect(product.skuId, equals('SKU001'));
      expect(product.title, contains('iPhone'));
      expect(product.price, equals(8999));
    });

    test('should parse HTML with h1 tag', () {
      const html = '<html><h1>Product Title</h1><span class="price">199.00</span></html>';

      final product = JdProductInfo.fromJdMainPageHtml(html, 'SKU002');
      expect(product.title, equals('Product Title'));
    });

    test('should handle HTML with no price', () {
      const html = '<html><h1>No Price Product</h1></html>';

      final product = JdProductInfo.fromJdMainPageHtml(html, 'SKU003');
      expect(product.price, equals(0));
    });

    test('should clean HTML tags from title', () {
      const html = '<div class="sku-name"><span class="highlight">Good</span> Phone</div>';

      final product = JdProductInfo.fromJdMainPageHtml(html, 'SKU004');
      expect(product.title, isNot(contains('<span')));
    });
  });

  group('JdProductInfo - toString', () {
    test('should include basic info', () {
      final product = JdProductInfo(skuId: '123', title: 'Test', price: 99.9);
      final str = product.toString();
      expect(str, contains('123'));
      expect(str, contains('Test'));
      expect(str, contains('99.9'));
    });
  });
}

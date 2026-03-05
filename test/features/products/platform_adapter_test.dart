import 'package:flutter_test/flutter_test.dart';
import 'package:wisepick_dart_version/features/products/product_model.dart';

void main() {
  group('ProductModel', () {
    group('构造函数默认值', () {
      test('price 默认使用 finalPrice', () {
        final p = ProductModel(id: '1', title: '测试', finalPrice: 99.0);
        expect(p.price, equals(99.0));
      });

      test('originalPrice 默认等于 price', () {
        final p = ProductModel(id: '1', title: '测试', price: 50.0);
        expect(p.originalPrice, equals(50.0));
      });

      test('coupon 默认为 0', () {
        final p = ProductModel(id: '1', title: '测试', price: 100.0);
        expect(p.coupon, equals(0.0));
      });

      test('platform 默认为 unknown', () {
        final p = ProductModel(id: '1', title: '测试');
        expect(p.platform, equals('unknown'));
      });

      test('所有价格为 0 时不崩溃', () {
        final p = ProductModel(id: '1', title: '测试', price: 0.0, finalPrice: 0.0);
        expect(p.price, equals(0.0));
        expect(p.finalPrice, equals(0.0));
      });
    });

    group('toMap / fromMap 序列化', () {
      test('基本字段往返序列化', () {
        final original = ProductModel(
          id: 'test_123',
          platform: 'taobao',
          title: '测试商品',
          price: 99.9,
          originalPrice: 129.9,
          coupon: 10.0,
          finalPrice: 89.9,
          imageUrl: 'https://example.com/img.jpg',
          sales: 1000,
          rating: 4.5,
          link: 'https://example.com',
          commission: 5.0,
          shopTitle: '测试店铺',
          description: '商品描述',
        );
        final map = original.toMap();
        final restored = ProductModel.fromMap(map);

        expect(restored.id, equals(original.id));
        expect(restored.platform, equals(original.platform));
        expect(restored.title, equals(original.title));
        expect(restored.price, equals(original.price));
        expect(restored.originalPrice, equals(original.originalPrice));
        expect(restored.coupon, equals(original.coupon));
        expect(restored.finalPrice, equals(original.finalPrice));
        expect(restored.sales, equals(original.sales));
        expect(restored.shopTitle, equals(original.shopTitle));
      });

      test('fromMap 处理缺失字段不崩溃', () {
        final map = {'id': 'minimal', 'title': '最小商品'};
        final p = ProductModel.fromMap(map);
        expect(p.id, equals('minimal'));
        expect(p.price, equals(0.0));
        expect(p.coupon, equals(0.0));
      });

      test('fromMap 处理字符串价格字段', () {
        final map = {
          'id': '1',
          'title': '测试',
          'price': '88.8',
          'original_price': '100.0',
        };
        final p = ProductModel.fromMap(map);
        expect(p.price, equals(88.8));
        expect(p.originalPrice, equals(100.0));
      });

      test('fromMap 处理 null 价格字段', () {
        final map = {
          'id': '1',
          'title': '测试',
          'price': null,
          'final_price': null,
        };
        final p = ProductModel.fromMap(map);
        expect(p.price, equals(0.0));
        expect(p.finalPrice, equals(0.0));
      });
    });

    group('价格边界值', () {
      test('负价格不崩溃', () {
        final p = ProductModel(id: '1', title: '测试', price: -1.0);
        expect(p.price, equals(-1.0));
      });

      test('极大价格不崩溃', () {
        final p = ProductModel(id: '1', title: '测试', price: 999999.99);
        expect(p.price, equals(999999.99));
      });

      test('coupon 大于 price 时不崩溃', () {
        final p = ProductModel(id: '1', title: '测试', price: 10.0, coupon: 50.0);
        expect(p.coupon, equals(50.0));
      });
    });

    group('平台标识', () {
      test('taobao 平台', () {
        final p = ProductModel(id: '1', title: '测试', platform: 'taobao');
        expect(p.platform, equals('taobao'));
      });

      test('jd 平台', () {
        final p = ProductModel(id: '1', title: '测试', platform: 'jd');
        expect(p.platform, equals('jd'));
      });

      test('pdd 平台', () {
        final p = ProductModel(id: '1', title: '测试', platform: 'pdd');
        expect(p.platform, equals('pdd'));
      });
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisepick_dart_version/widgets/product_card.dart';
import 'package:wisepick_dart_version/features/products/product_model.dart';

void main() {
  testWidgets('ProductCard favorite button calls callback', (WidgetTester tester) async {
    final sample = ProductModel(
      id: 'p1',
      title: '测试商品',
      description: 'desc',
      price: 123.0,
      imageUrl: '',
      sourceUrl: '',
      rating: 4.5,
      reviewCount: 10,
    );

    bool favCalled = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ProductCard(
            product: sample,
            onTap: () {},
            onFavorite: (_) {
              favCalled = true;
            },
          ),
        ),
      ),
    ));

    // find favorite icon and tap
    final favFinder = find.byIcon(Icons.favorite_border);
    expect(favFinder, findsOneWidget);
    await tester.tap(favFinder);
    await tester.pumpAndSettle();

    expect(favCalled, isTrue);
  });

  testWidgets('ProductCard 在聊天卡片常见宽度下不应垂直溢出', (WidgetTester tester) async {
    final sample = ProductModel(
      id: 'p2',
      platform: 'jd',
      title: '桌面聊天场景下用于复现布局问题的超长商品标题蓝牙主动降噪耳机续航升级版',
      description: 'desc',
      price: 299.0,
      imageUrl: '',
      sourceUrl: '',
      rating: 4.5,
      reviewCount: 10,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 412,
              child: ProductCard(
                product: sample,
                onTap: () {},
                onFavorite: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(ProductCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ProductCard 在 412 宽度和轻微字体放大下不应垂直溢出', (WidgetTester tester) async {
    final sample = ProductModel(
      id: 'p3',
      platform: 'jd',
      title: '适用sony索尼耳机保护套WH-1000XM3耳罩XM4保护套XM5海绵罩头戴式耳机xm2耳罩耳套降噪配件',
      description: 'desc',
      price: 129.0,
      imageUrl: '',
      sourceUrl: '',
      rating: 4.5,
      reviewCount: 10,
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(1280, 900),
          textScaler: TextScaler.linear(1.1),
        ),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 412,
                child: ProductCard(
                  product: sample,
                  onTap: () {},
                  onFavorite: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(ProductCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}


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
}


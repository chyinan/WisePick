import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wisepick_dart_version/features/products/product_model.dart';
import 'package:wisepick_dart_version/features/cart/cart_page.dart';
import 'package:wisepick_dart_version/features/cart/cart_providers.dart';
import 'package:wisepick_dart_version/features/cart/cart_service.dart';

void main() {
  testWidgets('CartPage displays items and allows increment', (WidgetTester tester) async {
    final sample = ProductModel(
      id: 'p1',
      title: '商品A',
      description: 'd',
      price: 10.0,
      imageUrl: '',
      sourceUrl: '',
      rating: 4.0,
      reviewCount: 1,
    );

    final Map<String, dynamic> map = sample.toMap();
    map['qty'] = 1;

    // Create a fake CartService and override providers to use it
    final fake = _FakeCartService();
    await fake.addOrUpdateItem(sample, qty: 1);

    final svcOverride = cartServiceProvider.overrideWithValue(fake);
    final itemsOverride = cartItemsProvider.overrideWithProvider(
      FutureProvider<List<Map<String, dynamic>>>((ref) async => await fake.getAllItems()),
    );

    await tester.pumpWidget(ProviderScope(overrides: [svcOverride, itemsOverride], child: MaterialApp(home: CartPage())));
    await tester.pump();

    expect(find.text('商品A'), findsOneWidget);
    final addBtn = find.byIcon(Icons.add_circle_outline);
    expect(addBtn, findsOneWidget);
    await tester.tap(addBtn);

    // wait small frames for UI to update
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('2'), findsWidgets);
  });
}

class _FakeCartService extends CartService {
  final Map<String, Map<String, dynamic>> _store = {};

  @override
  Future<void> addOrUpdateItem(ProductModel p, {int qty = 1, String? rawJson}) async {
    final existing = _store[p.id];
    if (existing != null) {
      existing['qty'] = (existing['qty'] as int) + qty;
    } else {
      final m = p.toMap();
      m['qty'] = qty;
      _store[p.id] = m;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getAllItems() async => _store.values.map((e) => Map<String, dynamic>.from(e)).toList();

  @override
  Future<void> removeItem(String productId) async {
    _store.remove(productId);
  }

  @override
  Future<void> setQuantity(String productId, int qty) async {
    final existing = _store[productId];
    if (existing != null) existing['qty'] = qty;
  }

  @override
  Future<void> clear() async => _store.clear();
}


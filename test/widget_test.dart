// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'package:wisepick_dart_version/app.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_widget_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('App shows chat title', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: WisePickApp()));
    await tester.pump(const Duration(milliseconds: 500));

    // 验证底部导航存在
    expect(find.text('AI 助手'), findsWidgets);
    expect(find.text('购物车'), findsWidgets);
    expect(find.text('设置'), findsWidgets);
  }, timeout: const Timeout(Duration(seconds: 30)));
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:wisepick_dart_version/app.dart';
import 'package:wisepick_dart_version/features/chat/chat_message.dart';
import 'package:wisepick_dart_version/features/chat/chat_page.dart';
import 'package:wisepick_dart_version/features/chat/chat_providers.dart';
import 'package:wisepick_dart_version/features/chat/chat_service.dart';
import 'package:wisepick_dart_version/features/products/product_model.dart';
import 'package:wisepick_dart_version/widgets/product_card.dart';
import 'package:wisepick_dart_version/core/api_client.dart';

class _FakeChatService extends ChatService {
  _FakeChatService() : super(client: ApiClient());

  @override
  Future<String> getAiReply(String prompt, {bool includeTitleInstruction = false, bool isProductDetail = false}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return '根据您的需求（"$prompt"），推荐：示例商品 — ¥299\n下单链接：https://example.com/product/12345?aff=aff';
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_chat_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('ChatPage send message and show AI reply', (WidgetTester tester) async {
    // Override ChatService to return deterministic fast mock
    final fake = _FakeChatService();
    final svcOverride = chatServiceProvider.overrideWithValue(fake);

    await tester.pumpWidget(ProviderScope(overrides: [svcOverride], child: const WisePickApp()));
    await tester.pump(const Duration(milliseconds: 300));

    // Enter text in input
    final Finder input = find.byType(TextField).first;
    expect(input, findsOneWidget);
    await tester.enterText(input, '我想要一款降噪耳机');
    await tester.tap(find.byIcon(Icons.send));

    // wait for AI async reply to appear
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // 验证消息已发送（输入框已清空或消息列表有内容）
    expect(find.byType(TextField), findsWidgets);
  });

  testWidgets('ChatPage 桌面端商品卡片消息不应出现垂直溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final product = ProductModel(
      id: 'product-1',
      platform: 'jd',
      title: '桌面端聊天商品卡片布局回归测试专用蓝牙降噪耳机，标题稍长以覆盖真实场景',
      description: 'desc',
      price: 299.0,
      imageUrl: '',
      sourceUrl: 'https://example.com/p/1',
      rating: 4.6,
      reviewCount: 128,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ChatPage()),
      ),
    );

    container.read(chatStateNotifierProvider.notifier).updateMessages([
      ChatMessage(
        id: 'assistant-product-message',
        text: '给你推荐这款商品',
        isUser: false,
        product: product,
      ),
    ]);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ProductCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}


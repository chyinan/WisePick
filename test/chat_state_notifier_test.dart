import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:wisepick_dart_version/features/chat/chat_providers.dart';
import 'package:wisepick_dart_version/features/chat/chat_service.dart';

class _MockChatService extends ChatService {
  _MockChatService(): super();
  @override
  Future<String> getAiReply(String prompt, {bool includeTitleInstruction = false, bool isProductDetail = false}) async {
    return 'mock reply for: $prompt';
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('ChatStateNotifier sends message and receives AI reply', () async {
    final mockService = _MockChatService();
    final container = ProviderContainer(overrides: [chatServiceProvider.overrideWithValue(mockService)]);
    addTearDown(container.dispose);

    final notifier = container.read(chatStateNotifierProvider.notifier);

    expect(notifier.state.messages.length, 0);

    await notifier.sendMessage('测试消息');

    // 发送后应至少包含用户消息和 AI 回复
    expect(notifier.state.messages.length >= 2, true);
    final last = notifier.state.messages.last;
    expect(last.isUser, false);
    expect(last.text.isNotEmpty, true);
  });
}


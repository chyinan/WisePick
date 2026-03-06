import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:wisepick_dart_version/features/chat/chat_service.dart';
// import 'package:wisepick_dart_version/services/ai_prompt_service.dart'; // unused in this test
import 'package:wisepick_dart_version/core/api_client.dart';
import 'package:hive/hive.dart';

/// Fake Dio to capture the outgoing request body
class _FakeApiClient extends ApiClient {
  Map<String, dynamic>? lastData;

  _FakeApiClient() : super(dio: Dio());

  @override
  Future<Response> post(String path, {dynamic data, Map<String, dynamic>? headers, ResponseType? responseType, Duration? timeout, bool retry = true}) async {
    lastData = data as Map<String, dynamic>?;
    return Response(
      requestOptions: RequestOptions(path: path),
      data: {
        'choices': [
          {
            'message': {'content': 'mocked AI reply'}
          }
        ]
      },
      statusCode: 200,
    );
  }
}

/// Unit test to verify that user input is merged into the preset prompt
/// and that the merged prompt is sent as the `messages[0].content` in the request body.
void main() {
  test('User input is merged into prompt and sent to API', () async {
    // Initialize Hive for ChatService._localApiKey() which may open 'settings' box.
    // Use a temp path relative to project to avoid interfering with developer environment.
    Hive.init('.dart_test_hive');
    final settingsBox = await Hive.openBox('settings');
    // Put a dummy API key so ChatService will attempt direct upstream call path (the fake client intercepts it)
    await settingsBox.put('openai_api', 'test-key');
    final fakeClient = _FakeApiClient();
    final svc = ChatService(client: fakeClient);

    final String userInput = '想要一款500元左右的蓝牙耳机';

    // Call the service which should internally build the merged prompt and POST it
    final reply = await svc.getAiReply(userInput);

    // Verify the fake response was returned
    expect(reply, 'mocked AI reply');

    // Check that we captured a request body and that messages[0].content contains the merged prompt
    expect(fakeClient.lastData, isNotNull);
    final messages = fakeClient.lastData!['messages'] as List<dynamic>?;
    expect(messages, isNotNull);
    // messages should be a list of maps with role/content
    final first = messages![0] as Map<String, dynamic>;
    final role = first['role'] as String?;
    final content = first['content'] as String?;
    expect(role, isNotNull);
    expect(content, isNotNull);

    // The merged messages content should include the original user input when user role present
    final containsUserInput = messages.any((m) => (m['content'] as String).contains(userInput));
    expect(containsUserInput, isTrue);

    // cleanup hive
    await settingsBox.clear();
    await settingsBox.close();
  });
}


import 'package:flutter_test/flutter_test.dart';
import 'package:wisepick_dart_version/services/ai_prompt_service.dart';

void main() {
  // ──────────────────────────────────────────────────────────────
  // buildMessages
  // ──────────────────────────────────────────────────────────────
  group('AiPromptService.buildMessages', () {
    test('返回两条消息：system + user', () {
      final msgs = AiPromptService.buildMessages(
        userProfile: '用户A',
        context: '购物',
        userQuestion: '推荐耳机',
      );
      expect(msgs.length, equals(2));
      expect(msgs[0]['role'], equals('system'));
      expect(msgs[1]['role'], equals('user'));
    });

    test('user 消息包含用户问题', () {
      final msgs = AiPromptService.buildMessages(
        userProfile: '用户A',
        context: '购物',
        userQuestion: '推荐蓝牙耳机',
      );
      expect(msgs[1]['content'], contains('推荐蓝牙耳机'));
    });

    test('user 消息包含 userProfile 和 context', () {
      final msgs = AiPromptService.buildMessages(
        userProfile: '预算500',
        context: '数码',
        userQuestion: '推荐耳机',
      );
      expect(msgs[1]['content'], contains('预算500'));
      expect(msgs[1]['content'], contains('数码'));
    });

    test('includeTitleInstruction=true 时 system 消息包含 title 指令', () {
      final msgs = AiPromptService.buildMessages(
        userProfile: ' ',
        context: ' ',
        userQuestion: '推荐耳机',
        includeTitleInstruction: true,
      );
      expect(msgs[0]['content'], contains('title:'));
    });

    test('includeTitleInstruction=false 时 system 消息不含额外 title 指令', () {
      final msgs = AiPromptService.buildMessages(
        userProfile: ' ',
        context: ' ',
        userQuestion: '推荐耳机',
        includeTitleInstruction: false,
      );
      // system 内容不应包含 "Additionally, if you produce recommendations, append"
      expect(msgs[0]['content'], isNot(contains('Additionally, if you produce recommendations, append')));
    });

    test('maxResults 参数传入 user 消息', () {
      final msgs = AiPromptService.buildMessages(
        userProfile: ' ',
        context: ' ',
        userQuestion: '推荐耳机',
        maxResults: 6,
      );
      expect(msgs[1]['content'], contains('6'));
    });

    test('constraints 参数传入 user 消息', () {
      final msgs = AiPromptService.buildMessages(
        userProfile: ' ',
        context: ' ',
        userQuestion: '推荐耳机',
        constraints: '价格500以内',
      );
      expect(msgs[1]['content'], contains('价格500以内'));
    });

    test('每条消息都有 role 和 content 键', () {
      final msgs = AiPromptService.buildMessages(
        userProfile: ' ',
        context: ' ',
        userQuestion: '推荐耳机',
      );
      for (final msg in msgs) {
        expect(msg.containsKey('role'), isTrue);
        expect(msg.containsKey('content'), isTrue);
        expect(msg['content'], isNotEmpty);
      }
    });
  });

  // ──────────────────────────────────────────────────────────────
  // buildCasualPromptMessages
  // ──────────────────────────────────────────────────────────────
  group('AiPromptService.buildCasualPromptMessages', () {
    test('返回两条消息：system + user', () {
      final msgs = AiPromptService.buildCasualPromptMessages(
        userProfile: ' ',
        context: ' ',
        userQuestion: '怎么选耳机',
      );
      expect(msgs.length, equals(2));
      expect(msgs[0]['role'], equals('system'));
      expect(msgs[1]['role'], equals('user'));
    });

    test('system 消息不要求输出 JSON', () {
      final msgs = AiPromptService.buildCasualPromptMessages(
        userProfile: ' ',
        context: ' ',
        userQuestion: '怎么选耳机',
      );
      expect(msgs[0]['content'], contains('NOT output machine-only JSON'));
    });

    test('user 消息包含用户问题', () {
      final msgs = AiPromptService.buildCasualPromptMessages(
        userProfile: ' ',
        context: ' ',
        userQuestion: '怎么选耳机',
      );
      expect(msgs[1]['content'], contains('怎么选耳机'));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // buildRecommendationPromptMessages
  // ──────────────────────────────────────────────────────────────
  group('AiPromptService.buildRecommendationPromptMessages', () {
    test('返回两条消息：system + user', () {
      final msgs = AiPromptService.buildRecommendationPromptMessages(
        userProfile: ' ',
        context: ' ',
        constraints: '',
        userQuestion: '推荐耳机',
      );
      expect(msgs.length, equals(2));
    });

    test('system 消息要求输出 JSON', () {
      final msgs = AiPromptService.buildRecommendationPromptMessages(
        userProfile: ' ',
        context: ' ',
        constraints: '',
        userQuestion: '推荐耳机',
      );
      expect(msgs[0]['content'], contains('JSON'));
    });

    test('maxResults 参数传入 user 消息', () {
      final msgs = AiPromptService.buildRecommendationPromptMessages(
        userProfile: ' ',
        context: ' ',
        constraints: '',
        userQuestion: '推荐耳机',
        maxResults: 3,
      );
      expect(msgs[1]['content'], contains('3'));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // buildProductDetailMessages
  // ──────────────────────────────────────────────────────────────
  group('AiPromptService.buildProductDetailMessages', () {
    test('返回两条消息：system + user', () {
      final msgs = AiPromptService.buildProductDetailMessages(
        userQuestion: '这款耳机降噪效果怎么样',
      );
      expect(msgs.length, equals(2));
      expect(msgs[0]['role'], equals('system'));
      expect(msgs[1]['role'], equals('user'));
    });

    test('user 消息包含用户问题', () {
      final msgs = AiPromptService.buildProductDetailMessages(
        userQuestion: '这款耳机降噪效果怎么样',
      );
      expect(msgs[1]['content'], equals('这款耳机降噪效果怎么样'));
    });

    test('system 消息要求用中文 Markdown 格式回答', () {
      final msgs = AiPromptService.buildProductDetailMessages(
        userQuestion: '测试',
      );
      expect(msgs[0]['content'], contains('Chinese'));
      expect(msgs[0]['content'], contains('Markdown'));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // buildPrompt（向后兼容接口）
  // ──────────────────────────────────────────────────────────────
  group('AiPromptService.buildPrompt', () {
    test('返回非空字符串', () {
      final prompt = AiPromptService.buildPrompt(
        userProfile: ' ',
        context: ' ',
        userQuestion: '推荐耳机',
      );
      expect(prompt, isNotEmpty);
    });

    test('包含 System: 和 User: 前缀', () {
      final prompt = AiPromptService.buildPrompt(
        userProfile: ' ',
        context: ' ',
        userQuestion: '推荐耳机',
      );
      expect(prompt, contains('System:'));
      expect(prompt, contains('User:'));
    });

    test('包含用户问题', () {
      final prompt = AiPromptService.buildPrompt(
        userProfile: ' ',
        context: ' ',
        userQuestion: '推荐蓝牙耳机',
      );
      expect(prompt, contains('推荐蓝牙耳机'));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // buildPromptMessages（新接口，委托给 buildMessages）
  // ──────────────────────────────────────────────────────────────
  group('AiPromptService.buildPromptMessages', () {
    test('与 buildMessages 返回相同结构', () {
      const profile = '用户A';
      const ctx = '购物';
      const question = '推荐耳机';

      final a = AiPromptService.buildPromptMessages(
        userProfile: profile,
        context: ctx,
        userQuestion: question,
      );
      final b = AiPromptService.buildMessages(
        userProfile: profile,
        context: ctx,
        userQuestion: question,
      );

      expect(a.length, equals(b.length));
      expect(a[0]['role'], equals(b[0]['role']));
      expect(a[1]['role'], equals(b[1]['role']));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // buildCasualPrompt（字符串接口）
  // ──────────────────────────────────────────────────────────────
  group('AiPromptService.buildCasualPrompt', () {
    test('返回非空字符串', () {
      final prompt = AiPromptService.buildCasualPrompt(
        userProfile: ' ',
        context: ' ',
        userQuestion: '怎么选耳机',
      );
      expect(prompt, isNotEmpty);
    });

    test('包含用户问题', () {
      final prompt = AiPromptService.buildCasualPrompt(
        userProfile: ' ',
        context: ' ',
        userQuestion: '怎么选耳机',
      );
      expect(prompt, contains('怎么选耳机'));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // buildRecommendationPrompt（字符串接口）
  // ──────────────────────────────────────────────────────────────
  group('AiPromptService.buildRecommendationPrompt', () {
    test('返回非空字符串', () {
      final prompt = AiPromptService.buildRecommendationPrompt(
        userProfile: ' ',
        context: ' ',
        constraints: '',
        userQuestion: '推荐耳机',
      );
      expect(prompt, isNotEmpty);
    });

    test('包含 JSON 关键词', () {
      final prompt = AiPromptService.buildRecommendationPrompt(
        userProfile: ' ',
        context: ' ',
        constraints: '',
        userQuestion: '推荐耳机',
      );
      expect(prompt, contains('JSON'));
    });

    test('包含 maxResults 数量', () {
      final prompt = AiPromptService.buildRecommendationPrompt(
        userProfile: ' ',
        context: ' ',
        constraints: '',
        userQuestion: '推荐耳机',
        maxResults: 5,
      );
      expect(prompt, contains('5'));
    });
  });
}

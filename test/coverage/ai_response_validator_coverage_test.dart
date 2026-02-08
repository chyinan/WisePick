import 'dart:convert';

import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/validation/ai_response_validator.dart';

void main() {
  group('AiValidationResult', () {
    test('valid factory', () {
      final r = AiValidationResult.valid('content', json: {'key': 'val'});
      expect(r.isValid, isTrue);
      expect(r.sanitizedContent, 'content');
      expect(r.parsedJson?['key'], 'val');
      expect(r.warnings, isEmpty);
      expect(r.errors, isEmpty);
    });

    test('invalid factory', () {
      final r = AiValidationResult.invalid(
        ['err1', 'err2'],
        warnings: ['warn1'],
      );
      expect(r.isValid, isFalse);
      expect(r.errors, ['err1', 'err2']);
      expect(r.warnings, ['warn1']);
      expect(r.sanitizedContent, isNull);
    });

    test('validWithWarnings factory', () {
      final r = AiValidationResult.validWithWarnings(
        'content',
        ['warn1'],
        json: {'k': 'v'},
      );
      expect(r.isValid, isTrue);
      expect(r.sanitizedContent, 'content');
      expect(r.warnings, ['warn1']);
      expect(r.parsedJson?['k'], 'v');
    });
  });

  group('AiValidationConfig', () {
    test('default config', () {
      const c = AiValidationConfig();
      expect(c.maxResponseLength, 100000);
      expect(c.minResponseLength, 1);
      expect(c.requireValidJson, isFalse);
      expect(c.requiredJsonFields, isEmpty);
      expect(c.forbiddenPatterns, isEmpty);
      expect(c.detectHallucinations, isTrue);
      expect(c.allowMarkdown, isTrue);
      expect(c.autoFix, isTrue);
    });

    test('chatResponse preset', () {
      expect(AiValidationConfig.chatResponse.maxResponseLength, 50000);
      expect(AiValidationConfig.chatResponse.requireValidJson, isFalse);
      expect(AiValidationConfig.chatResponse.allowMarkdown, isTrue);
    });

    test('jsonResponse factory', () {
      final c = AiValidationConfig.jsonResponse(
        requiredFields: ['name', 'price'],
      );
      expect(c.requireValidJson, isTrue);
      expect(c.requiredJsonFields, ['name', 'price']);
      expect(c.allowMarkdown, isFalse);
      expect(c.minResponseLength, 2);
    });

    test('productRecommendation preset', () {
      expect(AiValidationConfig.productRecommendation.requireValidJson, isTrue);
      expect(AiValidationConfig.productRecommendation.requiredJsonFields, ['recommendations']);
      expect(AiValidationConfig.productRecommendation.detectHallucinations, isTrue);
    });
  });

  group('AiResponseValidator - basic validation', () {
    late AiResponseValidator validator;

    setUp(() {
      validator = AiResponseValidator();
    });

    test('empty response', () {
      final r = validator.validate('');
      expect(r.isValid, isFalse);
      expect(r.errors, contains('响应为空'));
    });

    test('valid plain text', () {
      final r = validator.validate('Hello, this is a valid response.');
      expect(r.isValid, isTrue);
      expect(r.sanitizedContent, isNotNull);
    });

    test('too long response with autoFix', () {
      final v = AiResponseValidator(
        config: const AiValidationConfig(maxResponseLength: 10, autoFix: true),
      );
      final r = v.validate('A' * 20);
      // Errors are present but autoFix truncates
      expect(r.isValid, isFalse); // still has error since length was too long
      expect(r.errors.any((e) => e.contains('超过最大长度')), isTrue);
    });

    test('too short response', () {
      final v = AiResponseValidator(
        config: const AiValidationConfig(minResponseLength: 10),
      );
      final r = v.validate('Hi');
      expect(r.isValid, isFalse);
      expect(r.errors.any((e) => e.contains('长度不足')), isTrue);
    });
  });

  group('AiResponseValidator - JSON validation', () {
    test('valid JSON', () {
      final v = AiResponseValidator(
        config: AiValidationConfig.jsonResponse(),
      );
      final r = v.validate('{"key": "value"}');
      expect(r.isValid, isTrue);
      expect(r.parsedJson?['key'], 'value');
    });

    test('invalid JSON', () {
      final v = AiResponseValidator(
        config: AiValidationConfig.jsonResponse(),
      );
      final r = v.validate('not json');
      expect(r.isValid, isFalse);
      expect(r.errors.any((e) => e.contains('JSON')), isTrue);
    });

    test('JSON in markdown code block', () {
      final v = AiResponseValidator(
        config: AiValidationConfig.jsonResponse(),
      );
      final r = v.validate('```json\n{"key": "value"}\n```');
      expect(r.isValid, isTrue);
      expect(r.parsedJson?['key'], 'value');
      expect(r.warnings.any((w) => w.contains('Markdown')), isTrue);
    });

    test('JSON in plain code block', () {
      final v = AiResponseValidator(
        config: AiValidationConfig.jsonResponse(),
      );
      final r = v.validate('```\n{"key": "value"}\n```');
      expect(r.isValid, isTrue);
    });

    test('bare JSON object extraction', () {
      final v = AiResponseValidator(
        config: AiValidationConfig.jsonResponse(),
      );
      final r = v.validate('Here is the result: {"key": "value"} end');
      expect(r.isValid, isTrue);
    });

    test('required JSON fields present', () {
      final v = AiResponseValidator(
        config: AiValidationConfig.jsonResponse(requiredFields: ['name']),
      );
      final r = v.validate('{"name": "test"}');
      expect(r.isValid, isTrue);
    });

    test('required JSON fields missing', () {
      final v = AiResponseValidator(
        config: AiValidationConfig.jsonResponse(requiredFields: ['name', 'price']),
      );
      final r = v.validate('{"name": "test"}');
      expect(r.isValid, isFalse);
      expect(r.errors.any((e) => e.contains('price')), isTrue);
    });

    test('JSON is array not object', () {
      final v = AiResponseValidator(
        config: AiValidationConfig.jsonResponse(),
      );
      final r = v.validate('[1, 2, 3]');
      expect(r.isValid, isFalse);
    });
  });

  group('AiResponseValidator - sanitization', () {
    test('removes control characters', () {
      final v = AiResponseValidator();
      final r = v.validate('Hello\x00World\x07!');
      expect(r.isValid, isTrue);
      expect(r.sanitizedContent, 'HelloWorld!');
    });

    test('normalizes line endings', () {
      final v = AiResponseValidator();
      final r = v.validate('line1\r\nline2\rline3');
      expect(r.isValid, isTrue);
      expect(r.sanitizedContent, 'line1\nline2\nline3');
    });

    test('removes excessive newlines', () {
      final v = AiResponseValidator();
      final r = v.validate('line1\n\n\n\n\n\nline2');
      expect(r.isValid, isTrue);
      expect(r.sanitizedContent, 'line1\n\n\nline2');
    });

    test('trims whitespace', () {
      final v = AiResponseValidator();
      final r = v.validate('  hello  ');
      expect(r.isValid, isTrue);
      expect(r.sanitizedContent, 'hello');
    });

    test('autoFix disabled skips sanitization', () {
      final v = AiResponseValidator(
        config: const AiValidationConfig(autoFix: false),
      );
      final r = v.validate('  hello  ');
      expect(r.isValid, isTrue);
      expect(r.sanitizedContent, '  hello  ');
    });
  });

  group('AiResponseValidator - forbidden patterns', () {
    test('detects forbidden pattern with autoFix', () {
      final v = AiResponseValidator(
        config: AiValidationConfig(
          forbiddenPatterns: [RegExp(r'secret:\s*\w+')],
          autoFix: true,
          detectHallucinations: false,
        ),
      );
      final r = v.validate('Data: secret: password123 end');
      expect(r.isValid, isTrue); // warnings only
      expect(r.warnings.any((w) => w.contains('禁止的内容')), isTrue);
      expect(r.sanitizedContent?.contains('secret:'), isFalse);
    });
  });

  group('AiResponseValidator - hallucination detection', () {
    test('detects suspicious URLs with example.com', () {
      final v = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: true),
      );
      final r = v.validate('Check this: https://example.com/product/123');
      expect(r.warnings.any((w) => w.contains('虚假 URL')), isTrue);
    });

    test('does not flag example.com with 示例', () {
      final v = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: true),
      );
      final r = v.validate('这是一个示例：https://example.com/test');
      expect(r.warnings.where((w) => w.contains('虚假 URL')), isEmpty);
    });

    test('detects localhost URLs', () {
      final v = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: true),
      );
      final r = v.validate('Visit http://localhost:8080/api');
      expect(r.warnings.any((w) => w.contains('虚假 URL')), isTrue);
    });

    test('detects 127.0.0.1 URLs', () {
      final v = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: true),
      );
      final r = v.validate('Visit http://127.0.0.1:3000/');
      expect(r.warnings.any((w) => w.contains('虚假 URL')), isTrue);
    });

    test('detects 192.168.x URLs', () {
      final v = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: true),
      );
      final r = v.validate('Connect to http://192.168.1.1/admin');
      expect(r.warnings.any((w) => w.contains('虚假 URL')), isTrue);
    });

    test('detects placeholder ID patterns', () {
      final v = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: true),
      );
      final r = v.validate('Product: https://shop.com/product/000000');
      expect(r.warnings.any((w) => w.contains('虚假 URL')), isTrue);
    });

    test('detects fake path pattern', () {
      final v = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: true),
      );
      final r = v.validate('See https://shop.com/fake/item');
      expect(r.warnings.any((w) => w.contains('虚假 URL')), isTrue);
    });

    test('detects suspicious extreme numbers', () {
      final v = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: true),
      );
      final r = v.validate('This product costs ¥99,999,999.00');
      expect(r.warnings.any((w) => w.contains('虚假数据')), isTrue);
    });

    test('detects unreasonable percentages', () {
      final v = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: true),
      );
      final r = v.validate('Discount: 150%');
      expect(r.warnings.any((w) => w.contains('虚假数据')), isTrue);
    });

    test('allows percentage > 100 with growth keywords', () {
      final v = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: true),
      );
      final r = v.validate('销量增长了 200%');
      expect(r.warnings.where((w) => w.contains('虚假数据')), isEmpty);
    });

    test('detects contradictions in same line', () {
      final v = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: true),
      );
      final r = v.validate('这款产品最便宜同时也最贵');
      expect(r.warnings.any((w) => w.contains('矛盾')), isTrue);
    });

    test('detects overconfidence', () {
      final v = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: true),
      );
      final r = v.validate('100% 保证成功');
      expect(r.warnings.any((w) => w.contains('过于自信')), isTrue);
    });

    test('detects overconfidence - 绝对不会', () {
      final v = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: true),
      );
      final r = v.validate('绝对不会出错');
      expect(r.warnings.any((w) => w.contains('过于自信')), isTrue);
    });

    test('detects overconfidence - 永远不会', () {
      final v = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: true),
      );
      final r = v.validate('永远不会有问题');
      expect(r.warnings.any((w) => w.contains('过于自信')), isTrue);
    });

    test('detects overconfidence - 肯定会', () {
      final v = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: true),
      );
      final r = v.validate('肯定会成功的');
      expect(r.warnings.any((w) => w.contains('过于自信')), isTrue);
    });

    test('no hallucination warnings for clean text', () {
      final v = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: true),
      );
      final r = v.validate('这是一款不错的产品，建议购买。');
      expect(r.warnings, isEmpty);
    });

    test('hallucination detection disabled', () {
      final v = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: false),
      );
      final r = v.validate('100% 保证成功 https://localhost:8080/');
      // no hallucination warnings
      expect(r.warnings.where((w) => w.contains('过于自信')), isEmpty);
    });
  });

  group('AiResponseValidator - validateAsResult', () {
    test('valid response', () {
      final v = AiResponseValidator();
      final r = v.validateAsResult('Hello world');
      expect(r.isSuccess, isTrue);
    });

    test('invalid response', () {
      final v = AiResponseValidator();
      final r = v.validateAsResult('');
      expect(r.isFailure, isTrue);
    });
  });

  group('AiResponseValidator - validateJson', () {
    test('valid JSON', () {
      final v = AiResponseValidator(
        config: AiValidationConfig.jsonResponse(),
      );
      final r = v.validateJson('{"key": "value"}');
      expect(r.isSuccess, isTrue);
      expect(r.valueOrNull?['key'], 'value');
    });

    test('invalid response (empty)', () {
      final v = AiResponseValidator(
        config: AiValidationConfig.jsonResponse(),
      );
      final r = v.validateJson('');
      expect(r.isFailure, isTrue);
    });

    test('valid response but no parsed json', () {
      // Plain text validator with validateJson call
      final v = AiResponseValidator();
      final r = v.validateJson('not json');
      expect(r.isFailure, isTrue);
    });

    test('valid JSON via validateJson with parsed json', () {
      final v = AiResponseValidator(
        config: AiValidationConfig.jsonResponse(),
      );
      final json = jsonEncode({'name': 'test', 'value': 42});
      final r = v.validateJson(json);
      expect(r.isSuccess, isTrue);
      expect(r.valueOrNull?['name'], 'test');
    });
  });

  group('Convenience functions', () {
    test('validateAiResponse', () {
      final r = validateAiResponse('Hello world');
      expect(r.isValid, isTrue);
    });

    test('validateAiResponse with config', () {
      final r = validateAiResponse(
        '',
        config: const AiValidationConfig(),
      );
      expect(r.isValid, isFalse);
    });

    test('validateAiJsonResponse valid', () {
      final r = validateAiJsonResponse('{"name": "test"}');
      expect(r.isSuccess, isTrue);
    });

    test('validateAiJsonResponse with required fields', () {
      final r = validateAiJsonResponse(
        '{"name": "test"}',
        requiredFields: ['name', 'price'],
      );
      expect(r.isFailure, isTrue);
    });

    test('validateAiJsonResponse invalid JSON', () {
      final r = validateAiJsonResponse('not json');
      expect(r.isFailure, isTrue);
    });
  });
}

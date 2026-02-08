import 'dart:convert';
import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/validation/ai_response_validator.dart';

void main() {
  group('AiValidationResult', () {
    test('valid factory should create valid result', () {
      final result = AiValidationResult.valid('hello');
      expect(result.isValid, isTrue);
      expect(result.sanitizedContent, equals('hello'));
      expect(result.errors, isEmpty);
    });

    test('invalid factory should create invalid result', () {
      final result = AiValidationResult.invalid(['err1', 'err2']);
      expect(result.isValid, isFalse);
      expect(result.errors.length, equals(2));
    });

    test('validWithWarnings should be valid but have warnings', () {
      final result = AiValidationResult.validWithWarnings('ok', ['warn']);
      expect(result.isValid, isTrue);
      expect(result.warnings, contains('warn'));
    });
  });

  group('AiValidationConfig', () {
    test('default config should have reasonable limits', () {
      const config = AiValidationConfig();
      expect(config.maxResponseLength, equals(100000));
      expect(config.minResponseLength, equals(1));
      expect(config.requireValidJson, isFalse);
      expect(config.detectHallucinations, isTrue);
    });

    test('chatResponse preset should have correct settings', () {
      expect(AiValidationConfig.chatResponse.maxResponseLength, equals(50000));
      expect(AiValidationConfig.chatResponse.requireValidJson, isFalse);
      expect(AiValidationConfig.chatResponse.allowMarkdown, isTrue);
    });

    test('jsonResponse should require valid JSON', () {
      final config = AiValidationConfig.jsonResponse(
        requiredFields: ['name', 'price'],
      );
      expect(config.requireValidJson, isTrue);
      expect(config.requiredJsonFields, contains('name'));
      expect(config.requiredJsonFields, contains('price'));
    });

    test('productRecommendation should require recommendations field', () {
      expect(
        AiValidationConfig.productRecommendation.requiredJsonFields,
        contains('recommendations'),
      );
    });
  });

  group('AiResponseValidator - Basic validation', () {
    late AiResponseValidator validator;

    setUp(() {
      validator = AiResponseValidator();
    });

    test('should accept valid text response', () {
      final result = validator.validate('This is a valid response about products.');
      expect(result.isValid, isTrue);
      expect(result.sanitizedContent, isNotNull);
    });

    test('should reject empty response', () {
      final result = validator.validate('');
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('空')), isTrue);
    });

    test('should reject response exceeding max length', () {
      final longResponse = 'a' * 200000;
      final validator = AiResponseValidator(
        config: const AiValidationConfig(maxResponseLength: 100, autoFix: false),
      );
      final result = validator.validate(longResponse);
      expect(result.isValid, isFalse);
    });

    test('should auto-truncate when autoFix is enabled', () {
      final longResponse = 'a' * 200;
      final validator = AiResponseValidator(
        config: const AiValidationConfig(maxResponseLength: 100, autoFix: true),
      );
      final result = validator.validate(longResponse);
      // When autoFix is enabled, truncation happens but minLength is 1, so it should still
      // have errors from the original length check
      expect(result.errors.isNotEmpty || result.warnings.isNotEmpty, isTrue);
    });

    test('should reject response below min length', () {
      final validator = AiResponseValidator(
        config: const AiValidationConfig(minResponseLength: 10, autoFix: false),
      );
      final result = validator.validate('hi');
      expect(result.isValid, isFalse);
    });
  });

  group('AiResponseValidator - Content sanitization', () {
    late AiResponseValidator validator;

    setUp(() {
      validator = AiResponseValidator();
    });

    test('should remove control characters', () {
      final result = validator.validate('hello\x00\x01world');
      expect(result.isValid, isTrue);
      expect(result.sanitizedContent, isNot(contains('\x00')));
      expect(result.sanitizedContent, isNot(contains('\x01')));
    });

    test('should normalize line endings', () {
      final result = validator.validate('line1\r\nline2\rline3');
      expect(result.isValid, isTrue);
      expect(result.sanitizedContent, isNot(contains('\r')));
    });

    test('should reduce excessive newlines', () {
      final result = validator.validate('line1\n\n\n\n\n\nline2');
      expect(result.isValid, isTrue);
      // Should reduce to max 3 consecutive newlines
      expect(result.sanitizedContent!.contains('\n\n\n\n'), isFalse);
    });

    test('should trim whitespace', () {
      final result = validator.validate('  hello world  ');
      expect(result.isValid, isTrue);
      expect(result.sanitizedContent, equals('hello world'));
    });
  });

  group('AiResponseValidator - JSON validation', () {
    test('should accept valid JSON', () {
      final validator = AiResponseValidator(
        config: AiValidationConfig.jsonResponse(),
      );
      final json = jsonEncode({'name': 'Product', 'price': 99.99});
      final result = validator.validate(json);
      expect(result.isValid, isTrue);
      expect(result.parsedJson, isNotNull);
      expect(result.parsedJson!['name'], equals('Product'));
    });

    test('should reject invalid JSON when required', () {
      final validator = AiResponseValidator(
        config: AiValidationConfig.jsonResponse(),
      );
      final result = validator.validate('not json at all');
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('JSON')), isTrue);
    });

    test('should check required JSON fields', () {
      final validator = AiResponseValidator(
        config: AiValidationConfig.jsonResponse(
          requiredFields: ['name', 'price', 'description'],
        ),
      );
      final json = jsonEncode({'name': 'Product', 'price': 99.99});
      final result = validator.validate(json);
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('description')), isTrue);
    });

    test('should extract JSON from markdown code blocks', () {
      final validator = AiResponseValidator(
        config: AiValidationConfig.jsonResponse(),
      );
      final markdown = '''
Here is the result:
```json
{"name": "Product", "price": 99.99}
```
''';
      final result = validator.validate(markdown);
      expect(result.isValid, isTrue);
      expect(result.parsedJson!['name'], equals('Product'));
      expect(result.warnings.any((w) => w.contains('Markdown')), isTrue);
    });

    test('should extract JSON from bare code blocks', () {
      final validator = AiResponseValidator(
        config: AiValidationConfig.jsonResponse(),
      );
      final markdown = '''
```
{"name": "Test"}
```
''';
      final result = validator.validate(markdown);
      expect(result.isValid, isTrue);
    });

    test('validateJson should return Result type', () {
      final validator = AiResponseValidator(
        config: AiValidationConfig.jsonResponse(),
      );
      final json = jsonEncode({'key': 'value'});
      final result = validator.validateJson(json);
      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull!['key'], equals('value'));
    });

    test('validateAsResult should return Result<String>', () {
      final validator = AiResponseValidator();
      final result = validator.validateAsResult('valid response');
      expect(result.isSuccess, isTrue);
    });
  });

  group('AiResponseValidator - Forbidden patterns', () {
    test('should detect and warn about forbidden patterns', () {
      final validator = AiResponseValidator(
        config: AiValidationConfig(
          forbiddenPatterns: [RegExp(r'<script.*?>', caseSensitive: false)],
          autoFix: true,
        ),
      );
      final result = validator.validate('Hello <script>alert(1)</script> world');
      expect(result.warnings.isNotEmpty || result.sanitizedContent!.contains('[内容已移除]'), isTrue);
    });
  });

  group('AiResponseValidator - Hallucination detection', () {
    test('should detect suspicious URLs with example.com', () {
      final validator = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: true),
      );
      final result = validator.validate(
        'Check this product: https://example.com/product/123',
      );
      expect(result.warnings.any((w) => w.contains('URL')), isTrue);
    });

    test('should detect localhost URLs', () {
      final validator = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: true),
      );
      final result = validator.validate(
        'API is at http://localhost:3000/api/v1',
      );
      expect(result.warnings.any((w) => w.contains('URL')), isTrue);
    });

    test('should detect overconfident statements', () {
      final validator = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: true),
      );
      final result = validator.validate('这个产品100%保证质量');
      expect(result.warnings.any((w) => w.contains('自信')), isTrue);
    });

    test('should detect contradictions in same line', () {
      final validator = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: true),
      );
      final result = validator.validate('这个产品最便宜也是最贵的');
      expect(result.warnings.any((w) => w.contains('矛盾')), isTrue);
    });

    test('should not detect issues in clean text', () {
      final validator = AiResponseValidator(
        config: const AiValidationConfig(detectHallucinations: true),
      );
      final result = validator.validate(
        '这款手机性价比不错，屏幕清晰，电池续航好。推荐购买。',
      );
      expect(result.isValid, isTrue);
      expect(result.warnings, isEmpty);
    });
  });

  group('Convenience functions', () {
    test('validateAiResponse should validate text', () {
      final result = validateAiResponse('valid text');
      expect(result.isValid, isTrue);
    });

    test('validateAiJsonResponse should validate JSON', () {
      final json = jsonEncode({'name': 'Test'});
      final result = validateAiJsonResponse(json, requiredFields: ['name']);
      expect(result.isSuccess, isTrue);
    });

    test('validateAiJsonResponse should fail for missing fields', () {
      final json = jsonEncode({'name': 'Test'});
      final result = validateAiJsonResponse(json, requiredFields: ['name', 'missing']);
      expect(result.isFailure, isTrue);
    });
  });
}

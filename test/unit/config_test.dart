import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/config.dart';

void main() {
  group('Config - Placeholder detection', () {
    test('should detect YOUR_ prefix as placeholder', () {
      expect(Config.isPlaceholder('YOUR_API_KEY'), isTrue);
    });

    test('should detect your_ prefix as placeholder', () {
      expect(Config.isPlaceholder('your_api_key'), isTrue);
    });

    test('should detect empty string as placeholder', () {
      expect(Config.isPlaceholder(''), isTrue);
    });

    test('should not detect real values as placeholder', () {
      expect(Config.isPlaceholder('sk-1234567890'), isFalse);
      expect(Config.isPlaceholder('real_value_123'), isFalse);
      expect(Config.isPlaceholder('abc123'), isFalse);
    });

    test('should not detect partial match as placeholder', () {
      expect(Config.isPlaceholder('NOT_YOUR_KEY'), isFalse);
      expect(Config.isPlaceholder('myYOUR_KEY'), isFalse);
    });
  });

  group('Config - Platform configuration checks consistency', () {
    // These tests verify that the platform check methods are consistent
    // with the individual placeholder checks, regardless of environment.

    test('isTaobaoConfigured should be consistent with placeholder checks', () {
      final expected = !Config.isPlaceholder(Config.taobaoAppKey) &&
          !Config.isPlaceholder(Config.taobaoAppSecret) &&
          !Config.isPlaceholder(Config.taobaoAdzoneId);
      expect(Config.isTaobaoConfigured(), equals(expected));
    });

    test('isJdConfigured should be consistent with placeholder checks', () {
      final expected = !Config.isPlaceholder(Config.jdAppKey) &&
          !Config.isPlaceholder(Config.jdAppSecret) &&
          !Config.isPlaceholder(Config.jdUnionId);
      expect(Config.isJdConfigured(), equals(expected));
    });

    test('isPddConfigured should be consistent with placeholder checks', () {
      final expected = !Config.isPlaceholder(Config.pddClientId) &&
          !Config.isPlaceholder(Config.pddClientSecret) &&
          !Config.isPlaceholder(Config.pddPid);
      expect(Config.isPddConfigured(), equals(expected));
    });

    test('isOpenAiConfigured should be consistent with placeholder checks', () {
      final expected = !Config.isPlaceholder(Config.openAiApiKey);
      expect(Config.isOpenAiConfigured(), equals(expected));
    });
  });

  group('Config - Validation', () {
    test('validate should return list of string keys', () {
      final missing = Config.validate();
      expect(missing, isA<List<String>>());
      for (final key in missing) {
        expect(key, isA<String>());
        expect(key, isNotEmpty);
      }
    });

    test('validate results should be consistent with isPlaceholder', () {
      final missing = Config.validate();

      // Each reported missing key should have a placeholder value
      final allKeys = {
        'TAOBAO_APP_KEY': Config.taobaoAppKey,
        'TAOBAO_APP_SECRET': Config.taobaoAppSecret,
        'TAOBAO_ADZONE_ID': Config.taobaoAdzoneId,
        'JD_APP_KEY': Config.jdAppKey,
        'JD_APP_SECRET': Config.jdAppSecret,
        'JD_UNION_ID': Config.jdUnionId,
        'PDD_CLIENT_ID': Config.pddClientId,
        'PDD_CLIENT_SECRET': Config.pddClientSecret,
        'PDD_PID': Config.pddPid,
        'OPENAI_API_KEY': Config.openAiApiKey,
      };

      for (final key in missing) {
        expect(allKeys.containsKey(key), isTrue,
            reason: 'Missing key "$key" should be in config keys');
        expect(Config.isPlaceholder(allKeys[key]!), isTrue,
            reason: 'Missing key "$key" should have placeholder value');
      }

      // Configured keys (not in missing) should NOT be placeholders
      for (final entry in allKeys.entries) {
        if (!missing.contains(entry.key)) {
          expect(Config.isPlaceholder(entry.value), isFalse,
              reason:
                  'Configured key "${entry.key}" should not be placeholder');
        }
      }
    });

    test('validate should return at most 10 keys', () {
      final missing = Config.validate();
      expect(missing.length, lessThanOrEqualTo(10));
    });
  });

  group('Config - Getter existence', () {
    // These tests verify that all config getters exist and return strings
    test('affiliateId should return a string', () {
      expect(Config.affiliateId, isA<String>());
    });

    test('taobao config getters should return strings', () {
      expect(Config.taobaoAppKey, isA<String>());
      expect(Config.taobaoAppSecret, isA<String>());
      expect(Config.taobaoAdzoneId, isA<String>());
    });

    test('jd config getters should return strings', () {
      expect(Config.jdAppKey, isA<String>());
      expect(Config.jdAppSecret, isA<String>());
      expect(Config.jdUnionId, isA<String>());
    });

    test('pdd config getters should return strings', () {
      expect(Config.pddClientId, isA<String>());
      expect(Config.pddClientSecret, isA<String>());
      expect(Config.pddPid, isA<String>());
    });

    test('openAiApiKey should return a string', () {
      expect(Config.openAiApiKey, isA<String>());
    });
  });
}

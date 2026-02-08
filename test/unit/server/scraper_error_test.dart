import 'package:test/test.dart';

import '../../../server/lib/jd_scraper/models/scraper_error.dart';

void main() {
  group('ScraperErrorType', () {
    test('should have all expected types', () {
      expect(ScraperErrorType.values, contains(ScraperErrorType.cookieExpired));
      expect(ScraperErrorType.values, contains(ScraperErrorType.loginRequired));
      expect(ScraperErrorType.values, contains(ScraperErrorType.antiBotDetected));
      expect(ScraperErrorType.values, contains(ScraperErrorType.networkError));
      expect(ScraperErrorType.values, contains(ScraperErrorType.timeout));
      expect(ScraperErrorType.values, contains(ScraperErrorType.productNotFound));
      expect(ScraperErrorType.values, contains(ScraperErrorType.unknown));
    });
  });

  group('ScraperException - Factory constructors', () {
    test('cookieExpired should have correct type and message', () {
      final ex = ScraperException.cookieExpired();
      expect(ex.type, equals(ScraperErrorType.cookieExpired));
      expect(ex.message, contains('Cookie'));
    });

    test('cookieExpired should accept custom message', () {
      final ex = ScraperException.cookieExpired('custom message');
      expect(ex.message, equals('custom message'));
    });

    test('loginRequired should have correct type', () {
      final ex = ScraperException.loginRequired();
      expect(ex.type, equals(ScraperErrorType.loginRequired));
      expect(ex.message, contains('登录'));
    });

    test('antiBotDetected should have correct type', () {
      final ex = ScraperException.antiBotDetected();
      expect(ex.type, equals(ScraperErrorType.antiBotDetected));
      expect(ex.message, contains('反爬虫'));
    });

    test('networkError should wrap original error', () {
      final originalError = Exception('socket closed');
      final ex = ScraperException.networkError(originalError);
      expect(ex.type, equals(ScraperErrorType.networkError));
      expect(ex.originalError, equals(originalError));
      expect(ex.message, contains('网络错误'));
      expect(ex.message, contains('socket closed'));
    });

    test('networkError should capture stack trace', () {
      final stack = StackTrace.current;
      final ex = ScraperException.networkError(Exception('err'), stack);
      expect(ex.stackTrace, equals(stack));
    });

    test('timeout should have correct type', () {
      final ex = ScraperException.timeout();
      expect(ex.type, equals(ScraperErrorType.timeout));
      expect(ex.message, contains('超时'));
    });

    test('productNotFound should have correct type', () {
      final ex = ScraperException.productNotFound();
      expect(ex.type, equals(ScraperErrorType.productNotFound));
      expect(ex.message, contains('未找到'));
    });

    test('unknown should wrap original error', () {
      final ex = ScraperException.unknown('mysterious error');
      expect(ex.type, equals(ScraperErrorType.unknown));
      expect(ex.message, contains('mysterious error'));
      expect(ex.originalError, equals('mysterious error'));
    });
  });

  group('ScraperException - toString', () {
    test('should include type and message', () {
      final ex = ScraperException.cookieExpired('expired');
      final str = ex.toString();
      expect(str, contains('ScraperException'));
      expect(str, contains('cookieExpired'));
      expect(str, contains('expired'));
    });
  });

  group('ScraperException - toJson', () {
    test('should serialize basic fields', () {
      final ex = ScraperException.timeout('请求超时了');
      final json = ex.toJson();
      expect(json['type'], equals('timeout'));
      expect(json['message'], equals('请求超时了'));
      expect(json.containsKey('originalError'), isFalse);
    });

    test('should include originalError when present', () {
      final ex = ScraperException.networkError(Exception('connection failed'));
      final json = ex.toJson();
      expect(json.containsKey('originalError'), isTrue);
      expect(json['originalError'], contains('connection failed'));
    });
  });

  group('ScraperException - implements Exception', () {
    test('should be throwable and catchable', () {
      expect(
        () => throw ScraperException.cookieExpired(),
        throwsA(isA<ScraperException>()),
      );
    });

    test('should be catchable as Exception', () {
      expect(
        () => throw ScraperException.timeout(),
        throwsA(isA<Exception>()),
      );
    });
  });
}

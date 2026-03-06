import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/jd_sign.dart';

void main() {
  group('computeJdSign', () {
    test('should produce uppercase hex MD5', () {
      final params = {'app_key': '123', 'method': 'jd.union.open.goods.query'};
      final sign = computeJdSign(params, 'secret');

      // Should be 32 hex characters, all uppercase
      expect(sign.length, equals(32));
      expect(sign, equals(sign.toUpperCase()));
      expect(RegExp(r'^[0-9A-F]{32}$').hasMatch(sign), isTrue);
    });

    test('should be deterministic for same inputs', () {
      final params = {'key1': 'val1', 'key2': 'val2'};
      final sign1 = computeJdSign(params, 'secret');
      final sign2 = computeJdSign(params, 'secret');
      expect(sign1, equals(sign2));
    });

    test('should differ with different secrets', () {
      final params = {'key': 'value'};
      final sign1 = computeJdSign(params, 'secret1');
      final sign2 = computeJdSign(params, 'secret2');
      expect(sign1, isNot(equals(sign2)));
    });

    test('should differ with different params', () {
      final sign1 = computeJdSign({'key': 'value1'}, 'secret');
      final sign2 = computeJdSign({'key': 'value2'}, 'secret');
      expect(sign1, isNot(equals(sign2)));
    });

    test('should sort params alphabetically', () {
      final params1 = {'b': '2', 'a': '1'};
      final params2 = {'a': '1', 'b': '2'};
      expect(computeJdSign(params1, 'sec'), equals(computeJdSign(params2, 'sec')));
    });

    test('should handle empty params', () {
      final sign = computeJdSign({}, 'secret');
      // secret + secret = "secretsecret"
      final expected = md5.convert(utf8.encode('secretsecret')).toString().toUpperCase();
      expect(sign, equals(expected));
    });

    test('should handle single param', () {
      final sign = computeJdSign({'key': 'val'}, 'sec');
      // buffer = "sec" + "key" + "val" + "sec" = "seckeyvalsec"
      final correctExpected = md5.convert(utf8.encode('seckeyvalsec')).toString().toUpperCase();
      expect(sign, equals(correctExpected));
    });

    test('should produce correct sign for known inputs', () {
      // Verify against manual computation
      final params = {'method': 'test.api', 'app_key': '123456'};
      final secret = 'mysecret';

      // Sorted keys: app_key, method
      // String: mysecret + app_key123456 + methodtest.api + mysecret
      // = "mysecretapp_key123456methodtest.apimysecret"
      final inputStr = 'mysecretapp_key123456methodtest.apimysecret';
      final expectedSign = md5.convert(utf8.encode(inputStr)).toString().toUpperCase();

      expect(computeJdSign(params, secret), equals(expectedSign));
    });

    test('should handle Chinese characters', () {
      final params = {'keyword': '手机'};
      final sign = computeJdSign(params, 'secret');
      expect(sign.length, equals(32));
      expect(RegExp(r'^[0-9A-F]{32}$').hasMatch(sign), isTrue);
    });

    test('should handle empty values', () {
      final params = {'key1': '', 'key2': 'value'};
      final sign = computeJdSign(params, 'secret');
      expect(sign.length, equals(32));
    });
  });
}

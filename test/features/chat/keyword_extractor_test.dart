import 'package:flutter_test/flutter_test.dart';
import 'package:wisepick_dart_version/features/chat/keyword_extractor.dart';

void main() {
  group('KeywordExtractor', () {
    group('quickExtractKeywords', () {
      test('从 goods.title 提取关键词', () {
        const text = '{"goods": {"title": "无线耳机"}, "recommendations": []}';
        final result = KeywordExtractor.quickExtractKeywords(text);
        expect(result, contains('无线耳机'));
      });

      test('从通用 title 字段提取', () {
        const text = '{"title": "蓝牙音箱推荐", "description": "..."}';
        final result = KeywordExtractor.quickExtractKeywords(text);
        expect(result, contains('蓝牙音箱推荐'));
      });

      test('最多返回 6 个关键词', () {
        final titles = List.generate(10, (i) => '"title": "商品$i"').join(', ');
        final text = '{$titles}';
        final result = KeywordExtractor.quickExtractKeywords(text);
        expect(result.length, lessThanOrEqualTo(6));
      });

      test('空文本返回空列表', () {
        expect(KeywordExtractor.quickExtractKeywords(''), isEmpty);
      });

      test('无 title 字段返回空列表', () {
        const text = '{"description": "无标题内容"}';
        expect(KeywordExtractor.quickExtractKeywords(text), isEmpty);
      });

      test('去重处理', () {
        const text = '{"title": "相同商品"} {"title": "相同商品"}';
        final result = KeywordExtractor.quickExtractKeywords(text);
        expect(result.where((k) => k == '相同商品').length, equals(1));
      });

      test('title 长度过短（<3字符）不提取', () {
        const text = '{"title": "ab"}';
        final result = KeywordExtractor.quickExtractKeywords(text);
        expect(result, isEmpty);
      });
    });

    group('deriveKeywordsFromParsedMap', () {
      test('null 输入返回空列表', () {
        expect(KeywordExtractor.deriveKeywordsFromParsedMap(null), isEmpty);
      });

      test('从 keywords 字段提取', () {
        final pm = {
          'keywords': ['耳机', '蓝牙', '降噪'],
        };
        final result = KeywordExtractor.deriveKeywordsFromParsedMap(pm);
        expect(result, containsAll(['耳机', '蓝牙', '降噪']));
      });

      test('从 recommendations[].goods.title 提取', () {
        final pm = {
          'recommendations': [
            {'goods': {'title': '索尼耳机'}},
            {'goods': {'title': '苹果耳机'}},
          ],
        };
        final result = KeywordExtractor.deriveKeywordsFromParsedMap(pm);
        expect(result, containsAll(['索尼耳机', '苹果耳机']));
      });

      test('从 recommendations[].title 提取（回退）', () {
        final pm = {
          'recommendations': [
            {'title': '华为手机'},
          ],
        };
        final result = KeywordExtractor.deriveKeywordsFromParsedMap(pm);
        expect(result, contains('华为手机'));
      });

      test('recommendations 为字符串列表时提取', () {
        final pm = {
          'recommendations': ['手机壳', '钢化膜'],
        };
        final result = KeywordExtractor.deriveKeywordsFromParsedMap(pm);
        expect(result, containsAll(['手机壳', '钢化膜']));
      });

      test('keywords 优先于 recommendations', () {
        final pm = {
          'keywords': ['关键词A'],
          'recommendations': [
            {'title': '推荐商品B'},
          ],
        };
        final result = KeywordExtractor.deriveKeywordsFromParsedMap(pm);
        expect(result.first, equals('关键词A'));
      });

      test('最多返回 6 个关键词', () {
        final pm = {
          'keywords': List.generate(10, (i) => '关键词$i'),
        };
        final result = KeywordExtractor.deriveKeywordsFromParsedMap(pm);
        expect(result.length, lessThanOrEqualTo(6));
      });

      test('空字符串关键词被过滤', () {
        final pm = {
          'keywords': ['', '  ', '有效关键词'],
        };
        final result = KeywordExtractor.deriveKeywordsFromParsedMap(pm);
        expect(result, equals(['有效关键词']));
      });
    });
  });
}

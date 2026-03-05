import 'package:flutter_test/flutter_test.dart';
import 'package:wisepick_dart_version/features/chat/streaming_text_filter.dart';

void main() {
  group('StreamingTextFilter', () {
    group('streamingDisplayText', () {
      test('纯文本直接返回', () {
        const input = '这是一段普通文本';
        expect(StreamingTextFilter.streamingDisplayText(input), equals('这是一段普通文本'));
      });

      test('空字符串返回空', () {
        expect(StreamingTextFilter.streamingDisplayText(''), equals(''));
        expect(StreamingTextFilter.streamingDisplayText('   '), equals(''));
      });

      test('JSON 块被隐藏，返回占位符', () {
        const input = '{"recommendations": [{"title": "商品A"}]}';
        final result = StreamingTextFilter.streamingDisplayText(input);
        expect(result, equals('正在分析推荐结果…'));
      });

      test('JSON 前的文本被保留', () {
        const input = '为您推荐以下商品：\n{"recommendations": []}';
        final result = StreamingTextFilter.streamingDisplayText(input);
        expect(result, contains('为您推荐以下商品'));
      });

      test('提取 analysis 字段内容', () {
        const input = '{"analysis": "这是分析内容", "recommendations": []}';
        final result = StreamingTextFilter.streamingDisplayText(input);
        expect(result, equals('这是分析内容'));
      });

      test('analysis 字段转义字符正确处理', () {
        const input = '{"analysis": "第一行\\n第二行", "recommendations": []}';
        final result = StreamingTextFilter.streamingDisplayText(input);
        expect(result, contains('第一行'));
        expect(result, contains('第二行'));
      });

      test('markdown 代码围栏被剥除', () {
        const input = '```json\n{"analysis": "内容"}\n```';
        final result = StreamingTextFilter.streamingDisplayText(input);
        expect(result, equals('内容'));
      });

      test('JSON 前文本 + analysis 字段合并', () {
        const input = '前置文本\n{"analysis": "分析结果"}';
        final result = StreamingTextFilter.streamingDisplayText(input);
        expect(result, contains('前置文本'));
        expect(result, contains('分析结果'));
      });
    });

    group('stripMetaLines', () {
      test('过滤 title: 行', () {
        const input = 'title: 这是标题\n正文内容';
        final result = StreamingTextFilter.stripMetaLines(input);
        expect(result, equals('正文内容'));
        expect(result, isNot(contains('title:')));
      });

      test('过滤 标题: 行', () {
        const input = '标题：测试标题\n正文';
        final result = StreamingTextFilter.stripMetaLines(input);
        expect(result, equals('正文'));
      });

      test('过滤 PARSE_ 前缀行', () {
        const input = 'PARSE_STATUS:OK\n正文内容';
        final result = StreamingTextFilter.stripMetaLines(input);
        expect(result, equals('正文内容'));
      });

      test('过滤 FIRST_REC_KEYS: 行', () {
        const input = 'FIRST_REC_KEYS:title,desc\n正文';
        final result = StreamingTextFilter.stripMetaLines(input);
        expect(result, equals('正文'));
      });

      test('保留普通文本行', () {
        const input = '这是正常内容\n另一行内容';
        final result = StreamingTextFilter.stripMetaLines(input);
        expect(result, equals('这是正常内容\n另一行内容'));
      });

      test('空字符串返回空', () {
        expect(StreamingTextFilter.stripMetaLines(''), equals(''));
      });
    });
  });
}

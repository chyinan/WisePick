/// 流式文本过滤工具
/// 在 AI 流式响应过程中，过滤原始 JSON 噪声，只返回用户可见的正文。
class StreamingTextFilter {
  StreamingTextFilter._();

  /// 过滤流式原始内容，返回用户友好的显示文本。
  /// 规则：JSON 块一律隐藏，仅显示 JSON 前的纯文本或 analysis 字段；title 行也过滤掉。
  static String streamingDisplayText(String raw) {
    var trimmed = raw.trimLeft();
    if (trimmed.isEmpty) return '';

    // 剥掉 markdown 代码围栏
    trimmed = trimmed
        .replaceAll(RegExp(r'```(?:json)?\s*', caseSensitive: false), '')
        .trimLeft();

    final jsonStart = trimmed.indexOf('{');
    if (jsonStart == -1) return stripMetaLines(raw);

    final textBefore =
        jsonStart > 0 ? trimmed.substring(0, jsonStart).trim() : '';
    final jsonPart = trimmed.substring(jsonStart);

    final m =
        RegExp(r'"analysis"\s*:\s*"((?:[^"\\]|\\.)*)"').firstMatch(jsonPart);
    if (m != null && m.group(1) != null) {
      final analysis = m
          .group(1)!
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\"', '"')
          .replaceAll(r'\\', '\\')
          .trim();
      if (analysis.isNotEmpty) {
        return textBefore.isNotEmpty ? '$textBefore\n\n$analysis' : analysis;
      }
    }

    if (textBefore.isNotEmpty) return stripMetaLines(textBefore);
    return '正在分析推荐结果…';
  }

  /// 过滤掉 title/标题 行以及调试前缀行
  static String stripMetaLines(String text) {
    return text.split('\n').where((line) {
      final s = line.trimLeft();
      if (RegExp(r'^(?:title|标题)\s*[:：]', caseSensitive: false).hasMatch(s)) {
        return false;
      }
      if (s.startsWith('PARSE_') ||
          s.startsWith('FIRST_REC_KEYS:') ||
          s.startsWith('PARSE_KEYS:')) {
        return false;
      }
      return true;
    }).join('\n').trim();
  }
}

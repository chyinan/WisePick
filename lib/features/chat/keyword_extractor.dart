import 'dart:developer' show log;

/// 从 AI 响应文本或解析后的 Map 中提取商品关键词
class KeywordExtractor {
  KeywordExtractor._();

  /// 从流式 AI 文本中快速提取候选关键词（用于实时搜索触发）
  static List<String> quickExtractKeywords(String text) {
    try {
      final kws = <String>[];
      // 优先从嵌套 goods.title 提取
      final goodsTitleReg = RegExp(
          r'"goods"\s*:\s*\{[^}]*"title"\s*:\s*"([^"]+)"',
          multiLine: true);
      for (final m in goodsTitleReg.allMatches(text)) {
        final s = m.group(1)?.trim();
        if (s != null && s.isNotEmpty && !kws.contains(s)) {
          kws.add(s);
          if (kws.length >= 6) return kws;
        }
      }
      // 回退：通用 title 字段
      final titleReg =
          RegExp(r'"title"\s*:\s*"([^"]{3,120})"', multiLine: true);
      for (final m in titleReg.allMatches(text)) {
        final s = m.group(1)?.trim();
        if (s != null && s.isNotEmpty && !kws.contains(s)) {
          kws.add(s);
          if (kws.length >= 6) return kws;
        }
      }
      return kws;
    } catch (e, st) {
      log('Error extracting keywords from AI: $e',
          name: 'KeywordExtractor', error: e, stackTrace: st);
      return <String>[];
    }
  }

  /// 从已解析的 parsedMap 中提取关键词
  static List<String> deriveKeywordsFromParsedMap(Map<String, dynamic>? pm) {
    final out = <String>[];
    if (pm == null) return out;

    try {
      if (pm.containsKey('keywords') && pm['keywords'] is List) {
        for (final k in (pm['keywords'] as List)) {
          if (k is String) {
            final s = k.trim();
            if (s.isNotEmpty && !out.contains(s)) out.add(s);
            if (out.length >= 6) return out;
          }
        }
      }
    } catch (e, st) {
      log('KeywordExtractor error: $e',
          name: 'KeywordExtractor', error: e, stackTrace: st);
    }

    try {
      if (pm.containsKey('recommendations') && pm['recommendations'] is List) {
        for (final rec in (pm['recommendations'] as List)) {
          try {
            if (rec is Map<String, dynamic>) {
              String? s;
              if (rec.containsKey('goods') &&
                  rec['goods'] is Map &&
                  rec['goods']['title'] is String) {
                s = (rec['goods']['title'] as String).trim();
              }
              if ((s == null || s.isEmpty) &&
                  rec.containsKey('title') &&
                  rec['title'] is String) {
                s = (rec['title'] as String).trim();
              }
              if (s != null && s.isNotEmpty && !out.contains(s)) out.add(s);
            } else if (rec is String) {
              final s = rec.trim();
              if (s.isNotEmpty && !out.contains(s)) out.add(s);
            }
          } catch (e, st) {
            log('KeywordExtractor error: $e',
                name: 'KeywordExtractor', error: e, stackTrace: st);
          }
          if (out.length >= 6) break;
        }
      }
    } catch (e, st) {
      log('KeywordExtractor error: $e',
          name: 'KeywordExtractor', error: e, stackTrace: st);
    }

    return out;
  }
}

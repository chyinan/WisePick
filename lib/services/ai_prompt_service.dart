// Avoid external dependencies (intl) to keep the service lightweight.
/// AI Prompt Service
/// 提供两套 prompt 模板：普通问答（自然语言）与严格推荐（仅 JSON）
/// AI负责根据用户输入判断意图（是否为推荐请求），然后合并用户问题生成最终 prompt 字符串

class AiPromptService {
  // Note: intent is now decided by the model via hybrid system prompt. Keyword-based
  // intent detection has been removed in favor of model-based determination.

  /// 生成普通问答的 prompt（供 LLM 返回自然语言）
  static String buildCasualPrompt({required String userProfile, required String context, required String userQuestion}) {
    return '''System: You are a shopping assistant. When the user asks a question (not explicitly requesting product recommendations), answer in natural, helpful language in Chinese. You MAY include example products in prose, but do NOT output machine-only JSON.
User: 输入：user_profile=$userProfile, context=$context. 用户问题：$userQuestion
请直接用中文回答，给出可行建议与简短理由，如果建议商品，保持为普通文本描述，不要返回严格的 JSON.''';
  }

  /// 构建带角色的 messages 列表（符合 OpenAI Chat Completions 格式）
  /// 返回值为 List<Map<String, String>>，每项包含 'role' 与 'content'
  static List<Map<String, String>> buildMessages({required String userProfile, required String context, required String userQuestion, String constraints = '', int maxResults = 4, bool includeTitleInstruction = false}) {
    // Hybrid prompt: let the model decide whether to return structured JSON recommendations
    // or a natural-language answer. Prefer JSON when the user requests recommendations.
    final system = '''You are a shopping recommendation assistant. Decide whether the user requests concrete product recommendations or general advice.

If recommendations are requested, output exactly one compact JSON object (no extra text) with top-level keys `recommendations` (array) and `meta` (object).

Each recommendation must include:
- `goods.title` (string) — a concrete product model name or exact search phrase (e.g. "Sony WH-1000XM5" / "索尼 WH-1000XM5"). The client will use this as the search keyword.
- `goods.description` (short one-line)
- optional: `rating` (0-5), `tags`, `matchScore`, `reason`.

Example item JSON (no SKU/id required):
  {
    "goods": {
      "title": "索尼降噪耳机 WH-1000XM5",
      "description": "通勤降噪，续航30小时"
    },
    "rating": 4.5
  }

Additionally, include a top-level `analysis` string: a concise, persuasive summary in Chinese that explains the overall recommendation rationale (this will be shown above the suggested keywords/buttons). Keep it brief (<=150 characters).

Meta must include: `query`, `generatedAt` (ISO8601), `reason` (<=30 chars), `count`. Prefer `meta.title` for conversation title; as a fallback append a final line after the JSON exactly in this format on its own line:
  title: <concise Chinese title no longer than 15 characters>

If the user is NOT requesting recommendations, reply in concise, helpful Chinese (may include example products in prose). If JSON cannot be produced, return a short Chinese summary.''';

    final now = DateTime.now().toUtc().toIso8601String();
    final user = '输入：user_profile=$userProfile, context=$context, constraints=$constraints. 用户问题：$userQuestion. 返回最多 $maxResults 条推荐（如适用）。生成时间参考： $now';

    // Optionally append title instruction to system content when requested (used only on first user message)
    final systemContent = includeTitleInstruction
        ? system + '\n\nAdditionally, if you produce recommendations, append a final line to your response in the exact format:\ntitle: <a concise Chinese title no longer than 15 characters>\nThis title line must be on its own line at the very end of the assistant output so that it can be programmatically extracted and used as the conversation title.'
        : system;

    return [
      {'role': 'system', 'content': systemContent},
      {'role': 'user', 'content': user},
    ];
  }

  /// 返回 chat messages 列表，包含合适的 role 字段（'system' / 'user'）
  /// 这样可直接传给 OpenAI Chat Completions API 的 messages 参数
  static List<Map<String, String>> buildCasualPromptMessages({required String userProfile, required String context, required String userQuestion}) {
    final system = 'You are a shopping assistant. When the user asks a question (not explicitly requesting product recommendations), answer in natural, helpful language in Chinese. You MAY include example products in prose, but do NOT output machine-only JSON.';
    final user = '输入：user_profile=$userProfile, context=$context. 用户问题：$userQuestion\n请直接用中文回答，给出可行建议与简短理由，如果建议商品，保持为普通文本描述（可包含链接），不要返回严格的 JSON。';
    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  /// 生成严格推荐的 prompt（仅输出 JSON，供前端解析）
  static String buildRecommendationPrompt({required String userProfile, required String context, required String constraints, required String userQuestion, int maxResults = 4}) {
    final now = DateTime.now().toUtc().toIso8601String();
    return '''System: You are a shopping recommendation agent. IF the user requests product recommendations, ONLY output a single JSON object (no extra text). The JSON must have top-level keys `recommendations` (array), `analysis` (string) and `meta` (object). Each recommendation must include: id(string), title(string), description(string), rating(number 0-5). Optional per-item fields: currency(string, default CNY), availability('in_stock'|'out_of_stock'), tags(array[string]), matchScore(number 0.0-1.0), reason(string: one-line reason). Additionally, include a concise top-level `analysis` string in Chinese summarizing the recommendation rationale (<=150 characters). Meta must include: query(string), generatedAt(ISO8601), reason(string <=30 chars), count(int).
User: 输入：user_profile=$userProfile, context=$context, constraints=$constraints. 用户问题：$userQuestion. 返回最多 $maxResults 条推荐。生成时间参考： $now''';
  }

  /// 推荐场景下构建 messages（system + user），便于直接传入 API
  static List<Map<String, String>> buildRecommendationPromptMessages({required String userProfile, required String context, required String constraints, required String userQuestion, int maxResults = 4}) {
    final system = 'You are a shopping recommendation agent. IF the user requests product recommendations, ONLY output a single JSON object (no extra text). The JSON must have top-level keys `recommendations` (array), `analysis` (string) and `meta` (object). Each recommendation must include: id(string), title(string), description(string), price(number), imageUrl(string), sourceUrl(string), rating(number 0-5), reviewCount(int). Optional per-item fields: currency(string, default CNY), availability(\'in_stock\'|\'out_of_stock\'), tags(array[string]), matchScore(number 0.0-1.0), reason(string: one-line reason). Additionally include a concise top-level `analysis` string in Chinese summarizing the overall recommendation rationale (<=150 characters). Meta must include: query(string), generatedAt(ISO8601), reason(string <=30 chars), count(int). price MUST be a numeric value (no currency symbols).';
    final user = '输入：user_profile=$userProfile, context=$context, constraints=$constraints. 用户问题：$userQuestion. 返回最多 $maxResults 条推荐。生成时间参考： ${DateTime.now().toUtc().toIso8601String()}';
    return [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ];
  }

  /// 根据用户输入选择模板并返回最终 prompt 字符串
  static String buildPrompt({required String userProfile, required String context, required String userQuestion, String constraints = '', int maxResults = 4}) {
    // Compose a human-readable prompt string from the hybrid messages (backwards-compatible)
    final msgs = buildMessages(userProfile: userProfile, context: context, userQuestion: userQuestion, constraints: constraints, maxResults: maxResults);
    final system = msgs.isNotEmpty ? msgs[0]['content'] ?? '' : '';
    final user = msgs.length > 1 ? msgs[1]['content'] ?? '' : '';
    return 'System: ' + system + '\n\nUser: ' + user;
  }

  /// 新接口：根据意图返回可直接传给 OpenAI 的 messages 列表
  static List<Map<String, String>> buildPromptMessages({required String userProfile, required String context, required String userQuestion, String constraints = '', int maxResults = 4}) {
    return buildMessages(userProfile: userProfile, context: context, userQuestion: userQuestion, constraints: constraints, maxResults: maxResults);
  }

  /// 构建商品详情页介绍的 messages
  static List<Map<String, String>> buildProductDetailMessages({required String userQuestion}) {
    return [
      {'role': 'system', 'content': 'You are a helpful product analysis assistant. Please answer the user\'s request about product details in clear, objective Chinese using Markdown format.'},
      {'role': 'user', 'content': userQuestion},
    ];
  }
}



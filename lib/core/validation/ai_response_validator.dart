import 'dart:convert';
import 'dart:developer' as dev;

import '../resilience/result.dart';
import '../logging/app_logger.dart';

/// AI 响应验证结果
class AiValidationResult {
  final bool isValid;
  final String? sanitizedContent;
  final List<String> warnings;
  final List<String> errors;
  final Map<String, dynamic>? parsedJson;

  AiValidationResult({
    required this.isValid,
    this.sanitizedContent,
    this.warnings = const [],
    this.errors = const [],
    this.parsedJson,
  });

  factory AiValidationResult.valid(String content, {Map<String, dynamic>? json}) {
    return AiValidationResult(
      isValid: true,
      sanitizedContent: content,
      parsedJson: json,
    );
  }

  factory AiValidationResult.invalid(List<String> errors, {List<String> warnings = const []}) {
    return AiValidationResult(
      isValid: false,
      errors: errors,
      warnings: warnings,
    );
  }

  factory AiValidationResult.validWithWarnings(
    String content,
    List<String> warnings, {
    Map<String, dynamic>? json,
  }) {
    return AiValidationResult(
      isValid: true,
      sanitizedContent: content,
      warnings: warnings,
      parsedJson: json,
    );
  }
}

/// AI 响应验证配置
class AiValidationConfig {
  /// 最大响应长度
  final int maxResponseLength;

  /// 最小响应长度
  final int minResponseLength;

  /// 是否必须为有效 JSON
  final bool requireValidJson;

  /// 必须包含的 JSON 字段
  final List<String> requiredJsonFields;

  /// 禁止的内容模式
  final List<RegExp> forbiddenPatterns;

  /// 是否检测可能的幻觉
  final bool detectHallucinations;

  /// 是否允许 Markdown 格式
  final bool allowMarkdown;

  /// 是否自动修复常见问题
  final bool autoFix;

  const AiValidationConfig({
    this.maxResponseLength = 100000,
    this.minResponseLength = 1,
    this.requireValidJson = false,
    this.requiredJsonFields = const [],
    this.forbiddenPatterns = const [],
    this.detectHallucinations = true,
    this.allowMarkdown = true,
    this.autoFix = true,
  });

  /// 聊天响应配置
  static const AiValidationConfig chatResponse = AiValidationConfig(
    maxResponseLength: 50000,
    minResponseLength: 1,
    requireValidJson: false,
    allowMarkdown: true,
    detectHallucinations: true,
  );

  /// JSON 响应配置
  static AiValidationConfig jsonResponse({
    List<String> requiredFields = const [],
  }) {
    return AiValidationConfig(
      maxResponseLength: 100000,
      minResponseLength: 2, // "{}"
      requireValidJson: true,
      requiredJsonFields: requiredFields,
      allowMarkdown: false,
    );
  }

  /// 产品推荐配置
  static const AiValidationConfig productRecommendation = AiValidationConfig(
    maxResponseLength: 50000,
    minResponseLength: 10,
    requireValidJson: true,
    requiredJsonFields: ['recommendations'],
    detectHallucinations: true,
  );
}

/// AI 响应验证器
///
/// 验证和清洗 AI 生成的内容，防止幻觉和畸形输出
class AiResponseValidator {
  final AiValidationConfig config;
  final ModuleLogger _logger;

  AiResponseValidator({
    AiValidationConfig? config,
  })  : config = config ?? const AiValidationConfig(),
        _logger = AppLogger.instance.module('AiValidator');

  /// 验证 AI 响应
  AiValidationResult validate(String response) {
    final errors = <String>[];
    final warnings = <String>[];
    var sanitized = response;

    // 1. 基本检查
    if (response.isEmpty) {
      return AiValidationResult.invalid(['响应为空']);
    }

    // 2. 长度检查
    if (response.length > config.maxResponseLength) {
      errors.add('响应超过最大长度限制 (${response.length}/${config.maxResponseLength})');
      if (config.autoFix) {
        sanitized = response.substring(0, config.maxResponseLength);
        warnings.add('响应已被截断');
      }
    }

    if (response.length < config.minResponseLength) {
      errors.add('响应长度不足 (${response.length}/${config.minResponseLength})');
    }

    // 3. 清洗内容
    if (config.autoFix) {
      sanitized = _sanitizeResponse(sanitized);
    }

    // 4. JSON 验证（如果需要）
    Map<String, dynamic>? parsedJson;
    if (config.requireValidJson) {
      final jsonResult = _validateJson(sanitized);
      if (jsonResult.isFailure) {
        // 尝试从 Markdown 代码块中提取 JSON
        final extracted = _extractJsonFromMarkdown(sanitized);
        if (extracted != null) {
          final retryResult = _validateJson(extracted);
          if (retryResult.isSuccess) {
            sanitized = extracted;
            parsedJson = retryResult.valueOrNull;
            warnings.add('从 Markdown 代码块中提取了 JSON');
          } else {
            errors.add('JSON 解析失败: ${jsonResult.failureOrNull?.message}');
          }
        } else {
          errors.add('JSON 解析失败: ${jsonResult.failureOrNull?.message}');
        }
      } else {
        parsedJson = jsonResult.valueOrNull;
      }

      // 检查必需字段
      if (parsedJson != null && config.requiredJsonFields.isNotEmpty) {
        for (final field in config.requiredJsonFields) {
          if (!parsedJson.containsKey(field)) {
            errors.add('缺少必需字段: $field');
          }
        }
      }
    }

    // 5. 禁止模式检查
    for (final pattern in config.forbiddenPatterns) {
      if (pattern.hasMatch(sanitized)) {
        final match = pattern.firstMatch(sanitized);
        warnings.add('检测到禁止的内容模式: ${match?.group(0)}');
        if (config.autoFix) {
          sanitized = sanitized.replaceAll(pattern, '[内容已移除]');
        }
      }
    }

    // 6. 幻觉检测
    if (config.detectHallucinations) {
      final hallucinationWarnings = _detectHallucinations(sanitized);
      warnings.addAll(hallucinationWarnings);
    }

    // 返回结果
    if (errors.isNotEmpty) {
      return AiValidationResult.invalid(errors, warnings: warnings);
    }

    if (warnings.isNotEmpty) {
      _logger.warning('AI 响应验证警告', context: {'warnings': warnings});
      return AiValidationResult.validWithWarnings(sanitized, warnings, json: parsedJson);
    }

    return AiValidationResult.valid(sanitized, json: parsedJson);
  }

  /// 验证并返回 Result 类型
  Result<String> validateAsResult(String response) {
    final result = validate(response);
    if (result.isValid) {
      return Result.success(result.sanitizedContent ?? response);
    }
    return Result.failure(Failure.validation(
      message: result.errors.join('; '),
      context: {'warnings': result.warnings},
    ));
  }

  /// 验证 JSON 响应并解析
  Result<Map<String, dynamic>> validateJson(String response) {
    final result = validate(response);
    if (!result.isValid) {
      return Result.failure(Failure.validation(
        message: result.errors.join('; '),
        context: {'warnings': result.warnings},
      ));
    }

    if (result.parsedJson != null) {
      return Result.success(result.parsedJson!);
    }

    return _validateJson(result.sanitizedContent ?? response);
  }

  /// 清洗响应内容
  String _sanitizeResponse(String response) {
    var sanitized = response;

    // 移除控制字符（保留换行和制表符）
    sanitized = sanitized.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');

    // 修复常见的 Unicode 问题
    sanitized = _fixUnicodeIssues(sanitized);

    // 规范化换行符
    sanitized = sanitized.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // 移除过多的连续换行
    sanitized = sanitized.replaceAll(RegExp(r'\n{4,}'), '\n\n\n');

    // 移除首尾空白
    sanitized = sanitized.trim();

    return sanitized;
  }

  /// 修复 Unicode 问题
  String _fixUnicodeIssues(String text) {
    // 替换无效的 UTF-8 序列
    try {
      final bytes = utf8.encode(text);
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      // UTF-8 encoding/decoding failed, return original text
      return text;
    }
  }

  /// 验证 JSON
  Result<Map<String, dynamic>> _validateJson(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return Result.success(decoded);
      }
      return Result.failure(Failure.validation(
        message: '预期 JSON 对象，但得到 ${decoded.runtimeType}',
      ));
    } on FormatException catch (e) {
      return Result.failure(Failure.validation(
        message: 'JSON 格式错误: ${e.message}',
      ));
    }
  }

  /// 从 Markdown 代码块中提取 JSON
  String? _extractJsonFromMarkdown(String text) {
    // 匹配 ```json ... ``` 或 ``` ... ```
    final patterns = [
      RegExp(r'```json\s*([\s\S]*?)\s*```', multiLine: true),
      RegExp(r'```\s*([\s\S]*?)\s*```', multiLine: true),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final extracted = match.group(1)?.trim();
        if (extracted != null && extracted.startsWith('{')) {
          return extracted;
        }
      }
    }

    // 尝试查找裸 JSON 对象
    final jsonPattern = RegExp(r'\{[\s\S]*\}');
    final match = jsonPattern.firstMatch(text);
    return match?.group(0);
  }

  /// 检测可能的幻觉
  List<String> _detectHallucinations(String text) {
    final warnings = <String>[];

    // 检测不存在的 URL 模式
    final suspiciousUrls = _detectSuspiciousUrls(text);
    if (suspiciousUrls.isNotEmpty) {
      warnings.add('检测到可能的虚假 URL: ${suspiciousUrls.join(', ')}');
    }

    // 检测可能的虚假数据
    if (_containsSuspiciousNumbers(text)) {
      warnings.add('检测到可能的虚假数据（极端数值）');
    }

    // 检测矛盾陈述
    if (_containsContradictions(text)) {
      warnings.add('检测到可能的矛盾陈述');
    }

    // 检测过于自信的陈述
    if (_containsOverconfidence(text)) {
      warnings.add('检测到可能过于自信的陈述');
    }

    return warnings;
  }

  /// 检测可疑的 URL
  ///
  /// 识别 AI 可能虚构的 URL，例如使用 example.com、明显占位 ID、
  /// localhost 等。检测结果作为警告返回，不阻断验证流程。
  List<String> _detectSuspiciousUrls(String text) {
    final suspicious = <String>[];
    final urlPattern = RegExp(
      r'https?://[^\s<>"{}|\\^`\[\]]+',
      caseSensitive: false,
    );

    for (final match in urlPattern.allMatches(text)) {
      final url = match.group(0)!;

      String? reason;

      // 检查是否为明显虚构的域名
      if (url.contains('example.com') && !text.contains('示例')) {
        reason = 'example.com domain';
      }

      // 检查是否包含明显的占位 ID 路径（只检测明确的占位模式）
      if (reason == null &&
          (RegExp(r'/product/[09]{4,}').hasMatch(url) ||
           RegExp(r'/item/[012345]{4,}').hasMatch(url) ||
           url.contains('/fake/'))) {
        reason = 'placeholder ID pattern';
      }

      // 检查是否为 localhost 或内部地址（在 AI 生成内容中不应出现）
      if (reason == null &&
          (url.contains('localhost') ||
           url.contains('127.0.0.1') ||
           url.contains('192.168.'))) {
        reason = 'internal/localhost address';
      }

      if (reason != null) {
        suspicious.add(url);
        dev.log('Suspicious URL in AI response [$reason]: $url', name: 'AiValidator');
      }
    }

    return suspicious.toSet().toList(); // 去重
  }

  /// 检测可疑的数字
  bool _containsSuspiciousNumbers(String text) {
    // 检测极端价格
    final pricePattern = RegExp(r'[¥￥\$]?\s*(\d{1,3}(?:,\d{3})*(?:\.\d{2})?|\d+(?:\.\d{2})?)');
    for (final match in pricePattern.allMatches(text)) {
      final priceStr = match.group(1)?.replaceAll(',', '') ?? '0';
      final price = double.tryParse(priceStr) ?? 0;
      if (price > 10000000) {
        // 价格超过1000万
        return true;
      }
    }

    // 检测不合理的百分比
    final percentPattern = RegExp(r'(\d+(?:\.\d+)?)\s*[%％]');
    for (final match in percentPattern.allMatches(text)) {
      final percent = double.tryParse(match.group(1) ?? '0') ?? 0;
      if (percent > 100 && !text.contains('增长') && !text.contains('提升')) {
        return true;
      }
    }

    return false;
  }

  /// 检测矛盾陈述
  bool _containsContradictions(String text) {
    // 简单的矛盾检测
    final contradictions = [
      (RegExp(r'最便宜'), RegExp(r'最贵')),
      (RegExp(r'最好'), RegExp(r'最差')),
      (RegExp(r'推荐购买'), RegExp(r'不推荐')),
      (RegExp(r'免费'), RegExp(r'收费')),
    ];

    for (final (pattern1, pattern2) in contradictions) {
      if (pattern1.hasMatch(text) && pattern2.hasMatch(text)) {
        // 检查是否在同一段落中（可能是比较，不是矛盾）
        final lines = text.split('\n');
        for (final line in lines) {
          if (pattern1.hasMatch(line) && pattern2.hasMatch(line)) {
            return true;
          }
        }
      }
    }

    return false;
  }

  /// 检测过于自信的陈述
  bool _containsOverconfidence(String text) {
    final overconfidencePatterns = [
      RegExp(r'100%\s*(?:保证|确定|肯定|成功)'),
      RegExp(r'绝对(?:不会|没有|正确)'),
      RegExp(r'永远(?:不会|不可能)'),
      RegExp(r'肯定(?:是|会|能)'),
    ];

    for (final pattern in overconfidencePatterns) {
      if (pattern.hasMatch(text)) {
        return true;
      }
    }

    return false;
  }
}

/// 便捷函数：验证 AI 文本响应
AiValidationResult validateAiResponse(
  String response, {
  AiValidationConfig? config,
}) {
  return AiResponseValidator(config: config).validate(response);
}

/// 便捷函数：验证 AI JSON 响应
Result<Map<String, dynamic>> validateAiJsonResponse(
  String response, {
  List<String> requiredFields = const [],
}) {
  final config = AiValidationConfig.jsonResponse(requiredFields: requiredFields);
  return AiResponseValidator(config: config).validateJson(response);
}

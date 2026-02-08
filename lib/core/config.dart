// 全局配置和常量
// 注意：实际发布前不要把真实 API Key 写在源码中，使用安全存储或 CI 注入
//
// 所有配置项均优先从环境变量读取，回退到编译期常量（--dart-define），
// 最后回退到占位符。占位符值以 YOUR_ 或 your_ 开头，可通过
// Config.validate() 在应用启动时检测未配置的项并发出警告。

import 'dart:developer' as dev;
import 'dart:io';

/// 占位符前缀 — 任何以此开头的值都被视为未配置
const _placeholderPrefixes = ['YOUR_', 'your_'];

class Config {
  Config._();

  // ========== 电商联盟配置 ==========

  /// 模拟电商来源 id 或关联参数
  static String get affiliateId =>
      Platform.environment['AFFILIATE_ID'] ??
      const String.fromEnvironment('AFFILIATE_ID', defaultValue: 'your_aff_id');

  // -- 淘宝联盟 --
  static String get taobaoAppKey =>
      Platform.environment['TAOBAO_APP_KEY'] ??
      const String.fromEnvironment('TAOBAO_APP_KEY', defaultValue: 'YOUR_TAOBAO_APP_KEY');
  static String get taobaoAppSecret =>
      Platform.environment['TAOBAO_APP_SECRET'] ??
      const String.fromEnvironment('TAOBAO_APP_SECRET', defaultValue: 'YOUR_TAOBAO_APP_SECRET');
  static String get taobaoAdzoneId =>
      Platform.environment['TAOBAO_ADZONE_ID'] ??
      const String.fromEnvironment('TAOBAO_ADZONE_ID', defaultValue: 'YOUR_TAOBAO_ADZONE_ID');

  // -- 京东联盟 --
  static String get jdAppKey =>
      Platform.environment['JD_APP_KEY'] ??
      const String.fromEnvironment('JD_APP_KEY', defaultValue: 'YOUR_JD_APP_KEY');
  static String get jdAppSecret =>
      Platform.environment['JD_APP_SECRET'] ??
      const String.fromEnvironment('JD_APP_SECRET', defaultValue: 'YOUR_JD_APP_SECRET');
  static String get jdUnionId =>
      Platform.environment['JD_UNION_ID'] ??
      const String.fromEnvironment('JD_UNION_ID', defaultValue: 'YOUR_JD_UNION_ID');

  // -- 拼多多 --
  static String get pddClientId =>
      Platform.environment['PDD_CLIENT_ID'] ??
      const String.fromEnvironment('PDD_CLIENT_ID', defaultValue: 'YOUR_PDD_CLIENT_ID');
  static String get pddClientSecret =>
      Platform.environment['PDD_CLIENT_SECRET'] ??
      const String.fromEnvironment('PDD_CLIENT_SECRET', defaultValue: 'YOUR_PDD_CLIENT_SECRET');
  static String get pddPid =>
      Platform.environment['PDD_PID'] ??
      const String.fromEnvironment('PDD_PID', defaultValue: 'YOUR_PDD_PID');

  // ========== AI 配置 ==========

  /// OpenAI API Key（可选，仅在客户端直连 OpenAI 时使用）
  static String get openAiApiKey =>
      Platform.environment['OPENAI_API_KEY'] ??
      const String.fromEnvironment('OPENAI_API_KEY', defaultValue: 'YOUR_OPENAI_API_KEY');

  // ========== 占位符检测 ==========

  /// 判断某个配置值是否仍为未配置的占位符
  static bool isPlaceholder(String value) {
    if (value.isEmpty) return true;
    return _placeholderPrefixes.any((p) => value.startsWith(p));
  }

  /// 检查某个平台的配置是否已就绪（非占位符）
  static bool isTaobaoConfigured() =>
      !isPlaceholder(taobaoAppKey) &&
      !isPlaceholder(taobaoAppSecret) &&
      !isPlaceholder(taobaoAdzoneId);

  static bool isJdConfigured() =>
      !isPlaceholder(jdAppKey) &&
      !isPlaceholder(jdAppSecret) &&
      !isPlaceholder(jdUnionId);

  static bool isPddConfigured() =>
      !isPlaceholder(pddClientId) &&
      !isPlaceholder(pddClientSecret) &&
      !isPlaceholder(pddPid);

  static bool isOpenAiConfigured() => !isPlaceholder(openAiApiKey);

  /// 在应用启动时调用，检查所有配置项并输出警告日志。
  /// 返回未配置的键列表（空列表表示全部就绪）。
  static List<String> validate() {
    final missing = <String>[];

    final checks = <String, String>{
      'TAOBAO_APP_KEY': taobaoAppKey,
      'TAOBAO_APP_SECRET': taobaoAppSecret,
      'TAOBAO_ADZONE_ID': taobaoAdzoneId,
      'JD_APP_KEY': jdAppKey,
      'JD_APP_SECRET': jdAppSecret,
      'JD_UNION_ID': jdUnionId,
      'PDD_CLIENT_ID': pddClientId,
      'PDD_CLIENT_SECRET': pddClientSecret,
      'PDD_PID': pddPid,
      'OPENAI_API_KEY': openAiApiKey,
    };

    for (final entry in checks.entries) {
      if (isPlaceholder(entry.value)) {
        missing.add(entry.key);
      }
    }

    if (missing.isNotEmpty) {
      dev.log('⚠️  以下配置项仍为占位符，相关功能将不可用: ${missing.join(", ")}', name: 'Config');
      dev.log('   请通过环境变量或 --dart-define 注入真实值。', name: 'Config');
    }

    return missing;
  }
}

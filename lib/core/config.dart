// 全局配置和常量
// 注意：实际发布前不要把真实 API Key 写在源码中，使用安全存储或 CI 注入

import 'dart:io';

class Config {

  // 模拟电商来源 id 或关联参数
  static String get affiliateId => Platform.environment['AFFILIATE_ID'] ?? 'your_aff_id';

  // 淘宝联盟配置占位（请通过 CI 或安全存储注入真实值）
  static String get taobaoAppKey => Platform.environment['TAOBAO_APP_KEY'] ?? 'YOUR_TAOBAO_APP_KEY';
  static String get taobaoAppSecret => Platform.environment['TAOBAO_APP_SECRET'] ?? 'YOUR_TAOBAO_APP_SECRET';
  static String get taobaoAdzoneId => Platform.environment['TAOBAO_ADZONE_ID'] ?? 'YOUR_TAOBAO_ADZONE_ID';

  // 京东联盟配置（优先读取环境变量 JD_APP_KEY / JD_APP_SECRET / JD_UNION_ID）
  static String get jdAppKey => Platform.environment['JD_APP_KEY'] ?? 'YOUR_JD_APP_KEY';
  static String get jdAppSecret => Platform.environment['JD_APP_SECRET'] ?? 'YOUR_JD_APP_SECRET';
  static String get jdUnionId => Platform.environment['JD_UNION_ID'] ?? 'YOUR_JD_UNION_ID';
  // 拼多多（PDD）配置占位
  static String get pddClientId => Platform.environment['PDD_CLIENT_ID'] ?? 'YOUR_PDD_CLIENT_ID';
  static String get pddClientSecret => Platform.environment['PDD_CLIENT_SECRET'] ?? 'YOUR_PDD_CLIENT_SECRET';
  static String get pddPid => Platform.environment['PDD_PID'] ?? 'YOUR_PDD_PID';
  
  // OpenAI API Key (optional, used when calling OpenAI directly)
  static String get openAiApiKey => Platform.environment['OPENAI_API_KEY'] ?? 'YOUR_OPENAI_API_KEY';
}

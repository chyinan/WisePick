import 'package:hive_flutter/hive_flutter.dart';

import '../../features/products/product_model.dart';

/// Hive 本地存储配置
/// 
/// 集中管理所有 Box 名称和 TypeAdapter 注册
class HiveConfig {
  HiveConfig._();

  // Box 名称常量
  static const String settingsBox = 'settings';
  static const String cartBox = 'cart_box';
  static const String conversationsBox = 'conversations';
  static const String promoCacheBox = 'promo_cache';
  static const String taobaoItemCacheBox = 'taobao_item_cache';
  static const String favoritesBox = 'favorites';

  // 设置项 Key 常量
  static const String themeKey = 'theme_mode';
  static const String openaiApiKeyKey = 'openai_api_key';
  static const String openaiBaseUrlKey = 'openai_base_url';
  static const String proxyUrlKey = 'proxy_url';
  static const String selectedModelKey = 'selected_model';
  static const String maxTokensKey = 'max_tokens';
  static const String embedPromptKey = 'embed_prompt';
  static const String showRawResponseKey = 'show_raw_response';
  static const String mockAiModeKey = 'use_mock_ai';
  static const String jdSubUnionIdKey = 'jd_sub_union_id';
  static const String jdPidKey = 'jd_pid';
  static const String priceNotificationEnabledKey = 'price_notification_enabled';

  /// 初始化 Hive
  /// 
  /// 应在 main.dart 中调用
  static Future<void> init() async {
    await Hive.initFlutter();
    _registerAdapters();
    await _openBoxes();
  }

  /// 注册所有 TypeAdapter
  static void _registerAdapters() {
    // 注册 ProductModel Adapter
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ProductModelAdapter());
    }
    
    // 注册其他 Adapter（如需要）
    // 当前 ChatMessage 和 ConversationModel 使用 Map 序列化存储
  }

  /// 预打开常用 Box
  static Future<void> _openBoxes() async {
    await Future.wait([
      Hive.openBox(settingsBox),
      Hive.openBox(cartBox),
      Hive.openBox(conversationsBox),
      Hive.openBox(promoCacheBox),
    ]);
  }

  /// 获取设置 Box
  static Box get settings => Hive.box(settingsBox);

  /// 获取选品车 Box
  static Box get cart => Hive.box(cartBox);

  /// 获取会话 Box
  static Box get conversations => Hive.box(conversationsBox);

  /// 获取推广链接缓存 Box
  static Box get promoCache => Hive.box(promoCacheBox);

  /// 安全获取 Box（如果未打开则打开）
  static Future<Box> getBox(String name) async {
    if (Hive.isBoxOpen(name)) {
      return Hive.box(name);
    }
    return Hive.openBox(name);
  }

  /// 清除所有数据（用于调试或重置）
  static Future<void> clearAll() async {
    await Hive.box(settingsBox).clear();
    await Hive.box(cartBox).clear();
    await Hive.box(conversationsBox).clear();
    await Hive.box(promoCacheBox).clear();
  }
}




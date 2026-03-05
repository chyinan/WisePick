import 'package:hive_flutter/hive_flutter.dart';

import '../../features/products/product_model.dart';

/// Hive 本地存储配置
///
/// 集中管理所有 Box 名称、TypeAdapter 注册和 Box 生命周期。
/// 所有业务代码应通过 [getBox] / [getTypedBox] 访问 Box，
/// 而非直接调用 [Hive.openBox] 或 [Hive.box]，以避免重复的
/// "isBoxOpen → openBox → box" 样板代码和字符串拼写错误。
class HiveConfig {
  HiveConfig._();

  // ──────────────── Box 名称常量 ────────────────
  static const String settingsBox = 'settings';
  static const String cartBox = 'cart_box';
  static const String conversationsBox = 'conversations';
  static const String promoCacheBox = 'promo_cache';
  static const String taobaoItemCacheBox = 'taobao_item_cache';
  static const String pddItemCacheBox = 'pdd_item_cache';
  static const String favoritesBox = 'favorites';
  static const String authBox = 'auth';
  static const String syncMetaBox = 'sync_meta';
  static const String jdPriceCacheBox = 'jdPriceCache';
  static const String cartOpsLogBox = 'cart_ops_log';

  // ──────────────── 设置项 Key 常量 ────────────────
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
  static const String adminPasswordHashKey = 'admin_password_hash';
  static const String pddUidKey = 'pdd_uid';

  /// 默认管理员密码哈希（对应密码 "admin123"），仅首次启动时写入
  static const String _defaultAdminPasswordHash =
      'b054968e7426730e9a005f1430e6d5cd70a03b08370a82323f9a9b231cf270be';

  /// 初始化 Hive
  ///
  /// 应在 main.dart 中调用
  static Future<void> init() async {
    await Hive.initFlutter();
    _registerAdapters();
    await _openBoxes();
    await _initAdminPassword();
  }

  /// 首次启动时写入默认管理员密码哈希（若已存在则不覆盖）
  static Future<void> _initAdminPassword() async {
    final box = Hive.box(settingsBox);
    if (box.get(adminPasswordHashKey) == null) {
      await box.put(adminPasswordHashKey, _defaultAdminPasswordHash);
    }
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

  /// 预打开常用 Box（应用启动时批量打开，后续调用直接返回缓存实例）
  static Future<void> _openBoxes() async {
    await Future.wait([
      Hive.openBox(settingsBox),
      Hive.openBox(cartBox),
      Hive.openBox(conversationsBox),
      Hive.openBox(promoCacheBox),
      Hive.openBox(favoritesBox),
      Hive.openBox(taobaoItemCacheBox),
    ]);
  }

  // ──────────────── 同步便捷 getter（仅用于已预打开的 Box）────────────────

  /// 获取设置 Box
  static Box get settings => Hive.box(settingsBox);

  /// 获取购物车 Box
  static Box get cart => Hive.box(cartBox);

  /// 获取会话 Box
  static Box get conversations => Hive.box(conversationsBox);

  /// 获取推广链接缓存 Box
  static Box get promoCache => Hive.box(promoCacheBox);

  /// 获取收藏 Box
  static Box get favorites => Hive.box(favoritesBox);

  /// 获取淘宝商品缓存 Box
  static Box get taobaoItemCache => Hive.box(taobaoItemCacheBox);

  // ──────────────── 安全异步访问 ────────────────

  /// 安全获取 Box（如果未打开则打开）。
  ///
  /// **所有业务代码应统一使用此方法**，而非直接调用
  /// `Hive.openBox` / `Hive.box`，以消除重复的 isBoxOpen 检查。
  static Future<Box> getBox(String name) async {
    if (Hive.isBoxOpen(name)) {
      return Hive.box(name);
    }
    return Hive.openBox(name);
  }

  /// 安全获取带类型参数的 Box（如 `Box<double>`）。
  ///
  /// 用于如 JD 价格缓存等需要类型化 Box 的场景。
  static Future<Box<T>> getTypedBox<T>(String name) async {
    if (Hive.isBoxOpen(name)) {
      return Hive.box<T>(name);
    }
    return Hive.openBox<T>(name);
  }

  /// 清除所有数据（用于调试或重置）
  ///
  /// Uses [getBox] instead of [Hive.box] so this method is safe to call
  /// even if some boxes have not been opened yet (e.g. partial init failure).
  static Future<void> clearAll() async {
    await Future.wait([
      getBox(settingsBox).then((b) => b.clear()),
      getBox(cartBox).then((b) => b.clear()),
      getBox(conversationsBox).then((b) => b.clear()),
      getBox(promoCacheBox).then((b) => b.clear()),
      getBox(favoritesBox).then((b) => b.clear()),
      getBox(taobaoItemCacheBox).then((b) => b.clear()),
    ]);
  }
}




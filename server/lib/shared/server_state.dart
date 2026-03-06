import 'dart:io';

// ─── 调试历史缓冲 ────────────────────────────────────────────────────────────
// 最多保留 100 条，防止内存无限增长
const int kMaxDebugHistory = 100;
Map<String, dynamic>? lastReturnDebug;
final List<Map<String, dynamic>> lastReturnHistory = <Map<String, dynamic>>[];

void appendDebugHistory(Map<String, dynamic> entry) {
  lastReturnHistory.add(entry);
  if (lastReturnHistory.length > kMaxDebugHistory) {
    lastReturnHistory.removeAt(0);
  }
}

// ─── 价格缓存 ────────────────────────────────────────────────────────────────
// 最多缓存 500 个 SKU，超出时淘汰最旧条目
const int kMaxPriceCacheSize = 500;
final Map<String, Map<String, dynamic>> priceCache =
    <String, Map<String, dynamic>>{};

void setPriceCache(String key, Map<String, dynamic> value) {
  if (priceCache.length >= kMaxPriceCacheSize && !priceCache.containsKey(key)) {
    priceCache.remove(priceCache.keys.first);
  }
  priceCache[key] = value;
}

// ─── 安全工具 ────────────────────────────────────────────────────────────────

/// 常量时间字符串比较，防止时序攻击
/// 始终遍历完整长度，不因长度不等而提前返回
bool constantTimeEquals(String a, String b) {
  final maxLen = a.length > b.length ? a.length : b.length;
  var result = a.length ^ b.length; // 长度不等时 result != 0
  for (var i = 0; i < maxLen; i++) {
    final ca = i < a.length ? a.codeUnitAt(i) : 0;
    final cb = i < b.length ? b.codeUnitAt(i) : 0;
    result |= ca ^ cb;
  }
  return result == 0;
}

/// 校验调试端点访问权限
/// 通过环境变量 DEBUG_TOKEN 配置，未配置时仅允许本地回环地址访问
bool isDebugAuthorized(Map<String, String> headers) {
  final env = Platform.environment;
  final debugToken = env['DEBUG_TOKEN'] ?? '';

  if (debugToken.isNotEmpty) {
    final auth = headers['authorization'] ?? headers['Authorization'] ?? '';
    final provided = auth.startsWith('Bearer ') ? auth.substring(7) : '';
    return constantTimeEquals(provided.trim(), debugToken.trim());
  }

  final host = headers['host'] ?? '';
  return host.startsWith('localhost') ||
      host.startsWith('127.0.0.1') ||
      host.startsWith('::1');
}

import 'package:hive/hive.dart';
import '../products/product_model.dart';

/// 购物车服务：基于 Hive 存储购物车条目（包含数量）
class CartService {
  static const String boxName = 'cart_box';

  /// 获取所有购物车商品（包含数量）
  /// 存储格式：key = product.id, value = {product fields..., 'qty': int}
  Future<List<Map<String, dynamic>>> getAllItems() async {
    final box = await Hive.openBox(boxName);
    return box.values.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// 将商品加入购物车或更新数量。现在会在条目中保存完整的商品 JSON
  /// 存储内容包括 ProductModel.toMap() 的字段、'qty' 以及可选的 'raw_json'（当 ProductModel 包含额外未映射字段时可保存原始 JSON）
  Future<void> addOrUpdateItem(ProductModel p, {int qty = 1, String? rawJson}) async {
    final box = await Hive.openBox(boxName);
    final existing = box.get(p.id);
    if (existing != null) {
      final m = Map<String, dynamic>.from(existing);
      final int cur = (m['qty'] as int?) ?? 1;
      m['qty'] = cur + qty;
      // 若调用方提供了原始 JSON，则更新存储的 raw_json 字段以便详情页可用
      if (rawJson != null && rawJson.isNotEmpty) m['raw_json'] = rawJson;
      await box.put(p.id, m);
    } else {
      final m = p.toMap();
      m['qty'] = qty;
      if (rawJson != null && rawJson.isNotEmpty) m['raw_json'] = rawJson;
      await box.put(p.id, m);
    }
  }

  Future<void> setQuantity(String productId, int qty) async {
    final box = await Hive.openBox(boxName);
    final existing = box.get(productId);
    if (existing != null) {
      final m = Map<String, dynamic>.from(existing);
      m['qty'] = qty;
      await box.put(productId, m);
    }
  }

  Future<void> removeItem(String productId) async {
    final box = await Hive.openBox(boxName);
    await box.delete(productId);
    // 同步删除 favorites 中的收藏（若购物车删除时希望取消收藏）
    try {
      final favBox = await Hive.openBox('favorites');
      if (favBox.containsKey(productId)) {
        await favBox.delete(productId);
      }
    } catch (_) {}
  }

  Future<void> clear() async {
    final box = await Hive.openBox(boxName);
    await box.clear();
  }
}


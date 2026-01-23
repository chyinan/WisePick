import 'package:hive/hive.dart';

part 'product_model.g.dart';

/// 统一商品模型定义，兼容多个平台（taobao/jd/pdd）
@HiveType(typeId: 0)
class ProductModel {
  @HiveField(0)
  final String id; // 本地/平台商品ID：若后端返回则使用平台唯一ID（如淘宝 num_iid），否则前端会生成临时ID用于列表 key 和本地引用
  @HiveField(1)
  final String platform; // taobao | jd | pdd
  @HiveField(2)
  final String title;
  @HiveField(3)
  final double price;
  @HiveField(4)
  final double originalPrice;
  @HiveField(5)
  final double coupon;
  @HiveField(6)
  final double finalPrice;
  @HiveField(7)
  final String imageUrl;
  @HiveField(8)
  final int sales;
  @HiveField(9)
  final double rating; // 0.0 - 1.0
  @HiveField(13)
  final String shopTitle; // 商店/店铺名（来自淘宝的 shop_title 或 item_basic_info.shop_title）
  @HiveField(10)
  final String link; // 推广链接或口令
  @HiveField(11)
  final double commission;
  @HiveField(12)
  final String description;
  /// 构造函数兼容新/旧字段：你可以传入新模型字段或者旧的 `description/sourceUrl/reviewCount`，都会尽量映射
  ProductModel({
    required this.id,
    String? platform,
    required this.title,
    double? price,
    double? originalPrice,
    double? coupon,
    double? finalPrice,
    String? imageUrl,
    int? sales,
    double? rating,
    String? link,
    double? commission,
    String? shopTitle,
    // legacy fields (向后兼容)
    String? description,
    String? sourceUrl,
    int? reviewCount,
  })  : platform = platform ?? 'unknown',
        price = price ?? (finalPrice ?? 0.0),
        originalPrice = originalPrice ?? (price ?? (finalPrice ?? 0.0)),
        coupon = coupon ?? 0.0,
        finalPrice = finalPrice ?? ((price ?? 0.0) - (coupon ?? 0.0)),
        imageUrl = imageUrl ?? '',
        sales = sales ?? (reviewCount ?? 0),
        rating = rating ?? 0.0,
        link = link ?? (sourceUrl ?? ''),
        commission = commission ?? 0.0,
        shopTitle = shopTitle ?? '',
        description = description ?? '';

  /// 从 Map 解析（便于 Hive / JSON）
  factory ProductModel.fromMap(Map<String, dynamic> m) {
    // try top-level keys first
    // prefer short_title over sub_title, but fall back to explicit 'description' or 'desc' if present
    String? desc = (m['short_title'] as String?) ?? (m['sub_title'] as String?);
    if (desc == null || desc.isEmpty) {
      desc = (m['description'] as String?) ?? (m['desc'] as String?);
    }
    // fallback to nested item_basic_info if present
    try {
        if ((desc == null || desc.isEmpty) && m['item_basic_info'] is Map) {
        final basic = m['item_basic_info'] as Map<String, dynamic>;
        desc = (basic['short_title'] as String?) ?? (basic['sub_title'] as String?);
      }
    } catch (_) {}

    // extract shop title from top-level or nested item_basic_info
    String? shopTitle = (m['shop_title'] as String?) ?? (m['shopTitle'] as String?);
    try {
      if ((shopTitle == null || shopTitle.isEmpty) && m['item_basic_info'] is Map) {
        final basic = m['item_basic_info'] as Map<String, dynamic>;
        shopTitle = (basic['shop_title'] as String?) ?? (basic['shopTitle'] as String?);
      }
    } catch (_) {}

    // Helper for robust number parsing
    double? parseDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(RegExp(r'[^0-9\.-]'), ''));
      return null;
    }

    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.replaceAll(RegExp(r'[^0-9\.-]'), ''));
      return null;
    }

    String normalizeUrl(String? url) {
      if (url == null || url.isEmpty) return '';
      if (url.startsWith('//')) return 'https:$url';
      if (!url.startsWith('http')) return 'https://$url';
      return url;
    }

    return ProductModel(
      id: (m['id'] ?? '').toString(),
      platform: m['platform'] as String?,
      title: (m['title'] ?? '').toString(),
      price: parseDouble(m['price']),
      originalPrice: parseDouble(m['original_price']),
      coupon: parseDouble(m['coupon']),
      finalPrice: parseDouble(m['final_price']),
      imageUrl: normalizeUrl(m['image_url'] as String?),
      sales: parseInt(m['sales']),
      rating: parseDouble(m['rating']),
      shopTitle: shopTitle ?? '',
      link: m['link'] as String?,
      commission: parseDouble(m['commission']),
      description: desc ?? '',
      sourceUrl: m['sourceUrl'] as String? ?? m['source_url'] as String?,
      reviewCount: parseInt(m['reviewCount']) ?? parseInt(m['review_count']),
    );
  }

  /// 从 veapi/tb_search 返回的单项结果解析到统一 ProductModel
  factory ProductModel.fromVeApi(Map<String, dynamic> m) {
    // helper to safely parse numbers
    num? _num(Map map, List<String> keys) {
      for (final k in keys) {
        if (map.containsKey(k) && map[k] != null) {
          final v = map[k];
          if (v is num) return v;
          if (v is String) {
            final parsed = num.tryParse(v.replaceAll(RegExp('[^0-9\.]'), ''));
            if (parsed != null) return parsed;
          }
        }
      }
      return null;
    }

    String? _str(Map map, List<String> keys) {
      for (final k in keys) {
        if (map.containsKey(k) && map[k] != null) return map[k].toString();
      }
      return null;
    }

    String normalizeUrl(String? url) {
      if (url == null || url.isEmpty) return '';
      if (url.startsWith('//')) return 'https:$url';
      if (!url.startsWith('http')) return 'https://$url';
      return url;
    }

    final id = _str(m, ['num_iid', 'id', 'item_id', 'goods_id']) ?? _str(m, ['id']) ?? '';
    final title = (_str(m, ['title', 'item_title', 'name']) ?? '').trim();
    final imageUrl = normalizeUrl(_str(m, ['pic_url', 'pict_url', 'small_images', 'image_url']));
    final price = (_num(m, ['zk_final_price', 'price', 'reserve_price', 'final_price']) ?? 0).toDouble();
    final originalPrice = (_num(m, ['reserve_price', 'original_price', 'price']) ?? price).toDouble();
    final coupon = (_num(m, ['coupon_amount', 'coupon', 'CouponAmount']) ?? 0).toDouble();
    final finalPrice = (_num(m, ['after_coupon_price', 'final_price']) ?? (price - coupon)).toDouble();
    final sales = (_num(m, ['volume', 'sell_num', 'sales', 'trade_count']) ?? 0).toInt();
    final commission = (_num(m, ['commission', 'commission_rate', 'max_commission']) ?? 0).toDouble();
    final link = _str(m, ['click_url', 'clickURL', 'url', 'coupon_click_url', 'tklink', 'clickUrl']) ?? '';
    // prefer explicit short/sub title as description when available
    // prefer short_title over sub_title when available
    final descCandidate = _str(m, ['short_title', 'sub_title', 'subtitle', 'desc', 'description']);

    // extract shop title from veapi response: prefer top-level keys, then nested item_basic_info
    String? shopTitle = _str(m, ['shop_title', 'shopTitle', 'seller_shop_title']);
    try {
      if ((shopTitle == null || shopTitle.isEmpty) && m['item_basic_info'] is Map) {
        shopTitle = _str(m['item_basic_info'] as Map, ['shop_title', 'shopTitle', 'seller_shop_title']);
      }
    } catch (_) {}

    return ProductModel(
      id: id,
      platform: 'taobao',
      title: title,
      price: price,
      originalPrice: originalPrice,
      coupon: coupon,
      finalPrice: finalPrice,
      imageUrl: imageUrl,
      sales: sales,
      rating: ((_num(m, ['rating', 'score']) ?? 0) as num).toDouble(),
      link: link,
      commission: commission,
      description: descCandidate ?? '',
      shopTitle: shopTitle ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'platform': platform,
        'title': title,
        'price': price,
        'original_price': originalPrice,
        'coupon': coupon,
        'final_price': finalPrice,
        'image_url': imageUrl,
        'sales': sales,
        'rating': rating,
        'link': link,
        'commission': commission,
        'description': description,
        'shop_title': shopTitle,
      };

  /// Normalize product title returned by LLMs: strip the prefix used to mark product titles
  /// e.g. if AI returns "商品：A型号 蓝牙耳机", this will return "A型号 蓝牙耳机"
  static String normalizeTitle(String? raw) {
    if (raw == null) return '';
    var s = raw.trim();
    if (s.startsWith('商品：')) return s.substring(3).trim();
    if (s.startsWith('商品:')) return s.substring(3).trim();
    return s;
  }
}


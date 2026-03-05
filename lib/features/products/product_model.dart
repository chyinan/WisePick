import 'dart:developer' as dev;

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
  @HiveField(10)
  final String shopTitle; // 商店/店铺名（来自淘宝的 shop_title 或 item_basic_info.shop_title）
  @HiveField(11)
  final String link; // 推广链接或口令
  @HiveField(12)
  final double commission;
  @HiveField(13)
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

  ProductModel copyWith({
    String? id,
    String? platform,
    String? title,
    double? price,
    double? originalPrice,
    double? coupon,
    double? finalPrice,
    String? imageUrl,
    int? sales,
    double? rating,
    String? shopTitle,
    String? link,
    double? commission,
    String? description,
  }) {
    return ProductModel(
      id: id ?? this.id,
      platform: platform ?? this.platform,
      title: title ?? this.title,
      price: price ?? this.price,
      originalPrice: originalPrice ?? this.originalPrice,
      coupon: coupon ?? this.coupon,
      finalPrice: finalPrice ?? this.finalPrice,
      imageUrl: imageUrl ?? this.imageUrl,
      sales: sales ?? this.sales,
      rating: rating ?? this.rating,
      shopTitle: shopTitle ?? this.shopTitle,
      link: link ?? this.link,
      commission: commission ?? this.commission,
      description: description ?? this.description,
    );
  }

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
    } catch (e, st) {
      dev.log('Error parsing Taobao description: $e', name: 'ProductModel', error: e, stackTrace: st);
    }

    // extract shop title from top-level or nested item_basic_info
    String? shopTitle = (m['shop_title'] as String?) ?? (m['shopTitle'] as String?);
    try {
      if ((shopTitle == null || shopTitle.isEmpty) && m['item_basic_info'] is Map) {
        final basic = m['item_basic_info'] as Map<String, dynamic>;
        shopTitle = (basic['shop_title'] as String?) ?? (basic['shopTitle'] as String?);
      }
    } catch (e, st) {
      dev.log('Error parsing Taobao shop title: $e', name: 'ProductModel', error: e, stackTrace: st);
    }

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

  // fromVeApi 已移除 — VEAPI 已弃用，所有淘宝商品解析统一通过 TaobaoAdapter + fromJson

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


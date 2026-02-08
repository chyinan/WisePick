import 'dart:convert';
import 'dart:developer' as dev;

class PddProduct {
  final String goodsSign;
  final String name;
  final String imageUrl;
  final int minGroupPrice; // 单位：分
  final int minNormalPrice; // 单位：分
  final bool hasCoupon;
  final int couponDiscount; // 单位：分
  final int promotionRate; // 单位：千分比
  final int sale; // 最近销量或提示字段
  final List<int> optIds; // 商品标签 id

  PddProduct({
    required this.goodsSign,
    required this.name,
    required this.imageUrl,
    required this.minGroupPrice,
    required this.minNormalPrice,
    required this.hasCoupon,
    required this.couponDiscount,
    required this.promotionRate,
    required this.sale,
    required this.optIds,
  });

  factory PddProduct.fromJson(Map<String, dynamic> json) {
    List<int> parseIntList(dynamic v) {
      try {
        if (v is List) return v.map((e) => (e as num).toInt()).toList();
        if (v is String) {
          final dec = jsonDecode(v);
          if (dec is List) return dec.map((e) => (e as num).toInt()).toList();
        }
      } catch (e, st) {
        dev.log('Error parsing PDD goods_gallery_urls: $e', name: 'PddProductModel', error: e, stackTrace: st);
      }
      return <int>[];
    }

    return PddProduct(
      goodsSign: json['goods_sign']?.toString() ?? '',
      name: json['goods_name']?.toString() ?? '',
      imageUrl: json['goods_image_url']?.toString() ?? '',
      minGroupPrice: (json['min_group_price'] as num?)?.toInt() ?? 0,
      minNormalPrice: (json['min_normal_price'] as num?)?.toInt() ?? 0,
      hasCoupon: json['has_coupon'] == true,
      couponDiscount: (json['coupon_discount'] as num?)?.toInt() ?? 0,
      promotionRate: (json['promotion_rate'] as num?)?.toInt() ?? 0,
      sale: (json['sales_tip'] is String)
          ? int.tryParse(RegExp(r"(\d+)").firstMatch(json['sales_tip'] ?? '')?.group(0) ?? '') ?? 0
          : (json['sales_tip'] as num?)?.toInt() ?? 0,
      optIds: parseIntList(json['opt_ids'] ?? json['opt_ids']),
    );
  }
}


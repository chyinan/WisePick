import 'dart:async';

import 'package:hive/hive.dart';

import '../../core/config.dart';
import '../../core/pdd_client.dart';

class PddGoodsDetail {
  final List<String> images;
  final double? minGroupPrice;
  final double? minNormalPrice;
  final double? couponDiscount;
  final String? description;

  const PddGoodsDetail({
    this.images = const <String>[],
    this.minGroupPrice,
    this.minNormalPrice,
    this.couponDiscount,
    this.description,
  });

  double? get preferredPrice =>
      (minGroupPrice ?? minNormalPrice ?? 0) - (couponDiscount ?? 0);
}

class PddGoodsDetailService {
  final PddClient _client;

  PddGoodsDetailService({PddClient? client})
      : _client = client ??
            PddClient(
              clientId: Config.pddClientId,
              clientSecret: Config.pddClientSecret,
              pid: Config.pddPid,
            );

  Future<PddGoodsDetail?> fetchDetail(String goodsSign) async {
    if (goodsSign.isEmpty) return null;
    final response = await _client.fetchGoodsDetail({
      'goods_sign': goodsSign,
      'pid': Config.pddPid,
      'goods_img_type': 2,
      'need_sku_info': false,
    });

    if (response is Map &&
        response['goods_detail_response'] is Map &&
        (response['goods_detail_response']['goods_details'] is List)) {
      final List<dynamic> details =
          response['goods_detail_response']['goods_details'] as List<dynamic>;
      if (details.isEmpty) return null;
      final Map<String, dynamic> detail =
          Map<String, dynamic>.from(details.first as Map);

      final List<String> images = [];
      void addUrl(dynamic value) {
        if (value == null) return;
        var url = value.toString().trim();
        if (url.isEmpty) return;
        images.add(url);
      }

      final gallery = detail['goods_gallery_urls'];
      if (gallery is List) {
        for (final item in gallery) addUrl(item);
      }
      addUrl(detail['goods_image_url']);
      addUrl(detail['goods_thumbnail_url']);

      double? centsToYuan(dynamic v) {
        if (v == null) return null;
        if (v is num) return v.toDouble() / 100.0;
        final parsed = double.tryParse(v.toString());
        return parsed != null ? parsed / 100.0 : null;
      }

      return PddGoodsDetail(
        images: images,
        minGroupPrice: centsToYuan(detail['min_group_price']),
        minNormalPrice: centsToYuan(detail['min_normal_price']),
        couponDiscount: centsToYuan(detail['coupon_discount']),
        description: detail['goods_desc']?.toString(),
      );
    }
    return null;
  }
}



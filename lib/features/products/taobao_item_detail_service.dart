import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../core/config.dart';

class TaobaoItemDetail {
  final List<String> images;
  final double? finalPromotionPrice;
  final double? reservePrice;
  final double? zkFinalPrice;
  final double? predictRoundingUpPrice;

  const TaobaoItemDetail({
    this.images = const <String>[],
    this.finalPromotionPrice,
    this.reservePrice,
    this.zkFinalPrice,
    this.predictRoundingUpPrice,
  });

  double? get preferredPrice =>
      finalPromotionPrice ??
      predictRoundingUpPrice ??
      zkFinalPrice ??
      reservePrice;

  TaobaoItemDetail copyWith({
    List<String>? images,
    double? finalPromotionPrice,
    double? reservePrice,
    double? zkFinalPrice,
    double? predictRoundingUpPrice,
  }) {
    return TaobaoItemDetail(
      images: images ?? this.images,
      finalPromotionPrice: finalPromotionPrice ?? this.finalPromotionPrice,
      reservePrice: reservePrice ?? this.reservePrice,
      zkFinalPrice: zkFinalPrice ?? this.zkFinalPrice,
      predictRoundingUpPrice:
          predictRoundingUpPrice ?? this.predictRoundingUpPrice,
    );
  }
}

class TaobaoItemDetailService {
  static const _host = 'gw.api.taobao.com';
  static const _path = '/router/rest';

  Future<TaobaoItemDetail> fetchDetail(String itemId) async {
    if (Config.taobaoAppKey.startsWith('YOUR_') ||
        Config.taobaoAppSecret.startsWith('YOUR_')) {
      throw Exception('淘宝 API 未配置');
    }

    final params = <String, String>{
      'app_key': Config.taobaoAppKey,
      'format': 'json',
      'get_tlj_info': '0',
      'item_id': itemId,
      'method': 'taobao.tbk.item.info.upgrade.get',
      'partner_id': 'top-apitools',
      'sign_method': 'md5',
      'timestamp': _formatTimestamp(DateTime.now()),
      'v': '2.0',
    };
    final uri =
        Uri.https(_host, _path, {...params, 'sign': _generateSign(params)});

    final response = await http.get(uri).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('淘宝接口返回错误 ${response.statusCode}');
    }

    final payload =
        jsonDecode(response.body) as Map<String, dynamic>? ?? const {};

    if (payload.containsKey('error_response')) {
      final err = payload['error_response'] as Map<String, dynamic>;
      final msg = err['sub_msg'] ?? err['msg'] ?? '未知错误';
      throw Exception('淘宝接口错误: $msg');
    }

    final responseBody =
        payload['tbk_item_info_upgrade_get_response'] as Map<String, dynamic>? ??
            const {};
    final results = responseBody['results'] as Map<String, dynamic>? ?? const {};
    final List<dynamic> detailList =
        results['tbk_item_detail'] as List<dynamic>? ?? const [];
    if (detailList.isEmpty) return const TaobaoItemDetail();

    final Map<String, dynamic> detail =
        Map<String, dynamic>.from(detailList.first as Map);

    final images = _extractImages(detail);
    final priceInfo =
        detail['price_promotion_info'] as Map<String, dynamic>? ?? const {};
    final double? finalPromotionPrice =
        _maybeParseDouble(priceInfo['final_promotion_price']);
    final double? predictRoundingPrice =
        _maybeParseDouble(priceInfo['predict_rounding_up_price']);
    final double? reservePrice =
        _maybeParseDouble(priceInfo['reserve_price']) ??
            _maybeParseDouble(detail['reserve_price']);
    final double? zkFinalPrice =
        _maybeParseDouble(priceInfo['zk_final_price']) ??
            _maybeParseDouble(detail['zk_final_price']);

    return TaobaoItemDetail(
      images: images,
      finalPromotionPrice: finalPromotionPrice,
      predictRoundingUpPrice: predictRoundingPrice,
      reservePrice: reservePrice,
      zkFinalPrice: zkFinalPrice,
    );
  }

  static List<String> _extractImages(Map<String, dynamic> detail) {
    final images = <String>[];

    void addUrl(dynamic value) {
      if (value == null) return;
      var url = value.toString().trim();
      if (url.isEmpty) return;
      if (url.startsWith('//')) url = 'https:$url';
      if (!images.contains(url)) images.add(url);
    }

    void collect(dynamic node) {
      if (node is Map && node['string'] is List) {
        for (final entry in node['string'] as List) {
          addUrl(entry);
        }
      } else if (node is List) {
        for (final entry in node) {
          addUrl(entry);
        }
      }
    }

    final basic = detail['item_basic_info'];
    if (basic is Map<String, dynamic>) {
      addUrl(basic['pict_url'] ?? basic['pictUrl']);
      collect(basic['small_images']);
    }
    addUrl(detail['pict_url'] ?? detail['pictUrl']);
    collect(detail['small_images']);

    return images;
  }

  static double? _maybeParseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static String _generateSign(Map<String, String> params) {
    final sortedKeys = params.keys.toList()..sort();
    final buffer = StringBuffer(Config.taobaoAppSecret);
    for (final key in sortedKeys) {
      final value = params[key];
      if (value == null || value.isEmpty) continue;
      buffer
        ..write(key)
        ..write(value);
    }
    buffer.write(Config.taobaoAppSecret);
    final digest = md5.convert(utf8.encode(buffer.toString()));
    return digest.toString().toUpperCase();
  }

  static String _formatTimestamp(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }
}



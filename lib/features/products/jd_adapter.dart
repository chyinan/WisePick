import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import 'product_model.dart';
import 'jd_models.dart';

/// JD Adapter：负责调用京东联盟 API 并映射到 ProductModel
class JdAdapter {
  final ApiClient _client;

  JdAdapter({ApiClient? client}) : _client = client ?? ApiClient();

  /// Search JD goods using `jd.union.open.goods.query`.
  /// Builds the required system parameters, signs the request using MD5
  /// and posts form-encoded data to the configured API endpoint.
  Future<List<ProductModel>> search(String keyword, {int pageIndex = 1, int pageSize = 10}) async {
    // Prefer calling the backend proxy which performs signing and returns the
    // raw JD response. This avoids keeping JD app secret in the client.
    String backend = 'http://localhost:8080';
    try {
      if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
      final box = Hive.box('settings');
      final String? b = box.get('backend_base') as String?;
      if (b != null && b.trim().isNotEmpty) backend = b.trim();
      else backend = Platform.environment['BACKEND_BASE'] ?? backend;
    } catch (_) {}

    final apiUrl = '$backend/jd/union/goods/query';
    final resp = await _client.get(apiUrl, params: {'keyword': keyword, 'pageIndex': pageIndex, 'pageSize': pageSize});
    final body = resp.data;
    List<dynamic> items = [];
    try {
      if (body is Map) {
        if (body['data'] is List) {
          items = body['data'] as List<dynamic>;
        } else if (body['queryResult'] is Map) {
          final qr = body['queryResult'] as Map;
          final d = qr['data'];
          if (d is List) items = d as List<dynamic>;
          else if (d is Map) {
            if (d['goodsResp'] != null) {
              final gr = d['goodsResp'];
              if (gr is List) items = gr as List<dynamic>;
              else items = [gr];
            } else {
              items = [d];
            }
          }
        } else {
          // top-level wrapper case: jd_union_open_goods_query_responce
          for (final v in body.values) {
            if (v is Map && v['queryResult'] is Map) {
              final qr = v['queryResult'] as Map;
              final d = qr['data'];
              if (d is List) items = d as List<dynamic>;
              else if (d is Map) {
                if (d['goodsResp'] != null) {
                  final gr = d['goodsResp'];
                  if (gr is List) items = gr as List<dynamic>;
                  else items = [gr];
                } else {
                  items = [d];
                }
              }
              break;
            }
          }
        }
      } else if (body is List) {
        items = body as List<dynamic>;
      }
    } catch (_) {
      items = [];
    }

    final futures = items.map((e) async {
      final map = Map<String, dynamic>.from(e as Map);
      final price = (map['priceInfo'] != null && map['priceInfo'] is Map && map['priceInfo']['price'] != null)
          ? (map['priceInfo']['price'] as num).toDouble()
          : (map['price'] as num?)?.toDouble() ?? 0.0;
      final image = (map['imageInfo'] != null && map['imageInfo']['imageList'] != null && (map['imageInfo']['imageList'] as List).isNotEmpty)
          ? map['imageInfo']['imageList'][0]['url']
          : (map['imageUrl'] ?? '');
      final commission = (map['commissionInfo'] != null && map['commissionInfo']['commission'] != null) ? (map['commissionInfo']['commission'] as num).toDouble() : 0.0;

      var link = '';
      try {
        final skuId = map['skuId']?.toString() ?? '';
        if (skuId.isNotEmpty) {
          String backend = 'http://localhost:8080';
          try {
            if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
            final box = Hive.box('settings');
            final String? b = box.get('backend_base') as String?;
            if (b != null && b.trim().isNotEmpty) backend = b.trim();
            else backend = Platform.environment['BACKEND_BASE'] ?? backend;
          } catch (_) {}

          // ask backend to sign and/or generate promotion link using official JD SDK
          final signResp = await _client.post('$backend/sign/jd', data: {'skuId': skuId});
          if (signResp.data is Map && signResp.data['clickURL'] != null) {
            link = signResp.data['clickURL'] as String;
          } else {
            link = await generatePromotionLink(skuId);
          }
        }
      } catch (_) {
        link = '';
      }

      return ProductModel(
        id: map['skuId']?.toString() ?? '',
        platform: 'jd',
        title: map['skuName'] ?? '',
        price: price,
        originalPrice: price,
        coupon: 0.0,
        finalPrice: price,
        imageUrl: image,
        sales: (map['comments'] as num?)?.toInt() ?? 0,
        rating: (map['goodCommentsShare'] as num?)?.toDouble() ?? 0.0,
        link: link,
        commission: commission,
      );
    }).toList();

    return await Future.wait(futures);
  }

  /// 生成京东推广链接（简化）
  Future<String> generatePromotionLink(String skuId) async {
    // 京东官方接口需要签名；这里示例在客户端做 HMAC 签名（生产应在服务端签名）
    final apiUrl = 'https://api.example.com/jd/union/open/promotion/common/get';
    final payload = {'skuId': skuId, 'unionId': Config.jdUnionId};
    final ts = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
    final sign = _hmacSign(jsonEncode({...payload, 'ts': ts}), Config.jdAppSecret);
    final resp = await _client.post(apiUrl, data: {...payload, 'appKey': Config.jdAppKey, 'ts': ts, 'sign': sign});
    if (resp.data is Map && resp.data['clickURL'] != null) {
      return resp.data['clickURL'] as String;
    }
    return '';
  }

  String _hmacSign(String data, String secret) {
    final key = utf8.encode(secret);
    final bytes = utf8.encode(data);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    return digest.toString();
  }

  String _formatJdTimestamp() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  }

  String _md5Sign(Map<String, String> params, String secret) {
    final keys = params.keys.toList()..sort();
    final sb = StringBuffer();
    sb.write(secret);
    for (final k in keys) {
      sb.write(k);
      sb.write(params[k] ?? '');
    }
    sb.write(secret);
    final digest = md5.convert(utf8.encode(sb.toString()));
    return digest.toString().toUpperCase();
  }
}


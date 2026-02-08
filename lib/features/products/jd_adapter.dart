import 'dart:convert';
import 'dart:developer';

import 'package:crypto/crypto.dart';

import '../../core/api_client.dart';
import '../../core/backend_config.dart';
import 'product_model.dart';

/// JD Adapter：负责调用京东联盟 API 并映射到 ProductModel
class JdAdapter {
  final ApiClient _client;

  JdAdapter({ApiClient? client}) : _client = client ?? ApiClient();

  /// Search JD goods using `jd.union.open.goods.query`.
  /// Builds the required system parameters, signs the request using MD5
  /// and posts form-encoded data to the configured API endpoint.
  Future<List<ProductModel>> search(String keyword, {int pageIndex = 1, int pageSize = 10}) async {
    // 通过后端代理调用京东联盟 API（后端负责签名和密钥管理）
    final backend = BackendConfig.resolveSync();

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
          if (d is List) {
            items = d;
          } else if (d is Map) {
            if (d['goodsResp'] != null) {
              final gr = d['goodsResp'];
              if (gr is List) {
                items = gr;
              } else {
                items = [gr];
              }
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
              if (d is List) {
                items = d;
              } else if (d is Map) {
                if (d['goodsResp'] != null) {
                  final gr = d['goodsResp'];
                  if (gr is List) {
                    items = gr;
                  } else {
                    items = [gr];
                  }
                } else {
                  items = [d];
                }
              }
              break;
            }
          }
        }
      } else if (body is List) {
        items = body;
      }
    } catch (e, st) {
      log('JD response parsing failed: $e', name: 'JdAdapter', error: e, stackTrace: st);
      items = [];
    }

    final futures = items.map((e) async {
      final map = Map<String, dynamic>.from(e);
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
          final promoBackend = BackendConfig.resolveSync();
          final signResp = await _client.post('$promoBackend/sign/jd', data: {'skuId': skuId});
          if (signResp.data is Map && signResp.data['clickURL'] != null) {
            link = signResp.data['clickURL'] as String;
          } else {
            link = await generatePromotionLink(skuId);
          }
        }
      } catch (e, st) {
        log('JD sign/promotion link failed: $e', name: 'JdAdapter', error: e, stackTrace: st);
        link = '';
      }

      int sales = (map['inOrderCount30Days'] as num?)?.toInt() ?? 0;
      int comments = (map['comments'] as num?)?.toInt() ?? 0;
      double rating = (map['goodCommentsShare'] as num?)?.toDouble() ?? 0.0;

      // 如果没有找到30天销量，则使用评论数作为销量兜底
      if (sales == 0) {
        sales = comments;
      }

      // 启发式修复: 用户反馈JD接口有时会将好评率(如96)放在comments字段，而goodCommentsShare为空
      // 如果我们通过inOrderCount30Days获取到了真实销量，且rating为空，且comments看起来像好评率(80-100)，
      // 则尝试将comments作为rating使用
      if (rating <= 0.01 && sales > 0 && sales != comments && comments >= 80 && comments <= 100) {
        rating = comments.toDouble();
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
        sales: sales,
        rating: rating,
        link: link,
        commission: commission,
      );
    }).toList();

    return await Future.wait(futures);
  }

  /// 生成京东推广链接 — 通过后端代理完成签名
  Future<String> generatePromotionLink(String skuId) async {
    final backend = BackendConfig.resolveSync();
    try {
      final resp = await _client.post('$backend/sign/jd', data: {'skuId': skuId});
      if (resp.data is Map && resp.data['clickURL'] != null) {
        return resp.data['clickURL'] as String;
      }
    } catch (e, st) {
      log('JD promotion link generation failed: $e', name: 'JdAdapter', error: e, stackTrace: st);
    }
    return '';
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


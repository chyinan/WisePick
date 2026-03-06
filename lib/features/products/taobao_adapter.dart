import 'dart:developer';
import '../../core/api_client.dart';
import '../../core/backend_config.dart';
import 'product_model.dart';

/// Taobao Adapter：负责调用淘宝联盟 API 并映射到 ProductModel
///
/// 所有淘宝联盟接口调用均通过后端代理完成（后端负责签名和密钥管理），
/// 客户端不再直接调用 api.example.com 等占位地址。
class TaobaoAdapter {
  final ApiClient _client;

  TaobaoAdapter({ApiClient? client}) : _client = client ?? ApiClient();

  /// 搜索商品 — 通过后端代理调用淘宝联盟搜索接口
  Future<List<ProductModel>> search(String keyword, {int page = 1, int pageSize = 10}) async {
    // 通过后端代理搜索，后端负责签名和调用官方 API
    final backend = BackendConfig.resolveSync();
    final apiUrl = '$backend/api/products/search';
    final params = <String, dynamic>{
      'query': keyword,
      'platform': 'taobao',
      'page_no': page,
      'page_size': pageSize,
    };

    final resp = await _client.get(apiUrl, params: params);
    final dynamic rawData = resp.data;
    final List data;
    if (rawData is Map && rawData['results'] is List) {
      data = rawData['results'] as List;
    } else if (rawData is List) {
      data = rawData;
    } else {
      data = [];
    }

    final futures = data.map((e) async {
      final map = Map<String, dynamic>.from(e as Map);
      final price = double.tryParse(map['zk_final_price']?.toString() ?? map['price']?.toString() ?? '') ?? 0.0;
      final original = double.tryParse(map['reserve_price']?.toString() ?? map['originalPrice']?.toString() ?? '') ?? price;
      final coupon = (map['coupon_amount'] != null) ? double.tryParse(map['coupon_amount'].toString()) ?? 0.0
          : (map['coupon'] != null) ? double.tryParse(map['coupon'].toString()) ?? 0.0 : 0.0;
      final commissionRate = double.tryParse(map['commission_rate']?.toString() ?? '') ?? 0.0;
      final commission = price * (commissionRate / (commissionRate > 100 ? 10000 : 100));

      // Prefer coupon_share_url first (better for coupon forwarding), then click_url,
      // then coupon_click_url, then fall back to plain url/item_url.
      final sourceUrl = (map['coupon_share_url'] ?? map['click_url'] ?? map['coupon_click_url'] ?? map['url'] ?? map['item_url'] ?? map['link'] ?? '') as String;
      var link = '';
      if (sourceUrl.isNotEmpty) {
        try {
          final signBackend = BackendConfig.resolveSync();

          // Call backend proxy to create tpwd
          final signResp = await _client.post('$signBackend/sign/taobao', data: {'url': sourceUrl});
          if (signResp.data is Map) {
            if (signResp.data['tpwd'] != null) {
              link = signResp.data['tpwd'] as String;
            } else if (signResp.data['clickURL'] != null) {
              link = signResp.data['clickURL'] as String;
            }
          }
        } catch (e, st) {
          log('Taobao sign failed: $e', name: 'TaobaoAdapter', error: e, stackTrace: st);
          link = '';
        }
      }

      return ProductModel(
        id: map['num_iid']?.toString() ?? map['item_id']?.toString() ?? '',
        platform: 'taobao',
        title: map['title'] ?? '',
        price: price,
        originalPrice: original,
        coupon: coupon,
        finalPrice: (price - coupon),
        imageUrl: map['pict_url'] ?? map['pic_url'] ?? '',
        sales: int.tryParse(map['volume']?.toString() ?? '') ?? 0,
        rating: 0.0,
        link: link,
        commission: commission,
      );
    }).toList();

    return await Future.wait(futures);
  }

  /// 生成淘口令 — 通过后端代理完成签名和调用
  Future<String> generateTpwd(String url, {String text = ''}) async {
    final backend = BackendConfig.resolveSync();
    try {
      final resp = await _client.post('$backend/sign/taobao', data: {
        'url': url,
        'text': text,
      });
      if (resp.data is Map) {
        if (resp.data['tpwd'] != null) return resp.data['tpwd'] as String;
        if (resp.data['model'] != null) return resp.data['model'] as String;
      }
    } catch (e, st) {
      log('Taobao tpwd generation failed: $e', name: 'TaobaoAdapter', error: e, stackTrace: st);
    }
    return '';
  }
}



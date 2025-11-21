import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../../core/api_client.dart';
import '../../core/config.dart';
import 'product_model.dart';

/// Taobao Adapter：负责调用淘宝联盟 API 并映射到 ProductModel 
class TaobaoAdapter {
  final ApiClient _client;

  TaobaoAdapter({ApiClient? client}) : _client = client ?? ApiClient();

  /// 搜索商品（简化示例，真实接入需按官方 SDK/签名要求实现）
  Future<List<ProductModel>> search(String keyword, {int page = 1, int pageSize = 10}) async {
    // NOTE: 真实调用需要签名与 SDK，这里使用假设的 REST 网关或第三方代理
    final apiUrl = 'https://api.example.com/taobao/dg/material/optional';
    final params = <String, dynamic>{
      'q': keyword,
      'adzone_id': Config.taobaoAdzoneId,
      'page_no': page,
      'page_size': pageSize,
    };

    final resp = await _client.get(apiUrl, params: params);
    final List data = resp.data is Map && resp.data['results'] != null ? resp.data['results'] as List : (resp.data as List? ?? []);

    final futures = data.map((e) async {
      final map = Map<String, dynamic>.from(e as Map);
      final price = double.tryParse(map['zk_final_price']?.toString() ?? '') ?? 0.0;
      final original = double.tryParse(map['reserve_price']?.toString() ?? '') ?? price;
      final coupon = (map['coupon_amount'] != null) ? double.tryParse(map['coupon_amount'].toString()) ?? 0.0 : 0.0;
      final commissionRate = double.tryParse(map['commission_rate']?.toString() ?? '') ?? 0.0; // 千分比或万分比视返回
      final commission = price * (commissionRate / (commissionRate > 100 ? 10000 : 100));

    // Prefer coupon_share_url first (better for coupon forwarding), then click_url,
    // then coupon_click_url, then fall back to plain url/item_url.
    final sourceUrl = (map['coupon_share_url'] ?? map['click_url'] ?? map['coupon_click_url'] ?? map['url'] ?? map['item_url'] ?? '') as String;
      var link = '';
      if (sourceUrl.isNotEmpty) {
        try {
          // Read backend base from settings via a simple settings endpoint or assume localhost
          String backend = 'http://localhost:8080';
          try {
            final confResp = await _client.get('http://localhost:8080/__settings');
            if (confResp.statusCode == 200 && confResp.data is Map && confResp.data['backend_base'] != null) {
              backend = confResp.data['backend_base'] as String;
            }
          } catch (_) {}

          // Call backend proxy to create tpwd via veapi
          final signResp = await _client.post('\$backend/sign/taobao', data: {'url': sourceUrl});
          if (signResp.data is Map && signResp.data['sign'] != null) {
            // server may return a signed token; here we assume server will in turn call Taobao and return a tpwd
            if (signResp.data['tpwd'] != null) {
              link = signResp.data['tpwd'] as String;
            }
          }
          // Fallback: still try client-side generation if server didn't return tpwd
          if (link.isEmpty) {
            link = await generateTpwd(sourceUrl, text: map['title'] ?? '');
          }
        } catch (_) {
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

  /// 生成淘口令（简化）
  Future<String> generateTpwd(String url, {String text = ''}) async {
    // 使用官方 TBK 接口的 REST 代理示例：实际生产请用官方 SDK 或服务端签名
    final apiUrl = 'https://api.example.com/taobao/tbk/tpwd/create';
    // 如果我们有 appKey/secret，可在服务端生成签名，这里演示简单 HMAC 签名并传入
    final payload = {'url': url, 'text': text, 'adzone_id': Config.taobaoAdzoneId};
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final signature = _hmacSign(jsonEncode({...payload, 'ts': timestamp}), Config.taobaoAppSecret);
    final resp = await _client.post(apiUrl, data: {...payload, 'app_key': Config.taobaoAppKey, 'ts': timestamp, 'sign': signature});
    if (resp.data is Map && resp.data['model'] != null) {
      return resp.data['model'] as String;
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
}


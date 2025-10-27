import 'dart:convert';
import '../../core/api_client.dart';
import '../../core/config.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'product_model.dart';
import 'taobao_adapter.dart';
import 'jd_adapter.dart';
import 'pdd_adapter.dart';

/// 商品服务：整合各平台 adapter，返回统一的 ProductModel 列表
class ProductService {
  final ApiClient _client;
  final TaobaoAdapter _taobao;
  final JdAdapter _jd;
  final PddAdapter _pdd;
  // 简单内存缓存：map from product.id to {link, expiryMs}
  final Map<String, Map<String, dynamic>> _promoCache = {};

  ProductService({ApiClient? client})
      : _client = client ?? ApiClient(),
        _taobao = TaobaoAdapter(client: client),
        _jd = JdAdapter(client: client),
        _pdd = PddAdapter(client: client);

  /// 搜索不同平台的商品
  /// platform: 'taobao' | 'jd' | 'all'
  Future<List<ProductModel>> searchProducts(String platform, String keyword,
      {int page = 1, int pageSize = 10}) async {
    if (platform == 'taobao') {
      return await _taobao.search(keyword, page: page, pageSize: pageSize);
    }
    if (platform == 'jd') {
      return await _jd.search(keyword, pageIndex: page, pageSize: pageSize);
    }
    if (platform == 'pdd') {
      return await _pdd.search(keyword, page: page, pageSize: pageSize);
    }

    // all：并行查询并合并结果（去重，优先保留 JD 条目）
    final results = await Future.wait([
      _taobao.search(keyword, page: page, pageSize: pageSize),
      _jd.search(keyword, pageIndex: page, pageSize: pageSize),
      _pdd.search(keyword, page: page, pageSize: pageSize),
    ]);

    final List<ProductModel> taobaoList = List<ProductModel>.from(results[0]);
    final List<ProductModel> jdList = List<ProductModel>.from(results[1]);

    final merged = <ProductModel>[];
    final seenIds = <String, ProductModel>{};

    // First add Taobao items as base (but keep map to allow JD to replace)
    for (final p in taobaoList) {
      if (p.id.isEmpty) continue;
      seenIds[p.id] = p;
    }

    // Then add/replace with JD items when available (prefer JD)
    for (final p in jdList) {
      if (p.id.isEmpty) continue;
      // if JD item exists, prefer it (replace)
      seenIds[p.id] = p;
    }

    // produce merged preserving order: JD items first (as they are often preferred), then remaining Taobao
    final added = <String>{};
    for (final p in jdList) {
      if (p.id.isEmpty) continue;
      if (!added.contains(p.id)) {
        merged.add(seenIds[p.id]!);
        added.add(p.id);
      }
    }
    for (final p in taobaoList) {
      if (p.id.isEmpty) continue;
      if (!added.contains(p.id)) {
        merged.add(seenIds[p.id]!);
        added.add(p.id);
      }
    }

    return merged;
  }

  /// 为商品生成/获取推广链接（优先从后端 proxy 获取），返回 clickURL 或 tpwd（口令）
  Future<String?> generatePromotionLink(ProductModel p, {bool forceRefresh = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cache = _promoCache[p.id];
    if (!forceRefresh && cache != null) {
      final expiry = cache['expiry'] as int? ?? 0;
      if (expiry > now && cache['link'] != null && (cache['link'] as String).isNotEmpty) {
        return cache['link'] as String;
      }
    }

    // try load from persistent Hive cache
    try {
      if (!Hive.isBoxOpen('promo_cache')) await Hive.openBox('promo_cache');
      final box = Hive.box('promo_cache');
      final stored = box.get(p.id) as Map<dynamic, dynamic>?;
      if (stored != null) {
        final sLink = stored['link'] as String?;
        final sExpiry = (stored['expiry'] as int?) ?? 0;
        if (sLink != null && sLink.isNotEmpty && sExpiry > now) {
          _promoCache[p.id] = {'link': sLink, 'expiry': sExpiry};
          return sLink;
        }
      }
    } catch (_) {}

    // read backend base from Hive settings if available, else default to localhost
    String backend = 'http://localhost:8080';
    try {
      if (await _ensureHiveOpen()) {
        final box = Hive.box('settings');
        final String? b = box.get('backend_base') as String?;
        if (b != null && b.trim().isNotEmpty) backend = b.trim();
        else backend = const String.fromEnvironment('BACKEND_BASE', defaultValue: 'http://localhost:8080');
      } else {
        backend = const String.fromEnvironment('BACKEND_BASE', defaultValue: 'http://localhost:8080');
      }
    } catch (_) {}

    try {
      // If product is from JD, prefer backend sign endpoint for JD and DO NOT fall
      // back to Taobao/VEAPI if signing fails. Returning null makes the caller
      // show an appropriate message instead of attempting taobao conversion.
      if (p.platform == 'jd') {
        try {
          final signResp = await _client.post('$backend/sign/jd', data: {'skuId': p.id});
          if (signResp.data != null && signResp.data is Map) {
            final m = Map<String, dynamic>.from(signResp.data as Map);
            String? link;
            if (m['clickURL'] != null) link = m['clickURL'] as String?;
            if ((link == null || link.isEmpty) && m['tpwd'] != null) link = m['tpwd'] as String?;
            if (link != null && link.isNotEmpty) {
              final expiry = now + 30 * 60 * 1000;
              _promoCache[p.id] = {'link': link, 'expiry': expiry};
              try {
                if (!Hive.isBoxOpen('promo_cache')) await Hive.openBox('promo_cache');
                final box = Hive.box('promo_cache');
                await box.put(p.id, {'link': link, 'expiry': expiry});
              } catch (_) {}
              return link;
            }
          }
        } catch (_) {}
        // If sign endpoint didn't return a link, try the new promotion API (bysubunionid)
        try {
          // build promotionCodeReq: prefer existing product.link; fallback to mobile item url
          String materialId = p.link.isNotEmpty ? p.link : 'https://item.m.jd.com/product/${p.id}.html';
          final promoReq = <String, dynamic>{
            'materialId': materialId,
            'sceneId': 1,
            'chainType': 3,
          };

          // optionally include subUnionId or pid from settings if configured
          try {
            if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
            final box = Hive.box('settings');
            final String? sub = box.get('jd_sub_union_id') as String?;
            final String? pid = box.get('jd_pid') as String?;
            if (sub != null && sub.trim().isNotEmpty) promoReq['subUnionId'] = sub.trim();
            if (pid != null && pid.trim().isNotEmpty) promoReq['pid'] = pid.trim();
          } catch (_) {}

          final resp = await _client.post('$backend/jd/union/promotion/bysubunionid', data: {'promotionCodeReq': promoReq});
          if (resp.data != null) {
            Map<String, dynamic> m = {};
            if (resp.data is Map) m = Map<String, dynamic>.from(resp.data as Map);
            else {
              try {
                m = Map<String, dynamic>.from(jsonDecode(resp.data.toString()) as Map);
              } catch (_) {}
            }

            // robustly search common response shapes for clickURL/shortURL/jCommand
            String? link;
            try {
              // jd_union_open_promotion_bysubunionid_get_responce -> getResult -> data
              if (m.containsKey('jd_union_open_promotion_bysubunionid_get_responce')) {
                final top = m['jd_union_open_promotion_bysubunionid_get_responce'];
                if (top is Map && top['getResult'] is Map) {
                  final gr = top['getResult'] as Map;
                  final data = gr['data'] ?? gr['getResult'] ?? gr['result'];
                  if (data is Map) {
                    link = (data['clickURL'] ?? data['shortURL'] ?? data['jCommand'] ?? data['jShortCommand'])?.toString();
                  }
                }
              }
            } catch (_) {}

            try {
              // fallback: getResult -> data
              if (link == null && m.containsKey('getResult') && m['getResult'] is Map) {
                final gr = m['getResult'] as Map;
                final data = gr['data'] ?? gr['getResult'] ?? gr['result'];
                if (data is Map) link = (data['clickURL'] ?? data['shortURL'] ?? data['jCommand'] ?? data['jShortCommand'])?.toString();
              }
            } catch (_) {}

            try {
              // generic search for common keys
              if (link == null) {
                String? pick(Map mm, List<String> keys) {
                  for (final k in keys) if (mm.containsKey(k) && mm[k] != null) return mm[k].toString();
                  return null;
                }
                link = pick(m, ['clickURL', 'shortURL', 'jCommand', 'jShortCommand']);
                if (link == null) {
                  // dig one level deeper
                  for (final v in m.values) {
                    if (v is Map) {
                      link ??= pick(v, ['clickURL', 'shortURL', 'jCommand', 'jShortCommand']);
                      if (link != null) break;
                    }
                  }
                }
              }
            } catch (_) {}

            if (link != null && link.isNotEmpty) {
              final expiry = now + 30 * 60 * 1000;
              _promoCache[p.id] = {'link': link, 'expiry': expiry};
              try {
                if (!Hive.isBoxOpen('promo_cache')) await Hive.openBox('promo_cache');
                final box = Hive.box('promo_cache');
                await box.put(p.id, {'link': link, 'expiry': expiry});
              } catch (_) {}
              return link;
            }
          }
        } catch (_) {}

        // For JD products, if all attempts fail, fallback to a simple item page link
        // so the user can still go to the JD product page. Use skuId when available.
        try {
          final sku = p.id;
          if (sku.isNotEmpty) {
            final fallback = 'https://item.jd.com/${sku}.html';
            final expiry = now + 30 * 60 * 1000;
            _promoCache[p.id] = {'link': fallback, 'expiry': expiry};
            try {
              if (!Hive.isBoxOpen('promo_cache')) await Hive.openBox('promo_cache');
              final box = Hive.box('promo_cache');
              await box.put(p.id, {'link': fallback, 'expiry': expiry});
            } catch (_) {}
            return fallback;
          }
        } catch (_) {}

        // If fallback not possible, return null so caller can show a message
        return null;
      }

      // If product is from PDD, ask backend to generate PDD promotion link
      if (p.platform == 'pdd') {
        try {
          // Do not pass pid from the client app — let backend use its configured PDD_PID
          final signResp = await _client.post('$backend/sign/pdd', data: {'goods_sign_list': [p.id], 'custom_parameters': '{"uid":"chyinan"}'});
          if (signResp.data != null && signResp.data is Map) {
            final m = Map<String, dynamic>.from(signResp.data as Map);
            String? link = (m['clickURL'] ?? m['clickUrl'] ?? m['data'] ?? m['url'])?.toString();
            if ((link == null || link.isEmpty) && m['raw'] is Map) {
              final raw = m['raw'] as Map<String, dynamic>;
              try {
                if (raw.containsKey('goods_promotion_url_generate_response')) {
                  final g = raw['goods_promotion_url_generate_response'];
                  if (g is Map && g['goods_promotion_url_list'] is List && (g['goods_promotion_url_list'] as List).isNotEmpty) {
                    final entry = (g['goods_promotion_url_list'] as List).first as Map<String, dynamic>;
                    link = (entry['mobile_url'] ?? entry['url'] ?? entry['short_url'] ?? entry['mobile_short_url'])?.toString();
                  }
                }
              } catch (_) {}
            }
            if (link != null && link.isNotEmpty) {
              final expiry = now + 30 * 60 * 1000;
              _promoCache[p.id] = {'link': link, 'expiry': expiry};
              try {
                if (!Hive.isBoxOpen('promo_cache')) await Hive.openBox('promo_cache');
                final box = Hive.box('promo_cache');
                await box.put(p.id, {'link': link, 'expiry': expiry});
              } catch (_) {}
              return link;
            }
          }
        } catch (_) {}
      }

      // Try to call backend Taobao convert endpoint instead of veapi
      try {
        final resp = await _client.post('$backend/taobao/convert', data: {'id': p.id, 'url': p.link.isNotEmpty ? p.link : ''});
        if (resp.data != null) {
          Map<String, dynamic> m = {};
          if (resp.data is Map) m = Map<String, dynamic>.from(resp.data as Map);
          else {
            try {
              m = Map<String, dynamic>.from(jsonDecode(resp.data.toString()) as Map);
            } catch (_) {}
          }

          // extract common fields; prefer coupon_share_url, then clickURL, then tpwd
          String? link;
          if (m['coupon_share_url'] != null && (m['coupon_share_url'] as String).isNotEmpty) link = m['coupon_share_url'] as String;
          if ((link == null || link.isEmpty) && m['clickURL'] != null && (m['clickURL'] as String).isNotEmpty) link = m['clickURL'] as String;
          if ((link == null || link.isEmpty) && m['tpwd'] != null) link = m['tpwd'] as String?;

          if (link != null && link.isNotEmpty) {
            final expiry = now + 30 * 60 * 1000;
            _promoCache[p.id] = {'link': link, 'expiry': expiry};
            try {
              if (!Hive.isBoxOpen('promo_cache')) await Hive.openBox('promo_cache');
              final box = Hive.box('promo_cache');
              await box.put(p.id, {'link': link, 'expiry': expiry});
            } catch (_) {}
            return link;
          }
        }
      } catch (_) {}
    } catch (_) {}

    return null;
  }

  Future<bool> _ensureHiveOpen() async {
    try {
      if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
      return true;
    } catch (_) {
      return false;
    }
  }
}


import 'dart:convert';
import 'dart:developer';
import '../../core/api_client.dart';
import '../../core/backend_config.dart';
import '../../core/storage/hive_config.dart';
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
    final List<ProductModel> pddList = List<ProductModel>.from(results[2]);

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
      seenIds[p.id] = p;
    }

    // Then add PDD items (only if not already seen — PDD ids are typically
    // different from JD/Taobao ids, so most will be new entries)
    for (final p in pddList) {
      if (p.id.isEmpty) continue;
      seenIds.putIfAbsent(p.id, () => p);
    }

    // Produce merged preserving order: JD first, then Taobao, then PDD
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
    for (final p in pddList) {
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
      await HiveConfig.getBox(HiveConfig.promoCacheBox);
      final box = await HiveConfig.getBox(HiveConfig.promoCacheBox);
      final stored = box.get(p.id) as Map<dynamic, dynamic>?;
      if (stored != null) {
        final sLink = stored['link'] as String?;
        final sExpiry = (stored['expiry'] as int?) ?? 0;
        if (sLink != null && sLink.isNotEmpty && sExpiry > now) {
          _promoCache[p.id] = {'link': sLink, 'expiry': sExpiry};
          return sLink;
        }
      }
    } catch (e, st) {
      log('Error reading promo cache from Hive: $e', name: 'ProductService', error: e, stackTrace: st);
    }

    // 使用集中式后端地址解析
    final backend = BackendConfig.resolveSync();

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
                await HiveConfig.getBox(HiveConfig.promoCacheBox);
                final box = await HiveConfig.getBox(HiveConfig.promoCacheBox);
                await box.put(p.id, {'link': link, 'expiry': expiry});
              } catch (e, st) {
                log('Error writing JD sign link to promo cache: $e', name: 'ProductService', error: e, stackTrace: st);
              }
              return link;
            }
          }
        } catch (e, st) {
          log('JD sign endpoint failed for ${p.id}: $e', name: 'ProductService', error: e, stackTrace: st);
        }
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
            final box = await HiveConfig.getBox(HiveConfig.settingsBox);
            final String? sub = box.get('jd_sub_union_id') as String?;
            final String? pid = box.get('jd_pid') as String?;
            if (sub != null && sub.trim().isNotEmpty) promoReq['subUnionId'] = sub.trim();
            if (pid != null && pid.trim().isNotEmpty) promoReq['pid'] = pid.trim();
          } catch (e, st) {
            log('Error reading JD union settings: $e', name: 'ProductService', error: e, stackTrace: st);
          }

          final resp = await _client.post('$backend/jd/union/promotion/bysubunionid', data: {'promotionCodeReq': promoReq});
          if (resp.data != null) {
            Map<String, dynamic> m = {};
            if (resp.data is Map) m = Map<String, dynamic>.from(resp.data as Map);
            else {
              try {
                m = Map<String, dynamic>.from(jsonDecode(resp.data.toString()) as Map);
              } catch (e, st) {
                log('Error parsing JD promotion response: $e', name: 'ProductService', error: e, stackTrace: st);
              }
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
            } catch (e, st) {
              log('Error parsing JD bysubunionid response (top): $e', name: 'ProductService', error: e, stackTrace: st);
            }

            try {
              // fallback: getResult -> data
              if (link == null && m.containsKey('getResult') && m['getResult'] is Map) {
                final gr = m['getResult'] as Map;
                final data = gr['data'] ?? gr['getResult'] ?? gr['result'];
                if (data is Map) link = (data['clickURL'] ?? data['shortURL'] ?? data['jCommand'] ?? data['jShortCommand'])?.toString();
              }
            } catch (e, st) {
              log('Error parsing JD bysubunionid response (getResult): $e', name: 'ProductService', error: e, stackTrace: st);
            }

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
            } catch (e, st) {
              log('Error parsing JD promotion response (generic): $e', name: 'ProductService', error: e, stackTrace: st);
            }

            if (link != null && link.isNotEmpty) {
              final expiry = now + 30 * 60 * 1000;
              _promoCache[p.id] = {'link': link, 'expiry': expiry};
              try {
                await HiveConfig.getBox(HiveConfig.promoCacheBox);
                final box = await HiveConfig.getBox(HiveConfig.promoCacheBox);
                await box.put(p.id, {'link': link, 'expiry': expiry});
              } catch (e, st) { log('ProductService cache/parse error: $e', name: 'ProductService', error: e, stackTrace: st); }
              return link;
            }
          }
        } catch (e, st) { log('ProductService cache/parse error: $e', name: 'ProductService', error: e, stackTrace: st); }

        // For JD products, if all attempts fail, fallback to a simple item page link
        // so the user can still go to the JD product page. Use skuId when available.
        try {
          final sku = p.id;
          if (sku.isNotEmpty) {
            final fallback = 'https://item.jd.com/${sku}.html';
            final expiry = now + 30 * 60 * 1000;
            _promoCache[p.id] = {'link': fallback, 'expiry': expiry};
            try {
              await HiveConfig.getBox(HiveConfig.promoCacheBox);
              final box = await HiveConfig.getBox(HiveConfig.promoCacheBox);
              await box.put(p.id, {'link': fallback, 'expiry': expiry});
            } catch (e, st) { log('ProductService cache/parse error: $e', name: 'ProductService', error: e, stackTrace: st); }
            return fallback;
          }
        } catch (e, st) { log('ProductService cache/parse error: $e', name: 'ProductService', error: e, stackTrace: st); }

        // If fallback not possible, return null so caller can show a message
        return null;
      }

      // If product is from PDD, ask backend to generate PDD promotion link
      if (p.platform == 'pdd') {
        try {
          // 从设置中读取用户配置的 PDD uid，未配置则传空字符串
          String pddUid = '';
          try {
            final settingsBox = await HiveConfig.getBox(HiveConfig.settingsBox);
            pddUid = (settingsBox.get(HiveConfig.pddUidKey) as String?) ?? '';
          } catch (e, st) {
            log('Error reading PDD uid from settings: $e', name: 'ProductService', error: e, stackTrace: st);
          }
          final customParams = pddUid.isNotEmpty ? '{"uid":"$pddUid"}' : '';
          final signResp = await _client.post('$backend/sign/pdd', data: {'goods_sign_list': [p.id], if (customParams.isNotEmpty) 'custom_parameters': customParams});
          if (signResp.data != null && signResp.data is Map) {
            final m = Map<String, dynamic>.from(signResp.data as Map);
            String? link;

            // 响应结构：{ goods_promotion_url_generate_response: { goods_promotion_url_list: [...] } }
            try {
              final resp = m['goods_promotion_url_generate_response'] ?? m['response']?['goods_promotion_url_generate_response'];
              if (resp is Map && resp['goods_promotion_url_list'] is List && (resp['goods_promotion_url_list'] as List).isNotEmpty) {
                final entry = (resp['goods_promotion_url_list'] as List).first as Map<String, dynamic>;
                link = (entry['mobile_short_url'] ?? entry['short_url'] ?? entry['mobile_url'] ?? entry['url'])?.toString();
              }
            } catch (e, st) { log('ProductService PDD parse error: $e', name: 'ProductService', error: e, stackTrace: st); }

            if (link != null && link.isNotEmpty) {
              final expiry = now + 30 * 60 * 1000;
              _promoCache[p.id] = {'link': link, 'expiry': expiry};
              try {
                final box = await HiveConfig.getBox(HiveConfig.promoCacheBox);
                await box.put(p.id, {'link': link, 'expiry': expiry});
              } catch (e, st) { log('ProductService cache write error: $e', name: 'ProductService', error: e, stackTrace: st); }
              return link;
            }
          }
        } catch (e, st) { log('ProductService PDD sign error: $e', name: 'ProductService', error: e, stackTrace: st); }
        // PDD 获取失败时直接返回商品页链接，不继续走其他平台的逻辑
        return 'https://mobile.yangkeduo.com/goods.html?goods_id=${p.id}';
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
            } catch (e, st) { log('ProductService cache/parse error: $e', name: 'ProductService', error: e, stackTrace: st); }
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
              await HiveConfig.getBox(HiveConfig.promoCacheBox);
              final box = await HiveConfig.getBox(HiveConfig.promoCacheBox);
              await box.put(p.id, {'link': link, 'expiry': expiry});
            } catch (e, st) { log('ProductService cache/parse error: $e', name: 'ProductService', error: e, stackTrace: st); }
            return link;
          }
        }
      } catch (e) {
        log('Taobao convert fallback failed for ${p.id}: $e', name: 'ProductService');
      }
    } catch (e) {
      log('generatePromotionLink outer error for ${p.id} (${p.platform}): $e', name: 'ProductService');
    }

    return null;
  }
}


import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/api_client.dart';
import '../../core/pdd_client.dart';
import '../../core/config.dart';
import 'product_model.dart';
import 'pdd_product_model.dart';

/// PDD Adapter：负责调用多多进宝搜索并映射到 ProductModel
class PddAdapter {
  final ApiClient _client;
  final PddClient _pdd;

  PddAdapter({ApiClient? client}) : _client = client ?? ApiClient(), _pdd = PddClient(clientId: Config.pddClientId, clientSecret: Config.pddClientSecret, pid: Config.pddPid);

  Future<List<ProductModel>> search(String keyword, {int page = 1, int pageSize = 20, bool withCoupon = false}) async {
    final biz = <String, dynamic>{
      'keyword': keyword,
      'page': page,
      'page_size': pageSize,
      'pid': Config.pddPid,
      'with_coupon': withCoupon,
    };

    final resp = await _pdd.searchGoods(biz);
    Map<String, dynamic> body = {};
    try {
      if (resp is Map && resp.containsKey('error') && resp['error'] == true) {
        // return empty list on error to keep callers simple; caller can inspect logs
        return [];
      }
      if (resp is Map && resp['goods_search_response'] != null) body = Map<String, dynamic>.from(resp['goods_search_response'] as Map);
      else if (resp is Map) body = resp as Map<String, dynamic>;
    } catch (_) {
      return [];
    }

    final List items = body['goods_list'] is List ? body['goods_list'] as List : (body['goods_list'] != null ? [body['goods_list']] : []);

    final futures = items.map((e) async {
      final m = Map<String, dynamic>.from(e as Map);
      final p = PddProduct.fromJson(m);
      // attempt to build a promotion link via backend proxy if possible
      String link = '';
      try {
      String backend = 'http://localhost:8080';
        try {
          if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
          final box = Hive.box('settings');
          final String? b = box.get('backend_base') as String?;
          if (b != null && b.trim().isNotEmpty) backend = b.trim();
          else backend = Platform.environment['BACKEND_BASE'] ?? backend;
        } catch (_) {}
        // request backend to generate pdd promotion link if backend supports it
        try {
          final signResp = await _client.post('$backend/sign/pdd', data: {'goods_sign': p.goodsSign});
          if (signResp.data is Map && signResp.data['clickURL'] != null) link = signResp.data['clickURL'] as String;
        } catch (_) {}
      } catch (_) {}

      // parse sales from sales_tip like "521" or "28.8万+"
      int sales = 0;
      try {
        final st = (m['sales_tip'] ?? m['salesTip'] ?? m['sales_tip'] ?? '')?.toString() ?? '';
        if (st.isNotEmpty) {
          // try to extract number, handle '万' unit
          final wMatch = RegExp(r"([0-9]+\.?[0-9]*)万").firstMatch(st);
          if (wMatch != null) {
            final numv = double.tryParse(wMatch.group(1)!) ?? 0.0;
            sales = (numv * 10000).toInt();
          } else {
            final n = RegExp(r"(\d+)").firstMatch(st)?.group(1);
            if (n != null) sales = int.tryParse(n) ?? 0;
          }
        }
      } catch (_) {}

      // description fallback: goods_desc / desc_txt
      String desc = '';
      try {
        desc = (m['goods_desc'] ?? m['desc_txt'] ?? m['description'] ?? '')?.toString() ?? '';
      } catch (_) {}

      // shop title: prefer brand_name, then mall_name / opt_name
      String shopTitle = '';
      try {
        shopTitle = (m['brand_name'] ?? m['mall_name'] ?? m['mallName'] ?? m['opt_name'] ?? '')?.toString() ?? '';
      } catch (_) {}

      // tags: unified_tags
      List<String> tags = [];
      try {
        final ut = m['unified_tags'] ?? m['unifiedTags'];
        if (ut is List) tags = ut.map((e) => e.toString()).toList();
        else if (ut is String) tags = [ut];
      } catch (_) {}

      return ProductModel(
        id: p.goodsSign,
        platform: 'pdd',
        title: p.name,
        price: (p.minGroupPrice / 100.0),
        originalPrice: (p.minNormalPrice / 100.0),
        coupon: (p.couponDiscount / 100.0),
        finalPrice: (p.minGroupPrice / 100.0) - (p.couponDiscount / 100.0),
        imageUrl: p.imageUrl,
        sales: sales,
        rating: 0.0,
        link: link,
        commission: (p.promotionRate / 1000.0) * (p.minGroupPrice / 100.0),
        description: desc,
        shopTitle: shopTitle,
      );
    }).toList();

    return await Future.wait(futures);
  }
}


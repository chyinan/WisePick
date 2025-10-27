import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'product_model.dart';

class SearchService {
  final String baseUrl;

  SearchService({String? baseUrl}) : baseUrl = baseUrl ?? _resolveBackendBase();

  static String _resolveBackendBase() {
    String backend = 'http://localhost:8080';
    try {
      if (Hive.isBoxOpen('settings')) {
        final box = Hive.box('settings');
        final String? b = box.get('backend_base') as String?;
        if (b != null && b.trim().isNotEmpty) return b.trim();
      }
    } catch (_) {}
    return Platform.environment['BACKEND_BASE'] ?? backend;
  }

  Future<List<ProductModel>> search(String query, {int page = 1, int pageSize = 20, String? platform}) async {
    final uri = Uri.parse('$baseUrl/api/products/search?query=${Uri.encodeComponent(query)}&page_no=$page&page_size=$pageSize' + (platform != null ? '&platform=${Uri.encodeComponent(platform)}' : ''));
    final resp = await http.get(uri);
    if (resp.statusCode != 200) throw Exception('search failed ${resp.statusCode}');
    final Map<String, dynamic> body = Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
    final List items = (body['products'] is List) ? (body['products'] as List) : (body['products'] ?? []);
    return items.map((m) => ProductModel.fromMap(Map<String, dynamic>.from(m))).toList();
  }

  /// 返回带元信息的完整响应，包含 products 和 attempts（若后端提供）
  Future<Map<String, dynamic>> searchWithMeta(String query, {int page = 1, int pageSize = 20, String? platform}) async {
    final q = Uri.encodeComponent(query);
    final p = page.toString();
    final ps = pageSize.toString();
    final uri = Uri.parse('$baseUrl/api/products/search?query=$q&page_no=$p&page_size=$ps' + (platform != null ? '&platform=${Uri.encodeComponent(platform)}' : ''));
    final resp = await http.get(uri);
    if (resp.statusCode != 200) throw Exception('search failed ${resp.statusCode}');
    final Map body = jsonDecode(resp.body) as Map;
    final List items = body['products'] ?? [];
    final products = items.map((m) => ProductModel.fromMap(Map<String, dynamic>.from(m))).toList();
    // If backend included raw JD response, attempt to map and merge JD Paragraphs
    try {
      final raw = body['raw_jd'] ?? body['raw'] ?? body;
      if (raw is Map) {
        final Map<String, dynamic> rawMap = Map<String, dynamic>.from(raw as Map);
        final jdRootDynamic = rawMap['jingdong_search_ware_responce'];
        if (jdRootDynamic is Map) {
          final Map<String, dynamic> jdRoot = Map<String, dynamic>.from(jdRootDynamic as Map);
          final List<ProductModel> jdProducts = _mapJdSearchWare(jdRoot);
          if (jdProducts.isNotEmpty) {
            // merge avoiding duplicates by id
            final ids = products.map((p) => p.id).toSet();
            for (final jp in jdProducts) {
              if (!ids.contains(jp.id)) {
                products.add(jp);
                ids.add(jp.id);
              }
            }
          }
        }
      }
    } catch (_) {}
    final attempts = body['attempts'] ?? [];
    return {'products': products, 'attempts': attempts, 'raw': body};
  }

  /// 并行请求后端：同时向 taobao 和 jd 发起请求并合并结果（去重）。当某一方不可用时返回另一方结果。
  Future<Map<String, dynamic>> searchParallel(String query, {int page = 1, int pageSize = 20}) async {
    // 后端负责同时查询多个平台并返回聚合结果。
    // 直接调用后端的 searchWithMeta 统一接口，由后端决定如何并行调用各平台并合并。
    return await searchWithMeta(query, page: page, pageSize: pageSize);
  }

  List<ProductModel> _mapJdSearchWare(Map<String, dynamic> jdRoot) {
    try {
      List<dynamic>? paras;
      if (jdRoot.containsKey('Paragraph') && jdRoot['Paragraph'] is List) paras = jdRoot['Paragraph'] as List<dynamic>;
      else if (jdRoot.containsKey('Head') && jdRoot['Head'] is Map && jdRoot['Head']['Paragraph'] is List) paras = jdRoot['Head']['Paragraph'] as List<dynamic>;
      if (paras == null) return [];
      final out = <ProductModel>[];
      for (final it in paras) {
        if (it is! Map) continue;
        final id = (it['wareid'] ?? it['wareId'] ?? '').toString();
        String title = '';
        try {
          if (it['Content'] is Map) title = (it['Content']['warename'] ?? it['Content']['wareName'] ?? '').toString();
          if (title.isNotEmpty) title = Uri.decodeComponent(title);
        } catch (_) {}
        String imageUrl = '';
        try {
          if (it['Content'] is Map && it['Content']['imageurl'] != null) imageUrl = it['Content']['imageurl'].toString();
          else if (it['SlaveWare'] is List && it['SlaveWare'].isNotEmpty) {
            final sw = it['SlaveWare'][0];
            if (sw is Map && sw['Content'] is Map && sw['Content']['imageurl'] != null) imageUrl = sw['Content']['imageurl'].toString();
          }
          if (imageUrl.isNotEmpty && !imageUrl.startsWith('http')) imageUrl = 'https://img.360buyimg.com/' + imageUrl.replaceAll(RegExp(r'^/+'), '');
        } catch (_) {}
        final sales = (num.tryParse((it['good'] ?? it['sales'] ?? '0').toString()) ?? 0).toInt();
        final shopTitle = (it['shop_id'] ?? it['shopId'] ?? it['shopTitle'] ?? '').toString();
        out.add(ProductModel(
          id: id.isEmpty ? '${title.hashCode}' : id,
          platform: 'jd',
          title: title.isEmpty ? (it['title'] ?? '').toString() : title,
          price: 0.0,
          originalPrice: 0.0,
          coupon: 0.0,
          finalPrice: 0.0,
          imageUrl: imageUrl,
          sales: sales,
          rating: 0.0,
          link: '',
          commission: 0.0,
          shopTitle: shopTitle,
          description: title,
        ));
      }
      return out;
    } catch (_) {
      return [];
    }
  }
}


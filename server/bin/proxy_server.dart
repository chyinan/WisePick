import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf_io.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'dart:async';

// NOTE: veapi support removed per user request

// In-memory last-return debug store. Use the endpoint /__debug/last_return to inspect.
Map<String, dynamic>? _lastReturnDebug;
// History buffer of recent returns for deeper debugging
final List<Map<String, dynamic>> _lastReturnHistory = <Map<String, dynamic>>[];
// Simple in-memory price cache: sku -> {price, expiry}
final Map<String, Map<String, dynamic>> _priceCache = <String, Map<String, dynamic>>{};

// Normalize JD image URL fragments into full absolute URLs.
// Handles cases like:
// - already absolute (http/https) -> return as-is
// - protocol-relative (//img...) -> prefix with https:
// - hostless paths or hosts without scheme (img.360buyimg.com/...) -> prefix with https://
// - plain path (jfs/...) -> prefix with https://img.360buyimg.com/
String _normalizeJdImageUrl(dynamic raw) {
  try {
    if (raw == null) return '';
    var s = raw.toString().trim();
    if (s.isEmpty) return '';
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    if (s.startsWith('//')) return 'https:$s';

    // If the path looks like JD 'jfs/...' or 'sku/...' fragments, use the img30 sku host
    // Example: jfs/t1/311853/... -> https://img30.360buyimg.com/sku/jfs/t1/311853/...
    if (s.startsWith('jfs/') || s.startsWith('sku/') || s.contains(RegExp(r'jfs/'))) {
      return 'https://img30.360buyimg.com/sku/' + s.replaceAll(RegExp(r'^/+'), '');
    }

    // if contains known JD image hosts but missing scheme, preserve host and add scheme
    if (s.contains('360buyimg.com') || s.contains('jdimg.com')) {
      return s.startsWith('/') ? 'https:${s}' : 'https://$s';
    }

    // fallback: assume it's a JD image fragment and use img30 sku host
    return 'https://img30.360buyimg.com/sku/' + s.replaceAll(RegExp(r'^/+'), '');
  } catch (_) {
    return raw?.toString() ?? '';
  }
}

Future<Response> _handleProxy(Request req) async {
  try {
    final env = Platform.environment;
    final targetUrl = env['OPENAI_API_URL'] ?? 'https://api.openai.com/v1/chat/completions';
    final apiKey = env['OPENAI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      return Response(500, body: jsonEncode({'error': 'OPENAI_API_KEY not set'}), headers: {'content-type': 'application/json'});
    }

    // Read incoming request body
    final bodyBytes = await req.read().expand((x) => x).toList();
    final reqBodyStr = utf8.decode(bodyBytes);

    // If this is a signing proxy path (we will expose endpoints to sign for Taobao/JD), handle accordingly
    final path = req.requestedUri.path;
    if (path == '/sign/taobao' || path == '/sign/jd') {
      try {
        final env = Platform.environment;
        final secretKey = path == '/sign/taobao' ? env['TAOBAO_APP_SECRET'] : env['JD_APP_SECRET'];
        if (secretKey == null) return Response.internalServerError(body: jsonEncode({'error': 'secret not configured'}), headers: {'content-type': 'application/json'});

        // compute HMAC-SHA256 of body + ts if provided
        final ts = req.headers['x-ts'] ?? DateTime.now().toUtc().toIso8601String();
        final dataToSign = reqBodyStr + ts;
        final hmac = Hmac(sha256, utf8.encode(secretKey));
        final digest = hmac.convert(utf8.encode(dataToSign));
        final signature = digest.toString();

        // VEAPI support removed

        return Response.ok(jsonEncode({'ts': ts, 'sign': signature}), headers: {'content-type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': e.toString()}), headers: {'content-type': 'application/json'});
      }
    }

    // Check whether the client requested a streaming response
    bool wantsStream = false;
    try {
      final decoded = jsonDecode(reqBodyStr);
      if (decoded is Map && decoded['stream'] == true) {
        wantsStream = true;
      }
    } catch (_) {
      // ignore parse errors, assume non-stream
    }

    if (!wantsStream) {
      // Non-streaming: simple POST and return full body
      final upstreamResp = await http.post(
        Uri.parse(targetUrl),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: reqBodyStr,
      );

      return Response(upstreamResp.statusCode, body: upstreamResp.body, headers: {
        'content-type': upstreamResp.headers['content-type'] ?? 'application/json',
        'access-control-allow-origin': '*',
        'access-control-allow-methods': 'POST, OPTIONS',
        'access-control-allow-headers': 'Origin, Content-Type, Accept, Authorization'
      });
    }

    // Streaming: use a low-level request to forward the streamed bytes
    final client = http.Client();
    final upstreamReq = http.Request('POST', Uri.parse(targetUrl));
    upstreamReq.headers.addAll({
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    });
    upstreamReq.body = reqBodyStr;

    final streamedResp = await client.send(upstreamReq);

    // Build a Shelf Response that proxies the upstream byte stream directly
    final proxiedStream = streamedResp.stream.map((chunk) => chunk);

    final respHeaders = <String, String>{
      'content-type': streamedResp.headers['content-type'] ?? 'text/event-stream',
      'access-control-allow-origin': '*',
      'access-control-allow-methods': 'POST, OPTIONS',
      'access-control-allow-headers': 'Origin, Content-Type, Accept, Authorization'
    };

    return Response(streamedResp.statusCode, body: proxiedStream, headers: respHeaders);
  } catch (e) {
    return Response.internalServerError(body: jsonEncode({'error': e.toString()}), headers: {'content-type': 'application/json'});
  }
}

/// Run the full server. This was the original `main` body extracted so we can
/// optionally spawn it as a child process with injected environment variables.
Future<void> runServer(List<String> args) async {
  final router = Router();

  router.options('/<ignore|.*>', (Request r) => Response(200, headers: {
        'access-control-allow-origin': '*',
        'access-control-allow-methods': 'POST, OPTIONS',
        'access-control-allow-headers': 'Origin, Content-Type, Accept, Authorization'
      }));

  // Simple settings endpoint for clients to read backend_base (optional)
  router.get('/__settings', (Request r) async {
    final env = Platform.environment;
    final backend = env['BACKEND_BASE'] ?? 'http://localhost:8080';
    return Response.ok(jsonEncode({'backend_base': backend}), headers: {'content-type': 'application/json'});
  });

// Call universal convert and normalize response to a standard map.
// NOTE: veapi support was removed and related calls were replaced by
// direct Taobao/JD proxy calls. Keep file tidy without veapi-specific routes.
  // Proxy path compatible with OpenAI client expectations
  router.post('/v1/chat/completions', _handleProxy);

  // Debug endpoint to inspect last returned payloads
  router.get('/__debug/last_return', (Request r) async {
    try {
      final params = r.requestedUri.queryParameters;
      final asHistory = params['history'] == '1';
      if (asHistory) {
        try {
          return Response.ok(jsonEncode({'ok': true, 'history': _lastReturnHistory}), headers: {'content-type': 'application/json'});
        } catch (_) {
          // fallback to safe summary
          return Response.ok(jsonEncode({'ok': true, 'history_count': _lastReturnHistory.length}), headers: {'content-type': 'application/json'});
        }
      }
      if (_lastReturnDebug == null) return Response.ok(jsonEncode({'ok': false, 'msg': 'no debug info'}), headers: {'content-type': 'application/json'});
      try {
        return Response.ok(jsonEncode(_lastReturnDebug), headers: {'content-type': 'application/json'});
      } catch (_) {
        // fallback to stringified safe summary
        return Response.ok(jsonEncode({'ok': true, 'summary': _lastReturnDebug.toString()}), headers: {'content-type': 'application/json'});
      }
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}), headers: {'content-type': 'application/json'});
    }
  });

  // Alias routes for convenience (some clients/typos use single underscore or no underscore)
  router.get('/_debug/last_return', (Request r) async {
    final params = r.requestedUri.queryParameters;
    final asHistory = params['history'] == '1';
    if (asHistory) {
      return Response.ok(jsonEncode({'ok': true, 'history': _lastReturnHistory}), headers: {'content-type': 'application/json'});
    }
    if (_lastReturnDebug == null) return Response.ok(jsonEncode({'ok': false, 'msg': 'no debug info'}), headers: {'content-type': 'application/json'});
    return Response.ok(jsonEncode(_lastReturnDebug), headers: {'content-type': 'application/json'});
  });

  router.get('/debug/last_return', (Request r) async {
    final params = r.requestedUri.queryParameters;
    final asHistory = params['history'] == '1';
    if (asHistory) {
      return Response.ok(jsonEncode({'ok': true, 'history': _lastReturnHistory}), headers: {'content-type': 'application/json'});
    }
    if (_lastReturnDebug == null) return Response.ok(jsonEncode({'ok': false, 'msg': 'no debug info'}), headers: {'content-type': 'application/json'});
    return Response.ok(jsonEncode(_lastReturnDebug), headers: {'content-type': 'application/json'});
  });

  // helper to estimate matched count in a taobao body
  int _safeMatchCount(Map<dynamic, dynamic>? b) {
    if (b == null) return 0;
    try {
      // common places to find lists
      if (b.containsKey('tbk_dg_material_optional_upgrade_response')) {
        final r = b['tbk_dg_material_optional_upgrade_response'];
        if (r is Map && r.containsKey('result_list') && r['result_list'] is Map && r['result_list']['map_data'] is List) return (r['result_list']['map_data'] as List).length;
      }
      if (b.containsKey('tbk_sc_material_optional_response')) {
        final r = b['tbk_sc_material_optional_response'];
        if (r is Map && r.containsKey('result_list') && r['result_list'] is Map && r['result_list']['map_data'] is List) return (r['result_list']['map_data'] as List).length;
      }
      if (b.containsKey('tbk_shop_get_response')) {
        final r = b['tbk_shop_get_response'];
        if (r is Map && r.containsKey('results')) {
          final res = r['results'];
          if (res is Map && res['n_tbk_shop'] is List) return (res['n_tbk_shop'] as List).length;
        }
      }
      // fallback: search for any List<Map> in body
      int count = 0;
      void _walk(dynamic node) {
        if (node is List) {
          if (node.isNotEmpty && node.first is Map) count += node.length;
          for (final e in node) _walk(e);
        } else if (node is Map) {
          for (final v in node.values) _walk(v);
        }
      }
      _walk(b);
      return count;
    } catch (_) {
      return 0;
    }
  }

  // Generate candidate simplified queries from original query.
  // Rules: remove parenthesis content, split on /, remove common noise words, keep brand+model combos.
  List<String> _generateCandidates(String q) {
    try {
      var s = q.trim();
      // remove content inside parentheses/brackets
      s = s.replaceAll(RegExp(r"\([^)]*\)"), ' ');
      s = s.replaceAll(RegExp(r"\[[^\]]*\]"), ' ');
      // split on slashes and commas
      final parts = s.split(RegExp(r'[\\/,&]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      final tokens = <String>[];
      for (final p in parts) {
        // split by whitespace
        for (final t in p.split(RegExp(r'\s+'))) {
          final tt = t.trim();
          if (tt.isEmpty) continue;
          tokens.add(tt);
        }
      }
      // remove common noise words
      final noise = {'纯', 'USB', 'DAC', '耳放', '桌面', '旗舰', '版', '型', '款'};
      final filtered = tokens.where((t) => !noise.contains(t)).toList();
      final candidates = <String>[];
      // full simplified (join parts)
      final full = filtered.join(' ');
      if (full.isNotEmpty) candidates.add(full);
      // brand + first token
      if (filtered.length >= 2) {
        candidates.add('${filtered[0]} ${filtered[1]}');
      }
      // model-only tokens (longest tokens first)
      final byLen = filtered.toList()..sort((a, b) => b.length.compareTo(a.length));
      for (final t in byLen) {
        if (!candidates.contains(t)) candidates.add(t);
      }
      // also include original words parts (up to 6)
      for (final p in parts) {
        if (!candidates.contains(p) && candidates.length < 6) candidates.add(p);
      }
      // ensure uniqueness and limit
      final uniq = <String>[];
      for (final c in candidates) {
        final cc = c.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (cc.isEmpty) continue;
        if (!uniq.contains(cc)) uniq.add(cc);
        if (uniq.length >= 6) break;
      }
      return uniq;
    } catch (_) {
      return [q];
    }
  }

  // 标准化商品搜索接口：优先使用淘宝（若配置 TAOBAO_APP_KEY），否则回退到 veapi
  // 返回格式：{ "products": [ {..ProductModel.toMap()..}, ... ], "source": "taobao"|"veapi" }
  router.get('/api/products/search', (Request r) async {
    final params = r.requestedUri.queryParameters;
    final query = params['query'] ?? params['q'] ?? params['para'] ?? '';
    if (query.isEmpty) return Response(400, body: jsonEncode({'error': 'query parameter required'}), headers: {'content-type': 'application/json'});

    // decide source
    final env = Platform.environment;
    final useTaobao = env['TAOBAO_APP_KEY'] != null && (env['TAOBAO_APP_KEY']?.isNotEmpty ?? false);
    final useJd = env['JD_APP_KEY'] != null && (env['JD_APP_KEY']?.isNotEmpty ?? false);
    final platformParam = (params['platform'] ?? '').toString().toLowerCase();

    try {
      Map<String, dynamic> body = {};
      String source = 'unknown';

      // collect attempts for this request to return to client
      final List<Map<String, dynamic>> attemptsLocal = [];

      // If caller explicitly requested JD, prefer jingdong.search.ware (newer public search API)
      if (platformParam == 'jd' && useJd) {
        try {
          final appKeyEnv = env['JD_APP_KEY'];
          final appSecretEnv = env['JD_APP_SECRET'];
          if (appKeyEnv == null || appSecretEnv == null) throw Exception('JD keys not configured');
          final beijing2 = DateTime.now().toUtc().add(Duration(hours: 8));
          String two2(int n) => n.toString().padLeft(2, '0');
          final ts2 = '${beijing2.year}-${two2(beijing2.month)}-${two2(beijing2.day)} ${two2(beijing2.hour)}:${two2(beijing2.minute)}:${two2(beijing2.second)}';
          final paramsMap = <String, String>{
            'method': 'jingdong.search.ware',
            'app_key': appKeyEnv,
            'v': '2.0',
            'format': 'json',
            // JD search 'key' must be URL-encoded to avoid illegal characters (spaces etc.)
            // Use the encoded value both for the request body and for signature calculation below.
            'key': Uri.encodeComponent(query),
            'page': params['page'] ?? params['pageIndex'] ?? '1',
            'charset': 'utf-8',
            'urlencode': 'yes',
            'timestamp': ts2,
          };
          final keys = paramsMap.keys.toList()..sort();
          final sb = StringBuffer();
          sb.write(appSecretEnv);
          for (final k in keys) {
            sb.write(k);
            sb.write(paramsMap[k]);
          }
          sb.write(appSecretEnv);
          final sign = md5.convert(utf8.encode(sb.toString())).toString().toUpperCase();
          paramsMap['sign'] = sign;
          http.Response resp;
          String respBody = '';
          int respStatus = 0;
          try {
            resp = await http.post(Uri.parse('https://api.jd.com/routerjson'), headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: paramsMap).timeout(Duration(seconds: 8));
            respStatus = resp.statusCode;
            respBody = resp.body;
            if (respStatus != 200) {
              // record debug info and treat as failure so we don't silently return wrong data
              final dbg = {'reqParams': paramsMap, 'signBase': sb.toString(), 'respStatus': respStatus, 'respBody': respBody};
              try {
                attemptsLocal.add({'attempt': 'jd_search_http_error', 'debug': dbg});
                final rec = {'path': '/api/products/search', 'query': query, 'err': dbg, 'ts': DateTime.now().toIso8601String()};
                _lastReturnDebug = rec;
                _lastReturnHistory.add(rec);
                if (_lastReturnHistory.length > 20) _lastReturnHistory.removeAt(0);
              } catch (_) {}
              throw Exception('jingdong.search.ware failed ${respStatus}');
            }

            final parsed = jsonDecode(respBody) as Map<String, dynamic>;
            if (!parsed.containsKey('jingdong_search_ware_responce')) {
              final dbg2 = {'reqParams': paramsMap, 'signBase': sb.toString(), 'respBody': respBody};
              try {
                attemptsLocal.add({'attempt': 'jd_search_unexpected_body', 'debug': dbg2});
                final rec = {'path': '/api/products/search', 'query': query, 'err': dbg2, 'ts': DateTime.now().toIso8601String()};
                _lastReturnDebug = rec;
                _lastReturnHistory.add(rec);
                if (_lastReturnHistory.length > 20) _lastReturnHistory.removeAt(0);
              } catch (_) {}
              throw Exception('jingdong.search.ware returned unexpected structure');
            }

            body = parsed;
            source = 'jd_search';
          } catch (e) {
            rethrow;
          }
        } catch (e) {
          // If caller explicitly requested JD, do NOT fallback to Taobao — return empty JD response.
          // Falling back would cause duplicate Taobao results when the caller intended JD-only.
          if (platformParam == 'jd') {
            try {
              attemptsLocal.add({'attempt': 'jd_search_failed', 'debug': e.toString()});
            } catch (_) {}
            final outEmpty = {'products': <dynamic>[], 'source': 'jd', 'attempts': attemptsLocal, 'total': 0};
            return Response.ok(jsonEncode(outEmpty), headers: {'content-type': 'application/json'});
          }

          // Otherwise, if JD search failed and caller did not explicitly request JD,
          // we may fall back to Taobao when configured.
          if (useTaobao) {
            final uri = Uri.parse('http://localhost:8080/taobao/tbk_search?para=${Uri.encodeComponent(query)}');
            final resp = await http.get(uri).timeout(Duration(seconds: 8));
            if (resp.statusCode != 200) throw Exception('taobao proxy failed ${resp.statusCode}');
            body = jsonDecode(resp.body) as Map<String, dynamic>;
            source = 'taobao';
          } else {
            return Response.internalServerError(body: jsonEncode({'error': 'no data source configured'}), headers: {'content-type': 'application/json'});
          }
        }
      } else if (platformParam == 'pdd') {
        // Explicit PDD-only request: call pdd.ddk.goods.search and return mapped products
        try {
          final pddClientId = env['PDD_CLIENT_ID'];
          final pddClientSecret = env['PDD_CLIENT_SECRET'];
          final pddPid = env['PDD_PID'] ?? '';
          if (pddClientId == null || pddClientSecret == null || pddClientId.isEmpty) {
            return Response.internalServerError(body: jsonEncode({'error': 'PDD_CLIENT_ID/PDD_CLIENT_SECRET not configured'}), headers: {'content-type': 'application/json'});
          }

          final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
          final biz = <String, dynamic>{
            'client_id': pddClientId,
            'type': 'pdd.ddk.goods.search',
            'data_type': 'JSON',
            'timestamp': ts,
            'keyword': query,
            'page': params['page'] ?? params['pageIndex'] ?? '1',
            'page_size': params['page_size'] ?? params['pageSize'] ?? '20',
          };
          // Ensure custom_parameters is provided (PDD often requires this for member binding/备案)
          // Use a stable uid tag so member authority checks can match the PID binding used during 测试/备案.
          if (!biz.containsKey('custom_parameters')) {
            biz['custom_parameters'] = '{"uid":"chyinan"}';
          }
          if (pddPid.isNotEmpty) biz['pid'] = pddPid;
          if (params.containsKey('with_coupon')) biz['with_coupon'] = params['with_coupon'];

          final keys = biz.keys.toList()..sort();
          final sb = StringBuffer();
          sb.write(pddClientSecret);
          for (final k in keys) {
            sb.write(k);
            final v = biz[k];
            if (v is String) sb.write(v);
            else sb.write(jsonEncode(v));
          }
          sb.write(pddClientSecret);
          final sign = md5.convert(utf8.encode(sb.toString())).toString().toUpperCase();

          final form = <String, String>{};
          biz.forEach((k, v) {
            if (v == null) return;
            if (v is String) form[k] = v;
            else form[k] = jsonEncode(v);
          });
          form['sign'] = sign;

          final respP = await http.post(Uri.parse('https://gw-api.pinduoduo.com/api/router'), headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: form).timeout(Duration(seconds: 8));
          if (respP.statusCode != 200) {
            final dbg = {'status': respP.statusCode, 'body': respP.body};
            attemptsLocal.add({'attempt': 'pdd_search_http_error', 'debug': dbg});
            return Response.internalServerError(body: jsonEncode({'error': 'pdd api failed', 'detail': dbg}), headers: {'content-type': 'application/json'});
          }

          final Map<String, dynamic> pbody = jsonDecode(respP.body) as Map<String, dynamic>;
          final goodsResp = (pbody['goods_search_response'] is Map) ? pbody['goods_search_response'] as Map<String, dynamic> : null;
          final List<Map<String, dynamic>> pProducts = [];
          if (goodsResp != null && goodsResp['goods_list'] is List) {
            final gl = goodsResp['goods_list'] as List<dynamic>;
            for (final it in gl) {
              if (it is Map) {
                final m = Map<String, dynamic>.from(it as Map);
                try {
                  final id = (m['goods_sign'] ?? '').toString();
                  final title = (m['goods_name'] ?? '').toString();
                  final image = (m['goods_image_url'] ?? m['goods_thumbnail_url'] ?? '').toString();
                  final minGroup = ((m['min_group_price'] is num) ? (m['min_group_price'] as num).toDouble() : (double.tryParse((m['min_group_price'] ?? '0').toString()) ?? 0.0)) / 100.0;
                  final minNorm = ((m['min_normal_price'] is num) ? (m['min_normal_price'] as num).toDouble() : (double.tryParse((m['min_normal_price'] ?? '0').toString()) ?? 0.0)) / 100.0;
                  final coupon = ((m['coupon_discount'] is num) ? (m['coupon_discount'] as num).toDouble() : (double.tryParse((m['coupon_discount'] ?? '0').toString()) ?? 0.0)) / 100.0;
                  int sales = 0;
                  try {
                    final st = (m['sales_tip'] ?? '').toString();
                    if (st.contains('万')) {
                      final wm = RegExp(r"([0-9]+\.?[0-9]*)万").firstMatch(st);
                      if (wm != null) sales = (double.parse(wm.group(1)!) * 10000).toInt();
                    } else {
                      final n = RegExp(r"(\d+)").firstMatch(st)?.group(1);
                      if (n != null) sales = int.tryParse(n) ?? 0;
                    }
                  } catch (_) {}
                  // Prefer brand_name if present, otherwise fall back to mall_name / opt_name
                  final shopTitle = (m['brand_name'] ?? m['brandName'] ?? m['mall_name'] ?? m['mallName'] ?? m['opt_name'] ?? '')?.toString() ?? '';
                  final desc = (m['goods_desc'] ?? m['desc_txt'] ?? '').toString();

                  pProducts.add({
                    'id': id.isEmpty ? '${title.hashCode}' : id,
                    'platform': 'pdd',
                    'title': title,
                    'price': minGroup,
                    'original_price': minNorm,
                    'coupon': coupon,
                    'final_price': (minGroup - coupon),
                    'image_url': image,
                    'sales': sales,
                    'rating': 0.0,
                    'link': '',
                    'commission': ((m['promotion_rate'] is num) ? (m['promotion_rate'] as num).toDouble() : (double.tryParse((m['promotion_rate'] ?? '0').toString()) ?? 0.0)) / 1000.0 * minGroup,
                    'description': desc,
                    'shop_title': shopTitle,
                  });
                } catch (_) {}
              }
            }
          }

          final out = {'products': pProducts, 'source': 'pdd', 'attempts': attemptsLocal, 'total': pProducts.length};
          return Response.ok(jsonEncode(out), headers: {'content-type': 'application/json'});
        } catch (e) {
          return Response.internalServerError(body: jsonEncode({'error': e.toString()}), headers: {'content-type': 'application/json'});
        }
      } else if (useTaobao) {
        // call local taobao proxy route we already implemented
        final uri = Uri.parse('http://localhost:8080/taobao/tbk_search?para=${Uri.encodeComponent(query)}');
        final resp = await http.get(uri).timeout(Duration(seconds: 8));
        if (resp.statusCode != 200) throw Exception('taobao proxy failed ${resp.statusCode}');
        body = jsonDecode(resp.body) as Map<String, dynamic>;
        // record initial attempt
        try {
          final rec = {'attempt': 'initial', 'query': query, 'body': body, 'ts': DateTime.now().toIso8601String()};
          attemptsLocal.add({'attempt': 'initial', 'query': query, 'matched': _safeMatchCount(body)});
          _lastReturnDebug = rec;
          _lastReturnHistory.add(rec);
          if (_lastReturnHistory.length > 20) _lastReturnHistory.removeAt(0);
        } catch (_) {}
        source = 'taobao';
      } else {
        // fallback to veapi or JD when configured
        final veApiKey = env['VEAPI_KEY'];
        if ((platformParam == 'jd' || !useTaobao) && useJd) {
          // If the caller requested JD or Taobao is not configured, prefer JD
          try {
            final uri = Uri.parse('http://localhost:8080/jd/union/goods/query?keyword=${Uri.encodeComponent(query)}&pageIndex=${params['page'] ?? params['pageIndex'] ?? '1'}&pageSize=${params['page_size'] ?? params['pageSize'] ?? '20'}');
            final resp = await http.get(uri).timeout(Duration(seconds: 8));
            if (resp.statusCode != 200) throw Exception('jd proxy failed ${resp.statusCode}');
            // attempt parse JD union response
            Map<String, dynamic> jdBody = {};
            try {
              jdBody = jsonDecode(resp.body) as Map<String, dynamic>;
            } catch (_) {}

            // If JD returned a permission/sign error, fallback to jingdong.search.ware
            bool needFallbackToSearchWare = false;
            try {
              // jd_union_open_goods_query_responce -> queryResult may be stringified JSON
              if (jdBody.containsKey('jd_union_open_goods_query_responce')) {
                final inner = jdBody['jd_union_open_goods_query_responce'];
                if (inner is Map && inner['queryResult'] != null) {
                  final qrRaw = inner['queryResult'];
                  String qrStr = qrRaw is String ? qrRaw : jsonEncode(qrRaw);
                  try {
                    final qr = jsonDecode(qrStr) as Map<String, dynamic>;
                    if (qr['code'] != null && (qr['code'].toString() == '403' || qr['code'].toString() == '12')) {
                      needFallbackToSearchWare = true;
                    }
                  } catch (_) {}
                }
              }
              // Also check for top-level error_response code indicating invalid signature
              if (jdBody.containsKey('error_response')) {
                final er = jdBody['error_response'];
                if (er is Map && er['code'] != null && er['code'].toString() == '12') needFallbackToSearchWare = true;
              }
            } catch (_) {}

            if (!needFallbackToSearchWare) {
              body = jdBody;
              source = 'jd';
            } else {
              // call jingdong.search.ware as fallback (method version 2.0)
              try {
                final appKeyEnv = env['JD_APP_KEY'];
                final appSecretEnv = env['JD_APP_SECRET'];
                if (appKeyEnv == null || appSecretEnv == null) throw Exception('JD keys not configured');
                final beijing2 = DateTime.now().toUtc().add(Duration(hours: 8));
                String two2(int n) => n.toString().padLeft(2, '0');
                final ts2 = '${beijing2.year}-${two2(beijing2.month)}-${two2(beijing2.day)} ${two2(beijing2.hour)}:${two2(beijing2.minute)}:${two2(beijing2.second)}';
                final paramsMap = <String, String>{
                  'method': 'jingdong.search.ware',
                  'app_key': appKeyEnv,
                  'v': '2.0',
                  'format': 'json',
                  // ensure key is URL-encoded to avoid Illegal character in query errors
                  'key': Uri.encodeComponent(query),
                  'page': params['page'] ?? params['pageIndex'] ?? '1',
                  'charset': 'utf-8',
                  'urlencode': 'yes',
                  'timestamp': ts2,
                };
                final keys = paramsMap.keys.toList()..sort();
                final sb = StringBuffer();
                sb.write(appSecretEnv);
                for (final k in keys) {
                  sb.write(k);
                  sb.write(paramsMap[k]);
                }
                sb.write(appSecretEnv);
                final sign = md5.convert(utf8.encode(sb.toString())).toString().toUpperCase();
                paramsMap['sign'] = sign;
                final resp2 = await http.post(Uri.parse('https://api.jd.com/routerjson'), headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: paramsMap).timeout(Duration(seconds: 8));
                if (resp2.statusCode != 200) throw Exception('jingdong.search.ware failed ${resp2.statusCode}');
                body = jsonDecode(resp2.body) as Map<String, dynamic>;
                source = 'jd_search';
              } catch (e) {
                // final fallback: if Taobao is not available, return error
                return Response.internalServerError(body: jsonEncode({'error': 'no data source configured', 'detail': e.toString()}), headers: {'content-type': 'application/json'});
              }
            }
          } catch (e) {
            // fall back to Taobao if JD call failed
            if (useTaobao) {
              final uri = Uri.parse('http://localhost:8080/taobao/tbk_search?para=${Uri.encodeComponent(query)}');
              final resp = await http.get(uri).timeout(Duration(seconds: 8));
              if (resp.statusCode != 200) throw Exception('taobao proxy failed ${resp.statusCode}');
              body = jsonDecode(resp.body) as Map<String, dynamic>;
              source = 'taobao';
            } else {
              return Response.internalServerError(body: jsonEncode({'error': 'no data source configured'}), headers: {'content-type': 'application/json'});
            }
          }
        } else {
          // No Taobao configured and JD not selected -> error
          return Response.internalServerError(body: jsonEncode({'error': 'no data source configured'}), headers: {'content-type': 'application/json'});
        }
      }

      // 寻找包含商品列表的字段（兼容多种返回结构），递归查找首个 List<Map>
      List<dynamic>? items;
      List<dynamic>? _findListOfMaps(dynamic node) {
        if (node is List) {
          // 若列表内包含 Map 则认为是商品列表
          if (node.isNotEmpty && node.first is Map) return node;
          // 否则尝试在子元素中查找
          for (final e in node) {
            final r = _findListOfMaps(e);
            if (r != null) return r;
          }
          return null;
        }
        if (node is Map) {
          for (final v in node.values) {
            final r = _findListOfMaps(v);
            if (r != null) return r;
          }
          return null;
        }
        return null;
      }

      // Prefer explicit known Taobao response paths for reliability
      if (body is Map && body.containsKey('tbk_dg_material_optional_upgrade_response')) {
        try {
          final respMap = body['tbk_dg_material_optional_upgrade_response'];
          if (respMap is Map && respMap['result_list'] is Map && respMap['result_list']['map_data'] is List) {
            items = respMap['result_list']['map_data'] as List<dynamic>;
          }
        } catch (_) {}
      }
      if (items == null && body is Map && body.containsKey('tbk_sc_material_optional_response')) {
        try {
          final respMap = body['tbk_sc_material_optional_response'];
          if (respMap is Map && respMap['result_list'] is Map && respMap['result_list']['map_data'] is List) {
            items = respMap['result_list']['map_data'] as List<dynamic>;
          }
        } catch (_) {}
      }
      if (items == null && body is Map && body.containsKey('tbk_dg_material_optional_response')) {
        try {
          final respMap = body['tbk_dg_material_optional_response'];
          if (respMap is Map && respMap['result_list'] is Map && respMap['result_list']['map_data'] is List) {
            items = respMap['result_list']['map_data'] as List<dynamic>;
          }
        } catch (_) {}
      }

      // Fallback to recursive search
      if (items == null) items = _findListOfMaps(body);

      // If taobao returned an error or no items, attempt lightweight fallbacks:
      // 1) simplified query (strip special chars) -> retry taobao route
      // 2) shop.get to at least return shops
      try {
        bool bodyHasError = false;
        if (body is Map && body.containsKey('error_response')) bodyHasError = true;
      if (items == null || (items is List && items.isEmpty) || bodyHasError) {
          // Attempt 1: simplified query
          try {
            final candidates = _generateCandidates(query);
            for (final simplified in candidates) {
              if (simplified.isEmpty) continue;
              final uri2 = Uri.parse('http://localhost:8080/taobao/tbk_search?para=${Uri.encodeComponent(simplified)}');
              try {
                final resp2 = await http.get(uri2).timeout(Duration(seconds: 6));
                if (resp2.statusCode == 200) {
                  final body2 = jsonDecode(resp2.body) as Map<String, dynamic>;
                  final found = _findListOfMaps(body2);
                  // record attempt
                  try {
                    final rec = {'attempt': 'simplified', 'query': simplified, 'body': body2, 'ts': DateTime.now().toIso8601String()};
                    attemptsLocal.add({'attempt': 'simplified', 'query': simplified, 'matched': _safeMatchCount(body2)});
                    _lastReturnDebug = rec;
                    _lastReturnHistory.add(rec);
                    if (_lastReturnHistory.length > 20) _lastReturnHistory.removeAt(0);
                  } catch (_) {}
                  if (found != null && found.isNotEmpty) {
                    items = found;
                    body = body2;
                    bodyHasError = false;
                    break;
                  }
                }
              } catch (_) {}
            }
          } catch (_) {}

          // Attempt 2: shop.get to return shops (as fallback suggestions)
          if (items == null || (items is List && items.isEmpty)) {
            try {
              final uri3 = Uri.parse('http://localhost:8080/taobao/tbk_search?para=${Uri.encodeComponent(query)}&method=taobao.tbk.shop.get&fields=user_id,shop_title,shop_type,seller_nick,pict_url,shop_url');
              final resp3 = await http.get(uri3).timeout(Duration(seconds: 6));
              if (resp3.statusCode == 200) {
                final body3 = jsonDecode(resp3.body) as Map<String, dynamic>;
                final found3 = _findListOfMaps(body3);
                // record attempt
                try {
                  final rec = {'attempt': 'shop_get', 'query': query, 'body': body3, 'ts': DateTime.now().toIso8601String()};
                  attemptsLocal.add({'attempt': 'shop_get', 'query': query, 'matched': _safeMatchCount(body3)});
                  _lastReturnDebug = rec;
                  _lastReturnHistory.add(rec);
                  if (_lastReturnHistory.length > 20) _lastReturnHistory.removeAt(0);
                } catch (_) {}
                if (found3 != null && found3.isNotEmpty) {
                  items = found3;
                  body = body3;
                }
              }
            } catch (_) {}
          }
        }
      } catch (_) {}

      final products = <Map<String, dynamic>>[];

      // Special-case: if we used jingdong.search.ware fallback, map its Paragraph list
      try {
        if (source == 'jd_search' && body is Map && body.containsKey('jingdong_search_ware_responce')) {
          // Paragraph may be directly under the root of jingdong_search_ware_responce
          final rawJd = body['jingdong_search_ware_responce'] as Map<String, dynamic>;
          List<dynamic>? paras;
          if (rawJd.containsKey('Paragraph') && rawJd['Paragraph'] is List) {
            paras = rawJd['Paragraph'] as List<dynamic>;
          } else if (rawJd.containsKey('Head') && rawJd['Head'] is Map && rawJd['Head']['Paragraph'] is List) {
            paras = rawJd['Head']['Paragraph'] as List<dynamic>;
          }
          if (paras != null && paras is List) {
            final List<dynamic> _paras = paras;
            for (final it in _paras) {
              if (it is! Map) continue;
              // extract basic fields directly; prefer Content.warename + Content.imageurl
              final id = (it['wareid'] ?? it['wareId'] ?? '').toString();
              String title = '';
              try {
                final c = it['Content'];
                if (c is Map) {
                  title = (c['warename'] ?? c['wareName'] ?? '').toString();
                  if (title.isNotEmpty) {
                    try {
                      title = Uri.decodeComponent(title);
                    } catch (_) {}
                  }
                }
              } catch (_) {}

              String imageUrl = '';
              try {
                final c = it['Content'];
                if (c is Map && c['imageurl'] != null) imageUrl = _normalizeJdImageUrl(c['imageurl']);
                if ((imageUrl == null || imageUrl.isEmpty) && it['SlaveParagraph'] is List && it['SlaveParagraph'].isNotEmpty) {
                  final sp = it['SlaveParagraph'][0];
                  if (sp is Map && sp['SlaveContent'] is Map && sp['SlaveContent']['Slaveimageurl'] != null) imageUrl = _normalizeJdImageUrl(sp['SlaveContent']['Slaveimageurl']);
                }
                if (imageUrl != null && imageUrl.isNotEmpty) {
                  // already normalized by helper
                }
              } catch (_) {}

              int sales = 0;
              try {
                sales = (num.tryParse((it['good'] ?? it['sales'] ?? '0').toString()) ?? 0).toInt();
              } catch (_) {}

              double price = 0.0;
              try {
                // some Paragraphs don't include price; leave 0.0
                if (it.containsKey('price')) price = (num.tryParse(it['price'].toString()) ?? 0).toDouble();
              } catch (_) {}

              final link = (it['itemUrl'] ?? it['materialUrl'] ?? '').toString();

              // If id empty but Content contains slaveware, try to use first SlaveWare wareid
              String finalId = id;
              try {
                if ((finalId == null || finalId.isEmpty) && it['SlaveWare'] is List && it['SlaveWare'].isNotEmpty) {
                  final sw = it['SlaveWare'][0];
                  if (sw is Map && sw['wareid'] != null) finalId = sw['wareid'].toString();
                }
              } catch (_) {}

              // push mapped product
              products.add({
                'id': finalId ?? '',
                'platform': 'jd',
                'title': title ?? '',
                'price': price,
                'original_price': price,
                'coupon': 0.0,
                'final_price': price,
                'image_url': imageUrl ?? '',
                'sales': sales,
                'rating': 0.0,
                'link': link ?? '',
                'commission': 0.0,
                'description': title ?? '',
                'shop_title': (it['shop_id'] ?? it['shopTitle'] ?? '').toString(),
              });
            }
            // we've populated products from jd_search, skip the generic mapping below
            final out = {'products': products, 'source': source, 'attempts': attemptsLocal, 'total': products.length, 'raw_jd': body};
            try {
              final rec = {'path': '/api/products/search', 'query': query, 'out': out, 'ts': DateTime.now().toIso8601String()};
              _lastReturnDebug = rec;
              _lastReturnHistory.add(rec);
              if (_lastReturnHistory.length > 20) _lastReturnHistory.removeAt(0);
            } catch (_) {}
            return Response.ok(jsonEncode(out), headers: {'content-type': 'application/json'});
          }
        }
      } catch (_) {}
      if (items != null) {
        for (final it in items) {
          if (it is Map<String, dynamic>) {
            Map<String, dynamic> pmap;
            // Special-case: some Taobao material APIs return entries wrapped in 'item_basic_info'
            if (it.containsKey('item_basic_info') && it['item_basic_info'] is Map) {
              final basic = it['item_basic_info'] as Map<String, dynamic>;
              final id = (it['item_id'] ?? it['item_id'] ?? it['id'] ?? '').toString();
              final title = (basic['title'] ?? basic['short_title'] ?? '').toString();
              String imageUrl = (basic['pict_url'] ?? basic['pic_url'] ?? basic['white_image'] ?? '').toString();
              if (imageUrl.isEmpty && basic['small_images'] is Map && basic['small_images']['string'] is List) {
                final list = basic['small_images']['string'] as List;
                if (list.isNotEmpty) imageUrl = list[0].toString();
              }
              double price = 0.0;
              try {
                final cand = basic['zk_final_price'] ?? basic['reserve_price'] ??
                    (it['price_promotion_info'] is Map ? (it['price_promotion_info']['final_promotion_price'] ?? it['price_promotion_info']['zk_final_price'] ?? it['price_promotion_info']['reserve_price']) : null);
                price = (num.tryParse(cand?.toString() ?? '') ?? 0).toDouble();
              } catch (_) {
                price = 0.0;
              }
              double coupon = 0.0;
              try {
                final cnd = it['coupon_amount'] ?? it['coupon'] ?? (it['price_promotion_info'] is Map ? it['price_promotion_info']['coupon_amount'] ?? it['price_promotion_info']['coupon'] : null);
                coupon = (num.tryParse(cnd?.toString() ?? '') ?? 0).toDouble();
              } catch (_) {
                coupon = 0.0;
              }
              double finalPrice = 0.0;
              try {
                // prefer explicit final promotion price if present
                final fp = (it['price_promotion_info'] is Map ? (it['price_promotion_info']['final_promotion_price'] ?? it['price_promotion_info']['final_promotion_price']) : null);
                if (fp != null && fp.toString().isNotEmpty) {
                  finalPrice = (num.tryParse(fp.toString()) ?? (price - coupon)).toDouble();
                } else {
                  finalPrice = (price - coupon);
                }
              } catch (_) {
                finalPrice = (price - coupon);
              }
              int sales = (num.tryParse((basic['volume'] ?? basic['tk_total_sales'] ?? basic['sales'] ?? '0').toString()) ?? 0).toInt();
              double commission = (num.tryParse((it['commission'] ?? it['commission_rate'] ?? '0').toString()) ?? 0).toDouble();
              // Prefer coupon_share_url in publish_info, then publish_info.click_url, then other fields
              final link = (it['publish_info'] is Map && it['publish_info']['coupon_share_url'] != null)
                  ? it['publish_info']['coupon_share_url'].toString()
                  : (it['publish_info'] is Map && it['publish_info']['click_url'] != null)
                      ? it['publish_info']['click_url'].toString()
                      : (it['coupon_share_url'] ?? it['click_url'] ?? it['clickUrl'] ?? it['purl'] ?? '').toString();

              pmap = {
                'id': id,
                'platform': 'taobao',
                'title': title,
                'price': price,
                'original_price': price,
                'coupon': coupon,
                'final_price': finalPrice,
                'image_url': imageUrl,
                'sales': sales,
                'rating': 0.0,
                'link': link,
                'commission': commission,
                // expose sub_title/short_title to top-level so frontend can use them directly
                'sub_title': (basic['sub_title'] ?? '').toString(),
                'short_title': (basic['short_title'] ?? basic['short_title'] ?? basic['title'] ?? '').toString(),
                // expose shop title from nested item_basic_info when available
                'shop_title': (basic['shop_title'] ?? basic['shopTitle'] ?? '').toString(),
                // also provide a safe description field (kept for compatibility)
                // prefer short_title over sub_title for display
                'description': (basic['short_title'] ?? basic['sub_title'] ?? '').toString(),
              };
            } else if (source == 'veapi') {
              // best-effort map veapi item -> standard product map (avoid importing Flutter model)
              num? _num(Map m, List<String> keys) {
                for (final k in keys) {
                  if (m.containsKey(k) && m[k] != null) {
                    final v = m[k];
                    if (v is num) return v;
                    if (v is String) {
                      final parsed = num.tryParse(v.replaceAll(RegExp('[^0-9\.]'), ''));
                      if (parsed != null) return parsed;
                    }
    }

      // Fallback: if no products produced but JD raw response exists, try mapping Paragraph again
      try {
        if (products.isEmpty && body is Map && body.containsKey('jingdong_search_ware_responce')) {
          final rawJd2 = body['jingdong_search_ware_responce'] as Map<String, dynamic>;
          List<dynamic>? paras2;
          if (rawJd2.containsKey('Paragraph') && rawJd2['Paragraph'] is List) paras2 = rawJd2['Paragraph'] as List<dynamic>;
          else if (rawJd2.containsKey('Head') && rawJd2['Head'] is Map && rawJd2['Head']['Paragraph'] is List) paras2 = rawJd2['Head']['Paragraph'] as List<dynamic>;
          if (paras2 != null) {
            for (final it in paras2) {
              try {
                if (it is Map) {
                  final id = (it['wareid'] ?? it['wareId'] ?? '').toString();
                  String title = '';
                  try {
                    if (it['Content'] is Map) title = (it['Content']['warename'] ?? it['Content']['wareName'] ?? '').toString();
                    if (title.isNotEmpty) title = Uri.decodeComponent(title);
                  } catch (_) {}
                  String imageUrl = '';
                  try {
                    if (it['Content'] is Map && it['Content']['imageurl'] != null) imageUrl = _normalizeJdImageUrl(it['Content']['imageurl']);
                    else if (it['SlaveParagraph'] is List && it['SlaveParagraph'].isNotEmpty) {
                      final sp = it['SlaveParagraph'][0];
                      if (sp is Map && sp['SlaveContent'] is Map && sp['SlaveContent']['Slaveimageurl'] != null) imageUrl = _normalizeJdImageUrl(sp['SlaveContent']['Slaveimageurl']);
                    }
                  } catch (_) {}
                  double price = 0.0;
                  try {
                    if (it['price'] != null) price = (num.tryParse(it['price'].toString()) ?? 0).toDouble();
                  } catch (_) {}
                  final link = (it['itemUrl'] ?? it['materialUrl'] ?? '').toString();
                  products.add({
                    'id': id,
                    'platform': 'jd',
                    'title': title,
                    'price': price,
                    'original_price': price,
                    'coupon': 0.0,
                    'final_price': price,
                    'image_url': imageUrl,
                    'sales': (num.tryParse((it['good'] ?? it['sales'] ?? '0').toString()) ?? 0).toInt(),
                    'rating': 0.0,
                    'link': link,
                    'commission': 0.0,
                    'description': title ?? '',
                    'shop_title': (it['shop_id'] ?? it['shopTitle'] ?? '').toString(),
                  });
                }
              } catch (_) {}
            }
          }
        }
      } catch (_) {}
  }
  return null;
}

              String? _str(Map m, List<String> keys) {
                for (final k in keys) {
                  if (m.containsKey(k) && m[k] != null) return m[k].toString();
                }
                return null;
              }

              final id = _str(it, ['id', 'num_iid', 'item_id', 'goods_id']) ?? '';
              final title = (_str(it, ['title', 'item_title', 'name']) ?? '').trim();
              final imageUrl = _str(it, ['pic_url', 'pict_url', 'image_url', 'small_images']) ?? '';
              final price = (_num(it, ['zk_final_price', 'price', 'reserve_price', 'finalPrice', 'final_price']) ?? 0).toDouble();
              final originalPrice = (_num(it, ['original_price', 'reserve_price', 'price']) ?? price).toDouble();
              final coupon = (_num(it, ['coupon_amount', 'coupon']) ?? 0).toDouble();
              final finalPrice = (_num(it, ['after_coupon_price', 'final_price', 'finalPrice']) ?? (price - coupon)).toDouble();
              final sales = (_num(it, ['volume', 'sell_num', 'sales', 'trade_count']) ?? 0).toInt();
              final commission = (_num(it, ['commission', 'commission_rate', 'max_commission', 'commissionAmount']) ?? 0).toDouble();
              final link = _str(it, ['clickURL', 'click_url', 'url', 'coupon_click_url', 'tpwd', 'link']) ?? '';

              pmap = {
                'id': id,
                'platform': 'taobao',
                'title': title,
                'price': price,
                'original_price': originalPrice,
                'coupon': coupon,
                'final_price': finalPrice,
                'image_url': imageUrl,
                'sales': sales,
                'rating': 0.0,
                'link': link,
                'commission': commission,
                'sub_title': (it['sub_title'] ?? '').toString(),
                'short_title': (it['short_title'] ?? '').toString(),
                // prefer short_title over sub_title for display
                'description': (it['short_title'] ?? it['sub_title'] ?? it['title'] ?? '').toString(),
              };
            } else {
              // taobao mapping best-effort
              String id = (it['num_iid'] ?? it['id'] ?? it['item_id'] ?? it['goods_id'] ?? '').toString();
              String title = (it['title'] ?? it['item_title'] ?? it['name'] ?? '').toString();
              String imageUrl = (it['pic_url'] ?? it['pict_url'] ?? it['small_images'] ?? it['image_url'] ?? '').toString();
              // small_images may be object/array
              if (imageUrl.isEmpty && it['small_images'] is Map && it['small_images']['string'] is List) {
                final list = it['small_images']['string'] as List;
                if (list.isNotEmpty) imageUrl = list[0].toString();
              }
              double price = 0.0;
              try {
                price = (num.tryParse((it['zk_final_price'] ?? it['reserve_price'] ?? it['price'] ?? '0').toString()) ?? 0).toDouble();
              } catch (_) {}
              double originalPrice = price;
              double coupon = (num.tryParse((it['coupon_amount'] ?? it['coupon'] ?? '0').toString()) ?? 0).toDouble();
              double finalPrice = (num.tryParse((it['final_price'] ?? it['after_coupon_price'] ?? '').toString()) ?? (price - coupon)).toDouble();
              int sales = (num.tryParse((it['volume'] ?? it['sell_num'] ?? it['sales'] ?? '0').toString()) ?? 0).toInt();
              double commission = (num.tryParse((it['commission'] ?? it['commission_rate'] ?? '0').toString()) ?? 0).toDouble();
              String link = (it['click_url'] ?? it['url'] ?? it['coupon_click_url'] ?? '').toString();

              pmap = {
                'id': id,
                'platform': 'taobao',
                'title': title,
                'price': price,
                'original_price': originalPrice,
                'coupon': coupon,
                'final_price': finalPrice,
                'image_url': imageUrl,
                'sales': sales,
                'rating': 0.0,
                'link': link,
                'commission': commission,
                'sub_title': (it['sub_title'] ?? '').toString(),
                'short_title': (it['short_title'] ?? '').toString(),
                // prefer short_title over sub_title for display
                'description': (it['short_title'] ?? it['sub_title'] ?? it['title'] ?? '').toString(),
              };
            }
            products.add(pmap);
          }
        }
      }
      // If caller requested 'all' or 'both' or no explicit platform, and JD is available,
      // attempt to fetch JD results and append them to products (avoid duplicates later).
      if (useJd && (platformParam == 'all' || platformParam == 'both' || platformParam.isEmpty)) {
        try {
          final uri = Uri.parse('http://localhost:8080/jd/union/goods/query?keyword=${Uri.encodeComponent(query)}&pageIndex=${params['page'] ?? params['pageIndex'] ?? '1'}&pageSize=${params['page_size'] ?? params['pageSize'] ?? '20'}');
          final respJ = await http.get(uri).timeout(Duration(seconds: 8));
          if (respJ.statusCode == 200) {
            final bodyJ = jsonDecode(respJ.body);
            final jdItems = _findListOfMaps(bodyJ);
            if (jdItems != null) {
              for (final it in jdItems) {
                if (it is Map<String, dynamic>) {
                  try {
                    final id = (it['skuId'] ?? it['sku_id'] ?? it['itemId'] ?? it['item_id'] ?? '').toString();
                    final title = (it['skuName'] ?? it['sku_name'] ?? it['skuTitle'] ?? '').toString();
                    String imageUrl = '';
                    try {
                      if (it['imageInfo'] is Map && it['imageInfo']['imageList'] is List && it['imageInfo']['imageList'].isNotEmpty) imageUrl = it['imageInfo']['imageList'][0]['url'].toString();
                    } catch (_) {}
                    if (imageUrl.isEmpty) imageUrl = (it['imageUrl'] ?? it['imageUrl'] ?? '').toString();
                    double price = 0.0;
                    try {
                      // robust price extraction: try common fields and fallbacks, also walk nested structures
                      final List<dynamic> candidates = [];
                      if (it['priceInfo'] is Map) {
                        final pi = it['priceInfo'] as Map;
                        candidates.add(pi['price'] ?? pi['promotionPrice'] ?? pi['unitPrice'] ?? pi['lowestPrice'] ?? pi['priceInfo']);
                      }
                      candidates.add(it['price'] ?? it['finalPrice'] ?? it['priceInfo'] ?? it['jdPrice'] ?? it['lowestCouponPrice'] ?? it['coupon_price'] ?? it['zk_final_price'] ?? it['priceInfo']);

                      void _walkPrices(dynamic node) {
                        try {
                          if (node is Map) {
                            for (final entry in node.entries) {
                              final k = entry.key?.toString() ?? '';
                              final v = entry.value;
                              if (k.toLowerCase().contains('price') || k.toLowerCase().contains('amount')) candidates.add(v);
                              _walkPrices(v);
                            }
                          } else if (node is List) {
                            for (final e in node) _walkPrices(e);
                          }
                        } catch (_) {}
                      }

                      _walkPrices(it);

                      for (final c in candidates) {
                        if (c == null) continue;
                        final s = c.toString();
                        final parsed = num.tryParse(s.replaceAll(RegExp('[^0-9\.]'), ''));
                        if (parsed != null) {
                          price = parsed.toDouble();
                          break;
                        }
                      }
                    } catch (_) {}
                    double coupon = 0.0;
                    try {
                      if (it['couponInfo'] is Map) {
                        final ci = it['couponInfo'] as Map;
                        if (ci['couponList'] is Map && ci['couponList']['coupon'] is Map) {
                          coupon = (num.tryParse(ci['couponList']['coupon']['discount']?.toString() ?? '') ?? 0).toDouble();
                        } else if (ci['couponList'] is List && ci['couponList'].isNotEmpty) {
                          coupon = (num.tryParse(ci['couponList'][0]['discount']?.toString() ?? '') ?? 0).toDouble();
                        }
                      }
                    } catch (_) {}
                    String link = (it['materialUrl'] ?? it['couponInfo'] is Map && it['couponInfo']['couponList'] is Map ? (it['couponInfo']['couponList']['coupon'] is Map ? it['couponInfo']['couponList']['coupon']['link'] : null) : null) as String? ?? '';
                    if (link.isEmpty) link = (it['materialUrl'] ?? it['itemUrl'] ?? it['item_id'] ?? '').toString();
                    double commission = 0.0;
                    try {
                      commission = (it['commissionInfo'] != null && it['commissionInfo']['commission'] != null) ? (num.tryParse(it['commissionInfo']['commission'].toString()) ?? 0).toDouble() : 0.0;
                    } catch (_) {}
                    int sales = (num.tryParse((it['inOrderCount30Days'] ?? it['comments'] ?? '0').toString()) ?? 0).toInt();

                    // ensure price: if missing try cached or fetch from item page
                    double usedPrice = price ?? 0.0;
                    if ((usedPrice == 0.0 || usedPrice == null) && id.isNotEmpty) {
                      // check cache
                      try {
                        final entry = _priceCache[id];
                        final nowMs = DateTime.now().millisecondsSinceEpoch;
                        if (entry != null && (entry['expiry'] as int?) != null && (entry['expiry'] as int) > nowMs && entry['price'] != null) {
                          usedPrice = (entry['price'] as num).toDouble();
                        }
                      } catch (_) {}

                      // if still missing, try lightweight HTML fetch of mobile item page
                      if ((usedPrice == 0.0 || usedPrice == null)) {
                        try {
                    final itemUrl = 'https://item.jd.com/${id}.html';
                          final client = http.Client();
                          final resp = await client.get(Uri.parse(itemUrl), headers: {
                            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36',
                            'Accept-Language': 'zh-CN,zh;q=0.9'
                          }).timeout(Duration(seconds: 6));
                          if (resp.statusCode == 200) {
                            final body = resp.body;
                            // try several regex patterns to extract price number
                            final patterns = [RegExp(r'"price"\s*[:=]\s*"?(\d+[\.\d]*)"?'), RegExp(r'price\s*:\s*"?(\d+[\.\d]*)"?'), RegExp(r'"p\"\s*:\s*"?(\d+[\.\d]*)"?'), RegExp(r'\bprice\b[^0-9]{0,10}(\d+[\.\d]*)')];
                            for (final pat in patterns) {
                              final m = pat.firstMatch(body);
                              if (m != null && m.groupCount >= 1) {
                                final parsed = num.tryParse(m.group(1)!.replaceAll(RegExp('[^0-9\.]'), ''));
                                if (parsed != null) {
                                  usedPrice = parsed.toDouble();
                                  final expiry = DateTime.now().millisecondsSinceEpoch + 10 * 60 * 1000; // 10 minutes
                                  _priceCache[id] = {'price': usedPrice, 'expiry': expiry};
                                  break;
                                }
                              }
                            }
                          }
                        } catch (_) {}
                      }
                    }

                    products.add({
                      'id': id,
                      'platform': 'jd',
                      'title': title,
                      'price': usedPrice,
                      'original_price': usedPrice,
                      'coupon': coupon,
                      'final_price': (usedPrice - coupon),
                      'image_url': imageUrl,
                      'sales': sales,
                      'rating': 0.0,
                      'link': link,
                      'commission': commission,
                      'description': '',
                    });
                  } catch (_) {}
                }
              }
            }
          }
        } catch (_) {}
      }
      // 如果通用查找未找到列表，尝试识别物料接口的常见返回结构并解析
      if (items == null) {
        List<dynamic>? mlist;
        // 1) 直接的 result_list
        if (body.containsKey('result_list') && body['result_list'] is List) {
          mlist = body['result_list'] as List<dynamic>;
        }
        // 2) 新版物料响应可能在 tbk_sc_material_optional_response.result_list.map_data
        if (mlist == null && body.containsKey('tbk_sc_material_optional_response')) {
          final respMap = body['tbk_sc_material_optional_response'];
          if (respMap is Map) {
            if (respMap['result_list'] is Map && respMap['result_list']['map_data'] is List) {
              mlist = respMap['result_list']['map_data'] as List<dynamic>;
            } else if (respMap['result_list'] is List) {
              mlist = respMap['result_list'] as List<dynamic>;
            }
          }
        }
        // 3) 服务商/推广者物料升级接口返回结构 tbk_dg_material_optional_upgrade_response.result_list.map_data
        if (mlist == null && body.containsKey('tbk_dg_material_optional_upgrade_response')) {
          final respMap = body['tbk_dg_material_optional_upgrade_response'];
          if (respMap is Map) {
            if (respMap['result_list'] is Map && respMap['result_list']['map_data'] is List) {
              mlist = respMap['result_list']['map_data'] as List<dynamic>;
            } else if (respMap['result_list'] is List) {
              mlist = respMap['result_list'] as List<dynamic>;
            }
          }
        }

        if (mlist != null) {
          for (final it in mlist) {
            if (it is Map<String, dynamic>) {
              final id = (it['num_iid'] ?? it['item_id'] ?? it['id'] ?? '').toString();
              final title = (it['title'] ?? it['item_title'] ?? it['name'] ?? '').toString();
              final imageUrl = (it['pict_url'] ?? it['pic_url'] ?? it['small_images'] ?? it['image_url'] ?? '').toString();
              final price = (num.tryParse((it['zk_final_price'] ?? it['coupon_price'] ?? it['price'] ?? '0').toString()) ?? 0).toDouble();
              final sales = (num.tryParse((it['volume'] ?? it['sales'] ?? it['tk_total_sales'] ?? '0').toString()) ?? 0).toInt();
              // Prefer coupon_share_url when present (better for coupon forwarding), then click_url
              final link = (it['coupon_share_url'] ?? it['click_url'] ?? it['coupon_click_url'] ?? it['purl'] ?? it['clickUrl'] ?? '').toString();
              final commission = (num.tryParse((it['commission'] ?? it['commission_rate'] ?? '0').toString()) ?? 0).toDouble();
              final coupon = (num.tryParse((it['coupon_amount'] ?? it['coupon'] ?? '0').toString()) ?? 0).toDouble();

              products.add({
                'id': id,
                'platform': 'taobao',
                'title': title,
                'price': price,
                'original_price': price,
                'coupon': coupon,
                'final_price': (price - coupon),
                'image_url': imageUrl,
                'sales': sales,
                'rating': 0.0,
                'link': link,
                'commission': commission,
                'sub_title': (it['sub_title'] ?? '').toString(),
                'short_title': (it['short_title'] ?? '').toString(),
                'description': (it['sub_title'] ?? it['short_title'] ?? it['title'] ?? '').toString(),
              });
            }
          }
        }
      }
      // Also attempt to fetch PDD results when configured and caller allows multi-source
      try {
        final pddClientId = env['PDD_CLIENT_ID'];
        final pddClientSecret = env['PDD_CLIENT_SECRET'];
        final pddPid = env['PDD_PID'] ?? '';
        final wantPdd = pddClientId != null && pddClientSecret != null && pddClientId.isNotEmpty;
        if (wantPdd && (platformParam == 'all' || platformParam.isEmpty || platformParam == 'pdd')) {
          // build params for pdd.ddk.goods.search
          final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
          final biz = <String, dynamic>{
            'client_id': pddClientId,
            'type': 'pdd.ddk.goods.search',
            'data_type': 'JSON',
            'timestamp': ts,
            'keyword': query,
          };
          if (pddPid.isNotEmpty) biz['pid'] = pddPid;
          // sign: clientSecret + k+v... + clientSecret, keys sorted
          final keys = biz.keys.toList()..sort();
          final sb = StringBuffer();
          sb.write(pddClientSecret);
          for (final k in keys) {
            sb.write(k);
            final v = biz[k];
            if (v is String) sb.write(v);
            else sb.write(jsonEncode(v));
          }
          sb.write(pddClientSecret);
          final sign = md5.convert(utf8.encode(sb.toString())).toString().toUpperCase();

          // prepare form body (JSON-encode non-strings)
          final form = <String, String>{};
          biz.forEach((k, v) {
            if (v is String) form[k] = v;
            else form[k] = jsonEncode(v);
          });
          form['sign'] = sign;

          try {
            final respP = await http.post(Uri.parse('https://gw-api.pinduoduo.com/api/router'), headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: form).timeout(Duration(seconds: 8));
            if (respP.statusCode == 200) {
              final Map<String, dynamic> pbody = jsonDecode(respP.body) as Map<String, dynamic>;
              // persist raw PDD response to file for debugging
              try {
                final f = File('pdd_last_response.json');
                await f.writeAsString(JsonEncoder.withIndent('  ').convert(pbody));
              } catch (_) {}
              final goodsResp = (pbody['goods_search_response'] is Map) ? pbody['goods_search_response'] as Map<String, dynamic> : null;
              if (goodsResp != null && goodsResp['goods_list'] is List) {
                final List<dynamic> gl = goodsResp['goods_list'] as List<dynamic>;
                for (final it in gl) {
                  try {
                    if (it is Map) {
                      final m = Map<String, dynamic>.from(it as Map);
                      final id = (m['goods_sign'] ?? '').toString();
                      final title = (m['goods_name'] ?? '').toString();
                      final image = (m['goods_image_url'] ?? m['goods_thumbnail_url'] ?? '').toString();
                      final minGroup = ((m['min_group_price'] is num) ? (m['min_group_price'] as num).toDouble() : (double.tryParse((m['min_group_price'] ?? '0').toString()) ?? 0.0)) / 100.0;
                      final minNorm = ((m['min_normal_price'] is num) ? (m['min_normal_price'] as num).toDouble() : (double.tryParse((m['min_normal_price'] ?? '0').toString()) ?? 0.0)) / 100.0;
                      final coupon = ((m['coupon_discount'] is num) ? (m['coupon_discount'] as num).toDouble() : (double.tryParse((m['coupon_discount'] ?? '0').toString()) ?? 0.0)) / 100.0;
                      int sales = 0;
                      try {
                        final st = (m['sales_tip'] ?? '').toString();
                        if (st.contains('万')) {
                          final wm = RegExp(r"([0-9]+\.?[0-9]*)万").firstMatch(st);
                          if (wm != null) sales = (double.parse(wm.group(1)!) * 10000).toInt();
                        } else {
                          final n = RegExp(r"(\d+)").firstMatch(st)?.group(1);
                          if (n != null) sales = int.tryParse(n) ?? 0;
                        }
                      } catch (_) {}
                      final shopTitle = (m['mall_name'] ?? m['opt_name'] ?? '').toString();
                      final desc = (m['goods_desc'] ?? m['desc_txt'] ?? '').toString();

                      products.add({
                        'id': id.isEmpty ? '${title.hashCode}' : id,
                        'platform': 'pdd',
                        'title': title,
                        'price': minGroup,
                        'original_price': minNorm,
                        'coupon': coupon,
                        'final_price': (minGroup - coupon),
                        'image_url': image,
                        'sales': sales,
                        'rating': 0.0,
                        'link': '',
                        'commission': ((m['promotion_rate'] is num) ? (m['promotion_rate'] as num).toDouble() : (double.tryParse((m['promotion_rate'] ?? '0').toString()) ?? 0.0)) / 1000.0 * minGroup,
                        'description': desc,
                        'shop_title': shopTitle,
                      });
                    }
                  } catch (_) {}
                }
                // record attempt
                try {
                  attemptsLocal.add({'attempt': 'pdd_search', 'query': query, 'matched': gl.length});
                } catch (_) {}
              }
            }
          } catch (_) {}
        }
      } catch (_) {}

      // Force-merge: if backend already fetched raw jingdong.search.ware response,
      // always try to parse its Paragraph list and append JD products to `products`.
      // This ensures JD items are included even when Taobao results exist.
      try {
        if (body is Map && body.containsKey('jingdong_search_ware_responce')) {
          final rawJd = body['jingdong_search_ware_responce'] as Map<String, dynamic>;
          List<dynamic>? paras;
          if (rawJd.containsKey('Paragraph') && rawJd['Paragraph'] is List) paras = rawJd['Paragraph'] as List<dynamic>;
          else if (rawJd.containsKey('Head') && rawJd['Head'] is Map && rawJd['Head']['Paragraph'] is List) paras = rawJd['Head']['Paragraph'] as List<dynamic>;
          if (paras != null && paras.isNotEmpty) {
            final existingIds = products.map((p) => (p['id']?.toString() ?? '')).toSet();
            for (final it in paras) {
              try {
                if (it is Map) {
                  final id = (it['wareid'] ?? it['wareId'] ?? '').toString();
                  if (id.isEmpty) continue;
                  if (existingIds.contains(id)) continue;

                  String title = '';
                  try {
                    if (it['Content'] is Map) title = (it['Content']['warename'] ?? it['Content']['wareName'] ?? '').toString();
                    if (title.isNotEmpty) title = Uri.decodeComponent(title);
                  } catch (_) {}

                  String imageUrl = '';
                  try {
                    if (it['Content'] is Map && it['Content']['imageurl'] != null) imageUrl = _normalizeJdImageUrl(it['Content']['imageurl']);
                    else if (it['SlaveWare'] is List && it['SlaveWare'].isNotEmpty) {
                      final sw = it['SlaveWare'][0];
                      if (sw is Map && sw['Content'] is Map && sw['Content']['imageurl'] != null) imageUrl = _normalizeJdImageUrl(sw['Content']['imageurl']);
                    }
                  } catch (_) {}

                  double price = 0.0;
                  try {
                    if (it['price'] != null) price = (num.tryParse(it['price'].toString()) ?? 0).toDouble();
                  } catch (_) {}

                  final link = (it['materialUrl'] ?? it['itemUrl'] ?? '').toString();
                  final sales = (num.tryParse((it['good'] ?? it['sales'] ?? '0').toString()) ?? 0).toInt();

                  products.add({
                    'id': id,
                    'platform': 'jd',
                    'title': title,
                    'price': price,
                    'original_price': price,
                    'coupon': 0.0,
                    'final_price': price,
                    'image_url': imageUrl,
                    'sales': sales,
                    'rating': 0.0,
                    'link': link,
                    'commission': 0.0,
                    'description': title ?? '',
                    'shop_title': (it['shop_id'] ?? it['shopTitle'] ?? '').toString(),
                  });
                  existingIds.add(id);
                }
              } catch (_) {}
            }
          }
        }
      } catch (_) {}

      // Ensure every product has a safe description: prefer existing description,
      // otherwise fall back to sub_title, short_title or title (final safety net).
      for (final p in products) {
        try {
          final desc = (p['description'] ?? '').toString().trim();
          if (desc.isEmpty) {
            // choose first non-empty among sub_title, short_title, title
            String fallback = '';
            try {
            final cand1 = (p['short_title'] ?? '').toString().trim();
            final cand2 = (p['sub_title'] ?? '').toString().trim();
            final cand3 = (p['title'] ?? '').toString().trim();
            if (cand1.isNotEmpty) fallback = cand1;
            else if (cand2.isNotEmpty) fallback = cand2;
            else if (cand3.isNotEmpty) fallback = cand3;
            } catch (_) {}
            p['description'] = fallback;
          }
        } catch (_) {}
      }

      // Deduplicate products by normalized title (and fallback to id when title empty)
      String _normalize(String? s) {
        if (s == null) return '';
        return s.replaceAll(RegExp(r'[^0-9a-zA-Z\u4e00-\u9fa5]+'), '').toLowerCase();
      }

      double _score(Map p) {
        double score = 0.0;
        try {
          if ((p['link'] as String?)?.isNotEmpty ?? false) score += 100000.0;
          score += ((p['commission'] as num?)?.toDouble() ?? 0.0) * 100.0;
          score += ((p['sales'] as num?)?.toDouble() ?? 0.0) / 1000.0;
          // prefer lower final price slightly
          score -= ((p['final_price'] as num?)?.toDouble() ?? ((p['price'] as num?)?.toDouble() ?? 0.0)) / 10000.0;
        } catch (_) {}
        return score;
      }

      final Map<String, List<Map<String, dynamic>>> groups = {};
      for (final p in products) {
        try {
          final key = _normalize(p['title'] as String? ?? '') ?? '';
          final k = (key.isEmpty) ? ('id:' + (p['id']?.toString() ?? '')) : key;
          groups.putIfAbsent(k, () => []).add(p);
        } catch (_) {}
      }

      final merged = <Map<String, dynamic>>[];
      for (final entry in groups.entries) {
        final list = entry.value;
        if (list.length == 1) merged.add(list.first);
        else {
          list.sort((a, b) => _score(b).compareTo(_score(a)));
          // pick top-scoring as representative
          merged.add(list.first);
        }
      }

      // If we used jd_search as the source, only set missing platform fields to 'jd'.
      // Avoid overwriting existing platform values produced by other mappers (e.g. taobao).
      try {
        if (source == 'jd_search') {
          for (final p in products) {
            try {
              final cur = (p['platform'] ?? '').toString();
              if (cur.isEmpty) p['platform'] = 'jd';
            } catch (_) {}
          }
        }
      } catch (_) {}

      // Sorting: support sortName and sort (asc/desc). Defaults to our score descending.
      final sortName = (params['sortName'] ?? params['sort_name'] ?? '').toString().toLowerCase();
      final sortOrder = (params['sort'] ?? 'desc').toString().toLowerCase();
      int order = (sortOrder == 'asc') ? 1 : -1;

      int _cmpByField(String field, Map a, Map b) {
        final na = (a[field] as num?)?.toDouble() ?? 0.0;
        final nb = (b[field] as num?)?.toDouble() ?? 0.0;
        if (na == nb) return 0;
        return (na < nb) ? -1 * order : 1 * order;
      }

      if (sortName == 'price') {
        merged.sort((a, b) => _cmpByField('final_price', a, b));
      } else if (sortName == 'commission') {
        merged.sort((a, b) => _cmpByField('commission', a, b));
      } else if (sortName == 'sales' || sortName == 'inordercount30days') {
        merged.sort((a, b) => _cmpByField('sales', a, b));
      } else {
        // default: score desc
        merged.sort((a, b) => _score(b).compareTo(_score(a)));
      }

      // paging
      final page = int.tryParse((params['page'] ?? params['pageIndex'] ?? params['page_no'] ?? '1').toString()) ?? 1;
      final pageSize = int.tryParse((params['page_size'] ?? params['pageSize'] ?? params['pageSize'] ?? '20').toString()) ?? 20;
      final start = (page - 1) * pageSize;
      List<Map<String, dynamic>> finalProducts;
      if (start < 0 || start >= merged.length) finalProducts = [];
      else finalProducts = merged.skip(start).take(pageSize).toList();

      // For any JD product missing price, attempt a lightweight HTML fetch of the mobile item page
      // Do this in limited concurrency batches and cache results in _priceCache to avoid repeated fetches.
      try {
        final List<Future<void>> _priceFutures = [];
        for (int i = 0; i < finalProducts.length; i++) {
          final p = finalProducts[i];
          try {
            if ((p['platform']?.toString() ?? '') == 'jd') {
              final num? curPriceNum = (p['price'] is num) ? (p['price'] as num) : (num.tryParse((p['price'] ?? '').toString()));
              final bool needFetch = (curPriceNum == null || curPriceNum == 0);
              if (needFetch) {
                _priceFutures.add(Future(() async {
                  final id = (p['id']?.toString() ?? '');
                  if (id.isEmpty) return;
                  try {
                    final nowMs = DateTime.now().millisecondsSinceEpoch;
                    final cache = _priceCache[id];
                    if (cache != null && (cache['expiry'] as int?) != null && (cache['expiry'] as int) > nowMs && cache['price'] != null) {
                      final double cp = (cache['price'] as num).toDouble();
                      p['price'] = cp;
                      p['original_price'] = cp;
                      p['final_price'] = (cp - ((p['coupon'] as num?) ?? 0)).toDouble();
                      return;
                    }

                    final itemUrl = Uri.parse('https://item.jd.com/${Uri.encodeComponent(id)}.html');
                    final client = http.Client();
                    final resp = await client.get(itemUrl, headers: {
                      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36',
                      'Accept-Language': 'zh-CN,zh;q=0.9'
                    }).timeout(Duration(seconds: 6));
                    if (resp.statusCode == 200) {
                      final body = resp.body;
                      final List<RegExp> patterns = [
                        RegExp(r'"price"\s*[:=]\s*"?(\d+[\.\d]*)"?'),
                        RegExp(r'price\s*:\s*"?(\d+[\.\d]*)"?'),
                        RegExp(r'"p\\"\s*:\s*"?(\d+[\.\d]*)"?'),
                        RegExp(r'\bprice\b[^0-9]{0,10}(\d+[\.\d]*)')
                      ];
                      double found = 0.0;
                      for (final pat in patterns) {
                        try {
                          final m = pat.firstMatch(body);
                          if (m != null && m.groupCount >= 1) {
                            final parsed = num.tryParse(m.group(1)!.replaceAll(RegExp('[^0-9\.]'), ''));
                            if (parsed != null) {
                              found = parsed.toDouble();
                              break;
                            }
                          }
                        } catch (_) {}
                      }
                      if (found > 0) {
                        p['price'] = found;
                        p['original_price'] = found;
                        p['final_price'] = (found - ((p['coupon'] as num?) ?? 0)).toDouble();
                        final expiry = DateTime.now().millisecondsSinceEpoch + 10 * 60 * 1000;
                        _priceCache[id] = {'price': found, 'expiry': expiry};
                      }
                    }
                  } catch (_) {}
                }));
              }
            }
          } catch (_) {}

          if (_priceFutures.length >= 4) {
            try {
              await Future.wait(_priceFutures);
            } catch (_) {}
            _priceFutures.clear();
          }
        }

        if (_priceFutures.isNotEmpty) {
          try {
            await Future.wait(_priceFutures);
          } catch (_) {}
        }
      } catch (_) {}

      final out = {'products': finalProducts, 'source': source, 'attempts': attemptsLocal, 'total': merged.length};
      // store debug copy
      try {
        final rec = {'path': '/api/products/search', 'query': query, 'out': out, 'ts': DateTime.now().toIso8601String()};
        _lastReturnDebug = rec;
        _lastReturnHistory.add(rec);
        if (_lastReturnHistory.length > 20) _lastReturnHistory.removeAt(0);
      } catch (_) {}
      return Response.ok(jsonEncode(out), headers: {'content-type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}), headers: {'content-type': 'application/json'});
    }
  });

  // 淘宝客商品搜索（官方 API 封装，需设置 TAOBAO_APP_KEY 和 TAOBAO_APP_SECRET）
  router.get('/taobao/tbk_search', (Request r) async {
    final env = Platform.environment;
    final appKey = env['TAOBAO_APP_KEY'];
    final appSecret = env['TAOBAO_APP_SECRET'];
    if (appKey == null || appSecret == null || appKey.isEmpty || appSecret.isEmpty) {
      return Response.internalServerError(body: jsonEncode({'error': 'TAOBAO_APP_KEY/TAOBAO_APP_SECRET not configured'}), headers: {'content-type': 'application/json'});
    }

    final params = r.requestedUri.queryParameters;
    var para = params['para'] ?? '';

    // Fix common Windows/curl double-encoding: if para looks like Latin-1 representation
    // of UTF-8 bytes (e.g. 'å¥³è£' instead of '女装'), try to recover.
    String _tryRecoverUtf8(String s) {
      // if already contains CJK, keep
      if (RegExp(r'[\u4e00-\u9fff]').hasMatch(s)) return s;
      try {
        // map UTF-16 code units (for Latin-1 this equals original byte) back to bytes
        final bytes = s.codeUnits.map((u) => u & 0xFF).toList();
        final recovered = utf8.decode(bytes);
        // if recovered has CJK, assume recovery succeeded
        if (RegExp(r'[\u4e00-\u9fff]').hasMatch(recovered)) return recovered;
      } catch (_) {}
      return s;
    }

    para = _tryRecoverUtf8(para);
    if (para.isEmpty) return Response(400, body: jsonEncode({'error': 'para parameter required'}), headers: {'content-type': 'application/json'});

    // Prepare Taobao API params. 支持通过 query param 覆盖 method/fields（便于调试）
    // 默认使用推广者物料搜索（推广者用）：taobao.tbk.dg.material.optional.upgrade
    final requestedMethod = params['method'] ?? 'taobao.tbk.dg.material.optional.upgrade';
    final apiParams = <String, String>{
      'method': requestedMethod,
      'app_key': appKey,
      // timestamp will be set below in GMT+8 format
      'format': 'json',
      'v': '2.0',
      'sign_method': 'md5',
      'q': para,
      'page_size': params['page_size'] ?? '20',
    };

    // Merge optional params like cat and material-related params
    if (params.containsKey('cat')) apiParams['cat'] = params['cat']!;
    if (params.containsKey('fields')) apiParams['fields'] = params['fields']!;
    if (params.containsKey('page_no')) apiParams['page_no'] = params['page_no']!;
    if (params.containsKey('page_size')) apiParams['page_size'] = params['page_size']!;
    // 默认使用用户提供的推广位（adzone_id），若未传则使用项目默认推广位
    if (params.containsKey('adzone_id')) apiParams['adzone_id'] = params['adzone_id']!;
    else apiParams['adzone_id'] = params['adzone_id'] ?? '116145250221';
    if (params.containsKey('site_id')) apiParams['site_id'] = params['site_id']!;
    if (params.containsKey('material_id')) apiParams['material_id'] = params['material_id']!;
    if (params.containsKey('sort')) apiParams['sort'] = params['sort']!;
    if (params.containsKey('has_coupon')) apiParams['has_coupon'] = params['has_coupon']!;
    // Include partner_id when present in examples (some OpenAPI examples include partner_id=top-apitools)
    apiParams['partner_id'] = params['partner_id'] ?? 'top-apitools';

    // Ensure timestamp is GMT+8 formatted 'yyyy-MM-dd HH:mm:ss' and include it BEFORE signing
    final beijing = DateTime.now().toUtc().add(Duration(hours: 8));
    apiParams['timestamp'] = beijing.toIso8601String().split('.').first.replaceFirst('T', ' ');

    // Build sign: MD5(appSecret + keyvalue... + appSecret) uppercase
    final keys = apiParams.keys.toList()..sort();
    final sb = StringBuffer();
    for (final k in keys) {
      sb.write(k);
      sb.write(apiParams[k]);
    }
    final signBase = appSecret + sb.toString() + appSecret;
    final signDigest = md5.convert(utf8.encode(signBase)).toString().toUpperCase();
    apiParams['sign'] = signDigest;

    // Build request to Taobao router (use POST form-urlencoded as documented)
    final uri = Uri.https('eco.taobao.com', '/router/rest');

    try {
      // debug: if requested, return sign components without calling Taobao
      if (params['debug_sign'] == '1') {
        final debugBody = {
          'apiParams': apiParams,
          'signBase': signBase,
          'sign': apiParams['sign'],
          'called_method': requestedMethod,
        };
        return Response.ok(jsonEncode(debugBody), headers: {'content-type': 'application/json'});
      }

      final resp = await http.post(uri, headers: {'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8'}, body: apiParams).timeout(Duration(seconds: 8));
      if (resp.statusCode != 200) return Response.internalServerError(body: jsonEncode({'error': 'taobao api failed', 'status': resp.statusCode}), headers: {'content-type': 'application/json'});

      // 直接透传淘宝 JSON（上层可解析 items 列表），并添加来源字段
      final Map<String, dynamic> body = jsonDecode(resp.body) as Map<String, dynamic>;
      body['__taobao_source'] = requestedMethod;
      // include raw response string for debugging
      body['__raw_taobao'] = resp.body;
      // expose which method was actually called
      body['__called_method'] = requestedMethod;
      // store debug copy for inspection
      try {
        final rec = {'path': '/taobao/tbk_search', 'query': para, 'body': body, 'ts': DateTime.now().toIso8601String()};
        _lastReturnDebug = rec;
        _lastReturnHistory.add(rec);
        if (_lastReturnHistory.length > 20) _lastReturnHistory.removeAt(0);
      } catch (_) {}
      return Response.ok(jsonEncode(body), headers: {'content-type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}), headers: {'content-type': 'application/json'});
    }
  });

  // Temporary debug route: call jingdong.search.ware and return raw JD response
  // Usage: GET /proxy/test/jd_search?keyword=手机&page=1
  router.get('/proxy/test/jd_search', (Request r) async {
    final env = Platform.environment;
    final appKey = env['JD_APP_KEY'];
    final appSecret = env['JD_APP_SECRET'];
    if (appKey == null || appSecret == null || appKey.isEmpty || appSecret.isEmpty) {
      return Response.internalServerError(body: jsonEncode({'error': 'JD_APP_KEY/JD_APP_SECRET not configured'}), headers: {'content-type': 'application/json'});
    }
    final params = r.requestedUri.queryParameters;
    final keyword = params['keyword'] ?? params['q'] ?? '';
    final page = params['page'] ?? '1';
    if (keyword.isEmpty) return Response(400, body: jsonEncode({'error': 'keyword required'}), headers: {'content-type': 'application/json'});

    final beijing = DateTime.now().toUtc().add(Duration(hours: 8));
    String two(int n) => n.toString().padLeft(2, '0');
    final ts = '${beijing.year}-${two(beijing.month)}-${two(beijing.day)} ${two(beijing.hour)}:${two(beijing.minute)}:${two(beijing.second)}';

    final paramsMap = <String, String>{
      'method': 'jingdong.search.ware',
      'app_key': appKey,
      'v': '2.0',
      'format': 'json',
      'key': keyword,
      'page': page,
      'charset': 'utf-8',
      'urlencode': 'yes',
      'timestamp': ts,
    };
    final keys = paramsMap.keys.toList()..sort();
    final sb = StringBuffer();
    sb.write(appSecret);
    for (final k in keys) {
      sb.write(k);
      sb.write(paramsMap[k]);
    }
    sb.write(appSecret);
    final sign = md5.convert(utf8.encode(sb.toString())).toString().toUpperCase();
    paramsMap['sign'] = sign;

    try {
      final resp = await http.post(Uri.parse('https://api.jd.com/routerjson'), headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: paramsMap).timeout(Duration(seconds: 8));
      return Response(resp.statusCode, body: resp.body, headers: {'content-type': resp.headers['content-type'] ?? 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}), headers: {'content-type': 'application/json'});
    }
  });

  // 京东商品搜索代理（签名在服务器端完成，返回京东原始 JSON）
  router.get('/jd/union/goods/query', (Request r) async {
    final env = Platform.environment;
    final appKey = env['JD_APP_KEY'];
    final appSecret = env['JD_APP_SECRET'];
    if (appKey == null || appSecret == null || appKey.isEmpty || appSecret.isEmpty) {
      return Response.internalServerError(body: jsonEncode({'error': 'JD_APP_KEY/JD_APP_SECRET not configured'}), headers: {'content-type': 'application/json'});
    }

    final params = r.requestedUri.queryParameters;
    final keyword = params['keyword'] ?? params['q'] ?? '';
    if (keyword.isEmpty) return Response(400, body: jsonEncode({'error': 'keyword parameter required'}), headers: {'content-type': 'application/json'});
    final pageIndex = params['pageIndex'] ?? params['page'] ?? '1';
    final pageSize = params['pageSize'] ?? params['page_size'] ?? '20';

    // system params
    final apiParams = <String, String>{
      'method': 'jd.union.open.goods.query',
      'app_key': appKey,
      'format': 'json',
      'v': '1.0',
      'sign_method': 'md5',
    };

    // timestamp GMT+8
    final beijing = DateTime.now().toUtc().add(Duration(hours: 8));
    String two(int n) => n.toString().padLeft(2, '0');
    apiParams['timestamp'] = '${beijing.year}-${two(beijing.month)}-${two(beijing.day)} ${two(beijing.hour)}:${two(beijing.minute)}:${two(beijing.second)}';

    // business param: goodsReqDTO JSON
    final goodsReq = {'keyword': keyword, 'pageIndex': int.tryParse(pageIndex) ?? 1, 'pageSize': int.tryParse(pageSize) ?? 20};
    apiParams['goodsReqDTO'] = jsonEncode(goodsReq);

    // sign: MD5(appSecret + k1 + v1 + ... + appSecret) uppercase
    final keys = apiParams.keys.toList()..sort();
    final sb = StringBuffer();
    for (final k in keys) {
      sb.write(k);
      sb.write(apiParams[k]);
    }
    final signBase = appSecret + sb.toString() + appSecret;
    final signDigest = md5.convert(utf8.encode(signBase)).toString().toUpperCase();
    apiParams['sign'] = signDigest;

    // Debug mode: return signing info instead of calling JD
    if (params['debug_sign'] == '1') {
      final debugBody = {'apiParams': apiParams, 'signBase': signBase, 'sign': apiParams['sign'], 'called_method': apiParams['method']};
      return Response.ok(jsonEncode(debugBody), headers: {'content-type': 'application/json'});
    }

    try {
      final uri = Uri.parse('https://router.jd.com/routerjson');
      final resp = await http.post(uri, headers: {'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8'}, body: apiParams).timeout(Duration(seconds: 8));
      if (resp.statusCode != 200) return Response.internalServerError(body: jsonEncode({'error': 'jd api failed', 'status': resp.statusCode}), headers: {'content-type': 'application/json'});
      return Response.ok(resp.body, headers: {'content-type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}), headers: {'content-type': 'application/json'});
    }
  });

  // 京东转链/签名端点：后端生成推广链接（推荐：后端持有 JD secret 并调用京东推广转链接口）
  router.post('/sign/jd', (Request r) async {
    final env = Platform.environment;
    // 临时默认值，开发时方便使用（如果环境变量存在则优先使用）
    final appKey = (env['JD_APP_KEY'] ?? 'd26362a7d1037522f81c57afc70a78e7').toString().trim();
    final appSecret = (env['JD_APP_SECRET'] ?? '25638a02874e47858929243487818e72').toString().trim();
    final unionId = (env['JD_UNION_ID'] ?? '').toString().trim();
    if (appKey == null || appSecret == null || appKey.isEmpty || appSecret.isEmpty) {
      return Response.internalServerError(body: jsonEncode({'error': 'JD_APP_KEY/JD_APP_SECRET not configured'}), headers: {'content-type': 'application/json'});
    }

    final bodyStr = await r.readAsString();
    Map<String, dynamic> payload = {};
    // Accept both JSON and form-encoded bodies. Some clients post form data
    // (skuId=...) instead of JSON; try JSON first, otherwise fall back to
    // parsing url-encoded form body into a Map.
    try {
      payload = jsonDecode(bodyStr) as Map<String, dynamic>;
    } catch (_) {
      try {
        if (bodyStr.trim().isNotEmpty) {
          // parse key=value&... into map
          final parsed = Uri.splitQueryString(bodyStr);
          payload = Map<String, dynamic>.from(parsed);
        }
      } catch (_) {
        payload = {};
      }
    }

    // Expect either skuId or couponUrl or itemId
    final skuId = payload['skuId']?.toString() ?? payload['sku_id']?.toString() ?? payload['id']?.toString() ?? '';
    final couponUrl = payload['couponUrl']?.toString() ?? payload['coupon_url']?.toString() ?? '';
    // Allow payload to override env for optional promotion fields
    final payloadSiteId = payload['siteId']?.toString() ?? payload['site_id']?.toString() ?? '';
    final payloadMaterialId = payload['materialId']?.toString() ?? payload['material_id']?.toString() ?? '';
    final payloadPositionId = payload['positionId']?.toString() ?? payload['position_id']?.toString() ?? '';
    final payloadSubUnion = payload['subUnionId']?.toString() ?? payload['sub_union_id']?.toString() ?? payload['subUnion']?.toString() ?? '';
    final payloadUnionId = payload['unionId']?.toString() ?? payload['union_id']?.toString() ?? '';
    final payloadSceneId = payload['sceneId']?.toString() ?? payload['scene_id']?.toString() ?? '';

    // construct JD promotion request; using jd.union.open.promotion.common.get
    final apiParams = <String, String>{
      'method': 'jd.union.open.promotion.common.get',
      'app_key': appKey,
      'format': 'json',
      'v': '1.0',
      'sign_method': 'md5',
    };
    final beijing = DateTime.now().toUtc().add(Duration(hours: 8));
    String two(int n) => n.toString().padLeft(2, '0');
    apiParams['timestamp'] = '${beijing.year}-${two(beijing.month)}-${two(beijing.day)} ${two(beijing.hour)}:${two(beijing.minute)}:${two(beijing.second)}';

    final biz = <String, dynamic>{};
    if (skuId.isNotEmpty) biz['skuId'] = skuId;
    // Prefer unionId from payload (caller) over environment-configured unionId
    if (payloadUnionId.isNotEmpty) {
      biz['unionId'] = payloadUnionId;
    } else if (unionId.isNotEmpty) {
      biz['unionId'] = unionId;
    }
    if (couponUrl.isNotEmpty) biz['couponUrl'] = couponUrl;
    // Allow optional configuration from environment: siteId (required by some JD promo APIs),
    // positionId (推广位), subUnionId (子渠道) and sceneId.
    final siteIdEnv = env['JD_SITE_ID'] ?? env['JD_SITEID'] ?? env['JD_SITE'] ?? '4102034645';
    final positionIdEnv = env['JD_POSITION_ID'] ?? env['JD_POSITIONID'] ?? env['JD_PID'];
    final subUnionIdEnv = env['JD_SUB_UNION_ID'] ?? env['JD_SUBUNIONID'] ?? env['JD_SUB_UNION'];
    final sceneIdEnv = env['JD_SCENE_ID'] ?? env['JD_SCENEID'];
    // If payload explicitly gave a materialId, use it first
    if (payloadMaterialId.isNotEmpty) {
      biz['materialId'] = payloadMaterialId;
    }

    // priority: payload values override environment variables
    if (payloadSiteId.isNotEmpty) biz['siteId'] = payloadSiteId;
    else if (siteIdEnv != null && siteIdEnv.isNotEmpty) biz['siteId'] = siteIdEnv;

    if (payloadPositionId.isNotEmpty) {
      try {
        biz['positionId'] = int.parse(payloadPositionId);
      } catch (_) {
        biz['positionId'] = payloadPositionId;
      }
    } else if (positionIdEnv != null && positionIdEnv.isNotEmpty) {
      try {
        biz['positionId'] = int.parse(positionIdEnv);
      } catch (_) {
        biz['positionId'] = positionIdEnv;
      }
    }

    if (payloadSubUnion.isNotEmpty) biz['subUnionId'] = payloadSubUnion;
    else if (subUnionIdEnv != null && subUnionIdEnv.isNotEmpty) biz['subUnionId'] = subUnionIdEnv;

    if (payloadSceneId.isNotEmpty) {
      try {
        biz['sceneId'] = int.parse(payloadSceneId);
      } catch (_) {
        biz['sceneId'] = payloadSceneId;
      }
    } else if (sceneIdEnv != null && sceneIdEnv.isNotEmpty) {
      try {
        biz['sceneId'] = int.parse(sceneIdEnv);
      } catch (_) {
        biz['sceneId'] = sceneIdEnv;
      }
    }

    // If caller provided skuId but not materialId, construct a JD item URL and
    // set sceneId=2 (single-item scene) so JD accepts skuId-style material.
    if (!biz.containsKey('materialId') || (biz['materialId'] is String && (biz['materialId'] as String).isEmpty)) {
      if (skuId.isNotEmpty) {
        try {
          biz['materialId'] = 'https://item.jd.com/${skuId}.html';
          if (biz['sceneId'] == null) biz['sceneId'] = 2;
        } catch (_) {}
      }
    }
    // Build promotionCodeReq: use raw JSON for signing and send as form field
    // (JD requires the JSON value as-is for signature calculation; do NOT
    // pre-urlencode the JSON when computing the signature). We'll POST with
    // application/x-www-form-urlencoded so the HTTP client will URL-encode the
    // form body automatically, but signature must be computed over the raw
    // JSON string.
    final promotionJson = jsonEncode(biz);
    // place the raw JSON into params (http.post will encode form values)
    apiParams['promotionCodeReq'] = promotionJson;

    // Build sign base using raw JSON value (not URL-encoded). Per JD docs,
    // sign = MD5(appSecret + k1 + v1 + ... + appSecret) where v for
    // promotionCodeReq is the JSON string.
    final keys2 = apiParams.keys.toList()..sort();
    final sb2 = StringBuffer();
    sb2.write(appSecret);
    for (final k in keys2) {
      sb2.write(k);
      sb2.write(apiParams[k]);
    }
    sb2.write(appSecret);
    final signBase2 = sb2.toString();
    final sign2 = md5.convert(utf8.encode(signBase2)).toString().toUpperCase();
    apiParams['sign'] = sign2;

    // Debug mode: if query param debug_sign=1 or payload includes debug_sign true, return signing info
    final qp = r.requestedUri.queryParameters;
    bool debugSign = qp['debug_sign'] == '1';
    if (!debugSign) {
      try {
        if (payload.containsKey('debug_sign') && (payload['debug_sign'] == true || payload['debug_sign'] == '1')) debugSign = true;
      } catch (_) {}
    }
    if (debugSign) {
      final debugBody = {'apiParams': apiParams, 'signBase': signBase2, 'sign': apiParams['sign'], 'called_method': apiParams['method'], 'biz': biz};
      return Response.ok(jsonEncode(debugBody), headers: {'content-type': 'application/json'});
    }

    try {
      final uri = Uri.parse('https://router.jd.com/routerjson');
      final resp = await http.post(uri, headers: {'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8'}, body: apiParams).timeout(Duration(seconds: 8));
      int respStatusFinal = resp.statusCode;
      String respBodyFinal = resp.body;

      // Parse JD response and record debug details for this promotion call
      Map<String, dynamic>? parsedGetResult;
      try {
        final parsedResp = jsonDecode(respBodyFinal) as Map<String, dynamic>;
        if (parsedResp.containsKey('jd_union_open_promotion_common_get_responce')) {
          final inner = parsedResp['jd_union_open_promotion_common_get_responce'];
          if (inner is Map && inner['getResult'] != null) {
            final raw = inner['getResult'];
            final rawStr = raw is String ? raw : jsonEncode(raw);
            try {
              parsedGetResult = jsonDecode(rawStr) as Map<String, dynamic>;
            } catch (_) {
              // keep null if unparseable
            }
          }
        }
      } catch (_) {}

      // If JD reports that the provided siteId is not supported for this mode
      // (code 2001701 or message contains '不支持siteId'), attempt a single
      // retry without siteId (some siteId types like 导购媒体ID are not
      // accepted for this API). This is a best-effort fallback to improve UX.
      try {
        final shouldRetry = parsedGetResult != null && (parsedGetResult['code']?.toString() == '2001701' || (parsedGetResult['message'] is String && (parsedGetResult['message'] as String).contains('不支持siteId')));
        if (shouldRetry) {
          final bizRetry = Map<String, dynamic>.from(biz);
          bizRetry.remove('siteId');
          final promotionJsonRetry = jsonEncode(bizRetry);
          apiParams['promotionCodeReq'] = promotionJsonRetry;

          // recompute sign for retry
          final keysRetry = apiParams.keys.toList()..sort();
          final sbRetry = StringBuffer();
          sbRetry.write(appSecret);
          for (final k in keysRetry) {
            sbRetry.write(k);
            sbRetry.write(apiParams[k]);
          }
          sbRetry.write(appSecret);
          final signBaseRetry = sbRetry.toString();
          final signRetry = md5.convert(utf8.encode(signBaseRetry)).toString().toUpperCase();
          apiParams['sign'] = signRetry;

          try {
            final respRetry = await http.post(uri, headers: {'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8'}, body: apiParams).timeout(Duration(seconds: 8));
            respStatusFinal = respRetry.statusCode;
            respBodyFinal = respRetry.body;

            // parse getResult from retry response
            try {
              final parsedResp2 = jsonDecode(respBodyFinal) as Map<String, dynamic>;
              if (parsedResp2.containsKey('jd_union_open_promotion_common_get_responce')) {
                final inner2 = parsedResp2['jd_union_open_promotion_common_get_responce'];
                if (inner2 is Map && inner2['getResult'] != null) {
                  final raw2 = inner2['getResult'];
                  final rawStr2 = raw2 is String ? raw2 : jsonEncode(raw2);
                  try {
                    parsedGetResult = jsonDecode(rawStr2) as Map<String, dynamic>;
                  } catch (_) {}
                }
              }
            } catch (_) {}
          } catch (_) {
            // ignore retry failure
          }
        }
      } catch (_) {}

      final debugRecord = {
        'path': '/sign/jd',
        'rawBody': bodyStr,
        'reqBody': payload,
        'apiParams': apiParams,
        'signBase': signBase2,
        'sign': apiParams['sign'],
        'respStatus': respStatusFinal,
        'respBody': respBodyFinal,
        'parsedGetResult': parsedGetResult,
        'ts': DateTime.now().toIso8601String(),
      };
      try {
        _lastReturnDebug = debugRecord;
        _lastReturnHistory.add(debugRecord);
        if (_lastReturnHistory.length > 50) _lastReturnHistory.removeAt(0);
      } catch (_) {}

      if (respStatusFinal != 200) {
        return Response.internalServerError(body: jsonEncode({'error': 'jd api failed', 'status': respStatusFinal, 'debug': debugRecord}), headers: {'content-type': 'application/json'});
      }

      // Try to parse the JD response and detect presence of a promotion clickURL/tpwd
      Map<String, dynamic>? parsed;
      try {
        parsed = jsonDecode(respBodyFinal) as Map<String, dynamic>;
      } catch (_) {
        // If parsing fails, return body + debug
        return Response.internalServerError(body: jsonEncode({'error': 'jd response not json', 'debug': debugRecord}), headers: {'content-type': 'application/json'});
      }

      // extract common locations for clickURL/tpwd
      String? clickUrl;
      String? tpwd;
      try {
        void walk(Map m) {
          for (final e in m.entries) {
            final v = e.value;
            if (v is Map) walk(v);
            if (v is String) {
              final key = e.key.toLowerCase();
              if (clickUrl == null && (key.contains('clickurl') || key.contains('click_url') || key.contains('click'))) clickUrl = v;
              if (tpwd == null && key.contains('tpwd')) tpwd = v;
            }
          }
        }
        walk(parsed);
      } catch (_) {}

      if ((clickUrl == null || clickUrl!.isEmpty) && (tpwd == null || tpwd!.isEmpty)) {
        // If JD returned a parseable business result, surface that to the client
        final innerCode = parsedGetResult != null && parsedGetResult.containsKey('code') ? parsedGetResult['code'] : null;
        final innerMsg = parsedGetResult != null && parsedGetResult.containsKey('message') ? parsedGetResult['message'] : null;
        if (innerCode != null && innerCode.toString() != '200') {
          return Response(400, body: jsonEncode({'error': 'jd_business_error', 'code': innerCode, 'message': innerMsg, 'debug': debugRecord}), headers: {'content-type': 'application/json'});
        }
        // promotion link not found - return debug to client to aid troubleshooting
        return Response.internalServerError(body: jsonEncode({'error': 'no promotion link returned', 'debug': debugRecord}), headers: {'content-type': 'application/json'});
      }

      // Return JD raw response so frontend/backend client can extract clickURL/tpwd
      return Response.ok(resp.body, headers: {'content-type': 'application/json'});
    } catch (e) {
      final rec = {'path': '/sign/jd', 'error': e.toString(), 'payload': payload, 'ts': DateTime.now().toIso8601String()};
      try {
        _lastReturnDebug = rec;
        _lastReturnHistory.add(rec);
        if (_lastReturnHistory.length > 50) _lastReturnHistory.removeAt(0);
      } catch (_) {}
      return Response.internalServerError(body: jsonEncode({'error': e.toString(), 'debug': rec}), headers: {'content-type': 'application/json'});
    }
  });

  // 京东：通过 subUnionId 生成推广链接（jd.union.open.promotion.bysubunionid.get）
  router.post('/jd/union/promotion/bysubunionid', (Request r) async {
    final env = Platform.environment;
    final appKey = env['JD_APP_KEY'];
    final appSecret = env['JD_APP_SECRET'];
    if (appKey == null || appSecret == null || appKey.isEmpty || appSecret.isEmpty) {
      return Response.internalServerError(body: jsonEncode({'error': 'JD_APP_KEY/JD_APP_SECRET not configured'}), headers: {'content-type': 'application/json'});
    }

    final bodyStr = await r.readAsString();
    String promoReqJson = '';
    try {
      final parsed = jsonDecode(bodyStr);
      if (parsed is Map && parsed['promotionCodeReq'] != null) {
        promoReqJson = jsonEncode(parsed['promotionCodeReq']);
      } else if (parsed is Map) {
        // assume the whole body is the PromotionCodeReq
        promoReqJson = jsonEncode(parsed);
      } else {
        promoReqJson = bodyStr;
      }
    } catch (_) {
      // treat body as raw string
      promoReqJson = bodyStr;
    }

    // system params
    final apiParams = <String, String>{
      'method': 'jd.union.open.promotion.bysubunionid.get',
      'app_key': appKey,
      'format': 'json',
      'v': '2.0',
    };

    // timestamp GMT+8
    final beijing = DateTime.now().toUtc().add(Duration(hours: 8));
    String two(int n) => n.toString().padLeft(2, '0');
    apiParams['timestamp'] = '${beijing.year}-${two(beijing.month)}-${two(beijing.day)} ${two(beijing.hour)}:${two(beijing.minute)}:${two(beijing.second)}';

    // business param: promotionCodeReq JSON
    apiParams['promotionCodeReq'] = promoReqJson;

    // sign: MD5(appSecret + k1 + v1 + ... + appSecret) uppercase
    final keys = apiParams.keys.toList()..sort();
    final sb = StringBuffer();
    sb.write(appSecret);
    for (final k in keys) {
      sb.write(k);
      sb.write(apiParams[k]);
    }
    sb.write(appSecret);
    final sign = md5.convert(utf8.encode(sb.toString())).toString().toUpperCase();
    apiParams['sign'] = sign;

    // Debug mode: return signing info instead of calling JD
    try {
      final params = r.requestedUri.queryParameters;
      if (params['debug_sign'] == '1') {
        final debugBody = {'apiParams': apiParams, 'signBase': sb.toString(), 'sign': apiParams['sign'], 'called_method': apiParams['method']};
        return Response.ok(jsonEncode(debugBody), headers: {'content-type': 'application/json'});
      }
    } catch (_) {}

    try {
      // Use the router endpoint consistent with other JD calls
      final uri = Uri.parse('https://router.jd.com/routerjson');
      final resp = await http.post(uri, headers: {'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8'}, body: apiParams).timeout(Duration(seconds: 12));
      if (resp.statusCode != 200) return Response.internalServerError(body: jsonEncode({'error': 'jd api failed', 'status': resp.statusCode, 'body': resp.body}), headers: {'content-type': 'application/json'});
      return Response.ok(resp.body, headers: {'content-type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}), headers: {'content-type': 'application/json'});
    }
  });

  // PDD 备案相关路由：查询备案与生成小程序备案链接
  router.post('/pdd/authority/query', (Request r) async {
    try {
      final env = Platform.environment;
      final clientId = env['PDD_CLIENT_ID'] ?? env['PDD_CLIENTID'] ?? '';
      final clientSecret = env['PDD_CLIENT_SECRET'] ?? env['PDD_CLIENTSECRET'] ?? '';
      if (clientId.isEmpty || clientSecret.isEmpty) return Response.internalServerError(body: jsonEncode({'error': 'PDD_CLIENT_ID/PDD_CLIENT_SECRET not configured'}), headers: {'content-type': 'application/json'});

      final bodyStr = await r.readAsString();
      Map<String, dynamic> payload = {};
      try {
        payload = jsonDecode(bodyStr) as Map<String, dynamic>;
      } catch (_) {
        // try parsing form-encoded
        try {
          if (bodyStr.trim().isNotEmpty) payload = Map<String, dynamic>.from(Uri.splitQueryString(bodyStr));
        } catch (_) {}
      }

      final pidRaw = (payload['pid'] ?? payload['p_id'] ?? '')?.toString() ?? '';
      String pid = pidRaw;
      if (pid.isEmpty && env['PDD_PID'] != null) pid = env['PDD_PID']!;
      // ensure pid has underscore after 8 chars
      if (pid.isNotEmpty && !pid.contains('_') && pid.length > 8) pid = pid.substring(0, 8) + '_' + pid.substring(8);

      final customParameters = payload['custom_parameters'] ?? payload['customParameters'] ?? payload['customParametersJson'] ?? '';
      final biz = <String, dynamic>{};
      if (pid.isNotEmpty) biz['pid'] = pid;
      if (customParameters != null && customParameters.toString().isNotEmpty) biz['custom_parameters'] = customParameters is String ? customParameters : jsonEncode(customParameters);

      final allParams = <String, dynamic>{
        'client_id': clientId,
        'type': 'pdd.ddk.member.authority.query',
        'data_type': 'JSON',
        'timestamp': (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
      };
      allParams.addAll(biz);

      // sign
      final keys = allParams.keys.map((k) => k.toString()).toList()..sort();
      final sb = StringBuffer();
      sb.write(clientSecret);
      for (final k in keys) {
        final v = allParams[k];
        if (v == null) continue;
        sb.write(k);
        if (v is String) sb.write(v);
        else sb.write(jsonEncode(v));
      }
      sb.write(clientSecret);
      final sign = md5.convert(utf8.encode(sb.toString())).toString().toUpperCase();

      final form = <String, String>{};
      allParams.forEach((k, v) {
        if (v == null) return;
        if (v is String) form[k] = v;
        else form[k] = jsonEncode(v);
      });
      form['sign'] = sign;

      final upstream = await http.post(Uri.parse('https://gw-api.pinduoduo.com/api/router'), headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: form).timeout(Duration(seconds: 10));
      return Response(upstream.statusCode, body: upstream.body, headers: {'content-type': upstream.headers['content-type'] ?? 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}), headers: {'content-type': 'application/json'});
    }
  });

  // Sign/generate PDD promotion URL for a goods_sign (used by frontend to get a clickable link)
  router.post('/sign/pdd', (Request r) async {
    try {
      final env = Platform.environment;
      final clientId = env['PDD_CLIENT_ID'] ?? env['PDD_CLIENTID'] ?? '';
      final clientSecret = env['PDD_CLIENT_SECRET'] ?? env['PDD_CLIENTSECRET'] ?? '';
      if (clientId.isEmpty || clientSecret.isEmpty) return Response.internalServerError(body: jsonEncode({'error': 'PDD_CLIENT_ID/PDD_CLIENT_SECRET not configured'}), headers: {'content-type': 'application/json'});

      final bodyStr = await r.readAsString();
      Map<String, dynamic> payload = {};
      try {
        payload = jsonDecode(bodyStr) as Map<String, dynamic>;
      } catch (_) {
        try {
          if (bodyStr.trim().isNotEmpty) payload = Map<String, dynamic>.from(Uri.splitQueryString(bodyStr));
        } catch (_) {}
      }

      // collect goods_sign(s)
      List<String> goodsSignList = [];
      try {
        final rawList = payload['goods_sign_list'] ?? payload['goodsSignList'] ?? payload['goods_sign_list[]'] ?? payload['goods_sign'] ?? payload['goodsSign'] ?? '';
        if (rawList is List) goodsSignList = rawList.map((e) => e.toString()).toList();
        else if (rawList is String && rawList.isNotEmpty) {
          // try parse JSON array string
          try {
            final dec = jsonDecode(rawList);
            if (dec is List) goodsSignList = dec.map((e) => e.toString()).toList();
            else goodsSignList = [rawList.toString()];
          } catch (_) {
            goodsSignList = [rawList.toString()];
          }
        }
      } catch (_) {}

      if (goodsSignList.isEmpty && payload.containsKey('goods_sign')) {
        final gs = (payload['goods_sign'] ?? payload['goodsSign']).toString();
        if (gs.isNotEmpty) goodsSignList = [gs];
      }

      if (goodsSignList.isEmpty) return Response(400, body: jsonEncode({'error': 'goods_sign or goods_sign_list required'}), headers: {'content-type': 'application/json'});

      // Always use server-side configured PDD_PID to avoid clients passing placeholders.
      String pid = env['PDD_PID'] ?? '';
      if (pid.isEmpty) {
        // if server has no PDD_PID configured, fall back to any provided by client (for testing)
        pid = (payload['pid'] ?? payload['p_id'] ?? '')?.toString() ?? '';
      }
      if (pid.isNotEmpty && !pid.contains('_') && pid.length > 8) pid = pid.substring(0, 8) + '_' + pid.substring(8);

      final customParameters = payload['custom_parameters'] ?? payload['customParameters'] ?? payload['customParametersJson'] ?? '{"uid":"chyinan"}';

      final biz = <String, dynamic>{
        'goods_sign_list': goodsSignList,
        'p_id': pid,
        'custom_parameters': customParameters is String ? customParameters : jsonEncode(customParameters),
      };

      final allParams = <String, dynamic>{
        'client_id': clientId,
        'type': 'pdd.ddk.goods.promotion.url.generate',
        'data_type': 'JSON',
        'timestamp': (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
      };
      allParams.addAll(biz);

      final keys = allParams.keys.map((k) => k.toString()).toList()..sort();
      final sb = StringBuffer();
      sb.write(clientSecret);
      for (final k in keys) {
        sb.write(k);
        final v = allParams[k];
        if (v is String) sb.write(v);
        else sb.write(jsonEncode(v));
      }
      sb.write(clientSecret);
      final sign = md5.convert(utf8.encode(sb.toString())).toString().toUpperCase();

      final form = <String, String>{};
      allParams.forEach((k, v) {
        if (v == null) return;
        if (v is String) form[k] = v;
        else form[k] = jsonEncode(v);
      });
      form['sign'] = sign;

      // record debug info before calling PDD
      try {
        final recPre = {'path': '/sign/pdd', 'request': payload, 'allParams': allParams, 'signBase': sb.toString(), 'sign': sign, 'ts': DateTime.now().toIso8601String()};
        _lastReturnDebug = recPre;
        _lastReturnHistory.add(recPre);
        if (_lastReturnHistory.length > 20) _lastReturnHistory.removeAt(0);
        // also print to stdout for quick inspection
        print('PDD sign request: ' + jsonEncode(recPre));
      } catch (_) {}

      final resp = await http.post(Uri.parse('https://gw-api.pinduoduo.com/api/router'), headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: form).timeout(Duration(seconds: 8));
      // capture response for debugging
      Map<String, dynamic> pbody = {};
      try {
        if (resp.statusCode != 200) {
          final dbg = {'status': resp.statusCode, 'body': resp.body};
          final recErr = {'path': '/sign/pdd', 'error': dbg, 'ts': DateTime.now().toIso8601String()};
          _lastReturnDebug = recErr;
          _lastReturnHistory.add(recErr);
          if (_lastReturnHistory.length > 20) _lastReturnHistory.removeAt(0);
          print('PDD sign http error: ' + jsonEncode(dbg));
          return Response.internalServerError(body: jsonEncode({'error': 'pdd promotion api failed', 'detail': resp.body}), headers: {'content-type': 'application/json'});
        }
        pbody = jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (e) {
        final recErr = {'path': '/sign/pdd', 'parseError': e.toString(), 'raw': resp.body};
        _lastReturnDebug = recErr;
        _lastReturnHistory.add(recErr);
        if (_lastReturnHistory.length > 20) _lastReturnHistory.removeAt(0);
        print('PDD sign parse error: ' + e.toString());
        return Response.internalServerError(body: jsonEncode({'error': 'pdd promotion parse failed', 'detail': e.toString()}), headers: {'content-type': 'application/json'});
      }

      try {
        final recResp = {'path': '/sign/pdd', 'request': payload, 'sign': sign, 'status': resp.statusCode, 'response': pbody, 'ts': DateTime.now().toIso8601String()};
        _lastReturnDebug = recResp;
        _lastReturnHistory.add(recResp);
        if (_lastReturnHistory.length > 20) _lastReturnHistory.removeAt(0);
        print('PDD sign response: ' + jsonEncode(recResp));
      } catch (_) {}

      final genResp = (pbody['goods_promotion_url_generate_response'] is Map) ? pbody['goods_promotion_url_generate_response'] as Map<String, dynamic> : null;
      String clickURL = '';
      try {
        if (genResp != null && genResp['goods_promotion_url_list'] is List && (genResp['goods_promotion_url_list'] as List).isNotEmpty) {
          final entry = (genResp['goods_promotion_url_list'] as List).first as Map<String, dynamic>;
          // Prefer short_url (short link) -> mobile_short_url -> mobile_url -> url
          clickURL = (entry['short_url'] ?? entry['mobile_short_url'] ?? entry['mobile_url'] ?? entry['url'] ?? '').toString();
        }
      } catch (_) {}

      return Response.ok(jsonEncode({'clickURL': clickURL, 'raw': pbody}), headers: {'content-type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}), headers: {'content-type': 'application/json'});
    }
  });

  router.post('/pdd/rp/prom/generate', (Request r) async {
    try {
      final env = Platform.environment;
      final clientId = env['PDD_CLIENT_ID'] ?? env['PDD_CLIENTID'] ?? '';
      final clientSecret = env['PDD_CLIENT_SECRET'] ?? env['PDD_CLIENTSECRET'] ?? '';
      if (clientId.isEmpty || clientSecret.isEmpty) return Response.internalServerError(body: jsonEncode({'error': 'PDD_CLIENT_ID/PDD_CLIENT_SECRET not configured'}), headers: {'content-type': 'application/json'});

      final bodyStr = await r.readAsString();
      Map<String, dynamic> payload = {};
      try {
        payload = jsonDecode(bodyStr) as Map<String, dynamic>;
      } catch (_) {
        try {
          if (bodyStr.trim().isNotEmpty) payload = Map<String, dynamic>.from(Uri.splitQueryString(bodyStr));
        } catch (_) {}
      }

      final pidRaw = (payload['pid'] ?? payload['p_id'] ?? '')?.toString() ?? '';
      String pid = pidRaw;
      if (pid.isEmpty && env['PDD_PID'] != null) pid = env['PDD_PID']!;
      if (pid.isNotEmpty && !pid.contains('_') && pid.length > 8) pid = pid.substring(0, 8) + '_' + pid.substring(8);

      final customParameters = payload['custom_parameters'] ?? payload['customParameters'] ?? payload['customParametersJson'] ?? '';
      final pIdList = [pid];

      final biz = <String, dynamic>{
        'p_id_list': pIdList,
        'channel_type': 10,
        'generate_we_app': true,
      };
      if (customParameters != null && customParameters.toString().isNotEmpty) biz['custom_parameters'] = customParameters is String ? customParameters : jsonEncode(customParameters);

      final allParams = <String, dynamic>{
        'client_id': clientId,
        'type': 'pdd.ddk.rp.prom.url.generate',
        'data_type': 'JSON',
        'timestamp': (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
      };
      allParams.addAll(biz);

      final keys = allParams.keys.map((k) => k.toString()).toList()..sort();
      final sb = StringBuffer();
      sb.write(clientSecret);
      for (final k in keys) {
        final v = allParams[k];
        if (v == null) continue;
        sb.write(k);
        if (v is String) sb.write(v);
        else sb.write(jsonEncode(v));
      }
      sb.write(clientSecret);
      final sign = md5.convert(utf8.encode(sb.toString())).toString().toUpperCase();

      final form = <String, String>{};
      allParams.forEach((k, v) {
        if (v == null) return;
        if (v is String) form[k] = v;
        else form[k] = jsonEncode(v);
      });
      form['sign'] = sign;

      final upstream = await http.post(Uri.parse('https://gw-api.pinduoduo.com/api/router'), headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: form).timeout(Duration(seconds: 12));
      return Response(upstream.statusCode, body: upstream.body, headers: {'content-type': upstream.headers['content-type'] ?? 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}), headers: {'content-type': 'application/json'});
    }
  });

  // debug endpoint: accept POSTed form and forward to official router (useful for sign debugging)
  router.post('/pdd/search_debug', (Request r) async {
    try {
      final bodyStr = await r.readAsString();
      final Map<String, String> form = {};
      try {
        form.addAll(Uri.splitQueryString(bodyStr));
      } catch (_) {}
      final upstream = await http.post(Uri.parse('https://gw-api.pinduoduo.com/api/router'), headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: form).timeout(Duration(seconds: 10));
      return Response(upstream.statusCode, body: upstream.body, headers: {'content-type': upstream.headers['content-type'] ?? 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}), headers: {'content-type': 'application/json'});
    }
  });

  router.get('/api/get-jd-promotion', (Request r) async {
    final sku = r.url.queryParameters['sku'];
    if (sku == null || sku.isEmpty) {
      return Response.badRequest(body: jsonEncode({'status': 'error', 'message': 'Missing sku parameter'}), headers: {'Content-Type': 'application/json'});
    }

    final pythonExecutable = Platform.isWindows ? r'.venv\Scripts\python.exe' : '.venv/bin/python';
    final scriptPath = Platform.isWindows ? r'bin\jd_scraper.py' : 'bin/jd_scraper.py';

    try {
      final process = await Process.start(
        pythonExecutable,
        [scriptPath, sku],
        workingDirectory: Directory.current.path,
      );

      String stdoutOutput = '';
      String stderrOutput = '';
      
      process.stdout.transform(utf8.decoder).listen((data) {
        stdoutOutput += data;
      });
      process.stderr.transform(utf8.decoder).listen((data) {
        stderrOutput += data;
      });

      final exitCode = await process.exitCode;

      if (exitCode == 0) {
        final jsonResult = jsonDecode(stdoutOutput);
        if (jsonResult['status'] == 'success') {
          final content = jsonResult['data'] as String;
          final linkMatch = RegExp(r'https?://u\.jd\.com/[A-Za-z0-9]+').firstMatch(content);
          final priceMatch = RegExp(r'京东价：¥([0-9]+(?:\.[0-9]+)?)').firstMatch(content);
          
          final data = {
            'promotionUrl': linkMatch?.group(0),
            'price': priceMatch != null ? double.tryParse(priceMatch!.group(1)!) : null,
            'fullText': content,
          };
          return Response.ok(jsonEncode({'status': 'success', 'data': data}), headers: {'Content-Type': 'application/json'});
        } else {
           return Response.internalServerError(body: jsonEncode({'status': 'error', 'message': 'Python script failed: ${jsonResult['message']}'}), headers: {'Content-Type': 'application/json'});
        }
      } else {
        return Response.internalServerError(body: jsonEncode({'status': 'error', 'message': 'Python script execution failed (Exit Code: $exitCode)', 'details': stderrOutput}), headers: {'Content-Type': 'application/json'});
      }
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'status': 'error', 'message': 'Failed to launch Python script: $e'}), headers: {'Content-Type': 'application/json'});
    }
  });

  final handler = const Pipeline().addMiddleware(logRequests()).addHandler(router.call);
  final server = await serve(handler, '0.0.0.0', 8080);
  print('Server listening on port ${server.port}');
}

/// Interactive launcher: prompts for missing environment values and then
/// launches the server as a child process with the merged environment so the
/// rest of the code can keep using `Platform.environment` unchanged.
void main(List<String> args) async {
  // If we're already the child process, run the server directly.
  if (args.contains('--child')) {
    // remove the flag and forward remaining args to the server runner
    final remaining = List<String>.from(args)..remove('--child');
    await runServer(remaining);
    return;
  }
  // Resolve path to .env file next to this script
  final scriptPath = Platform.script.toFilePath();
  final scriptDir = File(scriptPath).parent;
  final envFile = File('${scriptDir.path}${Platform.pathSeparator}.env');

  // Helper: read simple key=value .env (ignore comments/empty lines)
  Map<String, String> readDotEnv(File f) {
    final out = <String, String>{};
    try {
      if (!f.existsSync()) return out;
      final lines = f.readAsLinesSync();
      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty) continue;
        if (line.startsWith('#')) continue;
        final idx = line.indexOf('=');
        if (idx <= 0) continue;
        final k = line.substring(0, idx).trim();
        var v = line.substring(idx + 1).trim();
        // strip surrounding quotes
        if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith('\'') && v.endsWith('\''))) {
          v = v.substring(1, v.length - 1);
        }
        out[k] = v;
      }
    } catch (_) {}
    return out;
  }

  // Helper: write dot env map to file (atomic write)
  Future<void> writeDotEnv(File f, Map<String, String> map) async {
    try {
      final buf = StringBuffer();
      buf.writeln('# Generated by proxy_server interactive launcher.');
      buf.writeln('# WARNING: Do NOT commit this file to version control. It may contain secrets.');
      final keys = map.keys.toList()..sort();
      for (final k in keys) {
        final v = map[k] ?? '';
        // escape newlines
        final safe = v.replaceAll('\n', '\\n');
        buf.writeln('$k=$safe');
      }
      await f.writeAsString(buf.toString(), flush: true);
    } catch (_) {}
  }

  // Map of environment keys we may prompt for and their human labels.
  final Map<String, String> promptKeys = {
    'JD_APP_KEY': '京东联盟App Key',
    'JD_APP_SECRET': '京东联盟App Secret',
    'JD_UNION_ID': '京东联盟 Union ID',
    'TAOBAO_APP_KEY': '淘宝联盟App Key',
    'TAOBAO_APP_SECRET': '淘宝联盟App Secret',
    'TAOBAO_ADZONE_ID': '淘宝推广位 Adzone ID',
    'PDD_CLIENT_ID': '拼多多 Client ID',
    'PDD_CLIENT_SECRET': '拼多多 Client Secret',
    'PDD_PID': '拼多多 PID',
  };

  // Build a mutable copy of current environment and overlay .env file values
  final Map<String, String> mergedEnv = Map<String, String>.from(Platform.environment);
  final Map<String, String> fileEnv = readDotEnv(envFile);
  for (final entry in fileEnv.entries) {
    final k = entry.key;
    final v = entry.value;
    if (mergedEnv[k] == null || mergedEnv[k]!.trim().isEmpty) mergedEnv[k] = v;
  }

  // Prompt for missing/placeholder values
  for (final entry in promptKeys.entries) {
    final k = entry.key;
    final label = entry.value;
    final current = mergedEnv[k] ?? '';
    if (current.trim().isEmpty || current.startsWith('YOUR_') || current.startsWith('your_')) {
      stdout.write('请输入${label}：');
      final input = stdin.readLineSync();
      // Allow empty input (user can press Enter); we'll still set it so child sees it.
      if (input != null) mergedEnv[k] = input;
    }
  }

  // Persist any entered values back to .env (merge with existing file values)
  final Map<String, String> newFileEnv = Map<String, String>.from(fileEnv);
  for (final k in promptKeys.keys) {
    final v = mergedEnv[k];
    if (v != null && v.trim().isNotEmpty) newFileEnv[k] = v;
  }
  await writeDotEnv(envFile, newFileEnv);

  // Spawn a child Dart process with the merged environment so that existing
  // code that reads Platform.environment continues to work unchanged.
  final String executable = Platform.resolvedExecutable;
  final String script = Platform.script.toFilePath();
  try {
    final process = await Process.start(
      executable,
      [script, '--child'],
      environment: mergedEnv,
      mode: ProcessStartMode.inheritStdio,
    );
    final exitCode = await process.exitCode;
    // Propagate child's exit code
    exit(exitCode);
  } catch (e) {
    stderr.writeln('Failed to spawn child process: $e');
    // As a fallback, run server in-process using the current (unmodified)
    // Platform.environment. This may not reflect user's interactive inputs.
    await runServer(args);
  }
}
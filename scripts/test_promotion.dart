// 简单的测试脚本：调用本地 proxy 的转链与签名接口，便于验证已接入的淘宝/京东功能
// 用法：
// 1) 在后端服务器上设置 VEAPI_KEY（或在 proxy 环境中配置）并启动 proxy:
//    VEAPI_KEY=your_key dart run server/bin/proxy_server.dart
// 2) 在另一个终端运行：
//    dart run scripts/test_promotion.dart

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final backend = Platform.environment['BACKEND_BASE'] ?? 'http://localhost:9527';
  print('Using backend: $backend');

  // 示例：测试淘宝万能转链接口
  final taobaoPayload = jsonEncode({'url': 'https://item.taobao.com/item.htm?id=123456789'});
  print('\n== Testing /taobao/convert ==');
  await _postJson('$backend/taobao/convert', taobaoPayload);

  // 示例：测试京东签名/转链（sign endpoint）
  final jdPayload = jsonEncode({'skuId': '2002'});
  print('\n== Testing /sign/jd ==');
  await _postJson('$backend/sign/jd', jdPayload);

  // 示例：测试淘宝签名端点（/sign/taobao）
  print('\n== Testing /sign/taobao ==');
  await _postJson('$backend/sign/taobao', jsonEncode({'url': 'https://item.taobao.com/item.htm?id=123456789'}));
}

Future<void> _postJson(String url, String body) async {
  try {
    final uri = Uri.parse(url);
    final client = HttpClient();
    final req = await client.postUrl(uri);
    req.headers.set('content-type', 'application/json');
    req.add(utf8.encode(body));
    final resp = await req.close();
    final respBody = await resp.transform(utf8.decoder).join();
    print('HTTP ${resp.statusCode}');
    try {
      final parsed = jsonDecode(respBody);
      print(jsonEncode(parsed));
    } catch (_) {
      print(respBody);
    }
    client.close();
  } catch (e) {
    print('Request to $url failed: $e');
  }
}


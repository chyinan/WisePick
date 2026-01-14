import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../lib/jd_scraper/jd_scraper.dart';

/// 京东爬虫服务测试服务器
///
/// 用法:
///   dart run bin/test_scraper_server.dart [port]
///
/// 默认端口: 8888
void main(List<String> args) async {
  final port = args.isNotEmpty ? int.tryParse(args.first) ?? 8888 : 8888;

  print('========================================');
  print('   京东爬虫服务测试服务器');
  print('========================================\n');

  // 创建主路由
  final router = Router();

  // 添加 CORS 处理
  router.options('/<ignored|.*>', (Request request) {
    return Response.ok('', headers: _corsHeaders);
  });

  // 挂载爬虫服务路由
  final scraperRoutes = JdScraperRoutes();
  router.mount('/', scraperRoutes.router.call);

  // 添加首页信息
  router.get('/', (Request request) {
    return Response.ok(
      jsonEncode({
        'name': 'JD Scraper Test Server',
        'version': '1.0.0',
        'endpoints': {
          'GET /api/jd/scraper/product/:skuId': '获取单个商品信息',
          'POST /api/jd/scraper/products/batch': '批量获取商品信息',
          'GET /api/jd/scraper/status': '获取服务状态',
          'GET /api/jd/cookie/status': '获取 Cookie 状态',
          'POST /api/jd/cookie/update': '更新 Cookie',
          'GET /api/jd/errors': '获取错误日志',
          'POST /api/jd/cache/clear': '清除缓存',
        },
      }),
      headers: {
        'Content-Type': 'application/json',
        ..._corsHeaders,
      },
    );
  });

  // 创建 handler
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsMiddleware())
      .addHandler(router.call);

  // 启动服务器
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);

  print('服务器已启动: http://localhost:${server.port}');
  print('\n可用端点:');
  print('  GET  /                              - 服务信息');
  print('  GET  /api/jd/scraper/product/:skuId - 获取商品信息');
  print('  POST /api/jd/scraper/products/batch - 批量获取商品');
  print('  GET  /api/jd/scraper/status         - 服务状态');
  print('  GET  /api/jd/cookie/status          - Cookie 状态');
  print('  POST /api/jd/cookie/update          - 更新 Cookie');
  print('  GET  /api/jd/errors                 - 错误日志');
  print('  POST /api/jd/cache/clear            - 清除缓存');
  print('\n示例:');
  print('  curl http://localhost:$port/api/jd/scraper/status');
  print('  curl http://localhost:$port/api/jd/cookie/status');
  print('  curl -X POST -d \'{"cookie":"your_cookie"}\' http://localhost:$port/api/jd/cookie/update');
  print('  curl http://localhost:$port/api/jd/scraper/product/10183999034312');
  print('\n按 Ctrl+C 停止服务器...');

  // 优雅关闭
  ProcessSignal.sigint.watch().listen((_) async {
    print('\n正在关闭服务器...');
    await scraperRoutes.close();
    await server.close();
    print('服务器已关闭');
    exit(0);
  });
}

/// CORS 响应头
const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
};

/// CORS 中间件
Middleware _corsMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      final response = await innerHandler(request);
      return response.change(headers: _corsHeaders);
    };
  };
}











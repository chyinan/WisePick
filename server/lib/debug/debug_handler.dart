import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../shared/server_state.dart';

class DebugHandler {
  /// 将调试路由直接注册到传入的 router，避免双重 mount('/') 冲突
  void registerRoutes(Router router) {
    router.get('/__debug/last_return', _handleDebug);
    router.get('/_debug/last_return', _handleDebug);
    router.get('/debug/last_return', _handleDebug);
  }

  Future<Response> _handleDebug(Request req) async {
    if (!isDebugAuthorized(req.headers)) {
      return Response(403,
          body: jsonEncode({'error': 'forbidden'}),
          headers: {'content-type': 'application/json'});
    }
    try {
      final params = req.requestedUri.queryParameters;
      final asHistory = params['history'] == '1';
      if (asHistory) {
        try {
          return Response.ok(
              jsonEncode({'ok': true, 'history': lastReturnHistory}),
              headers: {'content-type': 'application/json'});
        } catch (_) {
          return Response.ok(
              jsonEncode({'ok': true, 'history_count': lastReturnHistory.length}),
              headers: {'content-type': 'application/json'});
        }
      }
      if (lastReturnDebug == null) {
        return Response.ok(jsonEncode({'ok': false, 'msg': 'no debug info'}),
            headers: {'content-type': 'application/json'});
      }
      try {
        return Response.ok(jsonEncode(lastReturnDebug),
            headers: {'content-type': 'application/json'});
      } catch (_) {
        return Response.ok(
            jsonEncode({'ok': true, 'summary': lastReturnDebug.toString()}),
            headers: {'content-type': 'application/json'});
      }
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'content-type': 'application/json'});
    }
  }
}

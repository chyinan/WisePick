import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:http/http.dart' as http;

class ProxyHandler {
  Router get router {
    final r = Router();
    r.post('/v1/chat/completions', _handleProxy);
    r.options('/v1/chat/completions', _handleOptions);
    return r;
  }

  Future<Response> _handleOptions(Request req) async {
    return Response(200, headers: {
      'access-control-allow-origin': '*',
      'access-control-allow-methods': 'POST, OPTIONS',
      'access-control-allow-headers':
          'Origin, Content-Type, Accept, Authorization',
    });
  }

  Future<Response> _handleProxy(Request req) async {
    try {
      final env = Platform.environment;
      final targetUrl =
          env['OPENAI_API_URL'] ?? 'https://api.openai.com/v1/chat/completions';

      // 直接透传客户端的 Authorization 头，服务端不持有 API Key
      final clientAuth = req.headers['authorization'];

      final bodyBytes = await req.read().expand((x) => x).toList();
      final reqBodyStr = utf8.decode(bodyBytes);

      bool wantsStream = false;
      try {
        final decoded = jsonDecode(reqBodyStr);
        if (decoded is Map && decoded['stream'] == true) {
          wantsStream = true;
        }
      } catch (_) {}

      const corsHeaders = {
        'access-control-allow-origin': '*',
        'access-control-allow-methods': 'POST, OPTIONS',
        'access-control-allow-headers':
            'Origin, Content-Type, Accept, Authorization',
      };

      final upstreamHeaders = <String, String>{
        'Content-Type': 'application/json',
        if (clientAuth != null) 'Authorization': clientAuth,
      };

      if (!wantsStream) {
        final upstreamResp = await http.post(
          Uri.parse(targetUrl),
          headers: upstreamHeaders,
          body: reqBodyStr,
        );
        return Response(upstreamResp.statusCode,
            body: upstreamResp.body,
            headers: {
              'content-type':
                  upstreamResp.headers['content-type'] ?? 'application/json',
              ...corsHeaders,
            });
      }

      // 流式响应：监听 stream 结束后关闭 client，防止连接泄漏
      final client = http.Client();
      try {
        final upstreamReq = http.Request('POST', Uri.parse(targetUrl));
        upstreamReq.headers.addAll(upstreamHeaders);
        upstreamReq.body = reqBodyStr;

        final streamedResp = await client.send(upstreamReq);
        final stream = streamedResp.stream.transform(
          StreamTransformer.fromHandlers(
            handleData: (data, sink) => sink.add(data),
            handleDone: (sink) {
              sink.close();
              client.close();
            },
            handleError: (e, st, sink) {
              sink.addError(e, st);
              client.close();
            },
          ),
        );
        return Response(streamedResp.statusCode,
            body: stream,
            headers: {
              'content-type':
                  streamedResp.headers['content-type'] ?? 'text/event-stream',
              ...corsHeaders,
            });
      } catch (e) {
        client.close();
        rethrow;
      }
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'content-type': 'application/json'});
    }
  }
}

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../auth/auth_middleware.dart';
import 'cart_sync_service.dart';
import 'conversation_sync_service.dart';

/// 同步 API 路由处理器
class SyncHandler {
  final CartSyncService _cartSyncService;
  final ConversationSyncService _conversationSyncService;

  SyncHandler({
    CartSyncService? cartSyncService,
    ConversationSyncService? conversationSyncService,
  })  : _cartSyncService = cartSyncService ?? CartSyncService(),
        _conversationSyncService =
            conversationSyncService ?? ConversationSyncService();

  /// 获取路由
  Router get router {
    final router = Router();

    // 购物车同步
    router.post('/cart/sync', _handleCartSync);
    router.get('/cart', _handleGetCart);
    router.get('/cart/version', _handleGetCartVersion);

    // 会话同步
    router.post('/conversations/sync', _handleConversationSync);
    router.get('/conversations', _handleGetConversations);
    router.get('/conversations/<clientId>/messages', _handleGetMessages);
    router.get('/conversations/version', _handleGetConversationVersion);

    return router;
  }

  /// 获取需要认证的 Pipeline
  Handler get handler {
    return const Pipeline()
        .addMiddleware(requireAuth())
        .addHandler(router.call);
  }

  // ============================================================
  // 购物车同步接口
  // ============================================================

  /// POST /api/v1/sync/cart/sync
  /// 同步购物车
  Future<Response> _handleCartSync(Request request) async {
    try {
      final userId = request.context['userId'] as String?;
      if (userId == null) {
        return _jsonResponse({'success': false, 'message': '未授权'}, 401);
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final syncRequest = CartSyncRequest.fromJson(data);

      final response = await _cartSyncService.sync(userId, syncRequest);
      return _jsonResponse(response.toJson(), response.success ? 200 : 500);
    } catch (e) {
      print('[SyncHandler] Cart sync error: $e');
      return _jsonResponse({
        'success': false,
        'message': 'Sync failed: ${e.toString()}',
      }, 500);
    }
  }

  /// GET /api/v1/sync/cart
  /// 获取购物车所有商品
  Future<Response> _handleGetCart(Request request) async {
    try {
      final userId = request.context['userId'] as String?;
      if (userId == null) {
        return _jsonResponse({'success': false, 'message': '未授权'}, 401);
      }

      final items = await _cartSyncService.getCartItems(userId);
      final version = await _cartSyncService.getCurrentVersion(userId);

      return _jsonResponse({
        'success': true,
        'items': items,
        'current_version': version,
      });
    } catch (e) {
      print('[SyncHandler] Get cart error: $e');
      return _jsonResponse({
        'success': false,
        'message': 'Failed to get cart: ${e.toString()}',
      }, 500);
    }
  }

  /// GET /api/v1/sync/cart/version
  /// 获取购物车当前版本号
  Future<Response> _handleGetCartVersion(Request request) async {
    try {
      final userId = request.context['userId'] as String?;
      if (userId == null) {
        return _jsonResponse({'success': false, 'message': '未授权'}, 401);
      }

      final version = await _cartSyncService.getCurrentVersion(userId);
      return _jsonResponse({
        'success': true,
        'current_version': version,
      });
    } catch (e) {
      return _jsonResponse({
        'success': false,
        'message': 'Failed to get version: ${e.toString()}',
      }, 500);
    }
  }

  // ============================================================
  // 会话同步接口
  // ============================================================

  /// POST /api/v1/sync/conversations/sync
  /// 同步会话和消息
  Future<Response> _handleConversationSync(Request request) async {
    try {
      final userId = request.context['userId'] as String?;
      if (userId == null) {
        return _jsonResponse({'success': false, 'message': '未授权'}, 401);
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final syncRequest = ConversationSyncRequest.fromJson(data);

      final response =
          await _conversationSyncService.sync(userId, syncRequest);
      return _jsonResponse(response.toJson(), response.success ? 200 : 500);
    } catch (e) {
      print('[SyncHandler] Conversation sync error: $e');
      return _jsonResponse({
        'success': false,
        'message': 'Sync failed: ${e.toString()}',
      }, 500);
    }
  }

  /// GET /api/v1/sync/conversations
  /// 获取所有会话
  Future<Response> _handleGetConversations(Request request) async {
    try {
      final userId = request.context['userId'] as String?;
      if (userId == null) {
        return _jsonResponse({'success': false, 'message': '未授权'}, 401);
      }

      final conversations =
          await _conversationSyncService.getConversations(userId);
      final version =
          await _conversationSyncService.getCurrentVersion(userId);

      return _jsonResponse({
        'success': true,
        'conversations': conversations,
        'current_version': version,
      });
    } catch (e) {
      print('[SyncHandler] Get conversations error: $e');
      return _jsonResponse({
        'success': false,
        'message': 'Failed to get conversations: ${e.toString()}',
      }, 500);
    }
  }

  /// GET /api/v1/sync/conversations/<clientId>/messages
  /// 获取会话的所有消息
  Future<Response> _handleGetMessages(Request request, String clientId) async {
    try {
      final userId = request.context['userId'] as String?;
      if (userId == null) {
        return _jsonResponse({'success': false, 'message': '未授权'}, 401);
      }

      final messages =
          await _conversationSyncService.getMessages(userId, clientId);

      return _jsonResponse({
        'success': true,
        'messages': messages,
      });
    } catch (e) {
      print('[SyncHandler] Get messages error: $e');
      return _jsonResponse({
        'success': false,
        'message': 'Failed to get messages: ${e.toString()}',
      }, 500);
    }
  }

  /// GET /api/v1/sync/conversations/version
  /// 获取会话当前版本号
  Future<Response> _handleGetConversationVersion(Request request) async {
    try {
      final userId = request.context['userId'] as String?;
      if (userId == null) {
        return _jsonResponse({'success': false, 'message': '未授权'}, 401);
      }

      final version =
          await _conversationSyncService.getCurrentVersion(userId);
      return _jsonResponse({
        'success': true,
        'current_version': version,
      });
    } catch (e) {
      return _jsonResponse({
        'success': false,
        'message': 'Failed to get version: ${e.toString()}',
      }, 500);
    }
  }

  // ============================================================
  // 辅助方法
  // ============================================================

  /// 返回 JSON 响应
  Response _jsonResponse(Map<String, dynamic> data, [int statusCode = 200]) {
    return Response(
      statusCode,
      body: jsonEncode(data),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

/// 创建同步路由的便捷方法
Handler createSyncHandler() {
  return SyncHandler().handler;
}

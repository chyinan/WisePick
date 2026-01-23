import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/database.dart';

class AdminService {
  final Database db;

  AdminService(this.db);

  Router get router {
    final router = Router();
    router.get('/users/stats', _handleUserStats);
    router.get('/system/stats', _handleSystemStats);
    return router;
  }

  Future<Response> _handleUserStats(Request request) async {
    // Check auth (middleware should handle this, but for now we assume it's protected or we check headers)
    
    // Mock user stats
    final stats = {
      'totalUsers': 150,
      'activeUsers': {'daily': 12, 'monthly': 45},
    };
    return Response.ok(jsonEncode(stats), headers: {'content-type': 'application/json'});
  }

  Future<Response> _handleSystemStats(Request request) async {
    final stats = {
      'apiCalls': 1200,
      'errors': 5,
      'uptime': '24h',
    };
    return Response.ok(jsonEncode(stats), headers: {'content-type': 'application/json'});
  }
}

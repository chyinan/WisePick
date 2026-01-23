import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/database.dart';

class AnalyticsService {
  final Database db;

  AnalyticsService(this.db);

  Router get router {
    final router = Router();
    router.get('/consumption-structure', _handleConsumptionStructure);
    router.get('/preferences', _handlePreferences);
    router.get('/shopping-time', _handleShoppingTime);
    return router;
  }

  Future<Response> _handleConsumptionStructure(Request request) async {
    // TODO: Query 'cart_items' table for actual data
    // For now, returning a structure compatible with the frontend expectation
    // This allows the frontend to call this endpoint instead of local mock
    
    final mockData = {
      'categoryDistribution': [
        {'category': 'Electronics', 'count': 10, 'amount': 2500.0, 'percentage': 40.0},
        {'category': 'Clothing', 'count': 5, 'amount': 800.0, 'percentage': 15.0},
        {'category': 'Home', 'count': 8, 'amount': 1200.0, 'percentage': 20.0},
      ],
      'totalAmount': 4500.0,
      'totalProducts': 23,
    };

    return Response.ok(jsonEncode(mockData), headers: {'content-type': 'application/json'});
  }

  Future<Response> _handlePreferences(Request request) async {
    final mockData = {
      'preferredCategories': ['Electronics', 'Home'],
      'priceRange': {'min': 100, 'max': 1000},
      'platformRanking': ['JD', 'Taobao'],
    };
    return Response.ok(jsonEncode(mockData), headers: {'content-type': 'application/json'});
  }

  Future<Response> _handleShoppingTime(Request request) async {
    final mockData = {
      'peakHours': '20:00 - 22:00',
      'hourlyDistribution': List.generate(24, (i) => {'hour': i, 'count': (i > 18 && i < 23) ? 20 : 5}),
    };
    return Response.ok(jsonEncode(mockData), headers: {'content-type': 'application/json'});
  }
}

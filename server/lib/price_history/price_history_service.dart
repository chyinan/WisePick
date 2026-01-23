import 'dart:convert';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/database.dart';

class PriceHistoryService {
  final Database db;

  PriceHistoryService(this.db);

  Router get router {
    final router = Router();
    router.get('/<productId>', _handleGetHistory);
    router.post('/batch', _handleBatchHistory);
    return router;
  }

  Future<Response> _handleGetHistory(Request request, String productId) async {
    // Generate some mock history data
    // In production, query SELECT * FROM price_history WHERE product_id = @productId
    
    final random = Random(productId.hashCode);
    final history = List.generate(30, (index) {
      return {
        'productId': productId,
        'platform': 'jd',
        'timestamp': DateTime.now().subtract(Duration(days: 30 - index)).toIso8601String(),
        'price': 100.0 + random.nextDouble() * 50,
        'originalPrice': 150.0,
      };
    });

    return Response.ok(jsonEncode(history), headers: {'content-type': 'application/json'});
  }

  Future<Response> _handleBatchHistory(Request request) async {
    // Expect body: { "productIds": ["1", "2"] }
    final body = await request.readAsString();
    final json = jsonDecode(body);
    final ids = json['productIds'] as List;
    
    final result = {};
    for (var id in ids) {
      final random = Random(id.hashCode);
      result[id] = List.generate(10, (index) => {
        'price': 100.0 + random.nextDouble() * 20,
        'timestamp': DateTime.now().subtract(Duration(days: 10 - index)).toIso8601String(),
      });
    }
    
    return Response.ok(jsonEncode(result), headers: {'content-type': 'application/json'});
  }
}

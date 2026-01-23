import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

class DecisionService {
  Router get router {
    final router = Router();
    router.post('/compare', _handleCompare);
    router.post('/score', _handleScore);
    return router;
  }

  Future<Response> _handleCompare(Request request) async {
    final body = await request.readAsString();
    // Logic to fetch product details and return comparison matrix
    // For MVP, just echo or return mock
    return Response.ok(jsonEncode({'status': 'ok', 'message': 'Comparison data'}), headers: {'content-type': 'application/json'});
  }

  Future<Response> _handleScore(Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body);
    // Calculate score based on inputs
    // Assuming inputs: price, rating, sales, etc.
    
    final price = data['price'] as num? ?? 0;
    final score = (price < 200) ? 90 : 80; // Simple logic
    
    return Response.ok(jsonEncode({
      'totalScore': score,
      'breakdown': {'price': 20, 'rating': 20},
      'reasoning': 'Price is good.'
    }), headers: {'content-type': 'application/json'});
  }
}

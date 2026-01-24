import '../../core/api_client.dart';

class CartService {
  final ApiClient _apiClient;

  CartService(this._apiClient);

  Future<Map<String, dynamic>> getCartItems({
    int page = 1,
    int pageSize = 20,
    String? platform,
    String? userId,
  }) async {
    var url = '/api/v1/admin/cart-items?page=$page&pageSize=$pageSize';
    if (platform != null && platform.isNotEmpty) {
      url += '&platform=$platform';
    }
    if (userId != null && userId.isNotEmpty) {
      url += '&userId=$userId';
    }
    final response = await _apiClient.get(url);
    final data = response.data as Map<String, dynamic>;
    return {
      'items': List<Map<String, dynamic>>.from(data['items'] ?? []),
      'total': data['total'] ?? 0,
      'page': data['page'] ?? 1,
      'totalPages': data['totalPages'] ?? 1,
    };
  }

  Future<Map<String, dynamic>> getCartStats() async {
    final response = await _apiClient.get('/api/v1/admin/cart-items/stats');
    return response.data as Map<String, dynamic>;
  }

  Future<void> deleteCartItem(String id) async {
    await _apiClient.delete('/api/v1/admin/cart-items/$id');
  }
}

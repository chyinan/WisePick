import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../features/auth/token_manager.dart';

/// 购物车同步请求模型
class CartSyncRequest {
  final int lastSyncVersion;
  final List<CartItemChange> changes;

  CartSyncRequest({
    required this.lastSyncVersion,
    required this.changes,
  });

  Map<String, dynamic> toJson() {
    return {
      'last_sync_version': lastSyncVersion,
      'changes': changes.map((e) => e.toJson()).toList(),
    };
  }
}

/// 购物车项变更
class CartItemChange {
  final String productId;
  final String platform;
  final String? title;
  final double? price;
  final double? originalPrice;
  final double? coupon;
  final double? finalPrice;
  final String? imageUrl;
  final String? shopTitle;
  final String? link;
  final String? description;
  final double? rating;
  final int? sales;
  final double? commission;
  final int? quantity;
  final double? initialPrice;
  final double? currentPrice;
  final Map<String, dynamic>? rawData;
  final bool isDeleted;
  final int localVersion;

  CartItemChange({
    required this.productId,
    required this.platform,
    this.title,
    this.price,
    this.originalPrice,
    this.coupon,
    this.finalPrice,
    this.imageUrl,
    this.shopTitle,
    this.link,
    this.description,
    this.rating,
    this.sales,
    this.commission,
    this.quantity,
    this.initialPrice,
    this.currentPrice,
    this.rawData,
    this.isDeleted = false,
    this.localVersion = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'platform': platform,
      if (title != null) 'title': title,
      if (price != null) 'price': price,
      if (originalPrice != null) 'original_price': originalPrice,
      if (coupon != null) 'coupon': coupon,
      if (finalPrice != null) 'final_price': finalPrice,
      if (imageUrl != null) 'image_url': imageUrl,
      if (shopTitle != null) 'shop_title': shopTitle,
      if (link != null) 'link': link,
      if (description != null) 'description': description,
      if (rating != null) 'rating': rating,
      if (sales != null) 'sales': sales,
      if (commission != null) 'commission': commission,
      if (quantity != null) 'quantity': quantity,
      if (initialPrice != null) 'initial_price': initialPrice,
      if (currentPrice != null) 'current_price': currentPrice,
      if (rawData != null) 'raw_data': rawData,
      'is_deleted': isDeleted,
      'local_version': localVersion,
    };
  }

  /// 从本地购物车项创建变更
  factory CartItemChange.fromLocalItem(Map<String, dynamic> item, {bool isDeleted = false}) {
    return CartItemChange(
      productId: item['id'] as String? ?? item['product_id'] as String? ?? '',
      platform: item['platform'] as String? ?? 'taobao',
      title: item['title'] as String?,
      price: _parseDouble(item['price']),
      originalPrice: _parseDouble(item['original_price'] ?? item['originalPrice']),
      coupon: _parseDouble(item['coupon']),
      finalPrice: _parseDouble(item['final_price'] ?? item['finalPrice']),
      imageUrl: item['image_url'] as String? ?? item['imageUrl'] as String?,
      shopTitle: item['shop_title'] as String? ?? item['shopTitle'] as String?,
      link: item['link'] as String?,
      description: item['description'] as String?,
      rating: _parseDouble(item['rating']),
      sales: item['sales'] as int?,
      commission: _parseDouble(item['commission']),
      quantity: item['qty'] as int? ?? item['quantity'] as int? ?? 1,
      initialPrice: _parseDouble(item['initial_price'] ?? item['initialPrice']),
      currentPrice: _parseDouble(item['current_price'] ?? item['currentPrice']),
      rawData: item['raw_data'] as Map<String, dynamic>?,
      isDeleted: isDeleted,
      localVersion: item['local_version'] as int? ?? 0,
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

/// 购物车同步响应
class CartSyncResponse {
  final bool success;
  final int currentVersion;
  final List<Map<String, dynamic>> items;
  final List<String> deletedIds;
  final String? message;

  CartSyncResponse({
    required this.success,
    required this.currentVersion,
    required this.items,
    required this.deletedIds,
    this.message,
  });

  factory CartSyncResponse.fromJson(Map<String, dynamic> json) {
    return CartSyncResponse(
      success: json['success'] as bool? ?? false,
      currentVersion: json['current_version'] as int? ?? 0,
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      deletedIds: (json['deleted_ids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      message: json['message'] as String?,
    );
  }

  factory CartSyncResponse.error(String message) {
    return CartSyncResponse(
      success: false,
      currentVersion: 0,
      items: [],
      deletedIds: [],
      message: message,
    );
  }
}

/// 购物车同步客户端
class CartSyncClient {
  static const String _syncVersionKey = 'cart_sync_version';
  static const String _pendingChangesKey = 'cart_pending_changes';
  
  final Dio _dio;
  final TokenManager _tokenManager;

  String get _baseUrl {
    try {
      if (Hive.isBoxOpen('settings')) {
        final box = Hive.box('settings');
        final proxyUrl = box.get('proxy_url') as String?;
        if (proxyUrl != null && proxyUrl.isNotEmpty) {
          return proxyUrl;
        }
      }
    } catch (_) {}
    return 'http://localhost:9527';
  }

  String get _syncBaseUrl => '$_baseUrl/api/v1/sync';

  CartSyncClient({Dio? dio, TokenManager? tokenManager})
      : _dio = dio ?? Dio(),
        _tokenManager = tokenManager ?? TokenManager.instance {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  /// 获取请求头
  Map<String, String> _getHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final token = _tokenManager.accessToken;
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// 获取本地保存的同步版本号
  Future<int> getLocalSyncVersion() async {
    final box = await Hive.openBox('sync_meta');
    return box.get(_syncVersionKey, defaultValue: 0) as int;
  }

  /// 保存本地同步版本号
  Future<void> saveLocalSyncVersion(int version) async {
    final box = await Hive.openBox('sync_meta');
    await box.put(_syncVersionKey, version);
  }

  /// 获取待同步的变更
  Future<List<Map<String, dynamic>>> getPendingChanges() async {
    final box = await Hive.openBox('sync_meta');
    final changes = box.get(_pendingChangesKey, defaultValue: <dynamic>[]) as List<dynamic>;
    return changes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// 添加待同步的变更
  Future<void> addPendingChange(Map<String, dynamic> change) async {
    final box = await Hive.openBox('sync_meta');
    final changes = await getPendingChanges();
    
    // 查找是否已有相同 product_id 的变更
    final existingIndex = changes.indexWhere(
      (c) => c['product_id'] == change['product_id'],
    );
    
    if (existingIndex >= 0) {
      // 更新现有变更
      changes[existingIndex] = change;
    } else {
      // 添加新变更
      changes.add(change);
    }
    
    await box.put(_pendingChangesKey, changes);
  }

  /// 清除待同步的变更
  Future<void> clearPendingChanges() async {
    final box = await Hive.openBox('sync_meta');
    await box.put(_pendingChangesKey, <dynamic>[]);
  }

  /// 同步购物车
  Future<CartSyncResponse> sync({List<CartItemChange>? changes}) async {
    if (!_tokenManager.isLoggedIn) {
      return CartSyncResponse.error('用户未登录');
    }

    try {
      final lastVersion = await getLocalSyncVersion();
      
      // 合并传入的变更和待同步的变更
      final allChanges = <CartItemChange>[];
      if (changes != null) {
        allChanges.addAll(changes);
      }
      
      // 加载待同步的变更
      final pendingChanges = await getPendingChanges();
      for (final pending in pendingChanges) {
        allChanges.add(CartItemChange.fromLocalItem(pending, isDeleted: pending['is_deleted'] == true));
      }

      final request = CartSyncRequest(
        lastSyncVersion: lastVersion,
        changes: allChanges,
      );

      final response = await _dio.post(
        '$_syncBaseUrl/cart/sync',
        data: jsonEncode(request.toJson()),
        options: Options(headers: _getHeaders()),
      );

      final result = CartSyncResponse.fromJson(response.data as Map<String, dynamic>);

      if (result.success) {
        // 更新本地同步版本号
        await saveLocalSyncVersion(result.currentVersion);
        // 清除待同步的变更
        await clearPendingChanges();
      }

      return result;
    } on DioException catch (e) {
      return _handleDioError(e);
    } catch (e) {
      return CartSyncResponse.error('同步失败: ${e.toString()}');
    }
  }

  /// 获取云端所有购物车商品
  Future<CartSyncResponse> getCloudItems() async {
    if (!_tokenManager.isLoggedIn) {
      return CartSyncResponse.error('用户未登录');
    }

    try {
      final response = await _dio.get(
        '$_syncBaseUrl/cart',
        options: Options(headers: _getHeaders()),
      );

      final data = response.data as Map<String, dynamic>;
      if (data['success'] == true) {
        return CartSyncResponse(
          success: true,
          currentVersion: data['current_version'] as int? ?? 0,
          items: (data['items'] as List<dynamic>?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList() ??
              [],
          deletedIds: [],
        );
      }
      return CartSyncResponse.error(data['message'] as String? ?? '获取失败');
    } on DioException catch (e) {
      return _handleDioError(e);
    } catch (e) {
      return CartSyncResponse.error('获取失败: ${e.toString()}');
    }
  }

  /// 获取云端当前版本号
  Future<int> getCloudVersion() async {
    if (!_tokenManager.isLoggedIn) {
      return 0;
    }

    try {
      final response = await _dio.get(
        '$_syncBaseUrl/cart/version',
        options: Options(headers: _getHeaders()),
      );

      final data = response.data as Map<String, dynamic>;
      return data['current_version'] as int? ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// 处理 Dio 错误
  CartSyncResponse _handleDioError(DioException e) {
    if (e.response != null) {
      try {
        final data = e.response!.data;
        if (data is Map<String, dynamic>) {
          return CartSyncResponse.fromJson(data);
        }
      } catch (_) {}

      switch (e.response!.statusCode) {
        case 401:
          return CartSyncResponse.error('认证失败，请重新登录');
        case 403:
          return CartSyncResponse.error('没有权限');
        case 500:
          return CartSyncResponse.error('服务器错误');
        default:
          return CartSyncResponse.error('请求失败 (${e.response!.statusCode})');
      }
    }

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return CartSyncResponse.error('连接超时');
    }

    if (e.type == DioExceptionType.connectionError) {
      return CartSyncResponse.error('无法连接服务器');
    }

    return CartSyncResponse.error('网络错误: ${e.message}');
  }
}

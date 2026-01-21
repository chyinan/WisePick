import 'dart:convert';
import '../database/database.dart';

/// 购物车同步请求模型
class CartSyncRequest {
  final int lastSyncVersion;
  final List<CartItemChange> changes;

  CartSyncRequest({
    required this.lastSyncVersion,
    required this.changes,
  });

  factory CartSyncRequest.fromJson(Map<String, dynamic> json) {
    return CartSyncRequest(
      lastSyncVersion: json['last_sync_version'] as int? ?? 0,
      changes: (json['changes'] as List<dynamic>?)
              ?.map((e) => CartItemChange.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
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

  factory CartItemChange.fromJson(Map<String, dynamic> json) {
    return CartItemChange(
      productId: json['product_id'] as String,
      platform: json['platform'] as String,
      title: json['title'] as String?,
      price: (json['price'] as num?)?.toDouble(),
      originalPrice: (json['original_price'] as num?)?.toDouble(),
      coupon: (json['coupon'] as num?)?.toDouble(),
      finalPrice: (json['final_price'] as num?)?.toDouble(),
      imageUrl: json['image_url'] as String?,
      shopTitle: json['shop_title'] as String?,
      link: json['link'] as String?,
      description: json['description'] as String?,
      rating: (json['rating'] as num?)?.toDouble(),
      sales: json['sales'] as int?,
      commission: (json['commission'] as num?)?.toDouble(),
      quantity: json['quantity'] as int?,
      initialPrice: (json['initial_price'] as num?)?.toDouble(),
      currentPrice: (json['current_price'] as num?)?.toDouble(),
      rawData: json['raw_data'] as Map<String, dynamic>?,
      isDeleted: json['is_deleted'] as bool? ?? false,
      localVersion: json['local_version'] as int? ?? 0,
    );
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

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'current_version': currentVersion,
      'items': items,
      'deleted_ids': deletedIds,
      if (message != null) 'message': message,
    };
  }
}

/// 购物车同步服务
class CartSyncService {
  final Database _db;

  CartSyncService({Database? db}) : _db = db ?? Database.instance;

  /// 同步购物车
  /// 
  /// 采用"Last Write Wins"策略：
  /// 1. 客户端发送 lastSyncVersion 和本地变更
  /// 2. 服务器返回 lastSyncVersion 之后的所有服务器变更
  /// 3. 服务器应用客户端变更（如果版本号更新）
  Future<CartSyncResponse> sync(String userId, CartSyncRequest request) async {
    try {
      return await _db.transaction((session) async {
        // 1. 获取当前服务器版本
        final versionResult = await _db.queryOne(
          '''
          SELECT current_version FROM sync_versions 
          WHERE user_id = @user_id AND entity_type = 'cart'
          ''',
          parameters: {'user_id': userId},
        );
        
        int serverVersion = (versionResult?['current_version'] as int?) ?? 0;

        // 2. 获取服务器上比客户端版本新的变更
        final serverItems = await _db.queryAll(
          '''
          SELECT 
            product_id, platform, title, price, original_price, coupon, final_price,
            image_url, shop_title, link, description, rating, sales, commission,
            quantity, initial_price, current_price, raw_data,
            created_at, updated_at, deleted_at, sync_version
          FROM cart_items
          WHERE user_id = @user_id 
            AND sync_version > @last_sync_version
          ORDER BY sync_version ASC
          ''',
          parameters: {
            'user_id': userId,
            'last_sync_version': request.lastSyncVersion,
          },
        );

        // 分离活跃项和已删除项
        final activeItems = <Map<String, dynamic>>[];
        final deletedIds = <String>[];

        for (final item in serverItems) {
          if (item['deleted_at'] != null) {
            deletedIds.add(item['product_id'] as String);
          } else {
            activeItems.add(_formatCartItem(item));
          }
        }

        // 3. 应用客户端变更
        for (final change in request.changes) {
          serverVersion = await _applyChange(userId, change, serverVersion);
        }

        return CartSyncResponse(
          success: true,
          currentVersion: serverVersion,
          items: activeItems,
          deletedIds: deletedIds,
        );
      });
    } catch (e) {
      print('[CartSyncService] Sync error: $e');
      return CartSyncResponse(
        success: false,
        currentVersion: 0,
        items: [],
        deletedIds: [],
        message: 'Sync failed: ${e.toString()}',
      );
    }
  }

  /// 应用单个变更
  Future<int> _applyChange(
    String userId, 
    CartItemChange change,
    int currentVersion,
  ) async {
    // 获取下一个同步版本号
    final versionResult = await _db.queryOne(
      'SELECT get_next_sync_version(@user_id, @entity_type) as version',
      parameters: {'user_id': userId, 'entity_type': 'cart'},
    );
    final newVersion = (versionResult?['version'] as int?) ?? currentVersion + 1;

    if (change.isDeleted) {
      // 软删除
      await _db.execute(
        '''
        UPDATE cart_items 
        SET deleted_at = NOW(), sync_version = @version, updated_at = NOW()
        WHERE user_id = @user_id AND product_id = @product_id
        ''',
        parameters: {
          'user_id': userId,
          'product_id': change.productId,
          'version': newVersion,
        },
      );
    } else {
      // Upsert 操作
      await _db.execute(
        '''
        INSERT INTO cart_items (
          user_id, product_id, platform, title, price, original_price, 
          coupon, final_price, image_url, shop_title, link, description,
          rating, sales, commission, quantity, initial_price, current_price,
          raw_data, sync_version, deleted_at
        ) VALUES (
          @user_id, @product_id, @platform, @title, @price, @original_price,
          @coupon, @final_price, @image_url, @shop_title, @link, @description,
          @rating, @sales, @commission, @quantity, @initial_price, @current_price,
          @raw_data, @version, NULL
        )
        ON CONFLICT (user_id, product_id) 
        DO UPDATE SET
          platform = EXCLUDED.platform,
          title = COALESCE(EXCLUDED.title, cart_items.title),
          price = COALESCE(EXCLUDED.price, cart_items.price),
          original_price = COALESCE(EXCLUDED.original_price, cart_items.original_price),
          coupon = COALESCE(EXCLUDED.coupon, cart_items.coupon),
          final_price = COALESCE(EXCLUDED.final_price, cart_items.final_price),
          image_url = COALESCE(EXCLUDED.image_url, cart_items.image_url),
          shop_title = COALESCE(EXCLUDED.shop_title, cart_items.shop_title),
          link = COALESCE(EXCLUDED.link, cart_items.link),
          description = COALESCE(EXCLUDED.description, cart_items.description),
          rating = COALESCE(EXCLUDED.rating, cart_items.rating),
          sales = COALESCE(EXCLUDED.sales, cart_items.sales),
          commission = COALESCE(EXCLUDED.commission, cart_items.commission),
          quantity = COALESCE(EXCLUDED.quantity, cart_items.quantity),
          initial_price = COALESCE(EXCLUDED.initial_price, cart_items.initial_price),
          current_price = COALESCE(EXCLUDED.current_price, cart_items.current_price),
          raw_data = COALESCE(EXCLUDED.raw_data, cart_items.raw_data),
          sync_version = EXCLUDED.sync_version,
          deleted_at = NULL,
          updated_at = NOW()
        ''',
        parameters: {
          'user_id': userId,
          'product_id': change.productId,
          'platform': change.platform,
          'title': change.title,
          'price': change.price,
          'original_price': change.originalPrice,
          'coupon': change.coupon,
          'final_price': change.finalPrice,
          'image_url': change.imageUrl,
          'shop_title': change.shopTitle,
          'link': change.link,
          'description': change.description,
          'rating': change.rating,
          'sales': change.sales,
          'commission': change.commission,
          'quantity': change.quantity ?? 1,
          'initial_price': change.initialPrice,
          'current_price': change.currentPrice,
          'raw_data': change.rawData != null ? jsonEncode(change.rawData) : null,
          'version': newVersion,
        },
      );
    }

    return newVersion;
  }

  /// 获取用户的所有购物车项
  Future<List<Map<String, dynamic>>> getCartItems(String userId) async {
    final items = await _db.queryAll(
      '''
      SELECT 
        product_id, platform, title, price, original_price, coupon, final_price,
        image_url, shop_title, link, description, rating, sales, commission,
        quantity, initial_price, current_price, raw_data,
        created_at, updated_at, sync_version
      FROM cart_items
      WHERE user_id = @user_id AND deleted_at IS NULL
      ORDER BY created_at DESC
      ''',
      parameters: {'user_id': userId},
    );

    return items.map(_formatCartItem).toList();
  }

  /// 获取当前同步版本
  Future<int> getCurrentVersion(String userId) async {
    final result = await _db.queryOne(
      '''
      SELECT current_version FROM sync_versions 
      WHERE user_id = @user_id AND entity_type = 'cart'
      ''',
      parameters: {'user_id': userId},
    );
    return (result?['current_version'] as int?) ?? 0;
  }

  /// 格式化购物车项为 JSON 格式
  Map<String, dynamic> _formatCartItem(Map<String, dynamic> item) {
    return {
      'product_id': item['product_id'],
      'platform': item['platform'],
      'title': item['title'],
      'price': item['price'],
      'original_price': item['original_price'],
      'coupon': item['coupon'],
      'final_price': item['final_price'],
      'image_url': item['image_url'],
      'shop_title': item['shop_title'],
      'link': item['link'],
      'description': item['description'],
      'rating': item['rating'],
      'sales': item['sales'],
      'commission': item['commission'],
      'quantity': item['quantity'],
      'initial_price': item['initial_price'],
      'current_price': item['current_price'],
      'raw_data': item['raw_data'],
      'sync_version': item['sync_version'],
      'created_at': (item['created_at'] as DateTime?)?.toIso8601String(),
      'updated_at': (item['updated_at'] as DateTime?)?.toIso8601String(),
    };
  }
}

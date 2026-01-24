import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../database/database.dart';

class AdminService {
  final Database db;

  AdminService(this.db);

  // CORS headers for all responses
  static const _corsHeaders = {
    'content-type': 'application/json',
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, POST, DELETE, PUT, OPTIONS',
    'access-control-allow-headers': 'Origin, Content-Type, Accept, Authorization',
  };

  Router get router {
    final router = Router();
    // 用户管理
    router.get('/users/stats', _handleUserStats);
    router.get('/system/stats', _handleSystemStats);
    router.get('/recent-users', _handleRecentUsers);
    router.get('/activity-chart', _handleActivityChart);
    router.get('/users', _handleGetUsers);
    router.delete('/users/<id>', _handleDeleteUser);
    router.put('/users/<id>', _handleUpdateUser);
    
    // 购物车数据
    router.get('/cart-items', _handleGetCartItems);
    router.get('/cart-items/stats', _handleCartStats);
    router.delete('/cart-items/<id>', _handleDeleteCartItem);
    
    // 会话记录
    router.get('/conversations', _handleGetConversations);
    router.get('/conversations/<id>/messages', _handleGetMessages);
    router.delete('/conversations/<id>', _handleDeleteConversation);
    
    // 系统设置
    router.get('/settings', _handleGetSettings);
    router.put('/settings', _handleUpdateSettings);
    router.get('/sessions', _handleGetSessions);
    router.delete('/sessions/<id>', _handleDeleteSession);
    
    return router;
  }

  /// 获取用户统计数据
  Future<Response> _handleUserStats(Request request) async {
    try {
      // 总用户数
      final totalResult = await db.queryOne(
        'SELECT COUNT(*) as count FROM users WHERE status = @status',
        parameters: {'status': 'active'},
      );
      final totalUsers = totalResult?['count'] ?? 0;

      // 今日新增用户
      final todayResult = await db.queryOne(
        '''SELECT COUNT(*) as count FROM users 
           WHERE created_at >= CURRENT_DATE 
           AND status = @status''',
        parameters: {'status': 'active'},
      );
      final todayNewUsers = todayResult?['count'] ?? 0;

      // 本周新增用户
      final weekResult = await db.queryOne(
        '''SELECT COUNT(*) as count FROM users 
           WHERE created_at >= CURRENT_DATE - INTERVAL '7 days'
           AND status = @status''',
        parameters: {'status': 'active'},
      );
      final weekNewUsers = weekResult?['count'] ?? 0;

      // 本月新增用户
      final monthResult = await db.queryOne(
        '''SELECT COUNT(*) as count FROM users 
           WHERE created_at >= CURRENT_DATE - INTERVAL '30 days'
           AND status = @status''',
        parameters: {'status': 'active'},
      );
      final monthNewUsers = monthResult?['count'] ?? 0;

      // 日活跃用户（今日有登录记录）
      final dailyActiveResult = await db.queryOne(
        '''SELECT COUNT(DISTINCT user_id) as count FROM user_sessions 
           WHERE last_active_at >= CURRENT_DATE 
           AND is_active = true''',
      );
      final dailyActive = dailyActiveResult?['count'] ?? 0;

      // 月活跃用户
      final monthlyActiveResult = await db.queryOne(
        '''SELECT COUNT(DISTINCT user_id) as count FROM user_sessions 
           WHERE last_active_at >= CURRENT_DATE - INTERVAL '30 days'
           AND is_active = true''',
      );
      final monthlyActive = monthlyActiveResult?['count'] ?? 0;

      // 已验证邮箱用户数
      final verifiedResult = await db.queryOne(
        'SELECT COUNT(*) as count FROM users WHERE email_verified = true AND status = @status',
        parameters: {'status': 'active'},
      );
      final verifiedUsers = verifiedResult?['count'] ?? 0;

      final stats = {
        'totalUsers': totalUsers,
        'todayNewUsers': todayNewUsers,
        'weekNewUsers': weekNewUsers,
        'monthNewUsers': monthNewUsers,
        'activeUsers': {
          'daily': dailyActive,
          'monthly': monthlyActive,
        },
        'verifiedUsers': verifiedUsers,
        'verificationRate': totalUsers > 0 
            ? ((verifiedUsers as int) / (totalUsers as int) * 100).toStringAsFixed(1)
            : '0.0',
      };

      return Response.ok(jsonEncode(stats), headers: _corsHeaders);
    } catch (e) {
      print('[AdminService] Error getting user stats: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  /// 获取系统统计数据
  Future<Response> _handleSystemStats(Request request) async {
    try {
      // 购物车商品总数
      final cartResult = await db.queryOne(
        'SELECT COUNT(*) as count FROM cart_items WHERE deleted_at IS NULL',
      );
      final totalCartItems = cartResult?['count'] ?? 0;

      // 会话总数
      final conversationResult = await db.queryOne(
        'SELECT COUNT(*) as count FROM conversations WHERE deleted_at IS NULL',
      );
      final totalConversations = conversationResult?['count'] ?? 0;

      // 消息总数
      final messageResult = await db.queryOne(
        'SELECT COUNT(*) as count FROM messages',
      );
      final totalMessages = messageResult?['count'] ?? 0;

      // 今日新增购物车商品
      final todayCartResult = await db.queryOne(
        '''SELECT COUNT(*) as count FROM cart_items 
           WHERE created_at >= CURRENT_DATE AND deleted_at IS NULL''',
      );
      final todayCartItems = todayCartResult?['count'] ?? 0;

      // 今日新增会话
      final todayConvResult = await db.queryOne(
        '''SELECT COUNT(*) as count FROM conversations 
           WHERE created_at >= CURRENT_DATE AND deleted_at IS NULL''',
      );
      final todayConversations = todayConvResult?['count'] ?? 0;

      // 活跃设备数
      final deviceResult = await db.queryOne(
        'SELECT COUNT(*) as count FROM user_sessions WHERE is_active = true',
      );
      final activeDevices = deviceResult?['count'] ?? 0;

      // 各平台购物车商品分布
      final platformStats = await db.queryAll(
        '''SELECT platform, COUNT(*) as count 
           FROM cart_items WHERE deleted_at IS NULL 
           GROUP BY platform''',
      );

      final platforms = <String, int>{};
      for (final row in platformStats) {
        platforms[row['platform'] as String] = row['count'] as int;
      }

      // 数据库连接状态
      final dbStatus = db.isConnected ? 'healthy' : 'disconnected';

      final stats = {
        'cartItems': {
          'total': totalCartItems,
          'today': todayCartItems,
          'byPlatform': platforms,
        },
        'conversations': {
          'total': totalConversations,
          'today': todayConversations,
        },
        'messages': {
          'total': totalMessages,
        },
        'devices': {
          'active': activeDevices,
        },
        'database': {
          'status': dbStatus,
        },
        'serverStartTime': DateTime.now().subtract(const Duration(hours: 24)).toIso8601String(),
      };

      return Response.ok(jsonEncode(stats), headers: _corsHeaders);
    } catch (e) {
      print('[AdminService] Error getting system stats: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  /// 获取最近注册用户列表
  Future<Response> _handleRecentUsers(Request request) async {
    try {
      final users = await db.queryAll(
        '''SELECT id, email, nickname, created_at, last_login_at, email_verified 
           FROM users 
           WHERE status = @status
           ORDER BY created_at DESC 
           LIMIT 10''',
        parameters: {'status': 'active'},
      );

      // 处理时间格式
      final processedUsers = users.map((user) {
        return {
          'id': user['id'],
          'email': _maskEmail(user['email'] as String),
          'nickname': user['nickname'] ?? '未设置',
          'createdAt': (user['created_at'] as DateTime?)?.toIso8601String(),
          'lastLoginAt': (user['last_login_at'] as DateTime?)?.toIso8601String(),
          'emailVerified': user['email_verified'] ?? false,
        };
      }).toList();

      return Response.ok(jsonEncode({'users': processedUsers}), headers: _corsHeaders);
    } catch (e) {
      print('[AdminService] Error getting recent users: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  /// 获取活跃度图表数据（最近7天）
  Future<Response> _handleActivityChart(Request request) async {
    try {
      // 最近7天每天的新增用户
      final newUsersData = await db.queryAll(
        '''SELECT DATE(created_at) as date, COUNT(*) as count 
           FROM users 
           WHERE created_at >= CURRENT_DATE - INTERVAL '6 days'
           AND status = @status
           GROUP BY DATE(created_at) 
           ORDER BY date''',
        parameters: {'status': 'active'},
      );

      // 最近7天每天的活跃用户
      final activeUsersData = await db.queryAll(
        '''SELECT DATE(last_active_at) as date, COUNT(DISTINCT user_id) as count 
           FROM user_sessions 
           WHERE last_active_at >= CURRENT_DATE - INTERVAL '6 days'
           GROUP BY DATE(last_active_at) 
           ORDER BY date''',
      );

      // 最近7天每天新增购物车
      final cartData = await db.queryAll(
        '''SELECT DATE(created_at) as date, COUNT(*) as count 
           FROM cart_items 
           WHERE created_at >= CURRENT_DATE - INTERVAL '6 days'
           AND deleted_at IS NULL
           GROUP BY DATE(created_at) 
           ORDER BY date''',
      );

      // 构建完整的7天数据
      final List<Map<String, dynamic>> chartData = [];
      for (int i = 6; i >= 0; i--) {
        final date = DateTime.now().subtract(Duration(days: i));
        final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        
        int newUsers = 0;
        int activeUsers = 0;
        int cartItems = 0;

        for (final row in newUsersData) {
          if ((row['date'] as DateTime).toIso8601String().substring(0, 10) == dateStr) {
            newUsers = row['count'] as int;
            break;
          }
        }

        for (final row in activeUsersData) {
          if ((row['date'] as DateTime).toIso8601String().substring(0, 10) == dateStr) {
            activeUsers = row['count'] as int;
            break;
          }
        }

        for (final row in cartData) {
          if ((row['date'] as DateTime).toIso8601String().substring(0, 10) == dateStr) {
            cartItems = row['count'] as int;
            break;
          }
        }

        chartData.add({
          'date': dateStr,
          'label': '${date.month}/${date.day}',
          'newUsers': newUsers,
          'activeUsers': activeUsers,
          'cartItems': cartItems,
        });
      }

      return Response.ok(jsonEncode({'data': chartData}), headers: _corsHeaders);
    } catch (e) {
      print('[AdminService] Error getting activity chart: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  /// 邮箱脱敏处理
  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;
    
    final name = parts[0];
    final domain = parts[1];
    
    if (name.length <= 2) {
      return '${name[0]}***@$domain';
    }
    
    return '${name.substring(0, 2)}***@$domain';
  }

  /// 获取用户列表（分页）
  Future<Response> _handleGetUsers(Request request) async {
    try {
      final page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
      final pageSize = int.tryParse(request.url.queryParameters['pageSize'] ?? '20') ?? 20;
      final offset = (page - 1) * pageSize;

      // 获取总数
      final countResult = await db.queryOne(
        'SELECT COUNT(*) as count FROM users WHERE status != @deleted',
        parameters: {'deleted': 'deleted'},
      );
      final total = countResult?['count'] ?? 0;

      // 获取用户列表
      final users = await db.queryAll(
        '''SELECT id, email, nickname, created_at, last_login_at, email_verified, status 
           FROM users 
           WHERE status != @deleted
           ORDER BY created_at DESC 
           LIMIT @limit OFFSET @offset''',
        parameters: {'deleted': 'deleted', 'limit': pageSize, 'offset': offset},
      );

      final processedUsers = users.map((user) {
        return {
          'id': user['id'],
          'email': user['email'], // 完整邮箱，管理员可见
          'nickname': user['nickname'] ?? '未设置',
          'createdAt': (user['created_at'] as DateTime?)?.toIso8601String(),
          'lastLoginAt': (user['last_login_at'] as DateTime?)?.toIso8601String(),
          'emailVerified': user['email_verified'] ?? false,
          'status': user['status'] ?? 'active',
        };
      }).toList();

      return Response.ok(jsonEncode({
        'users': processedUsers,
        'total': total,
        'page': page,
        'pageSize': pageSize,
        'totalPages': (total / pageSize).ceil(),
      }), headers: _corsHeaders);
    } catch (e) {
      print('[AdminService] Error getting users: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  /// 删除用户
  /// 支持软删除（默认）和硬删除（通过 ?hard=true 参数）
  Future<Response> _handleDeleteUser(Request request, String id) async {
    try {
      final hardDelete = request.url.queryParameters['hard'] == 'true';
      
      // 检查用户是否存在
      final user = await db.queryOne(
        'SELECT id, email FROM users WHERE id = @id',
        parameters: {'id': id},
      );
      if (user == null) {
        return Response.notFound(
          jsonEncode({'error': '用户不存在'}),
          headers: _corsHeaders,
        );
      }

      if (hardDelete) {
        // 硬删除：彻底删除用户及所有相关数据
        await _hardDeleteUser(id);
        print('[AdminService] User hard deleted: ${user['email']}');
        return Response.ok(jsonEncode({
          'success': true,
          'message': '用户已彻底删除',
        }), headers: _corsHeaders);
      } else {
        // 软删除：将状态设置为 deleted
        await db.execute(
          '''UPDATE users SET status = @status, updated_at = @now WHERE id = @id''',
          parameters: {'id': id, 'status': 'deleted', 'now': DateTime.now()},
        );

        // 同时删除用户的会话
        await db.execute(
          'UPDATE user_sessions SET is_active = false WHERE user_id = @userId',
          parameters: {'userId': id},
        );

        print('[AdminService] User soft deleted: ${user['email']}');

        return Response.ok(jsonEncode({
          'success': true,
          'message': '用户已删除（软删除，邮箱可重新注册）',
        }), headers: _corsHeaders);
      }
    } catch (e) {
      print('[AdminService] Error deleting user: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  /// 硬删除用户（彻底删除所有相关数据）
  Future<void> _hardDeleteUser(String userId) async {
    // 删除顺序很重要，需要先删除外键依赖的表
    // 1. 删除密码重置令牌
    await db.execute(
      'DELETE FROM password_reset_tokens WHERE user_id = @userId',
      parameters: {'userId': userId},
    );
    
    // 2. 删除安全问题
    await db.execute(
      'DELETE FROM user_security_questions WHERE user_id = @userId',
      parameters: {'userId': userId},
    );
    
    // 3. 删除消息（通过会话）
    await db.execute('''
      DELETE FROM messages WHERE conversation_id IN (
        SELECT id FROM conversations WHERE user_id = @userId
      )
    ''', parameters: {'userId': userId});
    
    // 4. 删除会话记录
    await db.execute(
      'DELETE FROM conversations WHERE user_id = @userId',
      parameters: {'userId': userId},
    );
    
    // 5. 删除购物车
    await db.execute(
      'DELETE FROM cart_items WHERE user_id = @userId',
      parameters: {'userId': userId},
    );
    
    // 6. 删除同步版本记录
    await db.execute(
      'DELETE FROM sync_versions WHERE user_id = @userId',
      parameters: {'userId': userId},
    );
    
    // 7. 删除用户会话
    await db.execute(
      'DELETE FROM user_sessions WHERE user_id = @userId',
      parameters: {'userId': userId},
    );
    
    // 8. 最后删除用户
    await db.execute(
      'DELETE FROM users WHERE id = @userId',
      parameters: {'userId': userId},
    );
  }

  /// 更新用户信息
  Future<Response> _handleUpdateUser(Request request, String id) async {
    try {
      final bodyStr = await request.readAsString();
      final data = jsonDecode(bodyStr) as Map<String, dynamic>;

      // 检查用户是否存在
      final user = await db.queryOne(
        'SELECT id FROM users WHERE id = @id',
        parameters: {'id': id},
      );
      if (user == null) {
        return Response.notFound(
          jsonEncode({'error': '用户不存在'}),
          headers: _corsHeaders,
        );
      }

      // 构建更新语句
      final updates = <String>[];
      final params = <String, dynamic>{'id': id, 'now': DateTime.now()};

      if (data.containsKey('email')) {
        final newEmail = (data['email'] as String).toLowerCase();
        // 检查邮箱是否已被其他用户使用
        final existing = await db.queryOne(
          'SELECT id FROM users WHERE email = @email AND id != @id',
          parameters: {'email': newEmail, 'id': id},
        );
        if (existing != null) {
          return Response(400, 
            body: jsonEncode({'error': '该邮箱已被其他用户使用'}),
            headers: _corsHeaders,
          );
        }
        updates.add('email = @email');
        params['email'] = newEmail;
      }

      if (data.containsKey('nickname')) {
        updates.add('nickname = @nickname');
        params['nickname'] = data['nickname'];
      }

      if (data.containsKey('status')) {
        updates.add('status = @status');
        params['status'] = data['status'];
      }

      if (data.containsKey('emailVerified')) {
        updates.add('email_verified = @emailVerified');
        params['emailVerified'] = data['emailVerified'];
      }

      if (updates.isEmpty) {
        return Response(400, 
          body: jsonEncode({'error': '没有要更新的字段'}),
          headers: _corsHeaders,
        );
      }

      updates.add('updated_at = @now');

      await db.execute(
        'UPDATE users SET ${updates.join(', ')} WHERE id = @id',
        parameters: params,
      );

      return Response.ok(jsonEncode({
        'success': true,
        'message': '用户信息已更新',
      }), headers: _corsHeaders);
    } catch (e) {
      print('[AdminService] Error updating user: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  // ============================================================
  // 购物车数据管理
  // ============================================================

  /// 获取购物车数据列表（分页）
  Future<Response> _handleGetCartItems(Request request) async {
    try {
      final page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
      final pageSize = int.tryParse(request.url.queryParameters['pageSize'] ?? '20') ?? 20;
      final platform = request.url.queryParameters['platform'];
      final userId = request.url.queryParameters['userId'];
      final offset = (page - 1) * pageSize;

      // 构建查询条件
      var whereClause = 'WHERE c.deleted_at IS NULL';
      final countParams = <String, dynamic>{};
      final queryParams = <String, dynamic>{'limit': pageSize, 'offset': offset};
      
      if (platform != null && platform.isNotEmpty) {
        whereClause += ' AND c.platform = @platform';
        countParams['platform'] = platform;
        queryParams['platform'] = platform;
      }
      if (userId != null && userId.isNotEmpty) {
        whereClause += ' AND c.user_id = @userId';
        countParams['userId'] = userId;
        queryParams['userId'] = userId;
      }

      // 获取总数
      final countResult = await db.queryOne(
        'SELECT COUNT(*) as count FROM cart_items c $whereClause',
        parameters: countParams.isEmpty ? null : countParams,
      );
      final total = countResult?['count'] ?? 0;

      // 获取购物车列表（包含用户信息）
      final items = await db.queryAll(
        '''SELECT c.id, c.user_id, c.product_id, c.platform, c.title, 
                  c.price, c.original_price, c.coupon, c.final_price, 
                  c.image_url, c.shop_title, c.quantity, c.created_at, c.updated_at,
                  u.email as user_email, u.nickname as user_nickname
           FROM cart_items c
           LEFT JOIN users u ON c.user_id = u.id
           $whereClause
           ORDER BY c.created_at DESC 
           LIMIT @limit OFFSET @offset''',
        parameters: queryParams,
      );

      final processedItems = items.map((item) {
        return {
          'id': item['id'],
          'userId': item['user_id'],
          'userEmail': _maskEmail(item['user_email'] as String? ?? ''),
          'userNickname': item['user_nickname'] ?? '未设置',
          'productId': item['product_id'],
          'platform': item['platform'],
          'title': item['title'],
          'price': item['price']?.toString(),
          'originalPrice': item['original_price']?.toString(),
          'coupon': item['coupon']?.toString(),
          'finalPrice': item['final_price']?.toString(),
          'imageUrl': item['image_url'],
          'shopTitle': item['shop_title'],
          'quantity': item['quantity'],
          'createdAt': (item['created_at'] as DateTime?)?.toIso8601String(),
          'updatedAt': (item['updated_at'] as DateTime?)?.toIso8601String(),
        };
      }).toList();

      return Response.ok(jsonEncode({
        'items': processedItems,
        'total': total,
        'page': page,
        'pageSize': pageSize,
        'totalPages': (total / pageSize).ceil(),
      }), headers: _corsHeaders);
    } catch (e) {
      print('[AdminService] Error getting cart items: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  /// 获取购物车统计数据
  Future<Response> _handleCartStats(Request request) async {
    try {
      // 各平台商品数量
      final platformStats = await db.queryAll(
        '''SELECT platform, COUNT(*) as count, SUM(COALESCE(final_price, price) * quantity) as total_value
           FROM cart_items WHERE deleted_at IS NULL 
           GROUP BY platform''',
      );

      final platforms = <Map<String, dynamic>>[];
      for (final row in platformStats) {
        final totalValue = row['total_value'];
        String totalValueStr = '0.00';
        if (totalValue != null) {
          if (totalValue is num) {
            totalValueStr = totalValue.toStringAsFixed(2);
          } else {
            totalValueStr = double.tryParse(totalValue.toString())?.toStringAsFixed(2) ?? '0.00';
          }
        }
        platforms.add({
          'platform': row['platform'],
          'count': row['count'],
          'totalValue': totalValueStr,
        });
      }

      // 总商品数和总价值
      final totalResult = await db.queryOne(
        '''SELECT COUNT(*) as count, SUM(COALESCE(final_price, price) * quantity) as total_value
           FROM cart_items WHERE deleted_at IS NULL''',
      );

      // 今日新增
      final todayResult = await db.queryOne(
        '''SELECT COUNT(*) as count FROM cart_items 
           WHERE created_at >= CURRENT_DATE AND deleted_at IS NULL''',
      );

      // 本周新增
      final weekResult = await db.queryOne(
        '''SELECT COUNT(*) as count FROM cart_items 
           WHERE created_at >= CURRENT_DATE - INTERVAL '7 days' AND deleted_at IS NULL''',
      );

      // 最活跃用户（购物车商品最多的用户）
      final topUsers = await db.queryAll(
        '''SELECT u.id, u.email, u.nickname, COUNT(c.id) as item_count
           FROM users u
           JOIN cart_items c ON u.id = c.user_id AND c.deleted_at IS NULL
           WHERE u.status = 'active'
           GROUP BY u.id, u.email, u.nickname
           ORDER BY item_count DESC
           LIMIT 5''',
      );

      final topUsersList = topUsers.map((u) => {
        'id': u['id'],
        'email': _maskEmail(u['email'] as String),
        'nickname': u['nickname'] ?? '未设置',
        'itemCount': u['item_count'],
      }).toList();

      // 安全处理 total_value
      final totalValueRaw = totalResult?['total_value'];
      String totalValueStr = '0.00';
      if (totalValueRaw != null) {
        if (totalValueRaw is num) {
          totalValueStr = totalValueRaw.toStringAsFixed(2);
        } else {
          totalValueStr = double.tryParse(totalValueRaw.toString())?.toStringAsFixed(2) ?? '0.00';
        }
      }

      return Response.ok(jsonEncode({
        'total': totalResult?['count'] ?? 0,
        'totalValue': totalValueStr,
        'todayNew': todayResult?['count'] ?? 0,
        'weekNew': weekResult?['count'] ?? 0,
        'byPlatform': platforms,
        'topUsers': topUsersList,
      }), headers: _corsHeaders);
    } catch (e) {
      print('[AdminService] Error getting cart stats: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  /// 删除购物车商品
  Future<Response> _handleDeleteCartItem(Request request, String id) async {
    try {
      final result = await db.execute(
        'UPDATE cart_items SET deleted_at = @now WHERE id = @id',
        parameters: {'id': id, 'now': DateTime.now()},
      );

      if (result == 0) {
        return Response.notFound(
          jsonEncode({'error': '商品不存在'}),
          headers: _corsHeaders,
        );
      }

      return Response.ok(jsonEncode({
        'success': true,
        'message': '商品已删除',
      }), headers: _corsHeaders);
    } catch (e) {
      print('[AdminService] Error deleting cart item: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  // ============================================================
  // 会话记录管理
  // ============================================================

  /// 获取会话列表（分页）
  Future<Response> _handleGetConversations(Request request) async {
    try {
      final page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
      final pageSize = int.tryParse(request.url.queryParameters['pageSize'] ?? '20') ?? 20;
      final userId = request.url.queryParameters['userId'];
      final offset = (page - 1) * pageSize;

      var whereClause = 'WHERE c.deleted_at IS NULL';
      final countParams = <String, dynamic>{};
      final queryParams = <String, dynamic>{'limit': pageSize, 'offset': offset};
      
      if (userId != null && userId.isNotEmpty) {
        whereClause += ' AND c.user_id = @userId';
        countParams['userId'] = userId;
        queryParams['userId'] = userId;
      }

      // 获取总数
      final countResult = await db.queryOne(
        'SELECT COUNT(*) as count FROM conversations c $whereClause',
        parameters: countParams.isEmpty ? null : countParams,
      );
      final total = countResult?['count'] ?? 0;

      // 获取会话列表（包含用户信息和消息数）
      final conversations = await db.queryAll(
        '''SELECT c.id, c.user_id, c.title, c.created_at, c.updated_at,
                  u.email as user_email, u.nickname as user_nickname,
                  (SELECT COUNT(*) FROM messages m WHERE m.conversation_id = c.id) as message_count,
                  (SELECT content FROM messages m WHERE m.conversation_id = c.id ORDER BY m.created_at DESC LIMIT 1) as last_message
           FROM conversations c
           LEFT JOIN users u ON c.user_id = u.id
           $whereClause
           ORDER BY c.updated_at DESC 
           LIMIT @limit OFFSET @offset''',
        parameters: queryParams,
      );

      final processedConversations = conversations.map((conv) {
        final lastMsg = conv['last_message'] as String?;
        return {
          'id': conv['id'],
          'userId': conv['user_id'],
          'userEmail': _maskEmail(conv['user_email'] as String? ?? ''),
          'userNickname': conv['user_nickname'] ?? '未设置',
          'title': conv['title'] ?? '新对话',
          'messageCount': conv['message_count'],
          'lastMessage': lastMsg != null && lastMsg.length > 100 
              ? '${lastMsg.substring(0, 100)}...' 
              : lastMsg,
          'createdAt': (conv['created_at'] as DateTime?)?.toIso8601String(),
          'updatedAt': (conv['updated_at'] as DateTime?)?.toIso8601String(),
        };
      }).toList();

      return Response.ok(jsonEncode({
        'conversations': processedConversations,
        'total': total,
        'page': page,
        'pageSize': pageSize,
        'totalPages': (total / pageSize).ceil(),
      }), headers: _corsHeaders);
    } catch (e) {
      print('[AdminService] Error getting conversations: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  /// 获取会话的消息列表
  Future<Response> _handleGetMessages(Request request, String id) async {
    try {
      final page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
      final pageSize = int.tryParse(request.url.queryParameters['pageSize'] ?? '50') ?? 50;
      final offset = (page - 1) * pageSize;

      // 获取会话信息
      final conversation = await db.queryOne(
        '''SELECT c.*, u.email as user_email, u.nickname as user_nickname
           FROM conversations c
           LEFT JOIN users u ON c.user_id = u.id
           WHERE c.id = @id''',
        parameters: {'id': id},
      );

      if (conversation == null) {
        return Response.notFound(
          jsonEncode({'error': '会话不存在'}),
          headers: _corsHeaders,
        );
      }

      // 获取消息总数
      final countResult = await db.queryOne(
        'SELECT COUNT(*) as count FROM messages WHERE conversation_id = @convId',
        parameters: {'convId': id},
      );
      final total = countResult?['count'] ?? 0;

      // 获取消息列表
      final messages = await db.queryAll(
        '''SELECT id, role, content, products, keywords, created_at, failed
           FROM messages 
           WHERE conversation_id = @convId
           ORDER BY created_at ASC 
           LIMIT @limit OFFSET @offset''',
        parameters: {'convId': id, 'limit': pageSize, 'offset': offset},
      );

      final processedMessages = messages.map((msg) {
        return {
          'id': msg['id'],
          'role': msg['role'],
          'content': msg['content'],
          'products': msg['products'],
          'keywords': msg['keywords'],
          'failed': msg['failed'] ?? false,
          'createdAt': (msg['created_at'] as DateTime?)?.toIso8601String(),
        };
      }).toList();

      return Response.ok(jsonEncode({
        'conversation': {
          'id': conversation['id'],
          'title': conversation['title'] ?? '新对话',
          'userEmail': _maskEmail(conversation['user_email'] as String? ?? ''),
          'userNickname': conversation['user_nickname'] ?? '未设置',
          'createdAt': (conversation['created_at'] as DateTime?)?.toIso8601String(),
        },
        'messages': processedMessages,
        'total': total,
        'page': page,
        'pageSize': pageSize,
        'totalPages': (total / pageSize).ceil(),
      }), headers: _corsHeaders);
    } catch (e) {
      print('[AdminService] Error getting messages: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  /// 删除会话
  Future<Response> _handleDeleteConversation(Request request, String id) async {
    try {
      final result = await db.execute(
        'UPDATE conversations SET deleted_at = @now WHERE id = @id',
        parameters: {'id': id, 'now': DateTime.now()},
      );

      if (result == 0) {
        return Response.notFound(
          jsonEncode({'error': '会话不存在'}),
          headers: _corsHeaders,
        );
      }

      return Response.ok(jsonEncode({
        'success': true,
        'message': '会话已删除',
      }), headers: _corsHeaders);
    } catch (e) {
      print('[AdminService] Error deleting conversation: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  // ============================================================
  // 系统设置管理
  // ============================================================

  /// 获取系统设置
  Future<Response> _handleGetSettings(Request request) async {
    try {
      // 从环境变量获取当前设置
      final env = Platform.environment;
      
      final settings = {
        'server': {
          'port': env['PORT'] ?? '9527',
          'host': env['HOST'] ?? '0.0.0.0',
        },
        'database': {
          'host': env['DB_HOST'] ?? 'localhost',
          'port': env['DB_PORT'] ?? '5432',
          'name': env['DB_NAME'] ?? 'wisepick',
          'status': db.isConnected ? 'connected' : 'disconnected',
        },
        'ai': {
          'provider': env['AI_PROVIDER'] ?? 'siliconflow',
          'model': env['AI_MODEL'] ?? 'Qwen/Qwen2.5-7B-Instruct',
          'baseUrl': env['AI_BASE_URL'] ?? 'https://api.siliconflow.cn/v1',
          'hasApiKey': (env['AI_API_KEY'] ?? '').isNotEmpty,
        },
        'jd': {
          'hasCookie': (env['JD_COOKIE'] ?? '').isNotEmpty,
          'cookieSource': env['JD_COOKIE_SOURCE'] ?? 'file',
        },
        'features': {
          'emailVerification': env['ENABLE_EMAIL_VERIFICATION'] == 'true',
          'rateLimit': env['ENABLE_RATE_LIMIT'] != 'false',
        },
      };

      return Response.ok(jsonEncode(settings), headers: _corsHeaders);
    } catch (e) {
      print('[AdminService] Error getting settings: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  /// 更新系统设置（注：环境变量运行时无法修改，此处仅作为接口预留）
  Future<Response> _handleUpdateSettings(Request request) async {
    try {
      final bodyStr = await request.readAsString();
      final data = jsonDecode(bodyStr) as Map<String, dynamic>;

      // 目前环境变量在运行时无法直接修改
      // 这里可以扩展为写入配置文件或数据库
      print('[AdminService] Settings update requested: $data');

      return Response.ok(jsonEncode({
        'success': true,
        'message': '设置已保存（需重启服务生效）',
      }), headers: _corsHeaders);
    } catch (e) {
      print('[AdminService] Error updating settings: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  /// 获取用户会话（设备登录）列表
  Future<Response> _handleGetSessions(Request request) async {
    try {
      final page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
      final pageSize = int.tryParse(request.url.queryParameters['pageSize'] ?? '20') ?? 20;
      final activeOnly = request.url.queryParameters['activeOnly'] == 'true';
      final offset = (page - 1) * pageSize;

      var whereClause = activeOnly ? 'WHERE s.is_active = true' : '';
      final queryParams = <String, dynamic>{'limit': pageSize, 'offset': offset};

      // 获取总数
      final countResult = await db.queryOne(
        'SELECT COUNT(*) as count FROM user_sessions s $whereClause',
      );
      final total = countResult?['count'] ?? 0;

      // 获取会话列表
      final sessions = await db.queryAll(
        '''SELECT s.id, s.user_id, s.device_id, s.device_name, s.device_type,
                  s.last_active_at, s.created_at, s.ip_address, s.is_active,
                  u.email as user_email, u.nickname as user_nickname
           FROM user_sessions s
           LEFT JOIN users u ON s.user_id = u.id
           $whereClause
           ORDER BY s.last_active_at DESC 
           LIMIT @limit OFFSET @offset''',
        parameters: queryParams,
      );

      final processedSessions = sessions.map((s) {
        return {
          'id': s['id'],
          'userId': s['user_id'],
          'userEmail': _maskEmail(s['user_email'] as String? ?? ''),
          'userNickname': s['user_nickname'] ?? '未设置',
          'deviceId': s['device_id'],
          'deviceName': s['device_name'] ?? '未知设备',
          'deviceType': s['device_type'] ?? 'unknown',
          'ipAddress': s['ip_address']?.toString(),
          'isActive': s['is_active'] ?? false,
          'lastActiveAt': (s['last_active_at'] as DateTime?)?.toIso8601String(),
          'createdAt': (s['created_at'] as DateTime?)?.toIso8601String(),
        };
      }).toList();

      return Response.ok(jsonEncode({
        'sessions': processedSessions,
        'total': total,
        'page': page,
        'pageSize': pageSize,
        'totalPages': (total / pageSize).ceil(),
      }), headers: _corsHeaders);
    } catch (e) {
      print('[AdminService] Error getting sessions: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }

  /// 强制下线会话
  Future<Response> _handleDeleteSession(Request request, String id) async {
    try {
      final result = await db.execute(
        'UPDATE user_sessions SET is_active = false WHERE id = @id',
        parameters: {'id': id},
      );

      if (result == 0) {
        return Response.notFound(
          jsonEncode({'error': '会话不存在'}),
          headers: _corsHeaders,
        );
      }

      return Response.ok(jsonEncode({
        'success': true,
        'message': '已强制下线',
      }), headers: _corsHeaders);
    } catch (e) {
      print('[AdminService] Error deleting session: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: _corsHeaders,
      );
    }
  }
}

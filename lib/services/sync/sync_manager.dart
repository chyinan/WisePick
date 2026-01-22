import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../features/auth/token_manager.dart';
import '../../features/auth/auth_providers.dart';
import '../../features/cart/cart_service.dart';
import '../../features/chat/conversation_repository.dart';
import '../../features/chat/conversation_model.dart';
import '../../features/chat/chat_message.dart';
import '../../features/products/product_model.dart';
import 'cart_sync_client.dart';
import 'conversation_sync_client.dart';
import 'offline_sync_queue.dart';
import 'conflict_resolver.dart';

/// 同步状态
enum SyncStatus {
  idle,
  syncing,
  success,
  error,
  offline, // 离线状态，有待同步的变更
}

/// 同步状态模型
class SyncState {
  final SyncStatus cartStatus;
  final SyncStatus conversationStatus;
  final String? cartError;
  final String? conversationError;
  final DateTime? lastCartSync;
  final DateTime? lastConversationSync;
  final int pendingCartChanges;
  final int pendingConversationChanges;

  const SyncState({
    this.cartStatus = SyncStatus.idle,
    this.conversationStatus = SyncStatus.idle,
    this.cartError,
    this.conversationError,
    this.lastCartSync,
    this.lastConversationSync,
    this.pendingCartChanges = 0,
    this.pendingConversationChanges = 0,
  });

  SyncState copyWith({
    SyncStatus? cartStatus,
    SyncStatus? conversationStatus,
    String? cartError,
    String? conversationError,
    DateTime? lastCartSync,
    DateTime? lastConversationSync,
    int? pendingCartChanges,
    int? pendingConversationChanges,
  }) {
    return SyncState(
      cartStatus: cartStatus ?? this.cartStatus,
      conversationStatus: conversationStatus ?? this.conversationStatus,
      cartError: cartError,
      conversationError: conversationError,
      lastCartSync: lastCartSync ?? this.lastCartSync,
      lastConversationSync: lastConversationSync ?? this.lastConversationSync,
      pendingCartChanges: pendingCartChanges ?? this.pendingCartChanges,
      pendingConversationChanges: pendingConversationChanges ?? this.pendingConversationChanges,
    );
  }

  bool get isSyncing =>
      cartStatus == SyncStatus.syncing ||
      conversationStatus == SyncStatus.syncing;

  bool get hasPendingChanges =>
      pendingCartChanges > 0 || pendingConversationChanges > 0;
}

/// 购物车同步客户端 Provider
final cartSyncClientProvider = Provider<CartSyncClient>((ref) {
  // 使用 auth_providers 中的 tokenManager 确保一致性
  final tokenManager = ref.watch(tokenManagerProvider);
  return CartSyncClient(tokenManager: tokenManager);
});

/// 会话同步客户端 Provider
final conversationSyncClientProvider = Provider<ConversationSyncClient>((ref) {
  // 使用 auth_providers 中的 tokenManager 确保一致性
  final tokenManager = ref.watch(tokenManagerProvider);
  return ConversationSyncClient(tokenManager: tokenManager);
});

/// 离线同步队列 Provider
final offlineSyncQueueProvider = Provider<OfflineSyncQueue>((ref) {
  final queue = OfflineSyncQueue();
  // 初始化队列
  queue.init();
  return queue;
});

/// 同步状态管理器
class SyncManager extends StateNotifier<SyncState> {
  final CartSyncClient _cartSyncClient;
  final ConversationSyncClient _conversationSyncClient;
  final TokenManager _tokenManager;
  final OfflineSyncQueue _offlineQueue;
  final Ref _ref;

  /// 防抖计时器
  Timer? _cartDebounceTimer;
  Timer? _conversationDebounceTimer;

  /// 防抖延迟时间
  static const Duration _debounceDuration = Duration(seconds: 2);

  SyncManager({
    required CartSyncClient cartSyncClient,
    required ConversationSyncClient conversationSyncClient,
    required TokenManager tokenManager,
    required OfflineSyncQueue offlineQueue,
    required Ref ref,
  })  : _cartSyncClient = cartSyncClient,
        _conversationSyncClient = conversationSyncClient,
        _tokenManager = tokenManager,
        _offlineQueue = offlineQueue,
        _ref = ref,
        super(const SyncState()) {
    // 设置网络恢复回调
    _offlineQueue.onNetworkRestored = _onNetworkRestored;
    // 初始化时更新待同步变更数量
    _updatePendingChangesCount();
  }

  /// 网络恢复时自动同步
  void _onNetworkRestored() {
    if (isLoggedIn && _offlineQueue.hasPendingChanges) {
      syncAll();
    }
  }

  /// 更新待同步变更数量
  void _updatePendingChangesCount() {
    state = state.copyWith(
      pendingCartChanges: _offlineQueue.pendingCartChangesCount,
      pendingConversationChanges: _offlineQueue.pendingConversationChangesCount,
    );
  }

  /// 是否已登录
  bool get isLoggedIn => _tokenManager.isLoggedIn;

  /// 同步所有数据
  Future<void> syncAll() async {
    if (!isLoggedIn) return;

    // 在同步前检查并刷新 token
    await _ensureValidToken();

    await Future.wait([
      syncCart(),
      syncConversations(),
    ]);
  }

  /// 确保 token 有效，如果过期则刷新
  Future<bool> _ensureValidToken() async {
    if (_tokenManager.isAccessTokenExpired) {
      try {
        final authService = _ref.read(authServiceProvider);
        final result = await authService.refreshToken();
        return result.success;
      } catch (e) {
        return false;
      }
    }
    return true;
  }

  /// 同步购物车
  Future<void> syncCart() async {
    if (!isLoggedIn) return;

    // 检查网络连接
    final hasNetwork = await _offlineQueue.hasNetwork;
    if (!hasNetwork) {
      // 离线状态，更新 UI 显示
      state = state.copyWith(
        cartStatus: SyncStatus.offline,
        cartError: '无网络连接，变更已保存到本地队列',
      );
      _updatePendingChangesCount();
      return;
    }

    state = state.copyWith(cartStatus: SyncStatus.syncing, cartError: null);

    try {
      // 获取本地购物车数据
      final cartService = CartService();
      final localItems = await cartService.getAllItems();

      // 准备变更列表
      final changes = localItems.map((item) {
        return CartItemChange.fromLocalItem(item);
      }).toList();

      // 包含离线队列中的变更
      final offlineChanges = _offlineQueue.getCartChanges();
      for (final offlineChange in offlineChanges) {
        changes.add(CartItemChange.fromLocalItem(offlineChange));
      }

      // 执行同步
      final result = await _cartSyncClient.sync(changes: changes);

      if (result.success) {
        // 清空离线队列
        await _offlineQueue.clearCartChanges();
        
        // 应用服务器返回的变更到本地
        await _applyCartSyncResult(result);

        state = state.copyWith(
          cartStatus: SyncStatus.success,
          lastCartSync: DateTime.now(),
          pendingCartChanges: 0,
        );
      } else {
        state = state.copyWith(
          cartStatus: SyncStatus.error,
          cartError: result.message ?? '同步失败',
        );
      }
    } catch (e) {
      // 网络错误时保存到离线队列
      if (e.toString().contains('SocketException') || 
          e.toString().contains('network') ||
          e.toString().contains('connection')) {
        state = state.copyWith(
          cartStatus: SyncStatus.offline,
          cartError: '网络错误，变更已保存',
        );
      } else {
        state = state.copyWith(
          cartStatus: SyncStatus.error,
          cartError: e.toString(),
        );
      }
    }
  }

  /// 应用购物车同步结果到本地（带冲突解决）
  Future<void> _applyCartSyncResult(CartSyncResponse result) async {
    final box = await Hive.openBox(CartService.boxName);
    final cartService = CartService();

    // 获取本地所有项目
    final localItems = await cartService.getAllItems();

    // 转换服务器项目为标准格式
    final serverItems = result.items.map((item) {
      return _convertServerItemToLocal(item);
    }).toList();

    // 使用冲突解决器
    final resolver = CartConflictResolver();
    final resolutionResult = resolver.resolveConflicts(
      localItems: localItems,
      serverItems: serverItems,
      defaultStrategy: ConflictResolutionStrategy.merge,
    );

    // 清空现有数据
    await box.clear();

    // 删除已在服务器上删除的项目（不重新添加）
    final deletedIds = Set<String>.from(result.deletedIds);

    // 应用解决后的项目
    for (final item in resolutionResult.resolvedItems) {
      final productId = item['id'] as String?;
      if (productId == null) continue;
      if (deletedIds.contains(productId)) continue;

      await box.put(productId, item);
    }

    // 记录冲突解决统计（静默处理）
    if (resolutionResult.autoResolvedCount > 0) {
      // 冲突已自动解决
    }
  }

  /// 将服务器购物车项转换为本地格式
  Map<String, dynamic> _convertServerItemToLocal(Map<String, dynamic> serverItem) {
    return {
      'id': serverItem['product_id'],
      'platform': serverItem['platform'],
      'title': serverItem['title'],
      'price': serverItem['price'],
      'originalPrice': serverItem['original_price'],
      'coupon': serverItem['coupon'],
      'finalPrice': serverItem['final_price'],
      'imageUrl': serverItem['image_url'],
      'shopTitle': serverItem['shop_title'],
      'link': serverItem['link'],
      'description': serverItem['description'],
      'rating': serverItem['rating'],
      'sales': serverItem['sales'],
      'commission': serverItem['commission'],
      'qty': serverItem['quantity'] ?? 1,
      'initial_price': serverItem['initial_price'],
      'current_price': serverItem['current_price'],
      'raw_data': serverItem['raw_data'],
      'sync_version': serverItem['sync_version'],
    };
  }

  /// 同步会话
  Future<void> syncConversations() async {
    if (!isLoggedIn) return;

    // 检查网络连接
    final hasNetwork = await _offlineQueue.hasNetwork;
    if (!hasNetwork) {
      // 离线状态，更新 UI 显示
      state = state.copyWith(
        conversationStatus: SyncStatus.offline,
        conversationError: '无网络连接，变更已保存到本地队列',
      );
      _updatePendingChangesCount();
      return;
    }

    state = state.copyWith(
      conversationStatus: SyncStatus.syncing,
      conversationError: null,
    );

    try {
      // 获取本地会话数据
      final convRepo = ConversationRepository();
      final localConversations = await convRepo.listConversations();

      // 准备会话变更列表
      final convChanges = <ConversationChange>[];
      final msgChanges = <MessageChange>[];

      for (final conv in localConversations) {
        convChanges.add(ConversationChange(
          clientId: conv.id,
          title: conv.title,
          createdAt: conv.timestamp,
          updatedAt: conv.timestamp,
        ));

        // 准备消息变更
        for (final msg in conv.messages) {
          msgChanges.add(_convertMessageToChange(conv.id, msg));
        }
      }

      // 执行同步
      final result = await _conversationSyncClient.sync(
        conversationChanges: convChanges,
        messageChanges: msgChanges,
      );

      if (result.success) {
        // 清空离线队列
        await _offlineQueue.clearConversationChanges();
        await _offlineQueue.clearMessageChanges();

        // 应用服务器返回的变更到本地
        await _applyConversationSyncResult(result);

        state = state.copyWith(
          conversationStatus: SyncStatus.success,
          lastConversationSync: DateTime.now(),
          pendingConversationChanges: 0,
        );
      } else {
        state = state.copyWith(
          conversationStatus: SyncStatus.error,
          conversationError: result.message ?? '同步失败',
        );
      }
    } catch (e) {
      // 网络错误时保存到离线队列
      if (e.toString().contains('SocketException') || 
          e.toString().contains('network') ||
          e.toString().contains('connection')) {
        state = state.copyWith(
          conversationStatus: SyncStatus.offline,
          conversationError: '网络错误，变更已保存',
        );
      } else {
        state = state.copyWith(
          conversationStatus: SyncStatus.error,
          conversationError: e.toString(),
        );
      }
    }
  }

  /// 将本地消息转换为变更对象
  MessageChange _convertMessageToChange(String conversationId, ChatMessage msg) {
    List<Map<String, dynamic>>? products;
    if (msg.products != null) {
      products = msg.products!.map((p) => p.toMap()).toList();
    } else if (msg.product != null) {
      products = [msg.product!.toMap()];
    }

    return MessageChange(
      conversationClientId: conversationId,
      clientId: msg.id,
      role: msg.isUser ? 'user' : 'assistant',
      content: msg.text,
      products: products,
      keywords: msg.keywords,
      aiParsedRaw: msg.aiParsedRaw,
      failed: msg.failed,
      retryForText: msg.retryForText,
      createdAt: msg.timestamp,
    );
  }

  /// 应用会话同步结果到本地
  Future<void> _applyConversationSyncResult(ConversationSyncResponse result) async {
    final convRepo = ConversationRepository();

    // 删除已在服务器上删除的会话
    for (final deletedId in result.deletedConversationIds) {
      await convRepo.deleteConversation(deletedId);
    }

    // 按会话分组消息
    final messagesByConv = <String, List<Map<String, dynamic>>>{};
    for (final msg in result.messages) {
      final convId = msg['conversation_client_id'] as String?;
      if (convId == null) continue;
      messagesByConv.putIfAbsent(convId, () => []).add(msg);
    }

    // 更新/添加服务器返回的会话
    for (final convData in result.conversations) {
      final convId = convData['client_id'] as String?;
      if (convId == null) continue;

      // 获取现有会话
      var existingConv = await convRepo.getConversation(convId);
      final existingMessages = existingConv?.messages ?? [];

      // 合并服务器消息
      final serverMsgs = messagesByConv[convId] ?? [];
      final mergedMessages = _mergeMessages(existingMessages, serverMsgs);

      // 创建或更新会话
      final conv = ConversationModel(
        id: convId,
        title: convData['title'] as String? ?? '新对话',
        messages: mergedMessages,
        timestamp: DateTime.tryParse(convData['updated_at'] as String? ?? '') ??
            DateTime.now(),
      );

      await convRepo.saveConversation(conv);
    }
  }

  /// 合并本地和服务器消息
  List<ChatMessage> _mergeMessages(
    List<ChatMessage> localMessages,
    List<Map<String, dynamic>> serverMessages,
  ) {
    final messageMap = <String, ChatMessage>{};

    // 添加本地消息
    for (final msg in localMessages) {
      messageMap[msg.id] = msg;
    }

    // 添加/更新服务器消息
    for (final serverMsg in serverMessages) {
      final msgId = serverMsg['client_id'] as String?;
      if (msgId == null) continue;

      final chatMsg = _convertServerMessageToLocal(serverMsg);
      messageMap[msgId] = chatMsg;
    }

    // 按时间排序
    final result = messageMap.values.toList();
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  /// 将服务器消息转换为本地格式
  ChatMessage _convertServerMessageToLocal(Map<String, dynamic> serverMsg) {
    List<ProductModel>? products;
    final serverProducts = serverMsg['products'];
    if (serverProducts is List) {
      products = serverProducts.map((p) {
        if (p is Map) {
          return ProductModel.fromMap(Map<String, dynamic>.from(p));
        }
        return ProductModel(
          id: '',
          platform: 'unknown',
          title: '',
          price: 0,
          imageUrl: '',
        );
      }).toList();
    }

    List<String>? keywords;
    final serverKeywords = serverMsg['keywords'];
    if (serverKeywords is List) {
      keywords = serverKeywords.map((k) => k.toString()).toList();
    }

    return ChatMessage(
      id: serverMsg['client_id'] as String,
      text: serverMsg['content'] as String? ?? '',
      isUser: (serverMsg['role'] as String?) == 'user',
      products: products,
      keywords: keywords,
      aiParsedRaw: serverMsg['ai_parsed_raw'] as String?,
      failed: serverMsg['failed'] as bool? ?? false,
      retryForText: serverMsg['retry_for_text'] as String?,
      timestamp: DateTime.tryParse(serverMsg['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// 添加购物车项变更（用于增量同步）
  Future<void> addCartChange(Map<String, dynamic> item, {bool isDeleted = false}) async {
    if (!isLoggedIn) return;

    final change = Map<String, dynamic>.from(item);
    change['is_deleted'] = isDeleted;

    // 同时保存到内存和离线队列
    await _cartSyncClient.addPendingChange(change);
    await _offlineQueue.addCartChange(change);
    _updatePendingChangesCount();
  }

  /// 添加会话变更（用于增量同步）
  Future<void> addConversationChange(ConversationModel conv, {bool isDeleted = false}) async {
    if (!isLoggedIn) return;

    final change = {
      'client_id': conv.id,
      'title': conv.title,
      'is_deleted': isDeleted,
      'created_at': conv.timestamp.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    await _conversationSyncClient.addPendingConversationChange(change);
    await _offlineQueue.addConversationChange(change);
    _updatePendingChangesCount();
  }

  /// 添加消息变更（用于增量同步）
  Future<void> addMessageChange(String conversationId, ChatMessage msg) async {
    if (!isLoggedIn) return;

    final change = _convertMessageToChange(conversationId, msg);
    final changeJson = change.toJson();
    
    await _conversationSyncClient.addPendingMessageChange(changeJson);
    await _offlineQueue.addMessageChange(changeJson);
    _updatePendingChangesCount();
  }

  /// 触发延迟同步购物车（防抖）
  void scheduleSyncCart() {
    _cartDebounceTimer?.cancel();
    _cartDebounceTimer = Timer(_debounceDuration, () async {
      await syncCart();
    });
  }

  /// 触发延迟同步会话（防抖）
  void scheduleSyncConversations() {
    _conversationDebounceTimer?.cancel();
    _conversationDebounceTimer = Timer(_debounceDuration, () async {
      await syncConversations();
    });
  }

  /// 清理资源
  @override
  void dispose() {
    _cartDebounceTimer?.cancel();
    _conversationDebounceTimer?.cancel();
    super.dispose();
  }
}

/// 同步管理器 Provider
final syncManagerProvider = StateNotifierProvider<SyncManager, SyncState>((ref) {
  final cartSyncClient = ref.watch(cartSyncClientProvider);
  final conversationSyncClient = ref.watch(conversationSyncClientProvider);
  final offlineQueue = ref.watch(offlineSyncQueueProvider);
  // 使用 auth_providers 中的 tokenManagerProvider
  final tokenManager = ref.watch(tokenManagerProvider);

  final syncManager = SyncManager(
    cartSyncClient: cartSyncClient,
    conversationSyncClient: conversationSyncClient,
    tokenManager: tokenManager,
    offlineQueue: offlineQueue,
    ref: ref,
  );

  // 注册登录后同步回调
  final authNotifier = ref.read(authStateProvider.notifier);
  authNotifier.onLoginSuccess = () async {
    await syncManager.syncAll();
  };

  return syncManager;
});

/// 是否正在同步 Provider
final isSyncingProvider = Provider<bool>((ref) {
  return ref.watch(syncManagerProvider).isSyncing;
});

/// 上次购物车同步时间 Provider
final lastCartSyncProvider = Provider<DateTime?>((ref) {
  return ref.watch(syncManagerProvider).lastCartSync;
});

/// 上次会话同步时间 Provider
final lastConversationSyncProvider = Provider<DateTime?>((ref) {
  return ref.watch(syncManagerProvider).lastConversationSync;
});

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/token_manager.dart';
import '../../features/auth/auth_providers.dart';
import '../../features/cart/cart_service.dart';
import '../../core/storage/hive_config.dart';
import '../../features/chat/conversation_repository.dart';
import '../../features/chat/conversation_model.dart';
import '../../features/chat/chat_message.dart';
import '../../features/products/product_model.dart';
import '../../core/resilience/resilience.dart';
import '../../core/logging/app_logger.dart';
import 'cart_sync_client.dart';
import 'conversation_sync_client.dart';
import 'offline_sync_queue.dart';
import 'conflict_resolver.dart';

/// Sentinel to distinguish "parameter not passed" from "explicitly set to null"
/// in [SyncState.copyWith] for nullable [String?] fields.
class _Undefined {
  const _Undefined();
}

const _undefined = _Undefined();

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
  final int cartRetryCount;
  final int conversationRetryCount;

  const SyncState({
    this.cartStatus = SyncStatus.idle,
    this.conversationStatus = SyncStatus.idle,
    this.cartError,
    this.conversationError,
    this.lastCartSync,
    this.lastConversationSync,
    this.pendingCartChanges = 0,
    this.pendingConversationChanges = 0,
    this.cartRetryCount = 0,
    this.conversationRetryCount = 0,
  });

  /// Creates a copy with specified fields updated.
  ///
  /// For nullable [String?] fields ([cartError], [conversationError]):
  /// - **Omit** the parameter to preserve the existing value.
  /// - Pass **`null`** explicitly to clear the value.
  /// - Pass a **new string** to replace the value.
  SyncState copyWith({
    SyncStatus? cartStatus,
    SyncStatus? conversationStatus,
    Object? cartError = _undefined,
    Object? conversationError = _undefined,
    DateTime? lastCartSync,
    DateTime? lastConversationSync,
    int? pendingCartChanges,
    int? pendingConversationChanges,
    int? cartRetryCount,
    int? conversationRetryCount,
  }) {
    return SyncState(
      cartStatus: cartStatus ?? this.cartStatus,
      conversationStatus: conversationStatus ?? this.conversationStatus,
      cartError: cartError is _Undefined ? this.cartError : cartError as String?,
      conversationError: conversationError is _Undefined
          ? this.conversationError
          : conversationError as String?,
      lastCartSync: lastCartSync ?? this.lastCartSync,
      lastConversationSync: lastConversationSync ?? this.lastConversationSync,
      pendingCartChanges: pendingCartChanges ?? this.pendingCartChanges,
      pendingConversationChanges:
          pendingConversationChanges ?? this.pendingConversationChanges,
      cartRetryCount: cartRetryCount ?? this.cartRetryCount,
      conversationRetryCount:
          conversationRetryCount ?? this.conversationRetryCount,
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

/// 同步操作锁 - 防止并发同步
class _SyncLock {
  bool _cartLock = false;
  bool _conversationLock = false;

  bool tryAcquireCart() {
    if (_cartLock) return false;
    _cartLock = true;
    return true;
  }

  void releaseCart() => _cartLock = false;

  bool tryAcquireConversation() {
    if (_conversationLock) return false;
    _conversationLock = true;
    return true;
  }

  void releaseConversation() => _conversationLock = false;
}

/// 同步状态管理器
///
/// 增强版特性：
/// - 使用 [NetworkErrorDetector] 进行网络错误分类
/// - 幂等性控制（通过操作 ID 去重）
/// - 自动重试带指数退避
/// - 详细日志记录
/// - 并发控制（防止重复同步）
class SyncManager extends StateNotifier<SyncState> {
  final CartSyncClient _cartSyncClient;
  final ConversationSyncClient _conversationSyncClient;
  final TokenManager _tokenManager;
  final OfflineSyncQueue _offlineQueue;
  final Ref _ref;
  final ModuleLogger _logger = AppLogger.instance.module('SyncManager');
  final _SyncLock _syncLock = _SyncLock();

  /// 重试执行器
  late final RetryExecutor _retryExecutor;

  /// 防抖计时器
  Timer? _cartDebounceTimer;
  Timer? _conversationDebounceTimer;

  /// 重试计时器
  Timer? _cartRetryTimer;
  Timer? _conversationRetryTimer;

  /// 防抖延迟时间
  static const Duration _debounceDuration = Duration(seconds: 2);

  /// 重试配置
  static const int _maxAutoRetries = 3;
  static const Duration _initialRetryDelay = Duration(seconds: 5);
  static const Duration _maxRetryDelay = Duration(minutes: 2);

  /// 已处理的操作 ID（用于幂等性检查）
  final Set<String> _processedOperationIds = {};

  /// 是否已被销毁（防止 Timer 在 dispose 后触发）
  bool _disposed = false;

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
    // 初始化重试执行器
    _retryExecutor = RetryExecutor(
      config: const RetryConfig(
        maxAttempts: _maxAutoRetries,
        initialDelay: _initialRetryDelay,
        maxDelay: _maxRetryDelay,
      ),
    );

    // 设置网络恢复回调
    _offlineQueue.onNetworkRestored = _onNetworkRestored;

    // Await queue initialization before reading counts to avoid
    // silently reporting 0 pending changes during the init window.
    _initPendingCounts();

    _logger.info('SyncManager initialized');
  }

  /// Ensure the offline queue is initialized before reading pending counts.
  Future<void> _initPendingCounts() async {
    try {
      await _offlineQueue.init();
    } catch (e) {
      _logger.warning('OfflineSyncQueue init failed: $e');
    }
    _updatePendingChangesCount();
  }

  /// 网络恢复时自动同步
  void _onNetworkRestored() {
    _logger.info('Network restored, checking pending changes');
    if (isLoggedIn && _offlineQueue.hasPendingChanges) {
      _logger.info('Has pending changes, triggering sync');
      syncAll();
    }
  }

  /// 更新待同步变更数量
  void _updatePendingChangesCount() {
    final cartCount = _offlineQueue.pendingCartChangesCount;
    final convCount = _offlineQueue.pendingConversationChangesCount;

    state = state.copyWith(
      pendingCartChanges: cartCount,
      pendingConversationChanges: convCount,
    );

    _logger.debug('Pending changes: cart=$cartCount, conversations=$convCount');
  }

  /// 是否已登录
  bool get isLoggedIn => _tokenManager.isLoggedIn;

  /// 同步所有数据
  Future<void> syncAll() async {
    if (!isLoggedIn) {
      _logger.warning('Sync skipped: not logged in');
      return;
    }

    _logger.info('Starting full sync');

    // 在同步前检查并刷新 token
    final tokenValid = await _ensureValidToken();
    if (!tokenValid) {
      _logger.warning('Sync skipped: token refresh failed');
      return;
    }

    await Future.wait([
      syncCart(),
      syncConversations(),
    ]);

    _logger.info('Full sync completed');
  }

  /// 确保 token 有效，如果过期则刷新
  Future<bool> _ensureValidToken() async {
    if (_tokenManager.isAccessTokenExpired) {
      _logger.debug('Access token expired, attempting refresh');
      try {
        final authService = _ref.read(authServiceProvider);
        final result = await authService.refreshToken();
        if (result.success) {
          _logger.debug('Token refresh successful');
          return true;
        } else {
          _logger.warning('Token refresh failed: ${result.message}');
          return false;
        }
      } catch (e) {
        _logger.error('Token refresh error', error: e);
        return false;
      }
    }
    return true;
  }

  /// 同步购物车
  Future<void> syncCart() async {
    if (!isLoggedIn) return;

    // 尝试获取锁
    if (!_syncLock.tryAcquireCart()) {
      _logger.warning('Cart sync already in progress, skipping');
      return;
    }

    try {
      await _doSyncCart();
    } finally {
      _syncLock.releaseCart();
    }
  }

  /// 执行购物车同步
  Future<void> _doSyncCart() async {
    // 检查网络连接
    final hasNetwork = await _offlineQueue.hasNetwork;
    if (!hasNetwork) {
      _logger.info('Cart sync skipped: offline');
      state = state.copyWith(
        cartStatus: SyncStatus.offline,
        cartError: '无网络连接，变更已保存到本地队列',
      );
      _updatePendingChangesCount();
      return;
    }

    state = state.copyWith(
      cartStatus: SyncStatus.syncing,
      cartError: null,
    );

    _logger.info('Starting cart sync');

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

      _logger.debug('Cart sync: ${changes.length} items to sync');

      // 使用重试执行器
      final retryResult = await _retryExecutor.execute(
        () async {
          final result = await _cartSyncClient.sync(changes: changes);
          if (!result.success) {
            throw Exception(result.message ?? '同步失败');
          }
          return result;
        },
        operationName: 'cart_sync',
        retryIf: (e) => NetworkErrorDetector.isRetryable(e),
      );

      if (retryResult.isSuccess && retryResult.value != null) {
        // 清空离线队列
        await _offlineQueue.clearCartChanges();

        // 应用服务器返回的变更到本地
        await _applyCartSyncResult(retryResult.value!);

        state = state.copyWith(
          cartStatus: SyncStatus.success,
          cartError: null, // explicitly clear on success
          lastCartSync: DateTime.now(),
          pendingCartChanges: 0,
          cartRetryCount: 0,
        );

        _logger.info('Cart sync successful');
      } else {
        final errorMsg = retryResult.error?.toString() ?? '同步失败';
        _handleCartSyncFailure(errorMsg, retryResult.error);
      }
    } catch (e, stackTrace) {
      _logger.error('Cart sync error', error: e, stackTrace: stackTrace);
      _handleCartSyncFailure(e.toString(), e);
    }
  }

  /// 处理购物车同步失败
  void _handleCartSyncFailure(String errorMsg, Object? error) {
    final analysis = error != null
        ? NetworkErrorDetector.analyze(error)
        : NetworkErrorAnalysis(
            type: NetworkErrorType.unknown,
            message: errorMsg,
            isRetryable: false,
            suggestedRetryDelay: Duration.zero,
            userFriendlyMessage: errorMsg,
          );

    if (analysis.type == NetworkErrorType.noConnection) {
      state = state.copyWith(
        cartStatus: SyncStatus.offline,
        cartError: analysis.userFriendlyMessage,
      );
    } else {
      state = state.copyWith(
        cartStatus: SyncStatus.error,
        cartError: analysis.userFriendlyMessage,
        cartRetryCount: state.cartRetryCount + 1,
      );

      // 如果可重试且未超过最大重试次数，安排自动重试
      if (analysis.isRetryable && state.cartRetryCount < _maxAutoRetries) {
        _scheduleCartRetry(analysis.suggestedRetryDelay);
      }
    }

    _logger.warning(
      'Cart sync failed: ${analysis.userFriendlyMessage} '
      '(type: ${analysis.type}, retryable: ${analysis.isRetryable})',
    );
  }

  /// 安排购物车重试
  void _scheduleCartRetry(Duration delay) {
    _cartRetryTimer?.cancel();
    _cartRetryTimer = Timer(delay, () {
      if (_disposed) return; // 防止 dispose 后触发
      _logger.info('Auto-retrying cart sync');
      syncCart();
    });
  }

  /// 应用购物车同步结果到本地（带冲突解决）
  ///
  /// Uses incremental put/delete instead of clear-then-rewrite to avoid a
  /// data-loss window if the process is interrupted mid-operation.
  Future<void> _applyCartSyncResult(CartSyncResponse result) async {
    // Use HiveConfig.getBox for safe open-if-needed semantics, consistent
    // with the rest of the codebase.
    final box = await HiveConfig.getBox(CartService.boxName);
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

    // Build the desired final set of IDs
    final deletedIds = Set<String>.from(result.deletedIds);
    final desiredIds = <String>{};

    // Upsert resolved items (incremental — no clear())
    for (final item in resolutionResult.resolvedItems) {
      final productId = item['id'] as String?;
      if (productId == null) continue;
      if (deletedIds.contains(productId)) continue;

      desiredIds.add(productId);
      await box.put(productId, item);
    }

    // Remove items that should no longer exist locally.
    // Use .map(toString) instead of .cast<String>() to avoid a runtime
    // CastError if Hive contains a non-String key (e.g. corrupted data).
    final existingKeys = box.keys.map((k) => k.toString()).toSet();
    final toRemove = existingKeys.difference(desiredIds);
    for (final key in toRemove) {
      await box.delete(key);
    }

    // 记录冲突解决统计
    if (resolutionResult.autoResolvedCount > 0) {
      _logger.debug(
        'Cart conflicts resolved: ${resolutionResult.autoResolvedCount} auto-resolved',
      );
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

    // 尝试获取锁
    if (!_syncLock.tryAcquireConversation()) {
      _logger.warning('Conversation sync already in progress, skipping');
      return;
    }

    try {
      await _doSyncConversations();
    } finally {
      _syncLock.releaseConversation();
    }
  }

  /// 执行会话同步
  Future<void> _doSyncConversations() async {
    // 检查网络连接
    final hasNetwork = await _offlineQueue.hasNetwork;
    if (!hasNetwork) {
      _logger.info('Conversation sync skipped: offline');
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

    _logger.info('Starting conversation sync');

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

      _logger.debug(
        'Conversation sync: ${convChanges.length} conversations, ${msgChanges.length} messages',
      );

      // 使用重试执行器
      final retryResult = await _retryExecutor.execute(
        () async {
          final result = await _conversationSyncClient.sync(
            conversationChanges: convChanges,
            messageChanges: msgChanges,
          );
          if (!result.success) {
            throw Exception(result.message ?? '同步失败');
          }
          return result;
        },
        operationName: 'conversation_sync',
        retryIf: (e) => NetworkErrorDetector.isRetryable(e),
      );

      if (retryResult.isSuccess && retryResult.value != null) {
        // 清空离线队列
        await _offlineQueue.clearConversationChanges();
        await _offlineQueue.clearMessageChanges();

        // 应用服务器返回的变更到本地
        await _applyConversationSyncResult(retryResult.value!);

        state = state.copyWith(
          conversationStatus: SyncStatus.success,
          conversationError: null, // explicitly clear on success
          lastConversationSync: DateTime.now(),
          pendingConversationChanges: 0,
          conversationRetryCount: 0,
        );

        _logger.info('Conversation sync successful');
      } else {
        final errorMsg = retryResult.error?.toString() ?? '同步失败';
        _handleConversationSyncFailure(errorMsg, retryResult.error);
      }
    } catch (e, stackTrace) {
      _logger.error('Conversation sync error', error: e, stackTrace: stackTrace);
      _handleConversationSyncFailure(e.toString(), e);
    }
  }

  /// 处理会话同步失败
  void _handleConversationSyncFailure(String errorMsg, Object? error) {
    final analysis = error != null
        ? NetworkErrorDetector.analyze(error)
        : NetworkErrorAnalysis(
            type: NetworkErrorType.unknown,
            message: errorMsg,
            isRetryable: false,
            suggestedRetryDelay: Duration.zero,
            userFriendlyMessage: errorMsg,
          );

    if (analysis.type == NetworkErrorType.noConnection) {
      state = state.copyWith(
        conversationStatus: SyncStatus.offline,
        conversationError: analysis.userFriendlyMessage,
      );
    } else {
      state = state.copyWith(
        conversationStatus: SyncStatus.error,
        conversationError: analysis.userFriendlyMessage,
        conversationRetryCount: state.conversationRetryCount + 1,
      );

      // 如果可重试且未超过最大重试次数，安排自动重试
      if (analysis.isRetryable &&
          state.conversationRetryCount < _maxAutoRetries) {
        _scheduleConversationRetry(analysis.suggestedRetryDelay);
      }
    }

    _logger.warning(
      'Conversation sync failed: ${analysis.userFriendlyMessage} '
      '(type: ${analysis.type}, retryable: ${analysis.isRetryable})',
    );
  }

  /// 安排会话重试
  void _scheduleConversationRetry(Duration delay) {
    _conversationRetryTimer?.cancel();
    _conversationRetryTimer = Timer(delay, () {
      if (_disposed) return; // 防止 dispose 后触发
      _logger.info('Auto-retrying conversation sync');
      syncConversations();
    });
  }

  /// 将本地消息转换为变更对象
  MessageChange _convertMessageToChange(
      String conversationId, ChatMessage msg) {
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
  Future<void> _applyConversationSyncResult(
      ConversationSyncResponse result) async {
    final convRepo = ConversationRepository();

    // 删除已在服务器上删除的会话
    for (final deletedId in result.deletedConversationIds) {
      await convRepo.deleteConversation(deletedId);
      _logger.debug('Deleted conversation: $deletedId');
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
        timestamp:
            DateTime.tryParse(convData['updated_at'] as String? ?? '') ??
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
      timestamp:
          DateTime.tryParse(serverMsg['created_at'] as String? ?? '') ??
              DateTime.now(),
    );
  }

  /// Monotonic counter to guarantee a unique payload ID even within the
  /// same millisecond (e.g. batch deletes in a tight loop).
  int _operationCounter = 0;

  /// Generate a **unique** operation ID for the sync payload sent to the
  /// server. This ID is embedded in the change map and used for server-side
  /// idempotency tracking.
  String _generateOperationId(String resourceType, String resourceId) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return '${resourceType}_${resourceId}_${timestamp}_${_operationCounter++}';
  }

  /// Generate a **deterministic, time-windowed** key used for client-side
  /// dedup. Two calls for the same resource within the same second produce
  /// the same key, preventing rapid-fire duplicate queuing.
  ///
  /// NOTE: The dedup set is in-memory only. After an app restart, duplicate
  /// submissions are possible; the server must enforce final idempotency.
  String _generateDedupKey(String resourceType, String resourceId) {
    final secondTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return '${resourceType}_${resourceId}_$secondTimestamp';
  }

  /// 检查操作是否已处理（client-side dedup — in-memory, 1-second window）
  bool _isOperationProcessed(String dedupKey) {
    return _processedOperationIds.contains(dedupKey);
  }

  /// 标记操作已处理（存储 dedup key，非 operation ID）
  void _markOperationProcessed(String dedupKey) {
    _processedOperationIds.add(dedupKey);
    // 清理旧的 dedup key（保留最近 1000 个）
    if (_processedOperationIds.length > 1000) {
      // 必须先转为 List，因为 take() 返回惰性 Iterable，
      // 直接 removeAll 会在迭代过程中修改 Set 导致问题
      final toRemove = _processedOperationIds
          .take(_processedOperationIds.length - 1000)
          .toList();
      _processedOperationIds.removeAll(toRemove);
    }
  }

  /// 添加购物车项变更（用于增量同步）- 带幂等性控制
  Future<void> addCartChange(Map<String, dynamic> item,
      {bool isDeleted = false}) async {
    if (!isLoggedIn) return;

    final productId = item['id'] as String? ?? 'unknown';
    final dedupKey = _generateDedupKey('cart', productId);

    // 幂等性检查 — 同一秒内对同一商品的重复调用会被跳过
    if (_isOperationProcessed(dedupKey)) {
      _logger.debug('Cart change deduplicated: $dedupKey');
      return;
    }

    final operationId = _generateOperationId('cart', productId);
    final change = Map<String, dynamic>.from(item);
    change['is_deleted'] = isDeleted;
    change['operation_id'] = operationId;

    // 同时保存到内存和离线队列
    await _cartSyncClient.addPendingChange(change);
    await _offlineQueue.addCartChange(change);

    _markOperationProcessed(dedupKey);
    _updatePendingChangesCount();

    _logger.debug('Cart change queued: $operationId (deleted: $isDeleted)');
  }

  /// 添加会话变更（用于增量同步）- 带幂等性控制
  Future<void> addConversationChange(ConversationModel conv,
      {bool isDeleted = false}) async {
    if (!isLoggedIn) return;

    final dedupKey = _generateDedupKey('conversation', conv.id);

    // 幂等性检查 — 同一秒内对同一会话的重复调用会被跳过
    if (_isOperationProcessed(dedupKey)) {
      _logger.debug('Conversation change deduplicated: $dedupKey');
      return;
    }

    final operationId = _generateOperationId('conversation', conv.id);
    final change = {
      'client_id': conv.id,
      'title': conv.title,
      'is_deleted': isDeleted,
      'created_at': conv.timestamp.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      'operation_id': operationId,
    };

    await _conversationSyncClient.addPendingConversationChange(change);
    await _offlineQueue.addConversationChange(change);

    _markOperationProcessed(dedupKey);
    _updatePendingChangesCount();

    _logger.debug('Conversation change queued: $operationId');
  }

  /// 添加消息变更（用于增量同步）- 带幂等性控制
  Future<void> addMessageChange(String conversationId, ChatMessage msg) async {
    if (!isLoggedIn) return;

    final dedupKey = _generateDedupKey('message', msg.id);

    // 幂等性检查 — 同一秒内对同一消息的重复调用会被跳过
    if (_isOperationProcessed(dedupKey)) {
      _logger.debug('Message change deduplicated: $dedupKey');
      return;
    }

    final operationId = _generateOperationId('message', msg.id);
    final change = _convertMessageToChange(conversationId, msg);
    final changeJson = change.toJson();
    changeJson['operation_id'] = operationId;

    await _conversationSyncClient.addPendingMessageChange(changeJson);
    await _offlineQueue.addMessageChange(changeJson);

    _markOperationProcessed(dedupKey);
    _updatePendingChangesCount();

    _logger.debug('Message change queued: $operationId');
  }

  /// 触发延迟同步购物车（防抖）
  void scheduleSyncCart() {
    _cartDebounceTimer?.cancel();
    _cartDebounceTimer = Timer(_debounceDuration, () async {
      if (_disposed) return; // 防止 dispose 后触发
      await syncCart();
    });
  }

  /// 触发延迟同步会话（防抖）
  void scheduleSyncConversations() {
    _conversationDebounceTimer?.cancel();
    _conversationDebounceTimer = Timer(_debounceDuration, () async {
      if (_disposed) return; // 防止 dispose 后触发
      await syncConversations();
    });
  }

  /// 获取状态摘要（用于调试）
  Map<String, dynamic> getStatusSummary() {
    return {
      'isLoggedIn': isLoggedIn,
      'cartStatus': state.cartStatus.name,
      'conversationStatus': state.conversationStatus.name,
      'pendingCartChanges': state.pendingCartChanges,
      'pendingConversationChanges': state.pendingConversationChanges,
      'cartRetryCount': state.cartRetryCount,
      'conversationRetryCount': state.conversationRetryCount,
      'lastCartSync': state.lastCartSync?.toIso8601String(),
      'lastConversationSync': state.lastConversationSync?.toIso8601String(),
    };
  }

  /// 清理资源
  @override
  void dispose() {
    _disposed = true;
    _cartDebounceTimer?.cancel();
    _conversationDebounceTimer?.cancel();
    _cartRetryTimer?.cancel();
    _conversationRetryTimer?.cancel();
    _cartDebounceTimer = null;
    _conversationDebounceTimer = null;
    _cartRetryTimer = null;
    _conversationRetryTimer = null;
    _logger.info('SyncManager disposed');
    super.dispose();
  }
}

/// 同步管理器 Provider
final syncManagerProvider =
    StateNotifierProvider<SyncManager, SyncState>((ref) {
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

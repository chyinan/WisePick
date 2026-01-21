/// 同步冲突解决模块
/// 
/// 提供多种冲突解决策略：
/// - Last Write Wins (LWW): 最后写入获胜
/// - Merge: 智能合并两边数据
/// - User Choice: 让用户选择

/// 冲突类型
enum ConflictType {
  /// 新增冲突：两边都新增了相同 ID 的项
  bothAdded,
  
  /// 修改冲突：两边都修改了同一项
  bothModified,
  
  /// 删除冲突：一边删除，一边修改
  deleteVsModify,
  
  /// 版本冲突：服务器版本更新
  versionMismatch,
}

/// 冲突解决策略
enum ConflictResolutionStrategy {
  /// 使用本地版本
  keepLocal,
  
  /// 使用服务器版本
  keepServer,
  
  /// 合并两边数据
  merge,
  
  /// 让用户选择
  askUser,
  
  /// 最后写入获胜 (基于时间戳)
  lastWriteWins,
}

/// 单个冲突项
class SyncConflict<T> {
  final String id;
  final ConflictType type;
  final T? localData;
  final T? serverData;
  final DateTime? localModifiedAt;
  final DateTime? serverModifiedAt;
  final int? localVersion;
  final int? serverVersion;

  const SyncConflict({
    required this.id,
    required this.type,
    this.localData,
    this.serverData,
    this.localModifiedAt,
    this.serverModifiedAt,
    this.localVersion,
    this.serverVersion,
  });

  /// 获取推荐的解决方案
  ConflictResolutionStrategy get recommendedResolution {
    switch (type) {
      case ConflictType.bothAdded:
        // 两边都新增，建议合并
        return ConflictResolutionStrategy.merge;
        
      case ConflictType.bothModified:
        // 两边都修改，使用最后写入获胜
        return ConflictResolutionStrategy.lastWriteWins;
        
      case ConflictType.deleteVsModify:
        // 删除 vs 修改，保留修改（用户明确想要这个数据）
        return ConflictResolutionStrategy.keepLocal;
        
      case ConflictType.versionMismatch:
        // 版本不匹配，使用服务器版本
        return ConflictResolutionStrategy.keepServer;
    }
  }

  /// 自动解决冲突（根据推荐策略）
  T? autoResolve() {
    final strategy = recommendedResolution;
    return resolveWith(strategy);
  }

  /// 使用指定策略解决冲突
  T? resolveWith(ConflictResolutionStrategy strategy) {
    switch (strategy) {
      case ConflictResolutionStrategy.keepLocal:
        return localData;
        
      case ConflictResolutionStrategy.keepServer:
        return serverData;
        
      case ConflictResolutionStrategy.lastWriteWins:
        if (localModifiedAt == null) return serverData;
        if (serverModifiedAt == null) return localData;
        return localModifiedAt!.isAfter(serverModifiedAt!) 
            ? localData 
            : serverData;
        
      case ConflictResolutionStrategy.merge:
      case ConflictResolutionStrategy.askUser:
        // 这两种需要外部处理
        return null;
    }
  }
}

/// 冲突解决结果
class ConflictResolutionResult<T> {
  final List<T> resolvedItems;
  final List<SyncConflict<T>> unresolvedConflicts;
  final int autoResolvedCount;
  final int userResolvedCount;

  const ConflictResolutionResult({
    required this.resolvedItems,
    required this.unresolvedConflicts,
    required this.autoResolvedCount,
    required this.userResolvedCount,
  });

  bool get hasUnresolvedConflicts => unresolvedConflicts.isNotEmpty;
  bool get allResolved => unresolvedConflicts.isEmpty;
}

/// 购物车项冲突
class CartItemConflict extends SyncConflict<Map<String, dynamic>> {
  CartItemConflict({
    required super.id,
    required super.type,
    super.localData,
    super.serverData,
    super.localModifiedAt,
    super.serverModifiedAt,
    super.localVersion,
    super.serverVersion,
  });

  /// 合并购物车项
  Map<String, dynamic>? merge() {
    if (localData == null) return serverData;
    if (serverData == null) return localData;

    // 合并策略：
    // - 数量取较大值
    // - 其他字段取最新的
    final merged = Map<String, dynamic>.from(serverData!);
    
    final localQty = (localData!['qty'] as int?) ?? 1;
    final serverQty = (serverData!['qty'] as int?) ?? 1;
    merged['qty'] = localQty > serverQty ? localQty : serverQty;

    // 使用本地的一些用户偏好数据
    if (localData!.containsKey('notes')) {
      merged['notes'] = localData!['notes'];
    }

    return merged;
  }

  @override
  Map<String, dynamic>? resolveWith(ConflictResolutionStrategy strategy) {
    if (strategy == ConflictResolutionStrategy.merge) {
      return merge();
    }
    return super.resolveWith(strategy);
  }
}

/// 会话冲突
class ConversationConflict extends SyncConflict<Map<String, dynamic>> {
  final List<Map<String, dynamic>> localMessages;
  final List<Map<String, dynamic>> serverMessages;

  ConversationConflict({
    required super.id,
    required super.type,
    super.localData,
    super.serverData,
    super.localModifiedAt,
    super.serverModifiedAt,
    this.localMessages = const [],
    this.serverMessages = const [],
  });

  /// 合并会话（保留所有消息，按时间排序）
  Map<String, dynamic>? merge() {
    if (localData == null) return serverData;
    if (serverData == null) return localData;

    final merged = Map<String, dynamic>.from(serverData!);
    
    // 合并消息：使用 Set 去重，按时间排序
    final messageMap = <String, Map<String, dynamic>>{};
    
    for (final msg in localMessages) {
      final msgId = msg['client_id'] as String? ?? msg['id'] as String?;
      if (msgId != null) {
        messageMap[msgId] = msg;
      }
    }
    
    for (final msg in serverMessages) {
      final msgId = msg['client_id'] as String? ?? msg['id'] as String?;
      if (msgId != null) {
        // 服务器消息覆盖本地（服务器为准）
        messageMap[msgId] = msg;
      }
    }

    // 按时间排序
    final mergedMessages = messageMap.values.toList();
    mergedMessages.sort((a, b) {
      final aTime = DateTime.tryParse(a['created_at'] as String? ?? '') ?? DateTime.now();
      final bTime = DateTime.tryParse(b['created_at'] as String? ?? '') ?? DateTime.now();
      return aTime.compareTo(bTime);
    });

    merged['messages'] = mergedMessages;
    
    // 使用最新的标题
    if (localModifiedAt != null && serverModifiedAt != null) {
      if (localModifiedAt!.isAfter(serverModifiedAt!)) {
        merged['title'] = localData!['title'];
      }
    }

    return merged;
  }

  @override
  Map<String, dynamic>? resolveWith(ConflictResolutionStrategy strategy) {
    if (strategy == ConflictResolutionStrategy.merge) {
      return merge();
    }
    return super.resolveWith(strategy);
  }
}

/// 购物车冲突解决器
class CartConflictResolver {
  /// 检测并解决购物车冲突
  ConflictResolutionResult<Map<String, dynamic>> resolveConflicts({
    required List<Map<String, dynamic>> localItems,
    required List<Map<String, dynamic>> serverItems,
    ConflictResolutionStrategy defaultStrategy = ConflictResolutionStrategy.merge,
  }) {
    final localMap = <String, Map<String, dynamic>>{};
    final serverMap = <String, Map<String, dynamic>>{};
    
    for (final item in localItems) {
      final id = item['id'] as String? ?? item['product_id'] as String?;
      if (id != null) localMap[id] = item;
    }
    
    for (final item in serverItems) {
      final id = item['id'] as String? ?? item['product_id'] as String?;
      if (id != null) serverMap[id] = item;
    }

    final resolvedItems = <Map<String, dynamic>>[];
    final unresolvedConflicts = <SyncConflict<Map<String, dynamic>>>[];
    var autoResolvedCount = 0;

    final allIds = {...localMap.keys, ...serverMap.keys};

    for (final id in allIds) {
      final local = localMap[id];
      final server = serverMap[id];

      if (local != null && server == null) {
        // 只在本地存在
        resolvedItems.add(local);
      } else if (local == null && server != null) {
        // 只在服务器存在
        resolvedItems.add(server);
      } else if (local != null && server != null) {
        // 两边都存在，检测冲突
        final localDeleted = local['is_deleted'] == true;
        final serverDeleted = server['is_deleted'] == true;

        if (localDeleted && serverDeleted) {
          // 两边都删除了，跳过
          continue;
        } else if (localDeleted || serverDeleted) {
          // 删除 vs 修改冲突 - 自动解决：保留未删除的版本
          final resolved = localDeleted ? server : local;
          resolvedItems.add(resolved);
          autoResolvedCount++;
        } else {
          // 两边都修改了
          final conflict = CartItemConflict(
            id: id,
            type: ConflictType.bothModified,
            localData: local,
            serverData: server,
            localModifiedAt: _parseDateTime(local['updated_at']),
            serverModifiedAt: _parseDateTime(server['updated_at']),
            localVersion: local['sync_version'] as int?,
            serverVersion: server['sync_version'] as int?,
          );

          // 使用默认策略解决
          final resolved = conflict.resolveWith(defaultStrategy);
          if (resolved != null) {
            resolvedItems.add(resolved);
            autoResolvedCount++;
          } else {
            unresolvedConflicts.add(conflict);
          }
        }
      }
    }

    return ConflictResolutionResult(
      resolvedItems: resolvedItems,
      unresolvedConflicts: unresolvedConflicts,
      autoResolvedCount: autoResolvedCount,
      userResolvedCount: 0,
    );
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// 会话冲突解决器
class ConversationConflictResolver {
  /// 检测并解决会话冲突
  ConflictResolutionResult<Map<String, dynamic>> resolveConflicts({
    required List<Map<String, dynamic>> localConversations,
    required List<Map<String, dynamic>> serverConversations,
    ConflictResolutionStrategy defaultStrategy = ConflictResolutionStrategy.merge,
  }) {
    final localMap = <String, Map<String, dynamic>>{};
    final serverMap = <String, Map<String, dynamic>>{};
    
    for (final conv in localConversations) {
      final id = conv['id'] as String? ?? conv['client_id'] as String?;
      if (id != null) localMap[id] = conv;
    }
    
    for (final conv in serverConversations) {
      final id = conv['id'] as String? ?? conv['client_id'] as String?;
      if (id != null) serverMap[id] = conv;
    }

    final resolvedItems = <Map<String, dynamic>>[];
    final unresolvedConflicts = <SyncConflict<Map<String, dynamic>>>[];
    var autoResolvedCount = 0;

    final allIds = {...localMap.keys, ...serverMap.keys};

    for (final id in allIds) {
      final local = localMap[id];
      final server = serverMap[id];

      if (local != null && server == null) {
        // 只在本地存在
        resolvedItems.add(local);
      } else if (local == null && server != null) {
        // 只在服务器存在
        resolvedItems.add(server);
      } else if (local != null && server != null) {
        // 两边都存在，合并消息
        final conflict = ConversationConflict(
          id: id,
          type: ConflictType.bothModified,
          localData: local,
          serverData: server,
          localModifiedAt: _parseDateTime(local['updated_at']),
          serverModifiedAt: _parseDateTime(server['updated_at']),
          localMessages: _extractMessages(local),
          serverMessages: _extractMessages(server),
        );

        // 会话始终使用合并策略（保留所有消息）
        final resolved = conflict.merge();
        if (resolved != null) {
          resolvedItems.add(resolved);
          autoResolvedCount++;
        } else {
          unresolvedConflicts.add(conflict);
        }
      }
    }

    return ConflictResolutionResult(
      resolvedItems: resolvedItems,
      unresolvedConflicts: unresolvedConflicts,
      autoResolvedCount: autoResolvedCount,
      userResolvedCount: 0,
    );
  }

  List<Map<String, dynamic>> _extractMessages(Map<String, dynamic> conv) {
    final messages = conv['messages'];
    if (messages is List) {
      return messages.map((m) => Map<String, dynamic>.from(m as Map)).toList();
    }
    return [];
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

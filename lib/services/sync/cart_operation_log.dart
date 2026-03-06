import 'dart:developer' as dev;

import '../../core/storage/hive_config.dart';

/// 购物车操作类型
enum CartOperation {
  /// 添加商品
  add,

  /// 删除商品
  remove,

  /// 更新数量
  updateQuantity,
}

/// 购物车操作日志条目
class CartOperationLog {
  final String itemId;
  final CartOperation operation;
  final DateTime timestamp;
  final int? quantity; // updateQuantity 时使用

  const CartOperationLog({
    required this.itemId,
    required this.operation,
    required this.timestamp,
    this.quantity,
  });

  Map<String, dynamic> toMap() => {
        'item_id': itemId,
        'operation': operation.name,
        'timestamp': timestamp.millisecondsSinceEpoch,
        if (quantity != null) 'quantity': quantity,
      };

  factory CartOperationLog.fromMap(Map<String, dynamic> map) {
    return CartOperationLog(
      itemId: map['item_id'] as String,
      operation: CartOperation.values.firstWhere(
        (e) => e.name == map['operation'],
        orElse: () => CartOperation.updateQuantity,
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      quantity: map['quantity'] as int?,
    );
  }
}

/// 购物车操作日志管理器
///
/// 记录本地操作，用于在同步时进行基于操作的冲突解决，
/// 避免 Last Write Wins 导致的数据静默丢失。
class CartOperationLogger {
  /// 记录一条操作日志
  static Future<void> record(CartOperationLog entry) async {
    try {
      final box = await HiveConfig.getBox(HiveConfig.cartOpsLogBox);
      final key = '${entry.itemId}_${entry.timestamp.millisecondsSinceEpoch}';
      await box.put(key, entry.toMap());
    } catch (e, st) {
      dev.log('Failed to persist cart operation log: $e',
          name: 'CartOperationLogger', error: e, stackTrace: st);
    }
  }

  /// 获取指定商品的所有操作日志，按时间升序排列
  static Future<List<CartOperationLog>> getLogsForItem(String itemId) async {
    try {
      final box = await HiveConfig.getBox(HiveConfig.cartOpsLogBox);
      final entries = <CartOperationLog>[];
      for (final key in box.keys) {
        if (key.toString().startsWith('${itemId}_')) {
          final raw = box.get(key);
          if (raw is Map) {
            entries.add(CartOperationLog.fromMap(
                Map<String, dynamic>.from(raw)));
          }
        }
      }
      entries.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return entries;
    } catch (e, st) {
      dev.log('Failed to read cart operation logs: $e',
          name: 'CartOperationLogger', error: e, stackTrace: st);
      return [];
    }
  }

  /// 获取所有操作日志
  static Future<Map<String, List<CartOperationLog>>> getAllLogs() async {
    try {
      final box = await HiveConfig.getBox(HiveConfig.cartOpsLogBox);
      final result = <String, List<CartOperationLog>>{};
      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is Map) {
          final entry = CartOperationLog.fromMap(
              Map<String, dynamic>.from(raw));
          result.putIfAbsent(entry.itemId, () => []).add(entry);
        }
      }
      // 每个商品的日志按时间升序排列
      for (final list in result.values) {
        list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      }
      return result;
    } catch (e, st) {
      dev.log('Failed to read all cart operation logs: $e',
          name: 'CartOperationLogger', error: e, stackTrace: st);
      return {};
    }
  }

  /// 清除已同步的操作日志（同步成功后调用）
  static Future<void> clearSyncedLogs({DateTime? before}) async {
    try {
      final box = await HiveConfig.getBox(HiveConfig.cartOpsLogBox);
      final keysToDelete = <dynamic>[];
      for (final key in box.keys) {
        if (before == null) {
          keysToDelete.add(key);
        } else {
          final raw = box.get(key);
          if (raw is Map) {
            final ts = raw['timestamp'] as int?;
            if (ts != null &&
                DateTime.fromMillisecondsSinceEpoch(ts).isBefore(before)) {
              keysToDelete.add(key);
            }
          }
        }
      }
      for (final key in keysToDelete) {
        await box.delete(key);
      }
    } catch (e, st) {
      dev.log('Failed to clear cart operation logs: $e',
          name: 'CartOperationLogger', error: e, stackTrace: st);
    }
  }
}

/// 基于操作日志的购物车冲突合并器
///
/// 合并规则：
/// - `remove` 操作优先于 `updateQuantity`（删除不可被数量更新覆盖）
/// - 同一商品的 `updateQuantity` 取最新时间戳
/// - `add` 操作幂等（相同 itemId 不重复添加）
class CartOperationMerger {
  /// 根据操作日志决定商品的最终状态
  ///
  /// 返回 null 表示该商品应被删除
  static Map<String, dynamic>? mergeWithOperationLog(
    String itemId,
    Map<String, dynamic>? localItem,
    Map<String, dynamic>? serverItem,
    List<CartOperationLog> logs,
  ) {
    if (logs.isEmpty) {
      // 无操作日志，回退到 Last Write Wins
      return _lastWriteWins(localItem, serverItem);
    }

    // 检查是否有 remove 操作（remove 优先）
    final hasRemove = logs.any((l) => l.operation == CartOperation.remove);
    if (hasRemove) {
      // 找到最后一次 remove 之后是否有 add 操作
      final lastRemove = logs.lastWhere(
          (l) => l.operation == CartOperation.remove);
      final hasAddAfterRemove = logs.any((l) =>
          l.operation == CartOperation.add &&
          l.timestamp.isAfter(lastRemove.timestamp));
      if (!hasAddAfterRemove) {
        return null; // 最终状态：删除
      }
    }

    // 找最新的 updateQuantity
    final quantityLogs = logs
        .where((l) => l.operation == CartOperation.updateQuantity)
        .toList();
    if (quantityLogs.isNotEmpty) {
      final latest = quantityLogs.reduce(
          (a, b) => a.timestamp.isAfter(b.timestamp) ? a : b);
      final base = serverItem ?? localItem;
      if (base != null && latest.quantity != null) {
        return {...base, 'qty': latest.quantity};
      }
    }

    // 无特殊操作，使用 Last Write Wins
    return _lastWriteWins(localItem, serverItem);
  }

  static Map<String, dynamic>? _lastWriteWins(
    Map<String, dynamic>? local,
    Map<String, dynamic>? server,
  ) {
    if (local == null) return server;
    if (server == null) return local;

    final localTime = _parseDateTime(local['updated_at']);
    final serverTime = _parseDateTime(server['updated_at']);
    if (localTime == null) return server;
    if (serverTime == null) return local;
    return localTime.isAfter(serverTime) ? local : server;
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../core/storage/hive_config.dart';

/// 离线同步队列 - 用于在无网络时存储待同步的变更
class OfflineSyncQueue {
  static const String _boxName = 'offline_sync_queue';
  static const String _cartChangesKey = 'cart_changes';
  static const String _conversationChangesKey = 'conversation_changes';
  static const String _messageChangesKey = 'message_changes';

  Box? _box;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  
  /// 初始化锁 - 防止并发初始化
  Completer<void>? _initCompleter;
  
  /// 网络恢复回调
  Function()? onNetworkRestored;

  /// 初始化队列（带并发保护）
  Future<void> init() async {
    // 如果已初始化且 box 仍然打开，直接返回
    if (_box != null && _box!.isOpen) return;

    // If a previous init completed but the box was closed afterwards,
    // discard the stale completer so we can re-initialize.
    if (_initCompleter != null && _initCompleter!.isCompleted) {
      _initCompleter = null;
    }
    
    // 如果正在初始化，等待完成
    if (_initCompleter != null) {
      await _initCompleter!.future;
      return;
    }
    
    _initCompleter = Completer<void>();
    try {
      _box = await HiveConfig.getBox(_boxName);
      _startConnectivityMonitoring();
      _initCompleter!.complete();
    } catch (e) {
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }
  
  /// 确保已初始化（内部使用）
  Future<Box> _ensureInitialized() async {
    await init();
    return _box!;
  }

  /// 开始监听网络状态
  ///
  /// Cancels any previous subscription first to prevent duplicate listeners
  /// when [init] is called again after the box was closed.
  void _startConnectivityMonitoring() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      // 检查是否有任何非 none 的连接
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (hasConnection && hasPendingChanges) {
        onNetworkRestored?.call();
      }
    });
  }

  /// 检查当前是否有网络
  Future<bool> get hasNetwork async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// 是否有待同步的变更
  bool get hasPendingChanges {
    if (_box == null) return false;
    final cartChanges = _box!.get(_cartChangesKey, defaultValue: <dynamic>[]) as List;
    final convChanges = _box!.get(_conversationChangesKey, defaultValue: <dynamic>[]) as List;
    final msgChanges = _box!.get(_messageChangesKey, defaultValue: <dynamic>[]) as List;
    return cartChanges.isNotEmpty || convChanges.isNotEmpty || msgChanges.isNotEmpty;
  }

  /// 获取待同步的购物车变更数量
  int get pendingCartChangesCount {
    if (_box == null) return 0;
    final changes = _box!.get(_cartChangesKey, defaultValue: <dynamic>[]) as List;
    return changes.length;
  }

  /// 获取待同步的会话变更数量
  int get pendingConversationChangesCount {
    if (_box == null) return 0;
    final changes = _box!.get(_conversationChangesKey, defaultValue: <dynamic>[]) as List;
    return changes.length;
  }

  /// 添加购物车变更到队列
  /// Makes a defensive copy to avoid mutating the caller's map.
  Future<void> addCartChange(Map<String, dynamic> change) async {
    final box = await _ensureInitialized();
    
    final changes = List<dynamic>.from(
      box.get(_cartChangesKey, defaultValue: <dynamic>[]) as List,
    );
    
    // Defensive copy — never mutate the caller's map
    final copy = Map<String, dynamic>.from(change);
    copy['queued_at'] = DateTime.now().toIso8601String();
    changes.add(jsonEncode(copy));
    
    await box.put(_cartChangesKey, changes);
  }

  /// 添加会话变更到队列
  /// Makes a defensive copy to avoid mutating the caller's map.
  Future<void> addConversationChange(Map<String, dynamic> change) async {
    final box = await _ensureInitialized();
    
    final changes = List<dynamic>.from(
      box.get(_conversationChangesKey, defaultValue: <dynamic>[]) as List,
    );
    
    final copy = Map<String, dynamic>.from(change);
    copy['queued_at'] = DateTime.now().toIso8601String();
    changes.add(jsonEncode(copy));
    
    await box.put(_conversationChangesKey, changes);
  }

  /// 添加消息变更到队列
  /// Makes a defensive copy to avoid mutating the caller's map.
  Future<void> addMessageChange(Map<String, dynamic> change) async {
    final box = await _ensureInitialized();
    
    final changes = List<dynamic>.from(
      box.get(_messageChangesKey, defaultValue: <dynamic>[]) as List,
    );
    
    final copy = Map<String, dynamic>.from(change);
    copy['queued_at'] = DateTime.now().toIso8601String();
    changes.add(jsonEncode(copy));
    
    await box.put(_messageChangesKey, changes);
  }

  /// 获取所有待同步的购物车变更
  ///
  /// Corrupted entries are skipped and logged rather than crashing the entire
  /// retrieval, which would cause all queued changes to be lost.
  List<Map<String, dynamic>> getCartChanges() {
    return _deserializeChanges(_cartChangesKey);
  }

  /// 获取所有待同步的会话变更
  List<Map<String, dynamic>> getConversationChanges() {
    return _deserializeChanges(_conversationChangesKey);
  }

  /// 获取所有待同步的消息变更
  List<Map<String, dynamic>> getMessageChanges() {
    return _deserializeChanges(_messageChangesKey);
  }

  /// Shared deserialization with per-entry error handling.
  List<Map<String, dynamic>> _deserializeChanges(String key) {
    if (_box == null) return [];

    final changes = _box!.get(key, defaultValue: <dynamic>[]) as List;
    final result = <Map<String, dynamic>>[];
    for (final c in changes) {
      try {
        if (c is String) {
          result.add(Map<String, dynamic>.from(jsonDecode(c) as Map));
        } else if (c is Map) {
          result.add(Map<String, dynamic>.from(c));
        }
      } catch (e) {
        // Skip corrupted entry but log for diagnostics — prevents one bad
        // entry from discarding the entire queue.
        dev.log('Skipping corrupted sync queue entry (key=$key): $e',
            name: 'OfflineSyncQueue');
      }
    }
    return result;
  }

  /// 清空购物车变更队列
  Future<void> clearCartChanges() async {
    if (_box == null || !_box!.isOpen) return;
    await _box!.put(_cartChangesKey, <dynamic>[]);
  }

  /// 清空会话变更队列
  Future<void> clearConversationChanges() async {
    if (_box == null || !_box!.isOpen) return;
    await _box!.put(_conversationChangesKey, <dynamic>[]);
  }

  /// 清空消息变更队列
  Future<void> clearMessageChanges() async {
    if (_box == null || !_box!.isOpen) return;
    await _box!.put(_messageChangesKey, <dynamic>[]);
  }

  /// 清空所有队列
  Future<void> clearAll() async {
    await clearCartChanges();
    await clearConversationChanges();
    await clearMessageChanges();
  }

  /// 释放资源
  Future<void> dispose() async {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    if (_box != null && _box!.isOpen) {
      await _box!.close();
    }
    _box = null;
    _initCompleter = null;
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// 离线同步队列 - 用于在无网络时存储待同步的变更
class OfflineSyncQueue {
  static const String _boxName = 'offline_sync_queue';
  static const String _cartChangesKey = 'cart_changes';
  static const String _conversationChangesKey = 'conversation_changes';
  static const String _messageChangesKey = 'message_changes';

  Box? _box;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  
  /// 网络恢复回调
  Function()? onNetworkRestored;

  /// 初始化队列
  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    _startConnectivityMonitoring();
  }

  /// 开始监听网络状态
  void _startConnectivityMonitoring() {
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
  Future<void> addCartChange(Map<String, dynamic> change) async {
    if (_box == null) await init();
    
    final changes = List<dynamic>.from(
      _box!.get(_cartChangesKey, defaultValue: <dynamic>[]) as List,
    );
    
    // 添加时间戳
    change['queued_at'] = DateTime.now().toIso8601String();
    changes.add(jsonEncode(change));
    
    await _box!.put(_cartChangesKey, changes);
  }

  /// 添加会话变更到队列
  Future<void> addConversationChange(Map<String, dynamic> change) async {
    if (_box == null) await init();
    
    final changes = List<dynamic>.from(
      _box!.get(_conversationChangesKey, defaultValue: <dynamic>[]) as List,
    );
    
    change['queued_at'] = DateTime.now().toIso8601String();
    changes.add(jsonEncode(change));
    
    await _box!.put(_conversationChangesKey, changes);
  }

  /// 添加消息变更到队列
  Future<void> addMessageChange(Map<String, dynamic> change) async {
    if (_box == null) await init();
    
    final changes = List<dynamic>.from(
      _box!.get(_messageChangesKey, defaultValue: <dynamic>[]) as List,
    );
    
    change['queued_at'] = DateTime.now().toIso8601String();
    changes.add(jsonEncode(change));
    
    await _box!.put(_messageChangesKey, changes);
  }

  /// 获取所有待同步的购物车变更
  List<Map<String, dynamic>> getCartChanges() {
    if (_box == null) return [];
    
    final changes = _box!.get(_cartChangesKey, defaultValue: <dynamic>[]) as List;
    return changes.map((c) {
      if (c is String) {
        return Map<String, dynamic>.from(jsonDecode(c));
      }
      return Map<String, dynamic>.from(c as Map);
    }).toList();
  }

  /// 获取所有待同步的会话变更
  List<Map<String, dynamic>> getConversationChanges() {
    if (_box == null) return [];
    
    final changes = _box!.get(_conversationChangesKey, defaultValue: <dynamic>[]) as List;
    return changes.map((c) {
      if (c is String) {
        return Map<String, dynamic>.from(jsonDecode(c));
      }
      return Map<String, dynamic>.from(c as Map);
    }).toList();
  }

  /// 获取所有待同步的消息变更
  List<Map<String, dynamic>> getMessageChanges() {
    if (_box == null) return [];
    
    final changes = _box!.get(_messageChangesKey, defaultValue: <dynamic>[]) as List;
    return changes.map((c) {
      if (c is String) {
        return Map<String, dynamic>.from(jsonDecode(c));
      }
      return Map<String, dynamic>.from(c as Map);
    }).toList();
  }

  /// 清空购物车变更队列
  Future<void> clearCartChanges() async {
    if (_box == null) return;
    await _box!.put(_cartChangesKey, <dynamic>[]);
  }

  /// 清空会话变更队列
  Future<void> clearConversationChanges() async {
    if (_box == null) return;
    await _box!.put(_conversationChangesKey, <dynamic>[]);
  }

  /// 清空消息变更队列
  Future<void> clearMessageChanges() async {
    if (_box == null) return;
    await _box!.put(_messageChangesKey, <dynamic>[]);
  }

  /// 清空所有队列
  Future<void> clearAll() async {
    await clearCartChanges();
    await clearConversationChanges();
    await clearMessageChanges();
  }

  /// 释放资源
  void dispose() {
    _connectivitySubscription?.cancel();
  }
}

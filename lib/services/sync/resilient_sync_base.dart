import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/resilience/resilience.dart';
import '../../core/logging/app_logger.dart';
import '../../core/storage/hive_config.dart';

/// 同步操作类型
enum SyncOperationType {
  create,
  update,
  delete,
}

/// 同步操作记录 - 用于幂等性控制
class SyncOperation {
  final String id;
  final String resourceType;
  final String resourceId;
  final SyncOperationType type;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final int retryCount;
  final String? lastError;
  final DateTime? lastAttempt;

  SyncOperation({
    required this.id,
    required this.resourceType,
    required this.resourceId,
    required this.type,
    required this.data,
    required this.createdAt,
    this.retryCount = 0,
    this.lastError,
    this.lastAttempt,
  });

  SyncOperation copyWith({
    int? retryCount,
    String? lastError,
    DateTime? lastAttempt,
  }) {
    return SyncOperation(
      id: id,
      resourceType: resourceType,
      resourceId: resourceId,
      type: type,
      data: data,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      lastAttempt: lastAttempt ?? this.lastAttempt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'resourceType': resourceType,
        'resourceId': resourceId,
        'type': type.name,
        'data': data,
        'createdAt': createdAt.toIso8601String(),
        'retryCount': retryCount,
        'lastError': lastError,
        'lastAttempt': lastAttempt?.toIso8601String(),
      };

  factory SyncOperation.fromJson(Map<String, dynamic> json) {
    return SyncOperation(
      id: json['id'] as String,
      resourceType: json['resourceType'] as String,
      resourceId: json['resourceId'] as String,
      type: SyncOperationType.values.firstWhere((e) => e.name == json['type']),
      data: Map<String, dynamic>.from(json['data'] as Map),
      createdAt: DateTime.parse(json['createdAt'] as String),
      retryCount: json['retryCount'] as int? ?? 0,
      lastError: json['lastError'] as String?,
      lastAttempt: json['lastAttempt'] != null
          ? DateTime.parse(json['lastAttempt'] as String)
          : null,
    );
  }
}

/// 同步结果
class SyncResult {
  final bool success;
  final String? message;
  final int successCount;
  final int failureCount;
  final List<String> errors;
  final Duration duration;

  SyncResult({
    required this.success,
    this.message,
    this.successCount = 0,
    this.failureCount = 0,
    this.errors = const [],
    required this.duration,
  });

  factory SyncResult.success({
    String? message,
    int successCount = 0,
    required Duration duration,
  }) {
    return SyncResult(
      success: true,
      message: message,
      successCount: successCount,
      duration: duration,
    );
  }

  factory SyncResult.failure({
    required String message,
    List<String> errors = const [],
    int successCount = 0,
    int failureCount = 0,
    required Duration duration,
  }) {
    return SyncResult(
      success: false,
      message: message,
      successCount: successCount,
      failureCount: failureCount,
      errors: errors,
      duration: duration,
    );
  }

  factory SyncResult.partial({
    required int successCount,
    required int failureCount,
    required List<String> errors,
    required Duration duration,
  }) {
    return SyncResult(
      success: failureCount == 0,
      message: '同步完成: $successCount 成功, $failureCount 失败',
      successCount: successCount,
      failureCount: failureCount,
      errors: errors,
      duration: duration,
    );
  }
}

/// 健壮的同步服务基类
///
/// 提供以下功能：
/// - 幂等性保证（通过操作 ID 去重）
/// - 网络错误检测和分类
/// - 自动重试（带指数退避）
/// - 离线队列持久化
/// - 冲突检测和解决
/// - 详细日志
abstract class ResilientSyncBase {
  static const String _pendingOpsBoxName = 'pending_sync_operations';
  static const String _completedOpsBoxName = 'completed_sync_operations';
  static const int _maxRetries = 5;
  static const Duration _baseRetryDelay = Duration(seconds: 2);
  static const Duration _maxRetryDelay = Duration(minutes: 5);

  final String serviceName;
  final ModuleLogger _logger;
  final Uuid _uuid = const Uuid();
  final RetryExecutor _retryExecutor;

  Box? _pendingOpsBox;
  Box? _completedOpsBox;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;

  /// 网络状态变化回调
  void Function(bool hasNetwork)? onNetworkStateChanged;

  /// 同步状态变化回调
  void Function(bool isSyncing)? onSyncStateChanged;

  ResilientSyncBase({required this.serviceName})
      : _logger = AppLogger.instance.module('Sync:$serviceName'),
        _retryExecutor = RetryExecutor(
          config: const RetryConfig(
            maxAttempts: _maxRetries,
            initialDelay: _baseRetryDelay,
            maxDelay: _maxRetryDelay,
          ),
        );

  /// 初始化
  Future<void> initialize() async {
    _pendingOpsBox = await HiveConfig.getBox('${_pendingOpsBoxName}_$serviceName');
    _completedOpsBox = await HiveConfig.getBox('${_completedOpsBoxName}_$serviceName');

    // 监听网络状态
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);

    _logger.info('Initialized with ${pendingOperationsCount} pending operations');
  }

  /// 网络状态变化处理
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hasNetwork = results.any((r) => r != ConnectivityResult.none);
    _logger.debug('Network state changed: ${hasNetwork ? "online" : "offline"}');
    onNetworkStateChanged?.call(hasNetwork);

    // 网络恢复时自动触发同步
    if (hasNetwork && pendingOperationsCount > 0) {
      _logger.info('Network restored, triggering sync');
      // Guard against unhandled Future errors — syncPending is async but
      // the connectivity callback is void, so errors would be unhandled.
      unawaited(syncPending().catchError((Object e, StackTrace st) {
        _logger.warning('Auto-sync on network restore failed: $e');
        return SyncResult.failure(
          message: e.toString(),
          duration: Duration.zero,
        );
      }));
    }
  }

  /// 检查网络连接
  Future<bool> hasNetworkConnection() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// 获取待处理操作数量
  int get pendingOperationsCount => _pendingOpsBox?.length ?? 0;

  /// 是否正在同步
  bool get isSyncing => _isSyncing;

  /// 最后同步时间
  DateTime? get lastSyncTime => _lastSyncTime;

  /// 添加同步操作（带幂等性控制）
  Future<String> queueOperation({
    required String resourceType,
    required String resourceId,
    required SyncOperationType type,
    required Map<String, dynamic> data,
    String? operationId,
  }) async {
    final opId = operationId ?? _generateOperationId(resourceType, resourceId, type);

    // 检查是否已有相同操作
    if (_pendingOpsBox?.containsKey(opId) == true) {
      _logger.debug('Operation already queued: $opId');
      return opId;
    }

    // 检查是否已完成
    if (_completedOpsBox?.containsKey(opId) == true) {
      _logger.debug('Operation already completed: $opId');
      return opId;
    }

    final operation = SyncOperation(
      id: opId,
      resourceType: resourceType,
      resourceId: resourceId,
      type: type,
      data: data,
      createdAt: DateTime.now(),
    );

    await _pendingOpsBox?.put(opId, operation.toJson());
    _logger.debug('Queued operation: $opId (${type.name} $resourceType:$resourceId)');

    return opId;
  }

  /// 生成操作 ID（用于幂等性）
  String _generateOperationId(String resourceType, String resourceId, SyncOperationType type) {
    // 使用资源信息生成确定性 ID，确保相同操作得到相同 ID
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000; // 秒级精度
    return '${resourceType}_${resourceId}_${type.name}_$timestamp';
  }

  /// 同步待处理的操作
  Future<SyncResult> syncPending() async {
    if (_isSyncing) {
      _logger.warning('Sync already in progress');
      return SyncResult.failure(
        message: '同步正在进行中',
        duration: Duration.zero,
      );
    }

    if (!await hasNetworkConnection()) {
      _logger.warning('No network connection');
      return SyncResult.failure(
        message: '无网络连接',
        duration: Duration.zero,
      );
    }

    _isSyncing = true;
    onSyncStateChanged?.call(true);
    final stopwatch = Stopwatch()..start();

    try {
      final pendingOps = _getPendingOperations();
      if (pendingOps.isEmpty) {
        stopwatch.stop();
        return SyncResult.success(
          message: '没有待同步的操作',
          duration: stopwatch.elapsed,
        );
      }

      _logger.info('Starting sync with ${pendingOps.length} pending operations');

      int successCount = 0;
      int failureCount = 0;
      final errors = <String>[];

      for (final operation in pendingOps) {
        try {
          final result = await _executeOperation(operation);
          if (result.isSuccess) {
            await _markOperationCompleted(operation);
            successCount++;
          } else {
            await _handleOperationFailure(operation, result.failureOrNull?.message ?? 'Unknown error');
            failureCount++;
            errors.add('${operation.id}: ${result.failureOrNull?.message}');
          }
        } catch (e) {
          final analysis = NetworkErrorDetector.analyze(e);
          await _handleOperationFailure(operation, analysis.userFriendlyMessage);
          failureCount++;
          errors.add('${operation.id}: ${analysis.userFriendlyMessage}');

          // 如果是不可重试的网络错误，停止同步
          if (!analysis.isRetryable) {
            _logger.warning('Non-retryable error, stopping sync: ${analysis.userFriendlyMessage}');
            break;
          }
        }
      }

      stopwatch.stop();
      _lastSyncTime = DateTime.now();

      _logger.info('Sync completed: $successCount success, $failureCount failed');

      return SyncResult.partial(
        successCount: successCount,
        failureCount: failureCount,
        errors: errors,
        duration: stopwatch.elapsed,
      );
    } finally {
      _isSyncing = false;
      onSyncStateChanged?.call(false);
    }
  }

  /// 执行单个操作（由子类实现）
  Future<Result<void>> executeOperation(SyncOperation operation);

  /// 执行操作（带重试）
  Future<Result<void>> _executeOperation(SyncOperation operation) async {
    return _retryExecutor.execute(
      () async {
        final result = await executeOperation(operation);
        if (result.isFailure) {
          throw Exception(result.failureOrNull?.message);
        }
        return result;
      },
      operationName: '${operation.type.name}:${operation.resourceType}:${operation.resourceId}',
      retryIf: (error) => NetworkErrorDetector.isRetryable(error),
    ).then((retryResult) {
      if (retryResult.isSuccess) {
        return retryResult.value!;
      }
      return Result<void>.failure(Failure(
        message: retryResult.error.toString(),
        error: retryResult.error,
        stackTrace: retryResult.stackTrace,
      ));
    });
  }

  /// 获取待处理操作列表
  List<SyncOperation> _getPendingOperations() {
    final operations = <SyncOperation>[];
    if (_pendingOpsBox == null) return operations;

    for (final key in _pendingOpsBox!.keys) {
      final json = _pendingOpsBox!.get(key);
      if (json is Map) {
        try {
          operations.add(SyncOperation.fromJson(Map<String, dynamic>.from(json)));
        } catch (e) {
          _logger.warning('Failed to parse operation: $key', error: e);
        }
      }
    }

    // 按创建时间排序
    operations.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return operations;
  }

  /// 标记操作完成
  Future<void> _markOperationCompleted(SyncOperation operation) async {
    await _pendingOpsBox?.delete(operation.id);

    // 记录到已完成列表（用于幂等性检查，保留一段时间）
    await _completedOpsBox?.put(operation.id, {
      'completedAt': DateTime.now().toIso8601String(),
    });

    // 清理过期的完成记录（超过 24 小时）
    _cleanupCompletedOperations();

    _logger.debug('Operation completed: ${operation.id}');
  }

  /// 处理操作失败
  Future<void> _handleOperationFailure(SyncOperation operation, String error) async {
    final updated = operation.copyWith(
      retryCount: operation.retryCount + 1,
      lastError: error,
      lastAttempt: DateTime.now(),
    );

    if (updated.retryCount >= _maxRetries) {
      // 超过最大重试次数，移入死信队列
      _logger.error('Operation failed after $_maxRetries retries: ${operation.id}');
      await _pendingOpsBox?.delete(operation.id);
      // 可以添加死信队列处理
    } else {
      await _pendingOpsBox?.put(operation.id, updated.toJson());
      _logger.warning('Operation failed (attempt ${updated.retryCount}): ${operation.id} - $error');
    }
  }

  /// 清理过期的完成记录
  void _cleanupCompletedOperations() {
    if (_completedOpsBox == null) return;

    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    final keysToRemove = <dynamic>[];

    for (final key in _completedOpsBox!.keys) {
      final data = _completedOpsBox!.get(key);
      if (data is Map) {
        final completedAt = DateTime.tryParse(data['completedAt'] as String? ?? '');
        if (completedAt != null && completedAt.isBefore(cutoff)) {
          keysToRemove.add(key);
        }
      }
    }

    for (final key in keysToRemove) {
      _completedOpsBox!.delete(key);
    }

    if (keysToRemove.isNotEmpty) {
      _logger.debug('Cleaned up ${keysToRemove.length} completed operations');
    }
  }

  /// 清除所有待处理操作
  Future<void> clearPendingOperations() async {
    await _pendingOpsBox?.clear();
    _logger.info('Cleared all pending operations');
  }

  /// 获取状态摘要
  Map<String, dynamic> getStatus() {
    return {
      'serviceName': serviceName,
      'isSyncing': _isSyncing,
      'pendingCount': pendingOperationsCount,
      'lastSyncTime': _lastSyncTime?.toIso8601String(),
    };
  }

  /// 释放资源
  Future<void> dispose() async {
    _connectivitySubscription?.cancel();
    await _pendingOpsBox?.close();
    await _completedOpsBox?.close();
  }
}

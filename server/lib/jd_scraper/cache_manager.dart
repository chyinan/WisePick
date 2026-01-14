import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'models/product_info.dart';

/// 缓存配置
class CacheConfig {
  /// 默认缓存有效期
  final Duration defaultTtl;

  /// 最大缓存条目数
  final int maxEntries;

  /// 是否启用持久化
  final bool enablePersistence;

  /// 持久化文件路径
  final String persistencePath;

  /// 清理间隔
  final Duration cleanupInterval;

  const CacheConfig({
    this.defaultTtl = const Duration(minutes: 10),
    this.maxEntries = 1000,
    this.enablePersistence = false,
    this.persistencePath = 'data/product_cache.json',
    this.cleanupInterval = const Duration(minutes: 5),
  });
}

/// 缓存条目
class CacheEntry<T> {
  final T value;
  final DateTime createdAt;
  final DateTime expiresAt;
  int _hitCount = 0;
  DateTime _lastAccessedAt;

  CacheEntry({
    required this.value,
    required Duration ttl,
  })  : createdAt = DateTime.now(),
        expiresAt = DateTime.now().add(ttl),
        _lastAccessedAt = DateTime.now();

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  int get hitCount => _hitCount;

  DateTime get lastAccessedAt => _lastAccessedAt;

  /// 记录访问
  void recordAccess() {
    _hitCount++;
    _lastAccessedAt = DateTime.now();
  }

  /// 剩余有效时间
  Duration get remainingTtl {
    final remaining = expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

/// 高级缓存管理器
///
/// 提供 LRU 淘汰、TTL 过期、持久化等功能
class CacheManager<T> {
  final CacheConfig config;
  final LinkedHashMap<String, CacheEntry<T>> _cache = LinkedHashMap();
  Timer? _cleanupTimer;

  /// 缓存统计
  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;

  CacheManager({CacheConfig? config}) : config = config ?? const CacheConfig() {
    _startCleanupTimer();
  }

  /// 获取缓存
  T? get(String key) {
    final entry = _cache[key];

    if (entry == null) {
      _misses++;
      return null;
    }

    if (entry.isExpired) {
      _cache.remove(key);
      _misses++;
      return null;
    }

    // 记录访问并移到末尾（LRU）
    entry.recordAccess();
    _cache.remove(key);
    _cache[key] = entry;
    _hits++;

    return entry.value;
  }

  /// 设置缓存
  void set(String key, T value, {Duration? ttl}) {
    // 检查容量
    while (_cache.length >= config.maxEntries) {
      _evictOne();
    }

    _cache[key] = CacheEntry(
      value: value,
      ttl: ttl ?? config.defaultTtl,
    );
  }

  /// 检查是否存在
  bool contains(String key) {
    final entry = _cache[key];
    if (entry == null) return false;
    if (entry.isExpired) {
      _cache.remove(key);
      return false;
    }
    return true;
  }

  /// 删除缓存
  void remove(String key) {
    _cache.remove(key);
  }

  /// 清空缓存
  void clear() {
    _cache.clear();
    _hits = 0;
    _misses = 0;
    _evictions = 0;
  }

  /// 淘汰一个条目（LRU策略）
  void _evictOne() {
    if (_cache.isEmpty) return;

    // 找到最久未访问的条目
    String? oldestKey;
    DateTime? oldestAccess;

    for (final entry in _cache.entries) {
      if (oldestAccess == null ||
          entry.value.lastAccessedAt.isBefore(oldestAccess)) {
        oldestKey = entry.key;
        oldestAccess = entry.value.lastAccessedAt;
      }
    }

    if (oldestKey != null) {
      _cache.remove(oldestKey);
      _evictions++;
    }
  }

  /// 清理过期条目
  void cleanup() {
    final keysToRemove = <String>[];

    for (final entry in _cache.entries) {
      if (entry.value.isExpired) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      _cache.remove(key);
    }
  }

  /// 启动清理定时器
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(config.cleanupInterval, (_) {
      cleanup();
    });
  }

  /// 获取统计信息
  Map<String, dynamic> getStats() {
    final total = _hits + _misses;
    return {
      'size': _cache.length,
      'maxSize': config.maxEntries,
      'hits': _hits,
      'misses': _misses,
      'hitRate': total > 0 ? (_hits / total * 100).toStringAsFixed(2) : '0.00',
      'evictions': _evictions,
    };
  }

  /// 关闭缓存管理器
  void dispose() {
    _cleanupTimer?.cancel();
    _cache.clear();
  }
}

/// 商品缓存管理器
///
/// 专门用于缓存商品信息，支持持久化
class ProductCacheManager extends CacheManager<JdProductInfo> {
  ProductCacheManager({CacheConfig? config}) : super(config: config);

  /// 从持久化文件加载
  Future<void> loadFromFile() async {
    if (!config.enablePersistence) return;

    try {
      final file = File(config.persistencePath);
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>;

      for (final item in items) {
        final key = item['key'] as String;
        final productData = item['value'] as Map<String, dynamic>;
        final expiresAt = DateTime.parse(item['expiresAt'] as String);

        // 检查是否过期
        if (DateTime.now().isBefore(expiresAt)) {
          final product = JdProductInfo.fromJson(productData);
          final remaining = expiresAt.difference(DateTime.now());
          set(key, product, ttl: remaining);
        }
      }

      print('[ProductCache] 从文件加载了 ${_cache.length} 个缓存条目');
    } catch (e) {
      print('[ProductCache] 加载缓存文件失败: $e');
    }
  }

  /// 保存到持久化文件
  Future<void> saveToFile() async {
    if (!config.enablePersistence) return;

    try {
      final items = <Map<String, dynamic>>[];

      for (final entry in _cache.entries) {
        if (!entry.value.isExpired) {
          items.add({
            'key': entry.key,
            'value': entry.value.value.toJson(),
            'expiresAt': entry.value.expiresAt.toIso8601String(),
          });
        }
      }

      final data = {
        'savedAt': DateTime.now().toIso8601String(),
        'count': items.length,
        'items': items,
      };

      final dir = Directory(config.persistencePath).parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      await File(config.persistencePath).writeAsString(
        jsonEncode(data),
        flush: true,
      );

      print('[ProductCache] 保存了 ${items.length} 个缓存条目到文件');
    } catch (e) {
      print('[ProductCache] 保存缓存文件失败: $e');
    }
  }
}

/// 请求去重器
///
/// 对相同的并发请求进行合并，避免重复处理
class RequestDeduplicator<T> {
  final Map<String, _PendingRequest<T>> _pending = {};

  /// 执行或等待请求
  ///
  /// 如果已有相同 key 的请求在进行，则等待其结果
  /// 否则执行新请求
  Future<T> execute(
    String key,
    Future<T> Function() request,
  ) async {
    // 如果已有相同请求在进行，等待其结果
    if (_pending.containsKey(key)) {
      return await _pending[key]!.future;
    }

    // 创建新的待处理请求
    final completer = Completer<T>();
    final pending = _PendingRequest<T>(
      completer: completer,
      startTime: DateTime.now(),
    );
    _pending[key] = pending;

    try {
      final result = await request();
      completer.complete(result);
      return result;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _pending.remove(key);
    }
  }

  /// 检查是否有待处理的请求
  bool hasPending(String key) => _pending.containsKey(key);

  /// 获取待处理请求数量
  int get pendingCount => _pending.length;

  /// 获取统计信息
  Map<String, dynamic> getStats() {
    return {
      'pendingCount': _pending.length,
      'pendingKeys': _pending.keys.toList(),
    };
  }
}

class _PendingRequest<T> {
  final Completer<T> completer;
  final DateTime startTime;
  int waitingCount = 1;

  _PendingRequest({
    required this.completer,
    required this.startTime,
  });

  Future<T> get future => completer.future;
}

/// 高级并发控制器
///
/// 提供更细粒度的并发控制，支持优先级队列
class ConcurrencyController {
  final int maxConcurrency;
  int _currentCount = 0;
  final Queue<_QueuedTask> _queue = Queue();

  ConcurrencyController({this.maxConcurrency = 3});

  /// 执行任务（带并发控制）
  Future<T> execute<T>(
    Future<T> Function() task, {
    int priority = 0,
  }) async {
    // 如果有空闲槽位，直接执行
    if (_currentCount < maxConcurrency) {
      return await _runTask(task);
    }

    // 否则加入队列等待
    final completer = Completer<T>();
    final queuedTask = _QueuedTask(
      execute: () async {
        try {
          final result = await task();
          completer.complete(result);
        } catch (e) {
          completer.completeError(e);
        }
      },
      priority: priority,
    );

    // 按优先级插入队列
    _insertByPriority(queuedTask);

    return completer.future;
  }

  /// 执行任务
  Future<T> _runTask<T>(Future<T> Function() task) async {
    _currentCount++;
    try {
      return await task();
    } finally {
      _currentCount--;
      _processQueue();
    }
  }

  /// 按优先级插入队列
  void _insertByPriority(_QueuedTask task) {
    if (_queue.isEmpty) {
      _queue.add(task);
      return;
    }

    // 找到合适的位置插入
    final list = _queue.toList();
    int insertIndex = list.length;
    for (int i = 0; i < list.length; i++) {
      if (task.priority > list[i].priority) {
        insertIndex = i;
        break;
      }
    }

    list.insert(insertIndex, task);
    _queue.clear();
    _queue.addAll(list);
  }

  /// 处理队列
  void _processQueue() {
    if (_queue.isEmpty || _currentCount >= maxConcurrency) return;

    final task = _queue.removeFirst();
    _currentCount++;

    task.execute().whenComplete(() {
      _currentCount--;
      _processQueue();
    });
  }

  /// 获取状态
  Map<String, dynamic> getStats() {
    return {
      'maxConcurrency': maxConcurrency,
      'currentCount': _currentCount,
      'queueLength': _queue.length,
    };
  }
}

class _QueuedTask {
  final Future<void> Function() execute;
  final int priority;

  _QueuedTask({
    required this.execute,
    this.priority = 0,
  });
}











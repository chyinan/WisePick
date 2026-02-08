import 'dart:async';
import 'package:postgres/postgres.dart';

/// 数据库配置
class DatabaseConfig {
  final String host;
  final int port;
  final String database;
  final String username;
  final String password;

  /// 最大连接数
  final int maxConnections;

  /// 连接超时
  final Duration connectionTimeout;

  /// 查询超时
  final Duration queryTimeout;

  /// 空闲连接超时
  final Duration idleTimeout;

  /// 重连延迟
  final Duration reconnectDelay;

  /// 最大重连尝试次数
  final int maxReconnectAttempts;

  /// 健康检查间隔
  final Duration healthCheckInterval;

  /// SSL 模式
  final SslMode sslMode;

  const DatabaseConfig({
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
    this.maxConnections = 10,
    this.connectionTimeout = const Duration(seconds: 30),
    this.queryTimeout = const Duration(seconds: 60),
    this.idleTimeout = const Duration(minutes: 10),
    this.reconnectDelay = const Duration(seconds: 5),
    this.maxReconnectAttempts = 3,
    this.healthCheckInterval = const Duration(minutes: 1),
    this.sslMode = SslMode.disable,
  });

  /// 从环境变量创建配置
  factory DatabaseConfig.fromEnv(Map<String, String> env) {
    return DatabaseConfig(
      host: env['DB_HOST'] ?? 'localhost',
      port: int.tryParse(env['DB_PORT'] ?? '5432') ?? 5432,
      database: env['DB_NAME'] ?? 'wisepick',
      username: env['DB_USER'] ?? 'postgres',
      password: env['DB_PASSWORD'] ?? 'postgres',
      maxConnections: int.tryParse(env['DB_MAX_CONNECTIONS'] ?? '10') ?? 10,
    );
  }

  /// 开发环境配置
  factory DatabaseConfig.development() {
    return const DatabaseConfig(
      host: 'localhost',
      port: 5432,
      database: 'wisepick',
      username: 'postgres',
      password: 'postgres',
      maxConnections: 5,
      queryTimeout: Duration(seconds: 30),
    );
  }

  /// 生产环境配置
  factory DatabaseConfig.production({
    required String host,
    required String database,
    required String username,
    required String password,
    int port = 5432,
  }) {
    return DatabaseConfig(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
      maxConnections: 20,
      queryTimeout: const Duration(seconds: 120),
      sslMode: SslMode.require,
    );
  }

  Endpoint toEndpoint() {
    return Endpoint(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
    );
  }
}

/// 数据库健康状态
enum DatabaseHealthStatus {
  healthy,
  degraded,
  unhealthy,
}

/// 数据库健康检查结果
class DatabaseHealthCheck {
  final DatabaseHealthStatus status;
  final Duration responseTime;
  final String? error;
  final DateTime checkedAt;
  final int activeConnections;
  final int maxConnections;

  DatabaseHealthCheck({
    required this.status,
    required this.responseTime,
    this.error,
    required this.checkedAt,
    required this.activeConnections,
    required this.maxConnections,
  });

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'responseTime': '${responseTime.inMilliseconds}ms',
        'error': error,
        'checkedAt': checkedAt.toIso8601String(),
        'activeConnections': activeConnections,
        'maxConnections': maxConnections,
      };
}

/// 查询结果包装
class QueryResult<T> {
  final T? value;
  final Duration duration;
  final bool success;
  final String? error;
  final int? affectedRows;

  QueryResult._({
    this.value,
    required this.duration,
    required this.success,
    this.error,
    this.affectedRows,
  });

  factory QueryResult.success(T value, Duration duration, {int? affectedRows}) {
    return QueryResult._(
      value: value,
      duration: duration,
      success: true,
      affectedRows: affectedRows,
    );
  }

  factory QueryResult.failure(String error, Duration duration) {
    return QueryResult._(
      duration: duration,
      success: false,
      error: error,
    );
  }
}

/// 健壮的数据库管理器
///
/// 提供以下功能：
/// - 自动重连
/// - 连接池管理
/// - 健康检查
/// - 查询超时
/// - 事务重试
/// - 详细日志
class ResilientDatabase {
  final DatabaseConfig config;
  Pool? _pool;
  bool _isConnected = false;
  bool _isConnecting = false;
  int _reconnectAttempts = 0;
  Timer? _healthCheckTimer;
  DatabaseHealthCheck? _lastHealthCheck;

  /// 连接状态变化回调
  void Function(bool connected)? onConnectionStateChanged;

  /// 错误回调
  void Function(String error)? onError;

  ResilientDatabase(this.config);

  /// 是否已连接
  bool get isConnected => _isConnected;

  /// 获取最近的健康检查结果
  DatabaseHealthCheck? get lastHealthCheck => _lastHealthCheck;

  /// 连接数据库
  Future<bool> connect() async {
    if (_isConnected) return true;
    if (_isConnecting) {
      // 等待正在进行的连接
      while (_isConnecting) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return _isConnected;
    }

    _isConnecting = true;
    _log('Connecting to database...');
    _log('Host: ${config.host}:${config.port}, Database: ${config.database}');

    try {
      _pool = Pool.withEndpoints(
        [config.toEndpoint()],
        settings: PoolSettings(
          maxConnectionCount: config.maxConnections,
          sslMode: config.sslMode,
          connectTimeout: config.connectionTimeout,
          queryTimeout: config.queryTimeout,
        ),
      );

      // 测试连接
      await _pool!.execute('SELECT 1');
      _isConnected = true;
      _reconnectAttempts = 0;
      _log('Connected successfully!');

      // 启动健康检查
      _startHealthCheck();

      onConnectionStateChanged?.call(true);
      return true;
    } catch (e) {
      _log('Connection failed: $e');
      onError?.call('Database connection failed: $e');
      _isConnected = false;
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;

    if (_pool != null) {
      await _pool!.close();
      _pool = null;
      _isConnected = false;
      _log('Disconnected');
      onConnectionStateChanged?.call(false);
    }
  }

  /// 重连
  Future<bool> reconnect() async {
    if (_reconnectAttempts >= config.maxReconnectAttempts) {
      _log('Max reconnect attempts reached');
      onError?.call('Database reconnection failed after ${config.maxReconnectAttempts} attempts');
      return false;
    }

    _reconnectAttempts++;
    _log('Reconnect attempt $_reconnectAttempts/${config.maxReconnectAttempts}');

    await disconnect();
    await Future.delayed(config.reconnectDelay);
    return await connect();
  }

  /// 确保连接可用
  Future<bool> _ensureConnected() async {
    if (_isConnected && _pool != null) {
      return true;
    }

    // 尝试重连
    return await reconnect();
  }

  /// 执行查询
  Future<Result> execute(
    String sql, {
    Map<String, dynamic>? parameters,
    Duration? timeout,
  }) async {
    if (!await _ensureConnected()) {
      throw StateError('Database not connected');
    }

    final effectiveTimeout = timeout ?? config.queryTimeout;
    final stopwatch = Stopwatch()..start();

    try {
      final result = await _pool!
          .execute(
            Sql.named(sql),
            parameters: parameters ?? {},
          )
          .timeout(
            effectiveTimeout,
            onTimeout: () => throw TimeoutException('Query timed out', effectiveTimeout),
          );

      stopwatch.stop();
      _logQuery(sql, stopwatch.elapsed, parameters);
      return result;
    } catch (e) {
      stopwatch.stop();
      _logQuery(sql, stopwatch.elapsed, parameters, error: e.toString());

      // 检查是否需要重连
      if (_isConnectionError(e)) {
        _isConnected = false;
        onConnectionStateChanged?.call(false);
      }

      rethrow;
    }
  }

  /// 执行查询并返回单行
  Future<Map<String, dynamic>?> queryOne(
    String sql, {
    Map<String, dynamic>? parameters,
    Duration? timeout,
  }) async {
    final result = await execute(sql, parameters: parameters, timeout: timeout);
    if (result.isEmpty) return null;
    return result.first.toColumnMap();
  }

  /// 执行查询并返回所有行
  Future<List<Map<String, dynamic>>> queryAll(
    String sql, {
    Map<String, dynamic>? parameters,
    Duration? timeout,
  }) async {
    final result = await execute(sql, parameters: parameters, timeout: timeout);
    return result.map((row) => row.toColumnMap()).toList();
  }

  /// 执行带重试的事务
  Future<T> transaction<T>(
    Future<T> Function(Session session) action, {
    int maxRetries = 3,
    Duration retryDelay = const Duration(milliseconds: 500),
  }) async {
    if (!await _ensureConnected()) {
      throw StateError('Database not connected');
    }

    int attempt = 0;
    Object? lastError;

    while (attempt < maxRetries) {
      attempt++;
      try {
        return await _pool!.withConnection((connection) async {
          return await connection.runTx(action);
        });
      } catch (e) {
        lastError = e;
        _log('Transaction attempt $attempt failed: $e');

        // 检查是否为可重试的错误
        if (!_isRetryableTransactionError(e)) {
          rethrow;
        }

        if (attempt < maxRetries) {
          await Future.delayed(retryDelay * attempt);
        }
      }
    }

    throw lastError ?? Exception('Transaction failed after $maxRetries attempts');
  }

  /// 执行带重试的操作
  Future<T> executeWithRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration retryDelay = const Duration(milliseconds: 500),
    bool Function(Object error)? retryIf,
  }) async {
    int attempt = 0;
    Object? lastError;
    StackTrace? lastStackTrace;

    while (attempt < maxRetries) {
      attempt++;
      try {
        return await operation();
      } catch (e, stack) {
        lastError = e;
        lastStackTrace = stack;
        _log('Operation attempt $attempt failed: $e');

        // 检查是否应该重试
        final shouldRetry = retryIf?.call(e) ?? _isRetryableError(e);
        if (!shouldRetry) {
          rethrow;
        }

        if (attempt < maxRetries) {
          await Future.delayed(retryDelay * attempt);
        }
      }
    }

    Error.throwWithStackTrace(
      lastError ?? Exception('Operation failed after $maxRetries attempts'),
      lastStackTrace ?? StackTrace.current,
    );
  }

  /// 健康检查
  Future<DatabaseHealthCheck> healthCheck() async {
    final stopwatch = Stopwatch()..start();

    try {
      if (!_isConnected || _pool == null) {
        stopwatch.stop();
        return _lastHealthCheck = DatabaseHealthCheck(
          status: DatabaseHealthStatus.unhealthy,
          responseTime: stopwatch.elapsed,
          error: 'Not connected',
          checkedAt: DateTime.now(),
          activeConnections: 0,
          maxConnections: config.maxConnections,
        );
      }

      // 执行简单查询测试连接
      await _pool!.execute('SELECT 1').timeout(const Duration(seconds: 5));
      stopwatch.stop();

      final status = stopwatch.elapsedMilliseconds > 1000
          ? DatabaseHealthStatus.degraded
          : DatabaseHealthStatus.healthy;

      return _lastHealthCheck = DatabaseHealthCheck(
        status: status,
        responseTime: stopwatch.elapsed,
        checkedAt: DateTime.now(),
        activeConnections: 0, // Pool 不暴露此信息
        maxConnections: config.maxConnections,
      );
    } catch (e) {
      stopwatch.stop();
      return _lastHealthCheck = DatabaseHealthCheck(
        status: DatabaseHealthStatus.unhealthy,
        responseTime: stopwatch.elapsed,
        error: e.toString(),
        checkedAt: DateTime.now(),
        activeConnections: 0,
        maxConnections: config.maxConnections,
      );
    }
  }

  /// 启动健康检查定时器
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(config.healthCheckInterval, (_) async {
      final check = await healthCheck();
      if (check.status == DatabaseHealthStatus.unhealthy) {
        _log('Health check failed: ${check.error}');
        // 尝试重连
        await reconnect();
      }
    });
  }

  /// 判断是否为连接错误
  bool _isConnectionError(Object error) {
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('connection') ||
        errorStr.contains('socket') ||
        errorStr.contains('refused') ||
        errorStr.contains('reset') ||
        errorStr.contains('closed');
  }

  /// 判断是否为可重试的事务错误
  bool _isRetryableTransactionError(Object error) {
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('deadlock') ||
        errorStr.contains('serialization') ||
        errorStr.contains('lock wait') ||
        errorStr.contains('could not serialize');
  }

  /// 判断是否为可重试的错误
  bool _isRetryableError(Object error) {
    if (_isConnectionError(error)) return true;
    if (_isRetryableTransactionError(error)) return true;

    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('timeout') ||
        errorStr.contains('too many connections');
  }

  /// 记录日志
  void _log(String message) {
    print('[ResilientDatabase] $message');
  }

  /// 记录查询日志
  void _logQuery(String sql, Duration duration, Map<String, dynamic>? params, {String? error}) {
    final durationMs = duration.inMilliseconds;
    final truncatedSql = sql.length > 200 ? '${sql.substring(0, 200)}...' : sql;

    if (error != null) {
      print('[ResilientDatabase] QUERY ERROR (${durationMs}ms): $truncatedSql - $error');
    } else if (durationMs > 1000) {
      print('[ResilientDatabase] SLOW QUERY (${durationMs}ms): $truncatedSql');
    }
  }

  /// 获取状态摘要
  Map<String, dynamic> getStatus() {
    return {
      'connected': _isConnected,
      'reconnectAttempts': _reconnectAttempts,
      'config': {
        'host': config.host,
        'port': config.port,
        'database': config.database,
        'maxConnections': config.maxConnections,
      },
      'lastHealthCheck': _lastHealthCheck?.toJson(),
    };
  }
}

/// 便捷函数：创建并连接数据库
Future<ResilientDatabase> createDatabase(DatabaseConfig config) async {
  final db = ResilientDatabase(config);
  await db.connect();
  return db;
}

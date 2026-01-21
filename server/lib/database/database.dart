import 'package:postgres/postgres.dart';

/// PostgreSQL 数据库连接管理器
class Database {
  static Database? _instance;
  Pool? _pool;
  bool _isConnected = false;

  // 单例模式
  Database._();

  static Database get instance {
    _instance ??= Database._();
    return _instance!;
  }

  static final Map<String, String> _envVars = {};

  /// 设置环境变量（供启动时使用）
  static void setEnvVars(Map<String, String> vars) {
    _envVars.addAll(vars);
  }

  /// 从环境变量获取配置
  static String getEnv(String key, String defaultValue) {
    return _envVars[key] ?? defaultValue;
  }

  /// 获取连接池
  Pool get pool {
    if (_pool == null || !_isConnected) {
      throw StateError('Database not connected. Call connect() first.');
    }
    return _pool!;
  }

  /// 是否已连接
  bool get isConnected => _isConnected;

  /// 连接数据库
  Future<void> connect() async {
    if (_isConnected) return;

    final dbHost = getEnv('DB_HOST', 'localhost');
    final dbPort = int.tryParse(getEnv('DB_PORT', '5432')) ?? 5432;
    final dbName = getEnv('DB_NAME', 'wisepick');
    final dbUser = getEnv('DB_USER', 'postgres');
    final dbPassword = getEnv('DB_PASSWORD', 'postgres');

    print('[Database] Connecting to PostgreSQL...');
    print('[Database] Host: $dbHost:$dbPort, Database: $dbName');

    try {
      final endpoint = Endpoint(
        host: dbHost,
        port: dbPort,
        database: dbName,
        username: dbUser,
        password: dbPassword,
      );

      _pool = Pool.withEndpoints(
        [endpoint],
        settings: PoolSettings(
          maxConnectionCount: 10,
          sslMode: SslMode.disable, // 开发环境禁用 SSL
        ),
      );

      // 测试连接
      await _pool!.execute('SELECT 1');
      _isConnected = true;
      print('[Database] Connected successfully!');
    } catch (e) {
      print('[Database] Connection failed: $e');
      rethrow;
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    if (_pool != null) {
      await _pool!.close();
      _pool = null;
      _isConnected = false;
      print('[Database] Disconnected');
    }
  }

  /// 执行查询
  Future<Result> execute(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    if (!_isConnected) {
      throw StateError('Database not connected');
    }
    return await _pool!.execute(
      Sql.named(sql),
      parameters: parameters ?? {},
    );
  }

  /// 执行查询并返回单行
  Future<Map<String, dynamic>?> queryOne(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    final result = await execute(sql, parameters: parameters);
    if (result.isEmpty) return null;
    return result.first.toColumnMap();
  }

  /// 执行查询并返回所有行
  Future<List<Map<String, dynamic>>> queryAll(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    final result = await execute(sql, parameters: parameters);
    return result.map((row) => row.toColumnMap()).toList();
  }

  /// 执行事务
  Future<T> transaction<T>(
    Future<T> Function(Session session) action,
  ) async {
    if (!_isConnected) {
      throw StateError('Database not connected');
    }
    return await _pool!.withConnection((connection) async {
      return await connection.runTx(action);
    });
  }

  /// 测试连接
  Future<bool> testConnection() async {
    try {
      if (!_isConnected) {
        await connect();
      }
      final result = await execute('SELECT 1 as test');
      return result.isNotEmpty;
    } catch (e) {
      print('[Database] Test connection failed: $e');
      return false;
    }
  }

  /// 运行迁移脚本
  Future<void> runMigrations() async {
    print('[Database] Running migrations...');

    // 创建迁移记录表
    await execute('''
      CREATE TABLE IF NOT EXISTS _migrations (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) NOT NULL UNIQUE,
        applied_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      )
    ''');

    // 检查并运行迁移
    final migrations = [
      '001_create_user_tables',
    ];

    for (final migration in migrations) {
      final applied = await queryOne(
        'SELECT id FROM _migrations WHERE name = @name',
        parameters: {'name': migration},
      );

      if (applied == null) {
        print('[Database] Applying migration: $migration');
        // 在实际实现中，应该读取并执行迁移文件
        await execute(
          'INSERT INTO _migrations (name) VALUES (@name)',
          parameters: {'name': migration},
        );
        print('[Database] Migration applied: $migration');
      }
    }

    print('[Database] Migrations complete!');
  }
}

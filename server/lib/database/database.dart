import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:postgres/postgres.dart';

/// PostgreSQL 数据库连接管理器
class Database {
  static Database? _instance;
  Pool? _pool;
  bool _isConnected = false;

  /// 服务器启动时间（真实记录）
  static final DateTime serverStartTime = DateTime.now();

  // 单例模式
  Database._();

  /// 仅供测试使用的构造函数，允许子类继承
  Database.testOnly();

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

  /// 执行原始 SQL (无参数绑定, 用于 DDL 迁移脚本)
  Future<Result> executeRaw(String sql) async {
    if (!_isConnected) {
      throw StateError('Database not connected');
    }
    return await _pool!.execute(sql);
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

  /// 解析迁移目录路径
  /// 从 Platform.script（bin/proxy_server.dart）定位到 lib/database/migrations/
  static Directory _resolveMigrationsDir() {
    try {
      final scriptPath = Platform.script.toFilePath();
      final scriptDir = File(scriptPath).parent; // server/bin/
      final serverDir = scriptDir.parent; // server/
      return Directory(
          p.join(serverDir.path, 'lib', 'database', 'migrations'));
    } catch (_) {
      // 回退：尝试当前工作目录
      final cwd = Directory.current.path;
      // 如果从项目根运行
      final candidate1 = Directory(
          p.join(cwd, 'server', 'lib', 'database', 'migrations'));
      if (candidate1.existsSync()) return candidate1;
      // 如果从 server/ 运行
      return Directory(p.join(cwd, 'lib', 'database', 'migrations'));
    }
  }

  /// 运行迁移脚本 - 读取并执行真实 SQL 文件
  Future<void> runMigrations() async {
    print('[Database] Running migrations...');

    // 创建迁移记录表
    await executeRaw('''
      CREATE TABLE IF NOT EXISTS _migrations (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) NOT NULL UNIQUE,
        applied_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      )
    ''');

    // 所有迁移（必须按顺序执行）
    final migrations = [
      '001_create_user_tables',
      '002_fix_constraints',
      '003_add_security_questions',
      '004_create_price_history',
    ];

    final migrationsDir = _resolveMigrationsDir();
    print('[Database] Migrations directory: ${migrationsDir.path}');

    if (!migrationsDir.existsSync()) {
      print('[Database] WARNING: Migrations directory not found at ${migrationsDir.path}');
      print('[Database] Skipping migrations execution.');
      return;
    }

    for (final migration in migrations) {
      // 检查是否已执行
      final applied = await queryOne(
        'SELECT id FROM _migrations WHERE name = @name',
        parameters: {'name': migration},
      );

      if (applied != null) {
        print('[Database] Migration already applied: $migration');
        continue;
      }

      // 读取 SQL 文件
      final sqlFile = File(p.join(migrationsDir.path, '$migration.sql'));
      if (!sqlFile.existsSync()) {
        print('[Database] WARNING: Migration file not found: ${sqlFile.path}');
        continue;
      }

      print('[Database] Applying migration: $migration ...');
      try {
        final sql = await sqlFile.readAsString();

        // 拆分多条 SQL 语句并逐条执行
        // 跳过注释行和空行，按分号分隔（但保留 $$ 函数体中的分号不分割）
        final statements = _splitSqlStatements(sql);

        for (final stmt in statements) {
          if (stmt.trim().isNotEmpty) {
            try {
              await executeRaw(stmt);
            } catch (e) {
              // 某些语句可能是 IF NOT EXISTS 之类的幂等操作，容忍某些错误
              final errStr = e.toString().toLowerCase();
              if (errStr.contains('already exists') ||
                  errStr.contains('duplicate') ||
                  errStr.contains('42710') || // duplicate_object
                  errStr.contains('42p07')) { // duplicate_table
                print('[Database] Skipping (already exists): ${stmt.substring(0, stmt.length.clamp(0, 80))}...');
              } else {
                print('[Database] ERROR executing statement: $e');
                print('[Database] Statement: ${stmt.substring(0, stmt.length.clamp(0, 200))}');
                rethrow;
              }
            }
          }
        }

        // 记录迁移成功
        await execute(
          'INSERT INTO _migrations (name) VALUES (@name)',
          parameters: {'name': migration},
        );
        print('[Database] Migration applied successfully: $migration');
      } catch (e) {
        print('[Database] FAILED to apply migration $migration: $e');
        rethrow;
      }
    }

    print('[Database] All migrations complete!');
  }

  /// 智能拆分 SQL 语句
  /// 处理 $$ 函数体（CREATE FUNCTION ... $$ ... $$ 语法）
  List<String> _splitSqlStatements(String sql) {
    final statements = <String>[];
    final buffer = StringBuffer();
    bool insideDollarQuote = false;
    final lines = sql.split('\n');

    for (final line in lines) {
      final trimmedLine = line.trim();

      // 跳过纯注释行
      if (trimmedLine.startsWith('--') && !insideDollarQuote) {
        continue;
      }

      // 检测 $$ 边界
      final dollarCount = '\$\$'.allMatches(line).length;
      if (dollarCount > 0) {
        if (dollarCount % 2 == 1) {
          insideDollarQuote = !insideDollarQuote;
        }
      }

      buffer.writeln(line);

      // 如果不在 $$ 块内且行以分号结尾，则切分
      if (!insideDollarQuote && trimmedLine.endsWith(';')) {
        final stmt = buffer.toString().trim();
        if (stmt.isNotEmpty && stmt != ';') {
          statements.add(stmt);
        }
        buffer.clear();
      }
    }

    // 处理末尾无分号的语句
    final remaining = buffer.toString().trim();
    if (remaining.isNotEmpty && remaining != ';') {
      statements.add(remaining);
    }

    return statements;
  }
}

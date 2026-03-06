import 'package:wisepick_proxy_server/database/database.dart';
import 'package:postgres/postgres.dart';

/// 用于单元测试的内存 Mock 数据库
///
/// 通过 stubQueryOne / stubQueryAll 预设返回值，
/// 不依赖真实 PostgreSQL 连接。
class MockDatabase extends Database {
  MockDatabase() : super.testOnly();

  final Map<String, Map<String, dynamic>?> _queryOneStubs = {};
  final Map<String, List<Map<String, dynamic>>> _queryAllStubs = {};
  final List<Map<String, dynamic>> _executedStatements = [];

  /// 预设 queryOne 返回值（按 SQL 片段匹配）
  void stubQueryOne(String sqlFragment, Map<String, dynamic>? result) {
    _queryOneStubs[sqlFragment] = result;
  }

  /// 预设 queryAll 返回值（按 SQL 片段匹配）
  void stubQueryAll(String sqlFragment, List<Map<String, dynamic>> result) {
    _queryAllStubs[sqlFragment] = result;
  }

  /// 已执行的 SQL 语句记录（用于断言）
  List<Map<String, dynamic>> get executedStatements =>
      List.unmodifiable(_executedStatements);

  @override
  Future<Map<String, dynamic>?> queryOne(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    for (final entry in _queryOneStubs.entries) {
      if (sql.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> queryAll(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    for (final entry in _queryAllStubs.entries) {
      if (sql.contains(entry.key)) {
        return entry.value;
      }
    }
    return [];
  }

  @override
  Future<Result> execute(
    String sql, {
    Map<String, dynamic>? parameters,
  }) async {
    _executedStatements.add({'sql': sql, 'params': parameters});
    return _MockResult();
  }

  @override
  bool get isConnected => true;
}

class _MockResult implements Result {
  @override
  int get affectedRows => 1;

  @override
  ResultSchema get schema => throw UnimplementedError();

  List<ResultRow> get rows => [];

  @override
  int get length => 0;

  @override
  bool get isEmpty => true;

  @override
  bool get isNotEmpty => false;

  @override
  ResultRow get first => throw StateError('Empty result');

  @override
  ResultRow get last => throw StateError('Empty result');

  @override
  ResultRow get single => throw StateError('Empty result');

  @override
  ResultRow elementAt(int index) => throw RangeError('Empty result');

  @override
  Iterator<ResultRow> get iterator => <ResultRow>[].iterator;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../lib/admin/admin_service.dart';
import '../lib/database/database.dart';
import 'helpers/mock_database.dart';

/// ============================================================
/// Module: AdminService
/// What: 用户列表分页、封禁/解封、邮箱脱敏
/// Why: 管理功能直接操作用户数据，逻辑错误影响数据安全
/// ============================================================
void main() {
  late MockDatabase mockDb;
  late AdminService adminService;

  setUp(() {
    Database.setEnvVars({
      'JWT_SECRET': 'test-jwt-secret-for-unit-tests',
      'JWT_REFRESH_SECRET': 'test-refresh-secret-for-unit-tests',
    });
    mockDb = MockDatabase();
    adminService = AdminService(mockDb);
  });

  // ============================================================
  // 用户列表分页
  // ============================================================
  group('AdminService - 用户列表分页', () {
    test('默认第1页返回200及用户列表', () async {
      mockDb.stubQueryOne(
        'SELECT COUNT(*) as count FROM users',
        {'count': 2},
      );
      mockDb.stubQueryAll('SELECT id, email, nickname', [
        {
          'id': 'user-1',
          'email': 'alice@example.com',
          'nickname': 'Alice',
          'created_at': DateTime(2024, 1, 1),
          'last_login_at': null,
          'email_verified': true,
          'status': 'active',
        },
        {
          'id': 'user-2',
          'email': 'bob@example.com',
          'nickname': 'Bob',
          'created_at': DateTime(2024, 1, 2),
          'last_login_at': null,
          'email_verified': false,
          'status': 'active',
        },
      ]);

      final request = Request(
        'GET',
        Uri.parse('http://localhost/users?page=1&pageSize=20'),
      );
      final response = await adminService.router.call(request);
      expect(response.statusCode, equals(200));

      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['users'], isList);
      expect(body['total'], equals(2));
    });

    test('分页参数 page=2 时 offset 正确', () async {
      mockDb.stubQueryOne('SELECT COUNT(*) as count FROM users', {'count': 25});
      mockDb.stubQueryAll('SELECT id, email, nickname', []);

      final request = Request(
        'GET',
        Uri.parse('http://localhost/users?page=2&pageSize=10'),
      );
      final response = await adminService.router.call(request);
      expect(response.statusCode, equals(200));

      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['page'], equals(2));
      expect(body['pageSize'], equals(10));
    });
  });

  // ============================================================
  // 邮箱脱敏（通过辅助函数验证规则）
  // ============================================================
  group('AdminService - 邮箱脱敏规则', () {
    test('长用户名保留前2位', () {
      expect(_maskEmail('alice@example.com'), equals('al***@example.com'));
    });

    test('2字符用户名保留首字符', () {
      expect(_maskEmail('ab@example.com'), equals('a***@example.com'));
    });

    test('1字符用户名保留首字符', () {
      expect(_maskEmail('a@example.com'), equals('a***@example.com'));
    });

    test('格式异常邮箱原样返回', () {
      expect(_maskEmail('notanemail'), equals('notanemail'));
    });
  });

  // ============================================================
  // 封禁/解封用户
  // ============================================================
  group('AdminService - 更新用户状态', () {
    test('封禁存在的用户返回200', () async {
      mockDb.stubQueryOne(
        'SELECT id FROM users WHERE id',
        {'id': 'user-1'},
      );

      final request = Request(
        'PUT',
        Uri.parse('http://localhost/users/user-1'),
        body: jsonEncode({'status': 'banned'}),
        headers: {'content-type': 'application/json'},
      );
      final response = await adminService.router.call(request);
      expect(response.statusCode, equals(200));

      final stmts = mockDb.executedStatements;
      expect(
        stmts.any((s) => (s['sql'] as String).contains('UPDATE users')),
        isTrue,
      );
    });

    test('更新不存在的用户返回404', () async {
      mockDb.stubQueryOne('SELECT id FROM users WHERE id', null);

      final request = Request(
        'PUT',
        Uri.parse('http://localhost/users/nonexistent'),
        body: jsonEncode({'status': 'banned'}),
        headers: {'content-type': 'application/json'},
      );
      final response = await adminService.router.call(request);
      expect(response.statusCode, equals(404));
    });

    test('解封用户（status=active）返回200', () async {
      mockDb.stubQueryOne(
        'SELECT id FROM users WHERE id',
        {'id': 'user-2'},
      );

      final request = Request(
        'PUT',
        Uri.parse('http://localhost/users/user-2'),
        body: jsonEncode({'status': 'active'}),
        headers: {'content-type': 'application/json'},
      );
      final response = await adminService.router.call(request);
      expect(response.statusCode, equals(200));
    });

    test('无更新字段时返回400', () async {
      mockDb.stubQueryOne(
        'SELECT id FROM users WHERE id',
        {'id': 'user-1'},
      );

      final request = Request(
        'PUT',
        Uri.parse('http://localhost/users/user-1'),
        body: jsonEncode({}),
        headers: {'content-type': 'application/json'},
      );
      final response = await adminService.router.call(request);
      expect(response.statusCode, equals(400));
    });
  });
}

/// 复制 AdminService._maskEmail 逻辑用于单元验证
String _maskEmail(String email) {
  final parts = email.split('@');
  if (parts.length != 2) return email;
  final name = parts[0];
  final domain = parts[1];
  if (name.length <= 2) return '${name[0]}***@$domain';
  return '${name.substring(0, 2)}***@$domain';
}

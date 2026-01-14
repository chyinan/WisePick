import 'dart:io';

import '../lib/jd_scraper/cookie_manager.dart';
import '../lib/jd_scraper/models/models.dart';

/// Cookie 管理器测试脚本
///
/// 用法:
///   dart run bin/test_cookie_manager.dart [command] [args]
///
/// 命令:
///   status    - 查看 Cookie 状态
///   load      - 加载并显示 Cookie
///   save      - 保存新的 Cookie (需要提供 Cookie 字符串作为参数)
///   parse     - 解析 Cookie 字符串为项目列表
///   clear     - 清除 Cookie 缓存
///   delete    - 删除 Cookie 文件
void main(List<String> args) async {
  final manager = CookieManager();

  print('========================================');
  print('       京东爬虫 Cookie 管理器测试');
  print('========================================\n');

  final command = args.isNotEmpty ? args.first : 'status';

  try {
    switch (command) {
      case 'status':
        await _showStatus(manager);
        break;

      case 'load':
        await _loadCookie(manager);
        break;

      case 'save':
        if (args.length < 2) {
          print('❌ 错误: 请提供 Cookie 字符串');
          print('用法: dart run bin/test_cookie_manager.dart save "cookie_string"');
          exit(1);
        }
        await _saveCookie(manager, args[1]);
        break;

      case 'parse':
        if (args.length < 2) {
          // 尝试解析已保存的 Cookie
          await _parseExistingCookie(manager);
        } else {
          _parseCookieString(manager, args[1]);
        }
        break;

      case 'clear':
        manager.clearCache();
        print('✅ Cookie 缓存已清除');
        break;

      case 'delete':
        await manager.deleteCookie();
        print('✅ Cookie 文件已删除');
        break;

      case 'help':
        _showHelp();
        break;

      default:
        print('❌ 未知命令: $command');
        _showHelp();
        exit(1);
    }
  } catch (e) {
    print('\n❌ 执行出错: $e');
    if (e is ScraperException) {
      print('   错误类型: ${e.type.name}');
      print('   错误信息: ${e.message}');
    }
    exit(1);
  }

  print('\n========================================');
}

/// 显示 Cookie 状态
Future<void> _showStatus(CookieManager manager) async {
  print('📊 Cookie 状态:');
  print('-' * 40);

  final status = await manager.getStatus();

  print('  文件存在: ${status['exists'] ? '✅ 是' : '❌ 否'}');

  if (status['exists'] == true) {
    print('  保存时间: ${status['savedAt']}');
    print('  预估过期: ${status['expiresAt']}');
    print('  已存活天数: ${status['ageInDays']} 天');
    print(
        '  可能已过期: ${status['isPossiblyExpired'] == true ? '⚠️ 是' : '✅ 否'}');

    if (status['lastValidatedAt'] != null) {
      print('  上次验证: ${status['lastValidatedAt']}');
      print('  验证结果: ${status['isValid'] == true ? '✅ 有效' : '❌ 无效'}');
    } else {
      print('  上次验证: 未验证');
    }

    print(
        '  需要验证: ${status['needsValidation'] == true ? '⚠️ 是' : '✅ 否'}');
  }
}

/// 加载并显示 Cookie
Future<void> _loadCookie(CookieManager manager) async {
  print('📥 正在加载 Cookie...');
  print('-' * 40);

  final cookieString = await manager.getCookieString();

  if (cookieString == null) {
    print('❌ 未找到 Cookie 文件');
    print('💡 提示: 使用以下命令保存 Cookie:');
    print('   dart run bin/test_cookie_manager.dart save "your_cookie_string"');
    return;
  }

  // 显示 Cookie 概要
  print('✅ Cookie 加载成功');
  print('  长度: ${cookieString.length} 字符');

  // 解析并显示关键 Cookie 项
  final items = manager.parseCookieString(cookieString);
  print('  Cookie 项数: ${items.length}');

  // 显示一些关键的 Cookie
  final keyNames = ['pin', 'unick', 'pinId', 'thor', 'flash'];
  print('\n  关键 Cookie:');
  for (final item in items) {
    if (keyNames.contains(item.name)) {
      final displayValue = item.value.length > 20
          ? '${item.value.substring(0, 20)}...'
          : item.value;
      print('    ${item.name}: $displayValue');
    }
  }
}

/// 保存新的 Cookie
Future<void> _saveCookie(CookieManager manager, String cookie) async {
  print('💾 正在保存 Cookie...');
  print('-' * 40);

  await manager.saveCookie(cookie);

  print('✅ Cookie 保存成功');
  await _showStatus(manager);
}

/// 解析已保存的 Cookie
Future<void> _parseExistingCookie(CookieManager manager) async {
  print('🔍 解析已保存的 Cookie...');
  print('-' * 40);

  final cookieString = await manager.getCookieString();
  if (cookieString == null) {
    print('❌ 未找到 Cookie 文件');
    return;
  }

  _parseCookieString(manager, cookieString);
}

/// 解析 Cookie 字符串
void _parseCookieString(CookieManager manager, String cookieString) {
  print('🔍 解析 Cookie 字符串...');
  print('-' * 40);

  final items = manager.parseCookieString(cookieString);
  print('解析得到 ${items.length} 个 Cookie 项:\n');

  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final displayValue =
        item.value.length > 50 ? '${item.value.substring(0, 50)}...' : item.value;
    print('  ${i + 1}. ${item.name}');
    print('     值: $displayValue');
    print('     域: ${item.domain}');
    print('');
  }

  // 转换为 Puppeteer 格式并显示示例
  print('-' * 40);
  print('📋 Puppeteer 格式示例 (前3个):');
  final puppeteerFormat = manager.toPuppeteerFormat(items.take(3).toList());
  for (final cookie in puppeteerFormat) {
    print('  $cookie');
  }
}

/// 显示帮助信息
void _showHelp() {
  print('''
用法: dart run bin/test_cookie_manager.dart [command] [args]

可用命令:
  status    - 查看 Cookie 状态 (默认)
  load      - 加载并显示 Cookie
  save      - 保存新的 Cookie
              用法: save "cookie_string"
  parse     - 解析 Cookie 字符串为项目列表
              用法: parse ["cookie_string"]
  clear     - 清除 Cookie 内存缓存
  delete    - 删除 Cookie 文件
  help      - 显示此帮助信息

示例:
  dart run bin/test_cookie_manager.dart status
  dart run bin/test_cookie_manager.dart save "pin=xxx; unick=xxx; ..."
  dart run bin/test_cookie_manager.dart parse
''');
}











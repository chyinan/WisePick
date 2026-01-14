import 'dart:io';

import 'package:puppeteer/puppeteer.dart';

import '../lib/jd_scraper/browser_pool.dart';

/// 浏览器池管理器测试脚本
///
/// 用法:
///   dart run bin/test_browser_pool.dart [command]
///
/// 命令:
///   status    - 查看浏览器池状态
///   launch    - 启动浏览器并测试
///   stealth   - 测试反检测功能
///   pool      - 测试浏览器池复用
///   jd        - 访问京东联盟测试
void main(List<String> args) async {
  print('========================================');
  print('       浏览器池管理器测试');
  print('========================================\n');

  final command = args.isNotEmpty ? args.first : 'status';

  // 使用开发配置（非无头模式，便于观察）
  final pool = BrowserPool(
    config: BrowserPoolConfig(
      maxBrowsers: 2,
      browserTimeout: const Duration(minutes: 5),
      headless: false, // 非无头模式，便于观察
      slowMo: const Duration(milliseconds: 100),
    ),
  );

  try {
    switch (command) {
      case 'status':
        _showStatus(pool);
        break;

      case 'launch':
        await _testLaunch(pool);
        break;

      case 'stealth':
        await _testStealth(pool);
        break;

      case 'pool':
        await _testPoolReuse(pool);
        break;

      case 'jd':
        await _testJdAccess(pool);
        break;

      case 'help':
        _showHelp();
        break;

      default:
        print('❌ 未知命令: $command');
        _showHelp();
        exit(1);
    }
  } catch (e, stack) {
    print('\n❌ 执行出错: $e');
    print('堆栈: $stack');
    exit(1);
  } finally {
    await pool.closeAll();
  }

  print('\n========================================');
}

/// 显示浏览器池状态
void _showStatus(BrowserPool pool) {
  print('📊 浏览器池状态:');
  print('-' * 40);

  final status = pool.getStatus();

  print('  最大实例数: ${status['maxBrowsers']}');
  print('  当前实例数: ${status['total']}');
  print('  可用实例数: ${status['available']}');
  print('  使用中: ${status['inUse']}');
  print('  等待队列: ${status['waiting']}');
  print('  已关闭: ${status['closed'] ? '是' : '否'}');

  if ((status['instances'] as List).isNotEmpty) {
    print('\n  实例详情:');
    for (var i = 0; i < (status['instances'] as List).length; i++) {
      final inst = (status['instances'] as List)[i];
      print('    实例 ${i + 1}: 使用${inst['useCount']}次, '
          '存活${inst['age']}分钟, '
          '${inst['inUse'] ? '使用中' : '空闲'}');
    }
  }
}

/// 测试浏览器启动
Future<void> _testLaunch(BrowserPool pool) async {
  print('🚀 测试浏览器启动...');
  print('-' * 40);

  print('正在获取浏览器实例...');
  final pageWithInstance = await pool.acquirePage();

  print('✅ 浏览器启动成功');
  print('正在访问测试页面...');

  await pageWithInstance.page.goto(
    'https://www.example.com',
    wait: Until.networkIdle,
  );

  print('✅ 页面加载成功');

  // 获取页面标题
  final title = await pageWithInstance.page.title;
  print('页面标题: $title');

  // 截图保存
  final screenshot = await pageWithInstance.page.screenshot();
  await File('data/test_screenshot.png').writeAsBytes(screenshot);
  print('截图已保存到: data/test_screenshot.png');

  print('\n等待 3 秒后关闭...');
  await Future.delayed(const Duration(seconds: 3));

  await pageWithInstance.close();
  print('✅ 浏览器已关闭');

  _showStatus(pool);
}

/// 测试反检测功能
Future<void> _testStealth(BrowserPool pool) async {
  print('🕵️ 测试反检测功能...');
  print('-' * 40);

  final pageWithInstance = await pool.acquirePage();
  final page = pageWithInstance.page;

  print('正在访问 Bot 检测页面...');

  // 访问一个检测机器人的网站
  await page.goto(
    'https://bot.sannysoft.com/',
    wait: Until.networkIdle,
  );

  print('✅ 页面加载成功');

  // 检查 webdriver 属性
  final webdriverResult = await page.evaluate<dynamic>('''
    () => {
      return {
        webdriver: navigator.webdriver,
        chrome: typeof window.chrome !== 'undefined',
        plugins: navigator.plugins.length,
        languages: navigator.languages
      };
    }
  ''');

  print('\n检测结果:');
  print('  navigator.webdriver: ${webdriverResult['webdriver']}');
  print('  window.chrome: ${webdriverResult['chrome']}');
  print('  plugins 数量: ${webdriverResult['plugins']}');
  print('  languages: ${webdriverResult['languages']}');

  // 截图保存检测结果
  final screenshot = await page.screenshot(fullPage: true);
  await File('data/stealth_test.png').writeAsBytes(screenshot);
  print('\n检测结果截图已保存到: data/stealth_test.png');

  print('\n等待 5 秒后关闭（可查看浏览器中的检测结果）...');
  await Future.delayed(const Duration(seconds: 5));

  await pageWithInstance.close();
  print('✅ 测试完成');
}

/// 测试浏览器池复用
Future<void> _testPoolReuse(BrowserPool pool) async {
  print('♻️ 测试浏览器池复用...');
  print('-' * 40);

  // 第一次获取浏览器
  print('\n第一次获取浏览器实例...');
  final page1 = await pool.acquirePage();
  _showStatus(pool);

  // 第二次获取浏览器（应该创建新实例）
  print('\n第二次获取浏览器实例...');
  final page2 = await pool.acquirePage();
  _showStatus(pool);

  // 释放第一个
  print('\n释放第一个浏览器实例...');
  await page1.close();
  _showStatus(pool);

  // 第三次获取（应该复用第一个）
  print('\n第三次获取浏览器实例（应该复用）...');
  final page3 = await pool.acquirePage();
  _showStatus(pool);

  // 清理
  await page2.close();
  await page3.close();

  print('\n✅ 浏览器池复用测试完成');
  _showStatus(pool);
}

/// 测试访问京东联盟
Future<void> _testJdAccess(BrowserPool pool) async {
  print('🛒 测试访问京东联盟...');
  print('-' * 40);

  final pageWithInstance = await pool.acquirePage();
  final page = pageWithInstance.page;

  print('正在访问京东联盟首页...');

  try {
    await page.goto(
      'https://union.jd.com/',
      wait: Until.networkIdle,
      timeout: const Duration(seconds: 30),
    );

    print('✅ 页面加载成功');

    // 获取当前 URL
    final url = page.url ?? '';
    print('当前 URL: $url');

    // 检查是否跳转到登录页
    if (url.contains('passport.jd.com') || url.contains('login')) {
      print('⚠️ 已跳转到登录页，需要设置 Cookie');
    } else {
      print('✅ 访问正常，未被拦截');
    }

    // 获取页面内容
    final bodyText = await page.evaluate<String>(
      '() => document.body.innerText.substring(0, 200)',
    );
    print('\n页面内容预览:');
    print(bodyText);

    // 截图
    final screenshot = await page.screenshot(fullPage: true);
    await File('data/jd_test.png').writeAsBytes(screenshot);
    print('\n截图已保存到: data/jd_test.png');

    print('\n等待 5 秒后关闭...');
    await Future.delayed(const Duration(seconds: 5));
  } catch (e) {
    print('❌ 访问失败: $e');
  }

  await pageWithInstance.close();
  print('✅ 测试完成');
}

/// 显示帮助信息
void _showHelp() {
  print('''
用法: dart run bin/test_browser_pool.dart [command]

可用命令:
  status    - 查看浏览器池状态 (默认)
  launch    - 启动浏览器并测试基本功能
  stealth   - 测试反检测功能
  pool      - 测试浏览器池复用
  jd        - 访问京东联盟测试
  help      - 显示此帮助信息

示例:
  dart run bin/test_browser_pool.dart status
  dart run bin/test_browser_pool.dart launch
  dart run bin/test_browser_pool.dart stealth
  dart run bin/test_browser_pool.dart jd
''');
}


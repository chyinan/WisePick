import 'dart:io';

import 'package:puppeteer/puppeteer.dart';

import '../lib/jd_scraper/browser_pool.dart';
import '../lib/jd_scraper/human_behavior_simulator.dart';

/// 人类行为模拟器测试脚本
///
/// 用法:
///   dart run bin/test_human_behavior.dart [command]
///
/// 命令:
///   mouse     - 测试鼠标移动
///   type      - 测试人类输入
///   scroll    - 测试滚动行为
///   search    - 测试搜索操作
///   full      - 完整测试（访问京东联盟）
void main(List<String> args) async {
  print('========================================');
  print('       人类行为模拟器测试');
  print('========================================\n');

  final command = args.isNotEmpty ? args.first : 'mouse';

  // 创建浏览器池（非无头模式，便于观察）
  final pool = BrowserPool(
    config: BrowserPoolConfig(
      maxBrowsers: 1,
      headless: false,
      slowMo: const Duration(milliseconds: 50),
    ),
  );

  // 创建行为模拟器（启用详细日志）
  final behavior = HumanBehaviorSimulator(
    config: const BehaviorConfig(
      minWaitMs: 300,
      maxWaitMs: 800,
      minTypeDelayMs: 50,
      maxTypeDelayMs: 150,
      verbose: true,
    ),
  );

  try {
    switch (command) {
      case 'mouse':
        await _testMouseMove(pool, behavior);
        break;

      case 'type':
        await _testTyping(pool, behavior);
        break;

      case 'scroll':
        await _testScroll(pool, behavior);
        break;

      case 'search':
        await _testSearch(pool, behavior);
        break;

      case 'full':
        await _testFullBehavior(pool, behavior);
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

/// 测试鼠标移动
Future<void> _testMouseMove(
    BrowserPool pool, HumanBehaviorSimulator behavior) async {
  print('🖱️ 测试鼠标移动（贝塞尔曲线）...');
  print('-' * 40);

  final pageWithInstance = await pool.acquirePage();
  final page = pageWithInstance.page;

  // 访问测试页面
  await page.goto('https://www.example.com', wait: Until.networkIdle);
  print('页面加载完成\n');

  // 测试多次鼠标移动
  final points = [
    const Point2D(100, 100),
    const Point2D(500, 300),
    const Point2D(200, 400),
    const Point2D(600, 200),
    const Point2D(300, 350),
  ];

  for (var i = 0; i < points.length; i++) {
    print('\n移动 ${i + 1}/${points.length}:');
    await behavior.simulateMouseMove(page, points[i]);
    await Future.delayed(const Duration(milliseconds: 500));
  }

  print('\n✅ 鼠标移动测试完成');
  print('等待 3 秒后关闭...');
  await Future.delayed(const Duration(seconds: 3));

  await pageWithInstance.close();
}

/// 测试人类输入
Future<void> _testTyping(
    BrowserPool pool, HumanBehaviorSimulator behavior) async {
  print('⌨️ 测试人类输入...');
  print('-' * 40);

  final pageWithInstance = await pool.acquirePage();
  final page = pageWithInstance.page;

  // 访问百度（有搜索框）
  await page.goto('https://www.baidu.com', wait: Until.networkIdle);
  print('页面加载完成\n');

  // 测试输入
  final testText = 'Hello World 测试输入';
  print('准备输入: "$testText"');

  await behavior.typeLikeHuman(page, testText, selector: '#kw');

  print('\n✅ 输入测试完成');

  // 截图
  final screenshot = await page.screenshot();
  await File('data/type_test.png').writeAsBytes(screenshot);
  print('截图已保存到: data/type_test.png');

  print('等待 3 秒后关闭...');
  await Future.delayed(const Duration(seconds: 3));

  await pageWithInstance.close();
}

/// 测试滚动行为
Future<void> _testScroll(
    BrowserPool pool, HumanBehaviorSimulator behavior) async {
  print('📜 测试滚动行为...');
  print('-' * 40);

  final pageWithInstance = await pool.acquirePage();
  final page = pageWithInstance.page;

  // 访问一个长页面
  await page.goto('https://www.baidu.com', wait: Until.networkIdle);
  print('页面加载完成\n');

  // 测试滚动
  print('开始向下滚动...');
  await behavior.simulateScroll(page, scrollDown: true);

  await Future.delayed(const Duration(seconds: 1));

  print('\n开始向上滚动...');
  await behavior.simulateScroll(page, scrollDown: false);

  print('\n✅ 滚动测试完成');
  print('等待 3 秒后关闭...');
  await Future.delayed(const Duration(seconds: 3));

  await pageWithInstance.close();
}

/// 测试搜索操作
Future<void> _testSearch(
    BrowserPool pool, HumanBehaviorSimulator behavior) async {
  print('🔍 测试搜索操作...');
  print('-' * 40);

  final pageWithInstance = await pool.acquirePage();
  final page = pageWithInstance.page;

  // 访问百度
  await page.goto('https://www.baidu.com', wait: Until.networkIdle);
  print('页面加载完成\n');

  // 执行搜索
  await behavior.performSearch(
    page,
    inputSelector: '#kw',
    buttonSelector: '#su',
    keyword: 'Dart 编程语言',
  );

  // 等待搜索结果
  print('\n等待搜索结果...');
  await Future.delayed(const Duration(seconds: 3));

  // 截图
  final screenshot = await page.screenshot();
  await File('data/search_test.png').writeAsBytes(screenshot);
  print('截图已保存到: data/search_test.png');

  print('\n✅ 搜索测试完成');
  print('等待 3 秒后关闭...');
  await Future.delayed(const Duration(seconds: 3));

  await pageWithInstance.close();
}

/// 完整测试（访问京东联盟）
Future<void> _testFullBehavior(
    BrowserPool pool, HumanBehaviorSimulator behavior) async {
  print('🛒 完整测试（访问京东联盟）...');
  print('-' * 40);

  final pageWithInstance = await pool.acquirePage();
  final page = pageWithInstance.page;

  try {
    // 1. 访问京东联盟
    print('\n1. 访问京东联盟首页...');
    await page.goto(
      'https://union.jd.com/',
      wait: Until.networkIdle,
      timeout: const Duration(seconds: 30),
    );
    print('   页面加载完成');

    // 2. 随机浏览
    print('\n2. 模拟用户浏览页面...');
    await behavior.randomBrowse(page, duration: 3000);

    // 3. 检查页面状态
    print('\n3. 检查页面状态...');
    final url = page.url ?? '';
    if (url.contains('passport') || url.contains('login')) {
      print('   ⚠️ 需要登录，跳转到了登录页');
    } else {
      print('   ✅ 页面正常访问');
    }

    // 4. 截图
    final screenshot = await page.screenshot(fullPage: true);
    await File('data/full_test.png').writeAsBytes(screenshot);
    print('\n截图已保存到: data/full_test.png');

    print('\n✅ 完整测试完成');
  } catch (e) {
    print('\n❌ 测试失败: $e');
  }

  print('等待 5 秒后关闭...');
  await Future.delayed(const Duration(seconds: 5));

  await pageWithInstance.close();
}

/// 显示帮助信息
void _showHelp() {
  print('''
用法: dart run bin/test_human_behavior.dart [command]

可用命令:
  mouse     - 测试鼠标移动（贝塞尔曲线）
  type      - 测试人类输入
  scroll    - 测试滚动行为
  search    - 测试搜索操作
  full      - 完整测试（访问京东联盟）
  help      - 显示此帮助信息

示例:
  dart run bin/test_human_behavior.dart mouse
  dart run bin/test_human_behavior.dart type
  dart run bin/test_human_behavior.dart full
''');
}











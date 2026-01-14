import 'dart:io';

import '../lib/jd_scraper/jd_scraper.dart';

/// 京东爬虫服务集成测试脚本
///
/// 用法:
///   dart run bin/test_jd_scraper.dart [command] [args]
///
/// 命令:
///   status            - 查看服务状态
///   cookie <string>   - 设置 Cookie
///   get <skuId>       - 获取单个商品信息
///   batch <skuIds>    - 批量获取商品信息（逗号分隔）
///   demo              - 演示完整流程
void main(List<String> args) async {
  print('========================================');
  print('       京东爬虫服务集成测试');
  print('========================================\n');

  final command = args.isNotEmpty ? args.first : 'status';

  // 创建服务实例（开发配置）
  final service = JdScraperService(
    config: JdScraperConfig.development(),
  );

  try {
    switch (command) {
      case 'status':
        await _showStatus(service);
        break;

      case 'cookie':
        if (args.length < 2) {
          print('❌ 错误: 请提供 Cookie 字符串');
          print('用法: dart run bin/test_jd_scraper.dart cookie "your_cookie"');
          exit(1);
        }
        await _setCookie(service, args[1]);
        break;

      case 'get':
        if (args.length < 2) {
          print('❌ 错误: 请提供商品 SKU ID');
          print('用法: dart run bin/test_jd_scraper.dart get 10183999034312');
          exit(1);
        }
        await _getProduct(service, args[1]);
        break;

      case 'batch':
        if (args.length < 2) {
          print('❌ 错误: 请提供商品 SKU ID 列表（逗号分隔）');
          print('用法: dart run bin/test_jd_scraper.dart batch id1,id2,id3');
          exit(1);
        }
        final skuIds = args[1].split(',').map((s) => s.trim()).toList();
        await _getBatchProducts(service, skuIds);
        break;

      case 'demo':
        await _runDemo(service);
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
    if (e is ScraperException) {
      print('   错误类型: ${e.type.name}');
      print('   错误信息: ${e.message}');
    }
    print('\n堆栈: $stack');
    exit(1);
  } finally {
    await service.close();
  }

  print('\n========================================');
}

/// 显示服务状态
Future<void> _showStatus(JdScraperService service) async {
  print('📊 服务状态:');
  print('-' * 40);

  await service.initialize();
  final status = await service.getStatus();

  print('\n📌 服务信息:');
  print('  已初始化: ${status['initialized'] ? '✅ 是' : '❌ 否'}');
  print('  已关闭: ${status['closed'] ? '是' : '否'}');

  print('\n🍪 Cookie 状态:');
  final cookie = status['cookie'] as Map<String, dynamic>;
  print('  文件存在: ${cookie['exists'] ? '✅ 是' : '❌ 否'}');
  if (cookie['exists'] == true) {
    print('  保存时间: ${cookie['savedAt']}');
    print('  已存活天数: ${cookie['ageInDays']} 天');
    print('  可能已过期: ${cookie['isPossiblyExpired'] == true ? '⚠️ 是' : '✅ 否'}');
    print('  上次验证: ${cookie['lastValidatedAt'] ?? '未验证'}');
  }

  print('\n🌐 浏览器池:');
  final pool = status['browserPool'] as Map<String, dynamic>;
  print('  最大实例: ${pool['maxBrowsers']}');
  print('  当前实例: ${pool['total']}');
  print('  可用实例: ${pool['available']}');
  print('  使用中: ${pool['inUse']}');

  print('\n💾 缓存:');
  final cache = status['cache'] as Map<String, dynamic>;
  print('  启用: ${cache['enabled'] ? '是' : '否'}');
  print('  条目数: ${cache['size']}');
  print('  最大条目: ${cache['maxSize']}');
  print('  命中率: ${cache['hitRate']}%');
  print('  命中: ${cache['hits']} / 未命中: ${cache['misses']}');
  print('  淘汰: ${cache['evictions']}');
  
  print('\n⚠️ 错误统计:');
  final errors = status['errors'] as Map<String, dynamic>;
  print('  总错误数: ${errors['total']}');
  print('  最近24小时: ${errors['last24h']}');
  print('  最近1小时: ${errors['lastHour']}');
  if ((errors['byType'] as Map).isNotEmpty) {
    print('  按类型:');
    (errors['byType'] as Map).forEach((type, count) {
      print('    $type: $count');
    });
  }
  
  print('\n📈 性能统计:');
  final perf = status['performance'] as Map<String, dynamic>;
  print('  总请求数: ${perf['totalRequests']}');
  print('  总错误数: ${perf['totalErrors']}');
  
  print('\n🔄 请求去重:');
  final dedup = status['deduplicator'] as Map<String, dynamic>;
  print('  待处理请求: ${dedup['pendingCount']}');
  
  print('\n⚡ 并发控制:');
  final conc = status['concurrency'] as Map<String, dynamic>;
  print('  最大并发: ${conc['maxConcurrency']}');
  print('  当前并发: ${conc['currentCount']}');
  print('  队列长度: ${conc['queueLength']}');
}

/// 设置 Cookie
Future<void> _setCookie(JdScraperService service, String cookie) async {
  print('💾 设置 Cookie...');
  print('-' * 40);

  await service.cookieManager.saveCookie(cookie);

  print('✅ Cookie 保存成功');
  print('\n现在可以使用以下命令测试:');
  print('  dart run bin/test_jd_scraper.dart get <skuId>');
}

/// 获取单个商品信息
Future<void> _getProduct(JdScraperService service, String skuId) async {
  print('🔍 获取商品信息: $skuId');
  print('-' * 40);

  await service.initialize();

  final stopwatch = Stopwatch()..start();
  final info = await service.getProductInfo(skuId);
  stopwatch.stop();

  print('\n✅ 获取成功 (耗时: ${stopwatch.elapsedMilliseconds}ms)');
  print('-' * 40);
  _printProductInfo(info);
}

/// 批量获取商品信息
Future<void> _getBatchProducts(JdScraperService service, List<String> skuIds) async {
  print('🔍 批量获取商品信息: ${skuIds.length} 个');
  print('-' * 40);

  await service.initialize();

  final stopwatch = Stopwatch()..start();
  final results = await service.getBatchProductInfo(skuIds);
  stopwatch.stop();

  print('\n✅ 获取完成 (${results.length}/${skuIds.length} 成功, 耗时: ${stopwatch.elapsedMilliseconds}ms)');
  print('-' * 40);

  for (var i = 0; i < results.length; i++) {
    print('\n商品 ${i + 1}:');
    _printProductInfo(results[i]);
  }
}

/// 运行演示
Future<void> _runDemo(JdScraperService service) async {
  print('🎬 运行演示流程...');
  print('-' * 40);

  // 1. 检查 Cookie
  print('\n1️⃣ 检查 Cookie 状态...');
  final cookieStatus = await service.cookieManager.getStatus();
  if (cookieStatus['exists'] != true) {
    print('   ❌ 未找到 Cookie');
    print('\n请先设置 Cookie:');
    print('   dart run bin/test_jd_scraper.dart cookie "your_jd_cookie"');
    print('\n提示: Cookie 可以从京东联盟网站获取');
    return;
  }
  print('   ✅ Cookie 已配置');

  // 2. 初始化服务
  print('\n2️⃣ 初始化服务...');
  await service.initialize();
  print('   ✅ 服务已初始化');

  // 3. 提示用户输入 SKU
  print('\n3️⃣ 准备获取商品信息');
  print('   请提供一个京东商品 SKU ID 进行测试:');
  print('   dart run bin/test_jd_scraper.dart get <skuId>');
  print('\n   示例 SKU: 10183999034312');

  // 4. 显示状态
  print('\n4️⃣ 当前服务状态:');
  await _showStatus(service);
}

/// 打印商品信息
void _printProductInfo(JdProductInfo info) {
  print('  SKU ID: ${info.skuId}');
  print('  标题: ${info.title}');
  print('  价格: ¥${info.price}');
  if (info.originalPrice != null) {
    print('  原价: ¥${info.originalPrice}');
  }
  if (info.commission != null) {
    print('  佣金: ¥${info.commission}');
  }
  if (info.commissionRate != null) {
    print('  佣金率: ${(info.commissionRate! * 100).toStringAsFixed(2)}%');
  }
  if (info.promotionLink != null) {
    print('  推广链接: ${info.promotionLink}');
  }
  if (info.shortLink != null) {
    print('  短链接: ${info.shortLink}');
  }
  print('  来自缓存: ${info.cached ? '是' : '否'}');
  print('  获取时间: ${info.fetchTime}');
}

/// 显示帮助信息
void _showHelp() {
  print('''
用法: dart run bin/test_jd_scraper.dart [command] [args]

可用命令:
  status            - 查看服务状态 (默认)
  cookie <string>   - 设置京东联盟 Cookie
  get <skuId>       - 获取单个商品信息
  batch <skuIds>    - 批量获取商品信息（逗号分隔）
  demo              - 运行演示流程
  help              - 显示此帮助信息

示例:
  # 查看状态
  dart run bin/test_jd_scraper.dart status
  
  # 设置 Cookie（从京东联盟复制）
  dart run bin/test_jd_scraper.dart cookie "pin=xxx; unick=xxx; ..."
  
  # 获取单个商品
  dart run bin/test_jd_scraper.dart get 10183999034312
  
  # 批量获取
  dart run bin/test_jd_scraper.dart batch 10183999034312,10089387665015

Cookie 获取方法:
  1. 登录 https://union.jd.com/
  2. 打开浏览器开发者工具 (F12)
  3. 切换到 Network 标签
  4. 刷新页面
  5. 点击任意请求，在 Headers 中找到 Cookie
  6. 复制完整的 Cookie 字符串
''');
}


/// 京东联盟高级网页爬虫库
///
/// 提供京东联盟商品信息爬取功能，包括：
/// - Cookie 管理
/// - 浏览器自动化
/// - 人类行为模拟
/// - 错误处理和恢复
/// - 性能监控
/// - 高级缓存和请求去重
/// - HTTP API 路由集成
///
/// 使用示例:
/// ```dart
/// import 'package:wisepick_proxy_server/jd_scraper/jd_scraper.dart';
///
/// // 使用单例服务
/// final service = JdScraperService.instance;
/// await service.initialize();
///
/// // 获取商品信息
/// final info = await service.getProductInfo('10183999034312');
/// print('价格: ${info.price}');
/// print('推广链接: ${info.promotionLink}');
///
/// // 关闭服务
/// await service.close();
/// ```
///
/// 集成到 Shelf 服务器:
/// ```dart
/// import 'package:shelf/shelf.dart';
/// import 'package:shelf_router/shelf_router.dart';
/// import 'package:wisepick_proxy_server/jd_scraper/jd_scraper.dart';
///
/// final router = Router();
/// router.mount('/jd', createJdScraperRouter());
/// ```
library jd_scraper;

// 导出模型
export 'models/models.dart';

// 导出核心组件
export 'cookie_manager.dart';
export 'browser_pool.dart';
export 'human_behavior_simulator.dart';
export 'error_handler.dart';
export 'cache_manager.dart';
export 'jd_scraper_service.dart';

// 导出路由集成
export 'jd_scraper_routes.dart';

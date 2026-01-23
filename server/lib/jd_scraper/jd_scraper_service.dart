import 'dart:async';

import 'package:puppeteer/puppeteer.dart';

import 'browser_pool.dart';
import 'cache_manager.dart';
import 'cookie_manager.dart';
import 'error_handler.dart';
import 'human_behavior_simulator.dart';
import 'models/models.dart';

/// 京东爬虫服务配置
class JdScraperConfig {
  /// 浏览器池配置
  final BrowserPoolConfig browserConfig;

  /// 行为模拟配置
  final BehaviorConfig behaviorConfig;

  /// 请求超时时间
  final Duration requestTimeout;

  /// 页面加载超时时间
  final Duration pageLoadTimeout;

  /// 最大重试次数
  final int maxRetries;

  /// 重试间隔
  final Duration retryDelay;

  /// 是否启用缓存
  final bool enableCache;

  /// 缓存有效期
  final Duration cacheDuration;

  const JdScraperConfig({
    this.browserConfig = const BrowserPoolConfig(),
    this.behaviorConfig = const BehaviorConfig(),
    this.requestTimeout = const Duration(seconds: 30),
    this.pageLoadTimeout = const Duration(seconds: 30),
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 2),
    this.enableCache = true,
    this.cacheDuration = const Duration(minutes: 10),
  });

  /// 开发环境配置
  factory JdScraperConfig.development() {
    return JdScraperConfig(
      browserConfig: BrowserPoolConfig.development(),
      behaviorConfig: const BehaviorConfig(verbose: true),
      maxRetries: 2,
    );
  }

  /// 生产环境配置
  factory JdScraperConfig.production() {
    return JdScraperConfig(
      browserConfig: BrowserPoolConfig.production(),
      behaviorConfig: const BehaviorConfig(),
      maxRetries: 3,
    );
  }
}

/// 京东联盟爬虫服务
///
/// 整合 Cookie 管理、浏览器池、行为模拟等组件，
/// 提供完整的京东商品信息爬取功能
class JdScraperService {
  /// 单例实例
  static JdScraperService? _instance;

  /// 获取单例实例
  static JdScraperService get instance {
    _instance ??= JdScraperService();
    return _instance!;
  }

  /// 配置
  final JdScraperConfig config;

  /// Cookie 管理器
  final CookieManager cookieManager;

  /// 浏览器池
  late final BrowserPool browserPool;

  /// 行为模拟器
  late final HumanBehaviorSimulator behaviorSimulator;

  /// 错误处理器
  late final ErrorHandler errorHandler;

  /// 性能监控
  late final PerformanceMonitor performanceMonitor;

  /// 高级缓存管理器
  late final ProductCacheManager cacheManager;

  /// 请求去重器
  late final RequestDeduplicator<JdProductInfo> deduplicator;

  /// 并发控制器
  late final ConcurrencyController concurrencyController;

  /// 是否已初始化
  bool _initialized = false;

  /// 是否已关闭
  bool _closed = false;

  JdScraperService({
    JdScraperConfig? config,
    CookieManager? cookieManager,
    ErrorHandler? errorHandler,
  })  : config = config ?? const JdScraperConfig(),
        cookieManager = cookieManager ?? CookieManager() {
    browserPool = BrowserPool(config: this.config.browserConfig);
    behaviorSimulator = HumanBehaviorSimulator(config: this.config.behaviorConfig);
    performanceMonitor = PerformanceMonitor();
    
    // 初始化高级缓存管理器
    cacheManager = ProductCacheManager(
      config: CacheConfig(
        defaultTtl: this.config.cacheDuration,
        maxEntries: 500,
        enablePersistence: false,
      ),
    );
    
    // 初始化请求去重器
    deduplicator = RequestDeduplicator<JdProductInfo>();
    
    // 初始化并发控制器
    concurrencyController = ConcurrencyController(maxConcurrency: 3);
    
    // 初始化错误处理器，设置 Cookie 过期回调
    this.errorHandler = errorHandler ?? ErrorHandler(
      onCookieExpired: _handleCookieExpired,
      onAntiBotDetected: _handleAntiBotDetected,
    );
  }
  
  /// Cookie 过期处理
  Future<void> _handleCookieExpired() async {
    _log('⚠️ Cookie 已过期，请更新 Cookie');
    await cookieManager.updateValidationStatus(false);
  }
  
  /// 反爬虫检测处理
  Future<void> _handleAntiBotDetected() async {
    _log('⚠️ 检测到反爬虫系统，请稍后重试');
  }

  /// 初始化服务
  Future<void> initialize() async {
    if (_initialized) return;

    _log('初始化京东爬虫服务...');

    // 加载 Cookie
    final cookie = await cookieManager.loadCookieWithFallback();
    if (cookie == null) {
      _log('警告: 未找到有效的 Cookie，部分功能可能受限');
    }

    _initialized = true;
    _log('京东爬虫服务初始化完成');
  }

  /// 获取单个商品信息
  ///
  /// [skuId] 商品 SKU ID
  /// [forceRefresh] 是否强制刷新（忽略缓存）
  Future<JdProductInfo> getProductInfo(
    String skuId, {
    bool forceRefresh = false,
  }) async {
    _ensureNotClosed();
    await _ensureInitialized();

    // 检查高级缓存
    if (!forceRefresh && config.enableCache) {
      final cached = cacheManager.get(skuId);
      if (cached != null) {
        _log('从缓存获取商品信息: $skuId');
        return cached.markAsCached();
      }
    }

    // 使用请求去重器，避免重复请求
    return deduplicator.execute(skuId, () async {
      return _fetchProductInfoWithRetry(skuId);
    });
  }

  /// 带重试的商品信息获取
  Future<JdProductInfo> _fetchProductInfoWithRetry(String skuId) async {
    final stopwatch = Stopwatch()..start();
    ScraperException? lastError;
    
    for (int attempt = 1; attempt <= config.maxRetries; attempt++) {
      try {
        _log('获取商品信息 (尝试 $attempt/${config.maxRetries}): $skuId');
        
        // 使用并发控制器
        final info = await concurrencyController.execute(() => _fetchProductInfo(skuId));

        // 记录性能
        stopwatch.stop();
        performanceMonitor.recordRequest('getProductInfo', stopwatch.elapsed);

        // 缓存结果
        if (config.enableCache) {
          cacheManager.set(skuId, info);
        }

        return info;
      } on ScraperException catch (e) {
        lastError = e;
        _log('获取失败: ${e.message}');
        
        // 记录错误
        await errorHandler.handleError(e, skuId: skuId);
        performanceMonitor.recordError('getProductInfo');

        // Cookie 过期不重试
        if (e.type == ScraperErrorType.cookieExpired) {
          rethrow;
        }

        // 等待后重试
        if (attempt < config.maxRetries) {
          await Future.delayed(config.retryDelay);
        }
      } catch (e, stack) {
        // 根据异常类型创建适当的 ScraperException
        final errorStr = e.toString().toLowerCase();
        
        if (errorStr.contains('timeout')) {
          // 超时异常 - 可能是因为跳转到登录页导致页面加载缓慢
          lastError = ScraperException.timeout('请求超时: $e');
          _log('获取失败 (超时): $e');
        } else {
          lastError = ScraperException.unknown(e, stack);
          _log('获取失败: $e');
        }
        
        // 记录错误
        await errorHandler.handleError(lastError, skuId: skuId);
        performanceMonitor.recordError('getProductInfo');

        if (attempt < config.maxRetries) {
          await Future.delayed(config.retryDelay);
        }
      }
    }

    throw lastError ?? ScraperException.unknown('未知错误');
  }

  /// 批量获取商品信息
  ///
  /// [skuIds] 商品 SKU ID 列表
  /// [maxConcurrency] 最大并发数
  Future<List<JdProductInfo>> getBatchProductInfo(
    List<String> skuIds, {
    int maxConcurrency = 2,
  }) async {
    _ensureNotClosed();
    await _ensureInitialized();

    final results = <JdProductInfo>[];
    final errors = <String, dynamic>{};

    // 使用信号量控制并发
    final semaphore = _Semaphore(maxConcurrency);

    await Future.wait(
      skuIds.map((skuId) async {
        await semaphore.acquire();
        try {
          final info = await getProductInfo(skuId);
          results.add(info);
        } catch (e) {
          errors[skuId] = e;
          _log('批量获取失败 [$skuId]: $e');
        } finally {
          semaphore.release();
        }
      }),
    );

    _log('批量获取完成: ${results.length}/${skuIds.length} 成功');
    return results;
  }

  /// 获取商品信息的核心实现（京东联盟）
  Future<JdProductInfo> _fetchProductInfo(String skuId) async {
    final pageWithInstance = await browserPool.acquirePage();
    final page = pageWithInstance.page;

    try {
      // 1. 设置 Cookie
      await _setupCookies(page);

      // 2. 访问京东联盟推广页面
      _log('[京东联盟] 访问推广页面...');
      try {
        await page.goto(
          'https://union.jd.com/proManager/custompromotion',
          wait: Until.networkIdle,
          timeout: config.pageLoadTimeout,
        );
      } catch (e) {
        // 页面导航可能超时，但可能已经跳转到了登录页
        // 检查当前URL是否是登录页
        final currentUrl = page.url ?? '';
        _log('[京东联盟] 页面导航异常，当前URL: $currentUrl');
        
        if (await _isLoginRequired(page)) {
          _log('[京东联盟] ⚠️ 页面导航时检测到跳转至登录页');
          await cookieManager.updateValidationStatus(false);
          throw ScraperException.cookieExpired('Cookie 已过期，需要重新登录');
        }
        // 如果不是登录页，则重新抛出原始异常
        rethrow;
      }

      // 3. 检测是否需要登录
      if (await _isLoginRequired(page)) {
        await cookieManager.updateValidationStatus(false);
        throw ScraperException.cookieExpired('Cookie 已过期，需要重新登录');
      }

      // 4. 模拟人类行为：随机滚动
      await behaviorSimulator.simulateScroll(page);
      await behaviorSimulator.randomWait(minMs: 500, maxMs: 1000);

      // 5. 输入商品 ID
      _log('[京东联盟] 输入商品 ID: $skuId');
      const inputSelector = 'div.el-textarea textarea';
      await page.waitForSelector(inputSelector, timeout: config.requestTimeout);
      await behaviorSimulator.clearAndType(page, inputSelector, skuId);
      await behaviorSimulator.randomWait(minMs: 300, maxMs: 800);

      // 6. 点击获取推广链接按钮
      _log('[京东联盟] 点击获取推广链接按钮...');
      final clicked = await _clickPromotionButton(page);
      if (!clicked) {
        throw ScraperException(
          type: ScraperErrorType.unknown,
          message: '无法找到推广按钮',
        );
      }

      // 7. 等待结果加载
      _log('[京东联盟] 等待结果加载...');
      const resultSelector = '.result-text';
      await page.waitForSelector(resultSelector, timeout: config.requestTimeout);
      await behaviorSimulator.randomWait(minMs: 800, maxMs: 1500);

      // 8. 提取商品信息
      _log('[京东联盟] 提取推广信息...');
      final productInfo = await _extractProductInfo(page, skuId);

      // 更新 Cookie 验证状态
      await cookieManager.updateValidationStatus(true);

      return productInfo;
    } finally {
      await pageWithInstance.close();
    }
  }

  /// 设置 Cookie 到页面
  Future<void> _setupCookies(Page page) async {
    final cookieString = await cookieManager.getCookieString();
    if (cookieString == null || cookieString.isEmpty) {
      throw ScraperException.cookieExpired('Cookie 未配置');
    }

    final cookies = cookieManager.parseForPuppeteer(cookieString);
    final cookieParams = cookies.map((cookie) => CookieParam(
          name: cookie['name'] as String,
          value: cookie['value'] as String,
          domain: cookie['domain'] as String? ?? '.jd.com',
          path: cookie['path'] as String? ?? '/',
        )).toList();
    
    await page.setCookies(cookieParams);
  }

  /// 检测是否需要登录
  /// 
  /// 检测多种场景：
  /// 1. URL 跳转到京东 passport 登录页
  /// 2. URL 跳转到京东联盟登录页 (union.jd.com 的登录相关页面)
  /// 3. URL 包含 returnUrl 参数（通常是登录重定向）
  /// 4. 页面内容包含登录相关提示（仅用于京东联盟页面）
  Future<bool> _isLoginRequired(Page page) async {
    final url = page.url ?? '';

    // 检查 URL 是否跳转到登录页
    // 1. 京东 passport 登录
    if (url.contains('passport.jd.com') || url.contains('plogin.m.jd.com')) {
      _log('⚠️ 检测到跳转至京东 passport 登录页: $url');
      return true;
    }
    
    // 2. 京东联盟首页带 returnUrl（说明需要重新登录）
    if (url.contains('union.jd.com/index') && url.contains('returnUrl')) {
      _log('⚠️ 检测到跳转至京东联盟登录页（带returnUrl）: $url');
      return true;
    }
    
    // 3. 通用登录检测
    if (url.contains('/login') || url.contains('login.') || url.contains('signin')) {
      _log('⚠️ 检测到跳转至登录页: $url');
      return true;
    }

    // 对于京东商品详情页（item.jd.com），不需要检查页面文本
    // 因为导航栏总是有"请登录"链接，这不代表需要登录才能查看商品
    if (url.contains('item.jd.com') || url.contains('item.m.jd.com')) {
      return false;
    }

    // 检查页面内容（仅用于京东联盟等需要登录的页面）
    try {
      final bodyText = await page.evaluate<String>(
        '() => document.body.innerText',
      );
      if (bodyText != null) {
        // 检测常见的登录提示文本（排除导航栏的"请登录"）
        final loginIndicators = [
          '未登录', 
          '登录后查看',
          '请使用京东账号登录',
          '请先登录',
          '登录京东联盟',
        ];
        for (final indicator in loginIndicators) {
          if (bodyText.contains(indicator)) {
            _log('⚠️ 页面内容包含登录提示: "$indicator"');
            return true;
          }
        }
      }
    } catch (_) {}
    
    // 检查页面标题
    try {
      final title = await page.evaluate<String>('() => document.title');
      if (title != null) {
        if (title.contains('登录') || title.contains('Login')) {
          _log('⚠️ 页面标题包含登录: "$title"');
          return true;
        }
      }
    } catch (_) {}

    return false;
  }

  /// 点击推广按钮
  Future<bool> _clickPromotionButton(Page page) async {
    // 多种选择器策略，按优先级尝试
    final selectors = [
      '.superBtn button.el-button--primary',
      '.superBtn .el-button--primary',
      'button.el-button--primary:has(span)',
      '.el-button--primary',
    ];

    for (final selector in selectors) {
      try {
        _log('尝试选择器: $selector');
        
        // 使用 waitForSelector 等待按钮出现
        await page.waitForSelector(selector, timeout: const Duration(seconds: 3));
        
        // 获取按钮元素
        final button = await page.$(selector);
        if (button != null) {
          // 检查按钮文本是否包含"获取推广链接"
          final text = await button.evaluate<String>('el => el.textContent || el.innerText');
          _log('按钮文本: $text');
          
          if (text != null && text.contains('获取推广链接')) {
            // 使用人类行为模拟点击
            await behaviorSimulator.clickLikeHuman(page, button);
            _log('成功点击按钮 (选择器: $selector)');
            return true;
          }
        }
      } catch (e) {
        _log('选择器 $selector 失败: $e');
        continue;
      }
    }

    // 最后尝试：通过遍历所有按钮查找
    try {
      _log('尝试遍历所有按钮...');
      final buttons = await page.$$('button');
      for (final button in buttons) {
        try {
          final text = await button.evaluate<String>('el => el.textContent || el.innerText');
          if (text != null && text.contains('获取推广链接')) {
            await behaviorSimulator.clickLikeHuman(page, button);
            _log('通过遍历找到并点击了按钮');
            return true;
          }
        } catch (_) {
          continue;
        }
      }
    } catch (e) {
      _log('遍历按钮失败: $e');
    }

    return false;
  }

  /// 提取商品信息（京东联盟转链结果）
  Future<JdProductInfo> _extractProductInfo(Page page, String skuId) async {
    try {
      // 等待页面完全加载转链结果
      await behaviorSimulator.randomWait(minMs: 1000, maxMs: 2000);
      
      // 尝试多种选择器获取结果（按优先级排序）
      final selectors = [
        // 转链结果区域的可能选择器
        '.result-text',
        '.el-row.result-text',
        '.custompromotion .el-row',
        '[class*="result"]',
        '.el-textarea + div', // 输入框后面的结果区域
        '.app-content .el-row',
        'textarea + div',
      ];
      
      String? content;
      
      for (final selector in selectors) {
        try {
          final elements = await page.$$(selector);
          for (final element in elements) {
            final text = await element.evaluate<String>('el => el.innerText || el.textContent');
            // 检查内容是否包含关键信息（链接或价格）
            if (text != null && text.isNotEmpty) {
              if (text.contains('u.jd.com') || 
                  text.contains('京东价') || 
                  text.contains('到手价') ||
                  text.contains('抢购链接')) {
                content = text;
                _log('[京东联盟] 通过选择器 $selector 获取到有效内容');
                break;
              }
            }
          }
          if (content != null) break;
        } catch (e) {
          _log('[京东联盟] 选择器 $selector 失败: $e');
          continue;
        }
      }
      
      // 如果上面方法都失败，尝试获取整个页面的文本
      if (content == null || content.isEmpty) {
        _log('[京东联盟] 尝试从页面整体获取内容...');
        content = await page.evaluate<String>('document.body.innerText');
      }

      if (content == null || content.isEmpty) {
        throw ScraperException(
          type: ScraperErrorType.unknown,
          message: '无法获取推广结果',
        );
      }
      
      _log('[京东联盟] 获取到的原始内容长度: ${content.length}');
      // 打印前500字符用于调试
      _log('[京东联盟] 内容预览: ${content.substring(0, content.length > 500 ? 500 : content.length)}');

      // 解析结果
      return JdProductInfo.fromPromotionText(content, skuId);
    } catch (e) {
      if (e is ScraperException) rethrow;
      throw ScraperException.unknown(e);
    }
  }

  // ==================== 京东首页商品详情爬取 ====================

  // ==================== 获取商品信息（京东联盟） ====================

  /// 获取商品完整信息
  /// 
  /// 从京东联盟获取商品信息，包括：
  /// - 商品标题、价格
  /// - 推广链接、佣金信息
  /// 
  /// [skuId] 商品 SKU ID
  /// [forceRefresh] 是否强制刷新（忽略缓存）
  /// 
  /// 注意：京东首页爬取因风控严格已移除，仅使用京东联盟
  Future<JdProductInfo> getProductInfoEnhanced(
    String skuId, {
    bool forceRefresh = false,
  }) async {
    // 直接调用京东联盟的 getProductInfo
    return getProductInfo(skuId, forceRefresh: forceRefresh);
  }

  /// 批量获取商品完整信息
  /// 
  /// 注意：京东首页爬取因风控严格已移除，仅使用京东联盟
  Future<List<JdProductInfo>> getBatchProductInfoEnhanced(
    List<String> skuIds, {
    int maxConcurrency = 2,
  }) async {
    _ensureNotClosed();
    await _ensureInitialized();

    final results = <JdProductInfo>[];
    final errors = <String, dynamic>{};

    final semaphore = _Semaphore(maxConcurrency);

    await Future.wait(
      skuIds.map((skuId) async {
        await semaphore.acquire();
        try {
          final info = await getProductInfoEnhanced(skuId);
          results.add(info);
        } catch (e) {
          errors[skuId] = e;
          _log('批量增强获取失败 [$skuId]: $e');
        } finally {
          semaphore.release();
        }
      }),
    );

    _log('批量增强获取完成: ${results.length}/${skuIds.length} 成功');
    return results;
  }

  // ==================== 缓存管理 ====================

  /// 清除缓存
  void clearCache() {
    cacheManager.clear();
    _log('商品缓存已清除');
  }

  // ==================== 服务状态 ====================

  /// 获取服务状态
  Future<Map<String, dynamic>> getStatus() async {
    final cookieStatus = await cookieManager.getStatus();
    final poolStatus = browserPool.getStatus();
    final errorStats = errorHandler.getStatistics();
    final perfStats = performanceMonitor.getAllStats();
    final cacheStats = cacheManager.getStats();
    final deduplicatorStats = deduplicator.getStats();
    final concurrencyStats = concurrencyController.getStats();

    return {
      'initialized': _initialized,
      'closed': _closed,
      'cookie': cookieStatus,
      'browserPool': poolStatus,
      'cache': {
        'enabled': config.enableCache,
        ...cacheStats,
      },
      'deduplicator': deduplicatorStats,
      'concurrency': concurrencyStats,
      'errors': errorStats,
      'performance': perfStats,
    };
  }
  
  /// 获取错误历史
  List<ErrorEntry> getErrorHistory({
    ScraperErrorType? type,
    int? limit,
  }) {
    return errorHandler.getErrors(type: type, limit: limit);
  }

  /// 关闭服务
  Future<void> close() async {
    if (_closed) return;

    _log('关闭京东爬虫服务...');
    _closed = true;
    await browserPool.closeAll();
    cacheManager.dispose();
    _log('京东爬虫服务已关闭');
  }

  // ==================== 工具方法 ====================

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  void _ensureNotClosed() {
    if (_closed) {
      throw ScraperException(
        type: ScraperErrorType.unknown,
        message: '服务已关闭',
      );
    }
  }

  void _log(String message) {
    print('[JdScraperService] $message');
  }
}

/// 简单信号量实现（用于并发控制）
class _Semaphore {
  final int _maxCount;
  int _currentCount = 0;
  final _waitQueue = <Completer<void>>[];

  _Semaphore(this._maxCount);

  Future<void> acquire() async {
    if (_currentCount < _maxCount) {
      _currentCount++;
      return;
    }

    final completer = Completer<void>();
    _waitQueue.add(completer);
    await completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeAt(0);
      completer.complete();
    } else {
      _currentCount--;
    }
  }
}


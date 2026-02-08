import 'dart:async';

import 'package:puppeteer/puppeteer.dart';

import 'browser_pool.dart';
import 'cache_manager.dart';
import 'cookie_manager.dart';
import 'error_handler.dart';
import 'human_behavior_simulator.dart';
import 'models/models.dart';

/// 电路断路器状态
enum CircuitBreakerState {
  closed, // 正常状态，允许请求
  open, // 熔断状态，拒绝请求
  halfOpen, // 半开状态，允许部分请求测试
}

/// 电路断路器配置
class ScraperCircuitBreakerConfig {
  /// 失败阈值（连续失败次数触发熔断）
  final int failureThreshold;

  /// 成功阈值（半开状态下连续成功次数恢复）
  final int successThreshold;

  /// 熔断持续时间
  final Duration openDuration;

  /// 半开状态最大测试请求数
  final int halfOpenMaxRequests;

  const ScraperCircuitBreakerConfig({
    this.failureThreshold = 5,
    this.successThreshold = 3,
    this.openDuration = const Duration(minutes: 2),
    this.halfOpenMaxRequests = 3,
  });
}

/// 电路断路器
class ScraperCircuitBreaker {
  final ScraperCircuitBreakerConfig config;

  CircuitBreakerState _state = CircuitBreakerState.closed;
  int _failureCount = 0;
  int _successCount = 0;
  int _halfOpenRequestCount = 0;
  DateTime? _lastFailureTime;
  DateTime? _openedAt;

  ScraperCircuitBreaker({
    this.config = const ScraperCircuitBreakerConfig(),
  });

  CircuitBreakerState get state => _state;

  bool get isOpen => _state == CircuitBreakerState.open;

  bool get isClosed => _state == CircuitBreakerState.closed;

  bool get isHalfOpen => _state == CircuitBreakerState.halfOpen;

  /// 检查是否允许请求
  bool allowRequest() {
    switch (_state) {
      case CircuitBreakerState.closed:
        return true;
      case CircuitBreakerState.open:
        // 检查是否可以尝试半开
        if (_openedAt != null &&
            DateTime.now().difference(_openedAt!) >= config.openDuration) {
          _transitionToHalfOpen();
          return true;
        }
        return false;
      case CircuitBreakerState.halfOpen:
        // 半开状态限制请求数量
        if (_halfOpenRequestCount < config.halfOpenMaxRequests) {
          _halfOpenRequestCount++;
          return true;
        }
        return false;
    }
  }

  /// 记录成功
  void recordSuccess() {
    _failureCount = 0;
    _lastFailureTime = null;

    if (_state == CircuitBreakerState.halfOpen) {
      _successCount++;
      if (_successCount >= config.successThreshold) {
        _transitionToClosed();
      }
    }
  }

  /// 记录失败
  void recordFailure() {
    _failureCount++;
    _successCount = 0;
    _lastFailureTime = DateTime.now();

    if (_state == CircuitBreakerState.halfOpen) {
      // 半开状态下任何失败都回到开启状态
      _transitionToOpen();
    } else if (_state == CircuitBreakerState.closed &&
        _failureCount >= config.failureThreshold) {
      _transitionToOpen();
    }
  }

  void _transitionToOpen() {
    _state = CircuitBreakerState.open;
    _openedAt = DateTime.now();
    _halfOpenRequestCount = 0;
    print('[CircuitBreaker] 熔断器开启 - 连续失败 $_failureCount 次');
  }

  void _transitionToHalfOpen() {
    _state = CircuitBreakerState.halfOpen;
    _halfOpenRequestCount = 0;
    _successCount = 0;
    print('[CircuitBreaker] 熔断器进入半开状态');
  }

  void _transitionToClosed() {
    _state = CircuitBreakerState.closed;
    _failureCount = 0;
    _successCount = 0;
    _openedAt = null;
    print('[CircuitBreaker] 熔断器关闭 - 服务恢复正常');
  }

  /// 重置熔断器
  void reset() {
    _state = CircuitBreakerState.closed;
    _failureCount = 0;
    _successCount = 0;
    _halfOpenRequestCount = 0;
    _openedAt = null;
    _lastFailureTime = null;
  }

  Map<String, dynamic> getStatus() {
    return {
      'state': _state.name,
      'failureCount': _failureCount,
      'successCount': _successCount,
      'lastFailureTime': _lastFailureTime?.toIso8601String(),
      'openedAt': _openedAt?.toIso8601String(),
      'halfOpenRequestCount': _halfOpenRequestCount,
    };
  }
}

/// 降级策略类型
enum DegradationStrategyType {
  /// 返回缓存数据
  returnCached,

  /// 返回默认数据
  returnDefault,

  /// 返回部分数据（只有基本信息）
  returnPartial,

  /// 直接抛出异常
  throwError,
}

/// 降级策略
class DegradationStrategy {
  final DegradationStrategyType type;
  final Duration cacheFallbackAge;

  const DegradationStrategy({
    this.type = DegradationStrategyType.returnCached,
    this.cacheFallbackAge = const Duration(hours: 24),
  });

  /// 保守策略：优先使用缓存
  static const conservative = DegradationStrategy(
    type: DegradationStrategyType.returnCached,
    cacheFallbackAge: Duration(hours: 48),
  );

  /// 激进策略：直接报错
  static const aggressive = DegradationStrategy(
    type: DegradationStrategyType.throwError,
  );

  /// 宽松策略：返回部分数据
  static const lenient = DegradationStrategy(
    type: DegradationStrategyType.returnPartial,
  );
}

/// 健壮性配置
class ResilienceConfig {
  /// 电路断路器配置
  final ScraperCircuitBreakerConfig circuitBreakerConfig;

  /// 降级策略
  final DegradationStrategy degradationStrategy;

  /// 是否启用电路断路器
  final bool enableCircuitBreaker;

  /// 是否启用降级
  final bool enableDegradation;

  /// 健康检查间隔
  final Duration healthCheckInterval;

  const ResilienceConfig({
    this.circuitBreakerConfig = const ScraperCircuitBreakerConfig(),
    this.degradationStrategy = const DegradationStrategy(),
    this.enableCircuitBreaker = true,
    this.enableDegradation = true,
    this.healthCheckInterval = const Duration(minutes: 5),
  });
}

/// 京东爬虫服务配置（增强版）
class ResilientJdScraperConfig {
  /// 浏览器池配置
  final BrowserPoolConfig browserConfig;

  /// 行为模拟配置
  final BehaviorConfig behaviorConfig;

  /// 健壮性配置
  final ResilienceConfig resilienceConfig;

  /// 请求超时时间
  final Duration requestTimeout;

  /// 页面加载超时时间
  final Duration pageLoadTimeout;

  /// 最大重试次数
  final int maxRetries;

  /// 重试间隔
  final Duration retryDelay;

  /// 重试间隔最大值
  final Duration maxRetryDelay;

  /// 是否启用缓存
  final bool enableCache;

  /// 缓存有效期
  final Duration cacheDuration;

  /// 降级缓存有效期（更长）
  final Duration fallbackCacheDuration;

  const ResilientJdScraperConfig({
    this.browserConfig = const BrowserPoolConfig(),
    this.behaviorConfig = const BehaviorConfig(),
    this.resilienceConfig = const ResilienceConfig(),
    this.requestTimeout = const Duration(seconds: 30),
    this.pageLoadTimeout = const Duration(seconds: 30),
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 2),
    this.maxRetryDelay = const Duration(seconds: 30),
    this.enableCache = true,
    this.cacheDuration = const Duration(minutes: 10),
    this.fallbackCacheDuration = const Duration(hours: 24),
  });

  /// 开发环境配置
  factory ResilientJdScraperConfig.development() {
    return ResilientJdScraperConfig(
      browserConfig: BrowserPoolConfig.development(),
      behaviorConfig: const BehaviorConfig(verbose: true),
      resilienceConfig: const ResilienceConfig(
        enableCircuitBreaker: true,
        enableDegradation: true,
        circuitBreakerConfig: ScraperCircuitBreakerConfig(
          failureThreshold: 3,
          openDuration: Duration(minutes: 1),
        ),
      ),
      maxRetries: 2,
    );
  }

  /// 生产环境配置
  factory ResilientJdScraperConfig.production() {
    return ResilientJdScraperConfig(
      browserConfig: BrowserPoolConfig.production(),
      behaviorConfig: const BehaviorConfig(),
      resilienceConfig: const ResilienceConfig(
        enableCircuitBreaker: true,
        enableDegradation: true,
        circuitBreakerConfig: ScraperCircuitBreakerConfig(
          failureThreshold: 5,
          openDuration: Duration(minutes: 2),
        ),
        degradationStrategy: DegradationStrategy.conservative,
      ),
      maxRetries: 3,
    );
  }
}

/// 健壮的京东联盟爬虫服务
///
/// 增强特性：
/// - 电路断路器模式防止级联故障
/// - 降级策略提供服务可用性
/// - 指数退避重试
/// - 多级缓存（正常缓存 + 降级缓存）
/// - 详细的健康监控
/// - Cookie 过期自动检测和通知
class ResilientJdScraperService {
  /// 单例实例
  static ResilientJdScraperService? _instance;

  /// 获取单例实例
  static ResilientJdScraperService get instance {
    _instance ??= ResilientJdScraperService();
    return _instance!;
  }

  /// 配置
  final ResilientJdScraperConfig config;

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

  /// 正常缓存管理器
  late final ProductCacheManager cacheManager;

  /// 降级缓存管理器（更长的 TTL）
  late final ProductCacheManager fallbackCacheManager;

  /// 请求去重器
  late final RequestDeduplicator<JdProductInfo> deduplicator;

  /// 并发控制器
  late final ConcurrencyController concurrencyController;

  /// 电路断路器
  late final ScraperCircuitBreaker circuitBreaker;

  /// 健康检查定时器
  Timer? _healthCheckTimer;

  /// 是否已初始化
  bool _initialized = false;

  /// 是否已关闭
  bool _closed = false;

  /// 服务健康状态
  bool _healthy = true;

  /// 最后健康检查时间
  DateTime? _lastHealthCheck;

  /// Cookie 过期回调
  void Function()? onCookieExpired;

  /// 服务不可用回调
  void Function(String reason)? onServiceUnavailable;

  /// 服务恢复回调
  void Function()? onServiceRecovered;

  ResilientJdScraperService({
    ResilientJdScraperConfig? config,
    CookieManager? cookieManager,
    ErrorHandler? errorHandler,
    this.onCookieExpired,
    this.onServiceUnavailable,
    this.onServiceRecovered,
  })  : config = config ?? const ResilientJdScraperConfig(),
        cookieManager = cookieManager ?? CookieManager() {
    browserPool = BrowserPool(config: this.config.browserConfig);
    behaviorSimulator =
        HumanBehaviorSimulator(config: this.config.behaviorConfig);
    performanceMonitor = PerformanceMonitor();

    // 初始化正常缓存管理器
    cacheManager = ProductCacheManager(
      config: CacheConfig(
        defaultTtl: this.config.cacheDuration,
        maxEntries: 500,
        enablePersistence: false,
      ),
    );

    // 初始化降级缓存管理器（更长的 TTL）
    fallbackCacheManager = ProductCacheManager(
      config: CacheConfig(
        defaultTtl: this.config.fallbackCacheDuration,
        maxEntries: 1000,
        enablePersistence: true, // 持久化以便重启后可用
      ),
    );

    // 初始化请求去重器
    deduplicator = RequestDeduplicator<JdProductInfo>();

    // 初始化并发控制器
    concurrencyController = ConcurrencyController(maxConcurrency: 3);

    // 初始化电路断路器
    circuitBreaker = ScraperCircuitBreaker(
      config: this.config.resilienceConfig.circuitBreakerConfig,
    );

    // 初始化错误处理器
    this.errorHandler = errorHandler ??
        ErrorHandler(
          onCookieExpired: _handleCookieExpired,
          onAntiBotDetected: _handleAntiBotDetected,
        );
  }

  /// Cookie 过期处理
  Future<void> _handleCookieExpired() async {
    _log('⚠️ Cookie 已过期，请更新 Cookie');
    await cookieManager.updateValidationStatus(false);
    onCookieExpired?.call();
  }

  /// 反爬虫检测处理
  Future<void> _handleAntiBotDetected() async {
    _log('⚠️ 检测到反爬虫系统，触发电路断路器');
    circuitBreaker.recordFailure();
    _healthy = false;
  }

  /// 初始化服务
  Future<void> initialize() async {
    if (_initialized) return;

    _log('初始化健壮京东爬虫服务...');

    // 加载 Cookie
    final cookie = await cookieManager.loadCookieWithFallback();
    if (cookie == null) {
      _log('警告: 未找到有效的 Cookie，部分功能可能受限');
    }

    // 启动健康检查
    _startHealthCheck();

    _initialized = true;
    _log('健壮京东爬虫服务初始化完成');
  }

  /// 启动健康检查
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(
      config.resilienceConfig.healthCheckInterval,
      (_) => _performHealthCheck(),
    );
  }

  /// 执行健康检查
  Future<void> _performHealthCheck() async {
    _lastHealthCheck = DateTime.now();

    try {
      // 检查 Cookie 状态
      final cookieStatus = await cookieManager.getStatus();
      if (cookieStatus['isValid'] != true) {
        _log('健康检查: Cookie 无效');
        _healthy = false;
        return;
      }

      // 检查浏览器池状态
      final poolStatus = browserPool.getStatus();
      final availableInstances =
          poolStatus['availableInstances'] as int? ?? 0;
      if (availableInstances == 0) {
        _log('健康检查: 无可用浏览器实例');
        // 不标记为不健康，因为可能只是暂时繁忙
      }

      // 如果之前不健康但现在检查通过
      if (!_healthy && circuitBreaker.isClosed) {
        _healthy = true;
        _log('健康检查: 服务恢复正常');
        onServiceRecovered?.call();
      }
    } catch (e) {
      _log('健康检查失败: $e');
    }
  }

  /// 获取单个商品信息（带电路断路器和降级）
  ///
  /// [skuId] 商品 SKU ID
  /// [forceRefresh] 是否强制刷新（忽略缓存）
  Future<JdProductInfo> getProductInfo(
    String skuId, {
    bool forceRefresh = false,
  }) async {
    _ensureNotClosed();
    await _ensureInitialized();

    // 1. 检查正常缓存
    if (!forceRefresh && config.enableCache) {
      final cached = cacheManager.get(skuId);
      if (cached != null) {
        _log('从缓存获取商品信息: $skuId');
        return cached.markAsCached();
      }
    }

    // 2. 检查电路断路器
    if (config.resilienceConfig.enableCircuitBreaker &&
        !circuitBreaker.allowRequest()) {
      _log('电路断路器开启，尝试降级处理: $skuId');
      return _handleDegradation(skuId, '服务暂时不可用（熔断保护）');
    }

    // 3. 使用请求去重器
    try {
      final result = await deduplicator.execute(skuId, () async {
        return _fetchProductInfoWithRetry(skuId);
      });

      // 成功：记录到电路断路器
      circuitBreaker.recordSuccess();

      return result;
    } catch (e) {
      // 失败：记录到电路断路器
      circuitBreaker.recordFailure();

      // 检查是否应该触发降级
      if (config.resilienceConfig.enableDegradation) {
        return _handleDegradation(skuId, e.toString());
      }

      rethrow;
    }
  }

  /// 处理降级
  Future<JdProductInfo> _handleDegradation(
      String skuId, String reason) async {
    final strategy = config.resilienceConfig.degradationStrategy;

    switch (strategy.type) {
      case DegradationStrategyType.returnCached:
        // 尝试从降级缓存获取
        final fallbackCached = fallbackCacheManager.get(skuId);
        if (fallbackCached != null) {
          _log('降级: 返回缓存数据 $skuId');
          return fallbackCached.copyWith(
            isDegraded: true,
            degradationReason: reason,
          );
        }
        // 如果没有缓存，返回默认数据
        return _createDefaultProductInfo(skuId, reason);

      case DegradationStrategyType.returnDefault:
        return _createDefaultProductInfo(skuId, reason);

      case DegradationStrategyType.returnPartial:
        return _createPartialProductInfo(skuId, reason);

      case DegradationStrategyType.throwError:
        throw ScraperException(
          type: ScraperErrorType.unknown,
          message: '服务不可用: $reason',
        );
    }
  }

  /// 创建默认商品信息（降级）
  JdProductInfo _createDefaultProductInfo(String skuId, String reason) {
    _log('降级: 返回默认数据 $skuId');
    return JdProductInfo(
      skuId: skuId,
      title: '商品信息暂时不可用',
      price: 0.0,
      originalPrice: null,
      promotionLink: null,
      commission: null,
      commissionRate: null,
      cached: false,
      isDegraded: true,
      degradationReason: reason,
    );
  }

  /// 创建部分商品信息（降级）
  JdProductInfo _createPartialProductInfo(String skuId, String reason) {
    _log('降级: 返回部分数据 $skuId');
    return JdProductInfo(
      skuId: skuId,
      title: '商品 $skuId',
      price: 0.0,
      originalPrice: null,
      promotionLink: 'https://item.jd.com/$skuId.html',
      commission: null,
      commissionRate: null,
      cached: false,
      isDegraded: true,
      degradationReason: reason,
    );
  }

  /// 带重试的商品信息获取（带指数退避）
  Future<JdProductInfo> _fetchProductInfoWithRetry(String skuId) async {
    final stopwatch = Stopwatch()..start();
    ScraperException? lastError;
    Duration currentDelay = config.retryDelay;

    for (int attempt = 1; attempt <= config.maxRetries; attempt++) {
      try {
        _log('获取商品信息 (尝试 $attempt/${config.maxRetries}): $skuId');

        final info = await concurrencyController
            .execute(() => _fetchProductInfo(skuId));

        // 记录性能
        stopwatch.stop();
        performanceMonitor.recordRequest('getProductInfo', stopwatch.elapsed);

        // 缓存结果到两个缓存
        if (config.enableCache) {
          cacheManager.set(skuId, info);
          fallbackCacheManager.set(skuId, info); // 同时更新降级缓存
        }

        return info;
      } on ScraperException catch (e) {
        lastError = e;
        _log('获取失败 (${e.type}): ${e.message}');

        // 记录错误
        await errorHandler.handleError(e, skuId: skuId);
        performanceMonitor.recordError('getProductInfo');

        // Cookie 过期不重试
        if (e.type == ScraperErrorType.cookieExpired) {
          rethrow;
        }

        // 反爬虫检测：增加更长的等待时间
        if (e.type == ScraperErrorType.antiBotDetected) {
          currentDelay = Duration(seconds: currentDelay.inSeconds * 3);
        }

        // 等待后重试（指数退避）
        if (attempt < config.maxRetries) {
          _log('等待 ${currentDelay.inSeconds}s 后重试...');
          await Future.delayed(currentDelay);
          // 指数退避，但不超过最大延迟
          currentDelay = Duration(
            milliseconds: (currentDelay.inMilliseconds * 1.5).toInt(),
          );
          if (currentDelay > config.maxRetryDelay) {
            currentDelay = config.maxRetryDelay;
          }
        }
      } catch (e, stack) {
        final errorStr = e.toString().toLowerCase();

        if (errorStr.contains('timeout')) {
          lastError = ScraperException.timeout('请求超时: $e');
          _log('获取失败 (超时): $e');
        } else {
          lastError = ScraperException.unknown(e, stack);
          _log('获取失败: $e');
        }

        await errorHandler.handleError(lastError, skuId: skuId);
        performanceMonitor.recordError('getProductInfo');

        if (attempt < config.maxRetries) {
          _log('等待 ${currentDelay.inSeconds}s 后重试...');
          await Future.delayed(currentDelay);
          currentDelay = Duration(
            milliseconds: (currentDelay.inMilliseconds * 1.5).toInt(),
          );
          if (currentDelay > config.maxRetryDelay) {
            currentDelay = config.maxRetryDelay;
          }
        }
      }
    }

    throw lastError ?? ScraperException.unknown('未知错误');
  }

  /// 批量获取商品信息
  Future<List<JdProductInfo>> getBatchProductInfo(
    List<String> skuIds, {
    int maxConcurrency = 2,
  }) async {
    _ensureNotClosed();
    await _ensureInitialized();

    final results = <JdProductInfo>[];
    final errors = <String, dynamic>{};

    // 检查电路断路器
    if (config.resilienceConfig.enableCircuitBreaker &&
        circuitBreaker.isOpen) {
      _log('电路断路器开启，批量请求使用降级模式');
      // 全部使用降级
      for (final skuId in skuIds) {
        results.add(await _handleDegradation(skuId, '服务暂时不可用'));
      }
      return results;
    }

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

          // 尝试降级
          if (config.resilienceConfig.enableDegradation) {
            results.add(await _handleDegradation(skuId, e.toString()));
          }
        } finally {
          semaphore.release();
        }
      }),
    );

    _log('批量获取完成: ${results.length}/${skuIds.length} (错误: ${errors.length})');
    return results;
  }

  /// 获取商品信息的核心实现
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
        final currentUrl = page.url ?? '';
        _log('[京东联盟] 页面导航异常，当前URL: $currentUrl');

        if (await _isLoginRequired(page)) {
          _log('[京东联盟] ⚠️ 页面导航时检测到跳转至登录页');
          await cookieManager.updateValidationStatus(false);
          throw ScraperException.cookieExpired('Cookie 已过期，需要重新登录');
        }
        rethrow;
      }

      // 3. 检测是否需要登录
      if (await _isLoginRequired(page)) {
        await cookieManager.updateValidationStatus(false);
        throw ScraperException.cookieExpired('Cookie 已过期，需要重新登录');
      }

      // 4. 模拟人类行为
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
    final cookieParams = cookies
        .map((cookie) => CookieParam(
              name: cookie['name'] as String,
              value: cookie['value'] as String,
              domain: cookie['domain'] as String? ?? '.jd.com',
              path: cookie['path'] as String? ?? '/',
            ))
        .toList();

    await page.setCookies(cookieParams);
  }

  /// 检测是否需要登录
  Future<bool> _isLoginRequired(Page page) async {
    final url = page.url ?? '';

    if (url.contains('passport.jd.com') || url.contains('plogin.m.jd.com')) {
      _log('⚠️ 检测到跳转至京东 passport 登录页: $url');
      return true;
    }

    if (url.contains('union.jd.com/index') && url.contains('returnUrl')) {
      _log('⚠️ 检测到跳转至京东联盟登录页（带returnUrl）: $url');
      return true;
    }

    if (url.contains('/login') ||
        url.contains('login.') ||
        url.contains('signin')) {
      _log('⚠️ 检测到跳转至登录页: $url');
      return true;
    }

    if (url.contains('item.jd.com') || url.contains('item.m.jd.com')) {
      return false;
    }

    try {
      final bodyText = await page.evaluate<String>(
        '() => document.body.innerText',
      );
      if (bodyText != null) {
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
    final selectors = [
      '.superBtn button.el-button--primary',
      '.superBtn .el-button--primary',
      'button.el-button--primary:has(span)',
      '.el-button--primary',
    ];

    for (final selector in selectors) {
      try {
        _log('尝试选择器: $selector');
        await page.waitForSelector(selector,
            timeout: const Duration(seconds: 3));
        final button = await page.$(selector);
        if (button != null) {
          final text = await button
              .evaluate<String>('el => el.textContent || el.innerText');
          _log('按钮文本: $text');

          if (text != null && text.contains('获取推广链接')) {
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

    try {
      _log('尝试遍历所有按钮...');
      final buttons = await page.$$('button');
      for (final button in buttons) {
        try {
          final text = await button
              .evaluate<String>('el => el.textContent || el.innerText');
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

  /// 提取商品信息
  Future<JdProductInfo> _extractProductInfo(Page page, String skuId) async {
    try {
      await behaviorSimulator.randomWait(minMs: 1000, maxMs: 2000);

      final selectors = [
        '.result-text',
        '.el-row.result-text',
        '.custompromotion .el-row',
        '[class*="result"]',
        '.el-textarea + div',
        '.app-content .el-row',
        'textarea + div',
      ];

      String? content;

      for (final selector in selectors) {
        try {
          final elements = await page.$$(selector);
          for (final element in elements) {
            final text = await element
                .evaluate<String>('el => el.innerText || el.textContent');
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
      _log(
          '[京东联盟] 内容预览: ${content.substring(0, content.length > 500 ? 500 : content.length)}');

      return JdProductInfo.fromPromotionText(content, skuId);
    } catch (e) {
      if (e is ScraperException) rethrow;
      throw ScraperException.unknown(e);
    }
  }

  // ==================== 缓存管理 ====================

  /// 清除正常缓存
  void clearCache() {
    cacheManager.clear();
    _log('商品缓存已清除');
  }

  /// 清除所有缓存（包括降级缓存）
  void clearAllCaches() {
    cacheManager.clear();
    fallbackCacheManager.clear();
    _log('所有缓存已清除');
  }

  // ==================== 电路断路器管理 ====================

  /// 手动重置电路断路器
  void resetCircuitBreaker() {
    circuitBreaker.reset();
    _log('电路断路器已重置');
  }

  /// 获取电路断路器状态
  Map<String, dynamic> getCircuitBreakerStatus() {
    return circuitBreaker.getStatus();
  }

  // ==================== 服务状态 ====================

  /// 是否健康
  bool get isHealthy => _healthy && circuitBreaker.isClosed;

  /// 获取服务状态
  Future<Map<String, dynamic>> getStatus() async {
    final cookieStatus = await cookieManager.getStatus();
    final poolStatus = browserPool.getStatus();
    final errorStats = errorHandler.getStatistics();
    final perfStats = performanceMonitor.getAllStats();
    final cacheStats = cacheManager.getStats();
    final fallbackCacheStats = fallbackCacheManager.getStats();
    final deduplicatorStats = deduplicator.getStats();
    final concurrencyStats = concurrencyController.getStats();
    final circuitBreakerStatus = circuitBreaker.getStatus();

    return {
      'initialized': _initialized,
      'closed': _closed,
      'healthy': isHealthy,
      'lastHealthCheck': _lastHealthCheck?.toIso8601String(),
      'cookie': cookieStatus,
      'browserPool': poolStatus,
      'cache': {
        'enabled': config.enableCache,
        'normal': cacheStats,
        'fallback': fallbackCacheStats,
      },
      'circuitBreaker': circuitBreakerStatus,
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

    _log('关闭健壮京东爬虫服务...');
    _closed = true;
    _healthCheckTimer?.cancel();
    await browserPool.closeAll();
    cacheManager.dispose();
    fallbackCacheManager.dispose();
    _log('健壮京东爬虫服务已关闭');
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
    print('[ResilientJdScraperService] $message');
  }
}

/// 简单信号量实现
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

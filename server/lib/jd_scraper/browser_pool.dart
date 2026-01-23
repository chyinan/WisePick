import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:puppeteer/puppeteer.dart';

import 'models/scraper_error.dart';

/// 浏览器实例包装类
class BrowserInstance {
  /// 浏览器实例
  final Browser browser;

  /// 浏览器上下文（用于隔离会话）
  final BrowserContext? context;

  /// 超时时间
  final Duration timeout;

  /// 上次使用时间
  DateTime? _lastUsed;

  /// 是否正在使用中
  bool _inUse = false;

  /// 创建时间
  final DateTime createdAt;

  /// 使用次数
  int _useCount = 0;

  BrowserInstance(this.browser, this.timeout, {this.context})
      : createdAt = DateTime.now() {
    _lastUsed = DateTime.now();
  }

  /// 是否可用
  bool get isAvailable => !_inUse && !isExpired;

  /// 是否已过期
  bool get isExpired {
    if (_lastUsed == null) return true;
    return DateTime.now().difference(_lastUsed!) > timeout;
  }

  /// 获取使用次数
  int get useCount => _useCount;

  /// 获取存活时长
  Duration get age => DateTime.now().difference(createdAt);

  /// 标记为使用中
  void markInUse() {
    _inUse = true;
    _lastUsed = DateTime.now();
    _useCount++;
  }

  /// 标记为可用
  void markAvailable() {
    _inUse = false;
    _lastUsed = DateTime.now();
  }

  /// 检查浏览器是否仍然连接
  Future<bool> isConnected() async {
    try {
      // 尝试获取浏览器版本来检查连接状态
      await browser.version;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 关闭浏览器实例
  Future<void> close() async {
    try {
      // 先关闭所有页面
      final pages = await browser.pages;
      for (final page in pages) {
        try {
          await page.close();
        } catch (_) {}
      }
      
      // 关闭浏览器
      await browser.close();
      _log('浏览器实例已关闭');
    } catch (e) {
      _log('关闭浏览器实例失败: $e');
      // 尝试强制终止进程
      try {
        browser.process?.kill();
        _log('已强制终止浏览器进程');
      } catch (_) {}
    }
  }

  void _log(String message) {
    print('[BrowserInstance] $message');
  }
}

/// 浏览器池配置
class BrowserPoolConfig {
  /// 最大浏览器实例数
  final int maxBrowsers;

  /// 浏览器实例超时时间
  final Duration browserTimeout;
  
  /// 空闲超时时间（空闲多久后关闭浏览器）
  final Duration idleTimeout;

  /// 是否使用无头模式
  final bool headless;

  /// Chrome 可执行文件路径（可选）
  final String? executablePath;

  /// 额外的浏览器启动参数
  final List<String> extraArgs;

  /// 默认视口大小
  final DeviceViewport? defaultViewport;

  /// 是否忽略 HTTPS 错误
  final bool ignoreHttpsErrors;

  /// 操作减速（用于调试）
  final Duration? slowMo;
  
  /// 是否在请求完成后立即关闭浏览器（不复用）
  final bool closeAfterUse;

  const BrowserPoolConfig({
    this.maxBrowsers = 3,
    this.browserTimeout = const Duration(minutes: 30),
    this.idleTimeout = const Duration(minutes: 2),
    this.headless = true,
    this.executablePath,
    this.extraArgs = const [],
    this.defaultViewport,
    this.ignoreHttpsErrors = false,
    this.slowMo,
    this.closeAfterUse = false,
  });

  /// 创建开发环境配置
  factory BrowserPoolConfig.development() {
    return BrowserPoolConfig(
      maxBrowsers: 2,
      browserTimeout: const Duration(minutes: 15),
      idleTimeout: const Duration(minutes: 1),
      headless: true,
      slowMo: const Duration(milliseconds: 50),
      closeAfterUse: true,  // 开发环境下用完即关
    );
  }

  /// 创建生产环境配置
  factory BrowserPoolConfig.production() {
    return const BrowserPoolConfig(
      maxBrowsers: 5,
      browserTimeout: const Duration(minutes: 30),
      idleTimeout: const Duration(minutes: 2),
      headless: true,
      closeAfterUse: true,  // 生产环境也建议用完即关，避免进程残留
    );
  }
}

/// 浏览器池管理器
///
/// 负责浏览器实例的创建、复用、回收和健康检查
class BrowserPool {
  /// 配置
  final BrowserPoolConfig config;

  /// 浏览器实例列表
  final List<BrowserInstance> _browsers = [];

  /// 等待队列
  final Queue<Completer<BrowserInstance>> _waitingQueue = Queue();

  /// 是否已关闭
  bool _closed = false;

  /// 指纹随机化器
  final _fingerprintRandomizer = FingerprintRandomizer();
  
  /// 空闲清理定时器
  Timer? _idleCleanupTimer;

  BrowserPool({BrowserPoolConfig? config})
      : config = config ?? const BrowserPoolConfig() {
    // 启动空闲清理定时器
    _startIdleCleanupTimer();
  }
  
  /// 启动空闲清理定时器
  void _startIdleCleanupTimer() {
    _idleCleanupTimer?.cancel();
    _idleCleanupTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _cleanupIdleBrowsers(),
    );
  }
  
  /// 清理空闲超时的浏览器
  Future<void> _cleanupIdleBrowsers() async {
    if (_closed) return;
    
    final toRemove = <BrowserInstance>[];
    final now = DateTime.now();
    
    for (final instance in _browsers) {
      // 如果浏览器不在使用中，且空闲时间超过配置的空闲超时
      if (!instance._inUse && instance._lastUsed != null) {
        final idleTime = now.difference(instance._lastUsed!);
        if (idleTime > config.idleTimeout) {
          toRemove.add(instance);
          _log('浏览器空闲超时 (${idleTime.inSeconds}秒)，准备关闭');
        }
      }
    }
    
    for (final instance in toRemove) {
      await _removeInstance(instance);
    }
    
    if (toRemove.isNotEmpty) {
      _log('清理了 ${toRemove.length} 个空闲浏览器实例，剩余: ${_browsers.length}');
    }
  }

  /// 获取浏览器实例
  ///
  /// 如果有可用实例则直接返回，否则创建新实例或等待
  Future<BrowserInstance> acquire() async {
    if (_closed) {
      throw ScraperException(
        type: ScraperErrorType.unknown,
        message: '浏览器池已关闭',
      );
    }

    // 清理过期浏览器
    await _cleanupExpiredBrowsers();

    // 查找可用浏览器
    for (final instance in _browsers) {
      if (instance.isAvailable) {
        // 检查是否仍然连接
        if (await instance.isConnected()) {
          instance.markInUse();
          _log('复用浏览器实例 (使用次数: ${instance.useCount})');
          return instance;
        } else {
          // 移除断开连接的实例
          await _removeInstance(instance);
        }
      }
    }

    // 如果未达到上限，创建新浏览器
    if (_browsers.length < config.maxBrowsers) {
      final instance = await _createBrowserInstance();
      instance.markInUse();
      _browsers.add(instance);
      _log('创建新浏览器实例 (当前数量: ${_browsers.length}/${config.maxBrowsers})');
      return instance;
    }

    // 等待可用浏览器
    _log('等待可用浏览器实例...');
    final completer = Completer<BrowserInstance>();
    _waitingQueue.add(completer);
    return completer.future;
  }

  /// 释放浏览器实例
  Future<void> release(BrowserInstance instance) async {
    if (_closed) return;

    // 如果有等待的请求，分配浏览器（不关闭）
    if (_waitingQueue.isNotEmpty) {
      final completer = _waitingQueue.removeFirst();
      instance.markInUse();
      completer.complete(instance);
      _log('将浏览器实例分配给等待中的请求');
      return;
    }
    
    // 如果配置为用完即关，则直接关闭浏览器
    if (config.closeAfterUse) {
      _log('用完即关模式：关闭浏览器实例');
      await _removeInstance(instance);
      return;
    }

    // 否则标记为可用，等待复用
    instance.markAvailable();
    _log('浏览器实例已释放，等待复用');
  }

  /// 获取新页面
  ///
  /// 便捷方法：获取浏览器实例并创建新页面
  Future<PageWithInstance> acquirePage() async {
    final instance = await acquire();
    try {
      final page = await instance.browser.newPage();
      // 为新页面注入反检测脚本
      await _injectStealthScripts(page);
      return PageWithInstance(page, instance, this);
    } catch (e) {
      release(instance);
      rethrow;
    }
  }

  /// 创建浏览器实例
  Future<BrowserInstance> _createBrowserInstance() async {
    try {
      // 获取随机化的启动参数
      final args = _buildLaunchArgs();
      final viewport = _fingerprintRandomizer.getRandomViewport();

      final browser = await puppeteer.launch(
        headless: config.headless,
        executablePath: config.executablePath,
        args: args,
        defaultViewport: viewport,
        ignoreHttpsErrors: config.ignoreHttpsErrors,
        slowMo: config.slowMo,
      );

      // 注入反检测脚本到默认上下文
      final pages = await browser.pages;
      for (final page in pages) {
        await _injectStealthScripts(page);
      }

      return BrowserInstance(browser, config.browserTimeout);
    } catch (e, stack) {
      _log('创建浏览器实例失败: $e');
      throw ScraperException.unknown(e, stack);
    }
  }

  /// 构建浏览器启动参数
  List<String> _buildLaunchArgs() {
    final args = <String>[
      // 反检测参数
      '--disable-blink-features=AutomationControlled',
      '--disable-dev-shm-usage',
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-web-security',
      '--disable-features=IsolateOrigins,site-per-process',

      // 性能优化参数
      '--disable-background-networking',
      '--disable-default-apps',
      '--disable-extensions',
      '--disable-sync',
      '--disable-translate',
      '--metrics-recording-only',
      '--mute-audio',
      '--no-first-run',

      // 语言和地区设置
      '--lang=zh-CN',
    ];

    // 添加额外参数
    args.addAll(config.extraArgs);

    return args;
  }

  /// 注入反检测脚本
  Future<void> _injectStealthScripts(Page page) async {
    final userAgent = _fingerprintRandomizer.getRandomUserAgent();

    // 设置 User-Agent
    await page.setUserAgent(userAgent);

    // 注入反检测 JavaScript（增强版）
    await page.evaluateOnNewDocument('''
      // 1. 隐藏 webdriver 属性（最重要）
      Object.defineProperty(navigator, 'webdriver', {
        get: () => false,
        configurable: true
      });
      
      // 2. 删除 webdriver 相关属性
      if (navigator.__proto__) {
        delete navigator.__proto__.webdriver;
      }
      
      // 3. 模拟完整的 Chrome 对象
      window.chrome = {
        runtime: {
          onConnect: { addListener: function() {} },
          onMessage: { addListener: function() {} }
        },
        loadTimes: function() {
          return {
            requestTime: Date.now() / 1000,
            startLoadTime: Date.now() / 1000,
            commitLoadTime: Date.now() / 1000,
            finishDocumentLoadTime: Date.now() / 1000,
            finishLoadTime: Date.now() / 1000,
            firstPaintTime: Date.now() / 1000,
            firstPaintAfterLoadTime: Date.now() / 1000,
            navigationType: 'navigate'
          };
        },
        csi: function() {
          return { pageT: Date.now() };
        },
        app: {
          isInstalled: false,
          InstallState: { DISABLED: 'disabled', INSTALLED: 'installed', NOT_INSTALLED: 'not_installed' },
          RunningState: { CANNOT_RUN: 'cannot_run', READY_TO_RUN: 'ready_to_run', RUNNING: 'running' }
        }
      };
      
      // 4. 模拟真实的插件列表
      Object.defineProperty(navigator, 'plugins', {
        get: () => {
          const plugins = [
            { name: 'Chrome PDF Plugin', filename: 'internal-pdf-viewer', description: 'Portable Document Format' },
            { name: 'Chrome PDF Viewer', filename: 'mhjfbmdgcfjbbpaeojofohoefgiehjai', description: '' },
            { name: 'Native Client', filename: 'internal-nacl-plugin', description: '' }
          ];
          plugins.length = 3;
          return plugins;
        },
        configurable: true
      });
      
      // 5. 设置语言
      Object.defineProperty(navigator, 'languages', {
        get: () => ['zh-CN', 'zh', 'en-US', 'en'],
        configurable: true
      });
      
      // 6. 设置 platform
      Object.defineProperty(navigator, 'platform', {
        get: () => 'Win32',
        configurable: true
      });
      
      // 7. 修改 permissions 查询
      if (window.navigator.permissions) {
        const originalQuery = window.navigator.permissions.query;
        window.navigator.permissions.query = (parameters) => (
          parameters.name === 'notifications' ?
            Promise.resolve({ state: Notification.permission }) :
            originalQuery(parameters)
        );
      }
      
      // 8. 隐藏 Puppeteer/Playwright 特有的属性
      const puppeteerProps = ['__puppeteer_evaluation_script__', '__playwright'];
      puppeteerProps.forEach(prop => {
        if (window[prop]) delete window[prop];
      });
      
      // 9. 模拟真实的 WebGL 渲染器信息
      const getParameterProto = WebGLRenderingContext.prototype.getParameter;
      WebGLRenderingContext.prototype.getParameter = function(param) {
        if (param === 37445) return 'Intel Inc.';
        if (param === 37446) return 'Intel Iris OpenGL Engine';
        return getParameterProto.call(this, param);
      };
      
      // 10. 修改 connection 属性（网络信息）
      if (navigator.connection) {
        Object.defineProperty(navigator.connection, 'rtt', { get: () => 50 });
      }
    ''');
  }

  /// 清理过期浏览器
  Future<void> _cleanupExpiredBrowsers() async {
    final toRemove = <BrowserInstance>[];

    for (final instance in _browsers) {
      if (instance.isExpired && !instance._inUse) {
        toRemove.add(instance);
      }
    }

    for (final instance in toRemove) {
      await _removeInstance(instance);
    }

    if (toRemove.isNotEmpty) {
      _log('清理了 ${toRemove.length} 个过期浏览器实例');
    }
  }

  /// 移除浏览器实例
  Future<void> _removeInstance(BrowserInstance instance) async {
    if (!_browsers.contains(instance)) return;
    _browsers.remove(instance);
    await instance.close();
    _log('移除浏览器实例，剩余: ${_browsers.length}/${config.maxBrowsers}');
  }
  
  /// 立即关闭所有空闲浏览器（手动清理）
  Future<int> closeIdleBrowsers() async {
    if (_closed) return 0;
    
    final toRemove = <BrowserInstance>[];
    
    for (final instance in _browsers) {
      if (!instance._inUse) {
        toRemove.add(instance);
      }
    }
    
    for (final instance in toRemove) {
      await _removeInstance(instance);
    }
    
    if (toRemove.isNotEmpty) {
      _log('手动清理了 ${toRemove.length} 个空闲浏览器实例');
    }
    
    return toRemove.length;
  }

  /// 关闭所有浏览器
  Future<void> closeAll() async {
    _closed = true;
    
    // 取消空闲清理定时器
    _idleCleanupTimer?.cancel();
    _idleCleanupTimer = null;

    // 取消所有等待中的请求
    while (_waitingQueue.isNotEmpty) {
      final completer = _waitingQueue.removeFirst();
      completer.completeError(ScraperException(
        type: ScraperErrorType.unknown,
        message: '浏览器池已关闭',
      ));
    }

    // 关闭所有浏览器实例
    for (final instance in _browsers) {
      await instance.close();
    }
    _browsers.clear();

    _log('所有浏览器实例已关闭');
  }

  /// 获取池状态
  Map<String, dynamic> getStatus() {
    return {
      'total': _browsers.length,
      'maxBrowsers': config.maxBrowsers,
      'available': _browsers.where((b) => b.isAvailable).length,
      'inUse': _browsers.where((b) => b._inUse).length,
      'waiting': _waitingQueue.length,
      'closed': _closed,
      'instances': _browsers.map((b) => {
            'inUse': b._inUse,
            'useCount': b.useCount,
            'age': b.age.inMinutes,
            'isExpired': b.isExpired,
          }).toList(),
    };
  }

  void _log(String message) {
    print('[BrowserPool] $message');
  }
}

/// 页面和实例的组合，便于管理
class PageWithInstance {
  final Page page;
  final BrowserInstance instance;
  final BrowserPool pool;

  PageWithInstance(this.page, this.instance, this.pool);

  /// 关闭页面并释放浏览器实例
  Future<void> close() async {
    try {
      await page.close();
    } catch (_) {}
    await pool.release(instance);
  }
}

/// 指纹随机化器
///
/// 用于生成随机的浏览器指纹，避免被检测
class FingerprintRandomizer {
  final Random _random = Random();

  /// 获取随机 User-Agent
  String getRandomUserAgent() {
    final userAgents = [
      // Chrome Windows
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36',

      // Chrome macOS
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',

      // Edge
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0',
    ];

    return userAgents[_random.nextInt(userAgents.length)];
  }

  /// 获取随机视口大小
  DeviceViewport getRandomViewport() {
    final viewports = [
      DeviceViewport(width: 1920, height: 1080),
      DeviceViewport(width: 1366, height: 768),
      DeviceViewport(width: 1536, height: 864),
      DeviceViewport(width: 1440, height: 900),
      DeviceViewport(width: 1680, height: 1050),
    ];

    return viewports[_random.nextInt(viewports.length)];
  }

  /// 获取随机地理位置（中国城市）
  Map<String, double> getRandomGeolocation() {
    final locations = [
      {'latitude': 39.9042, 'longitude': 116.4074}, // 北京
      {'latitude': 31.2304, 'longitude': 121.4737}, // 上海
      {'latitude': 23.1291, 'longitude': 113.2644}, // 广州
      {'latitude': 22.5431, 'longitude': 114.0579}, // 深圳
      {'latitude': 30.5728, 'longitude': 104.0668}, // 成都
    ];

    return locations[_random.nextInt(locations.length)];
  }

  /// 获取随机时区
  String getRandomTimezone() {
    // 京东主要面向中国用户，使用中国时区
    return 'Asia/Shanghai';
  }
}











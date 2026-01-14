# 京东联盟高级网页爬虫设计文档

## 1. 项目概述

### 1.1 目标
开发一个能够模拟人类行为、避免被京东风控系统检测的高级网页爬虫，用于获取京东联盟商品的价格和商品详情，替代现有的简单HTTP请求方式。

### 1.2 核心需求
- ✅ 模拟真实人类浏览行为（点击、输入、滚动、鼠标移动）
- ✅ 避免触发京东风控系统，防止被强制退出登录
- ✅ 在用户感知范围内保持高效（单次请求 < 3秒）
- ✅ 自动识别Cookie过期并反馈错误日志
- ✅ 支持Cookie更新和手动浏览器登录
- ✅ 支持批量商品信息获取

### 1.3 技术挑战
- 京东联盟的反爬虫机制（行为检测、指纹识别）
- Cookie有效期管理
- 并发请求的性能与稳定性平衡
- 错误恢复机制

---

## 2. 技术栈选型

### 2.1 推荐技术栈

#### 方案A：Playwright + Dart（推荐）
**优势：**
- Playwright是当前最先进的浏览器自动化工具，反检测能力强
- 支持多浏览器引擎（Chromium、Firefox、WebKit）
- 内置反检测机制（stealth模式）
- Dart有官方binding：`playwright_dart`
- 性能优秀，支持并发

**依赖：**
```yaml
dependencies:
  playwright_dart: ^1.0.0
  http: ^0.13.0
  crypto: ^3.0.2
  path: ^1.8.0
  shared_preferences: ^2.0.0  # 用于存储Cookie
```

#### 方案B：Puppeteer + Dart（备选）
**优势：**
- 项目已有`puppeteer: ^2.2.0`依赖
- 社区成熟，文档丰富
- 需要额外配置反检测插件

**依赖：**
```yaml
dependencies:
  puppeteer: ^2.2.0
  puppeteer_stealth: ^1.0.0  # 需要Dart版本或自行实现
```

#### 方案C：Python + Playwright（独立服务）
**优势：**
- Python生态成熟，反检测库丰富
- 可作为独立微服务，与Dart后端通过HTTP通信
- 易于维护和调试

**推荐选择：方案A（Playwright + Dart）**

---

## 3. 架构设计

### 3.1 系统架构

```
┌─────────────────────────────────────────────────────────┐
│                    Dart后端服务器                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │        京东爬虫服务 (JdScraperService)             │   │
│  │  ┌──────────────┐  ┌──────────────┐              │   │
│  │  │ Cookie管理器  │  │ 浏览器池管理   │              │   │
│  │  │ (CookieMgr)  │  │ (BrowserPool)│              │   │
│  │  └──────────────┘  └──────────────┘              │   │
│  │  ┌──────────────┐  ┌──────────────┐              │   │
│  │  │ 行为模拟器     │  │ 错误处理器     │              │   │
│  │  │ (BehaviorSim)│  │ (ErrorHandler)│             │   │
│  │  └──────────────┘  └──────────────┘              │   │
│  └──────────────────────────────────────────────────┘   │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │          Playwright浏览器实例                      │   │
│  │  - 无头/有头模式切换                                │   │
│  │  - Stealth模式（反检测）                            │   │
│  │  - Cookie注入                                     │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### 3.2 核心模块

#### 3.2.1 Cookie管理器 (CookieManager)
**职责：**
- Cookie存储和读取（本地文件/数据库）
- Cookie有效性检测
- Cookie自动刷新机制
- Cookie过期通知

**实现要点：**
```dart
class CookieManager {
  // Cookie存储路径
  static const String cookiePath = 'data/jd_cookies.json';
  
  // 检测Cookie是否有效
  Future<bool> validateCookie(String cookie);
  
  // 保存Cookie
  Future<void> saveCookie(String cookie);
  
  // 加载Cookie
  Future<String?> loadCookie();
  
  // 检测Cookie过期（通过访问联盟首页）
  Future<bool> checkCookieExpired(Page page);
}
```

#### 3.2.2 浏览器池管理器 (BrowserPool)
**职责：**
- 浏览器实例复用（避免频繁创建）
- 并发控制（最多3-5个浏览器实例）
- 浏览器实例健康检查
- 自动重启失效实例

**实现要点：**
```dart
class BrowserPool {
  final int maxBrowsers = 3;
  final List<Browser> _browsers = [];
  final Queue<Completer<Browser>> _waitingQueue = Queue();
  
  Future<Browser> acquire();
  void release(Browser browser);
  Future<void> _createBrowser();
}
```

#### 3.2.3 人类行为模拟器 (HumanBehaviorSimulator)
**职责：**
- 随机鼠标移动轨迹
- 随机滚动行为
- 随机输入延迟
- 随机等待时间

**实现要点：**
```dart
class HumanBehaviorSimulator {
  // 模拟鼠标移动（贝塞尔曲线）
  Future<void> simulateMouseMove(Page page, Point from, Point to);
  
  // 模拟人类输入（随机延迟）
  Future<void> typeLikeHuman(Page page, String selector, String text);
  
  // 模拟滚动（随机速度和停顿）
  Future<void> simulateScroll(Page page);
  
  // 随机等待（避免固定延迟）
  Future<void> randomWait({int minMs = 500, int maxMs = 2000});
}
```

#### 3.2.4 错误处理器 (ErrorHandler)
**职责：**
- 识别Cookie过期错误
- 识别风控拦截
- 错误日志记录
- 错误恢复策略

**实现要点：**
```dart
class ErrorHandler {
  // 错误类型枚举
  enum ScraperError {
    cookieExpired,
    antiBotDetected,
    networkError,
    timeout,
    unknown
  }
  
  // 识别错误类型
  ScraperError identifyError(dynamic error, Page page);
  
  // 记录错误日志
  Future<void> logError(ScraperError error, String details);
  
  // 通知后端
  Future<void> notifyBackend(ScraperError error);
}
```

---

## 4. 核心实现细节

### 4.1 反检测策略

#### 4.1.1 Playwright Stealth配置
```dart
Future<Browser> createStealthBrowser() async {
  final browser = await playwright.chromium.launch(
    headless: false,  // 有头模式更不容易被检测
    args: [
      '--disable-blink-features=AutomationControlled',
      '--disable-dev-shm-usage',
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-web-security',
      '--disable-features=IsolateOrigins,site-per-process',
    ],
  );
  
  final context = await browser.newContext(
    viewport: Viewport(width: 1920, height: 1080),
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    locale: 'zh-CN',
    timezoneId: 'Asia/Shanghai',
    permissions: ['geolocation'],
    geolocation: Geolocation(latitude: 39.9042, longitude: 116.4074), // 北京
    extraHTTPHeaders: {
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
      'Accept-Encoding': 'gzip, deflate, br',
      'Connection': 'keep-alive',
      'Upgrade-Insecure-Requests': '1',
    },
  );
  
  // 注入反检测脚本
  await context.addInitScript('''
    Object.defineProperty(navigator, 'webdriver', {
      get: () => undefined
    });
    
    window.chrome = {
      runtime: {}
    };
    
    Object.defineProperty(navigator, 'plugins', {
      get: () => [1, 2, 3, 4, 5]
    });
    
    Object.defineProperty(navigator, 'languages', {
      get: () => ['zh-CN', 'zh', 'en']
    });
  ''');
  
  return browser;
}
```

#### 4.1.2 指纹随机化
```dart
class FingerprintRandomizer {
  static List<String> getUserAgents() {
    return [
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    ];
  }
  
  static Viewport getRandomViewport() {
    final viewports = [
      Viewport(width: 1920, height: 1080),
      Viewport(width: 1366, height: 768),
      Viewport(width: 1536, height: 864),
    ];
    return viewports[Random().nextInt(viewports.length)];
  }
}
```

### 4.2 商品信息获取流程

#### 4.2.1 单商品获取流程
```dart
Future<Map<String, dynamic>> getProductInfo(String skuId) async {
  final browser = await browserPool.acquire();
  Page? page;
  
  try {
    page = await browser.newPage();
    
    // 1. 设置Cookie
    await setCookies(page);
    
    // 2. 访问商品页面（使用联盟链接）
    final url = 'https://union.jd.com/proManager/custompromotion';
    await page.goto(url, wait: WaitUntilState.networkIdle);
    
    // 3. 检测是否需要登录
    if (await isLoginRequired(page)) {
      throw ScraperException('Cookie expired, login required');
    }
    
    // 4. 模拟人类行为：随机滚动
    await humanBehavior.simulateScroll(page);
    await humanBehavior.randomWait(minMs: 800, maxMs: 1500);
    
    // 5. 输入商品ID
    final inputSelector = 'div.el-textarea textarea';
    await page.waitForSelector(inputSelector);
    await humanBehavior.typeLikeHuman(page, inputSelector, skuId);
    await humanBehavior.randomWait(minMs: 500, maxMs: 1000);
    
    // 6. 点击搜索按钮（模拟鼠标移动+点击）
    final buttonSelector = '.superBtn button.el-button--primary';
    final button = await page.querySelector(buttonSelector);
    if (button != null) {
      final box = await button.boundingBox;
      if (box != null) {
        await humanBehavior.simulateMouseMove(
          page,
          Point(x: box.x + box.width / 2, y: box.y + box.height / 2),
        );
        await humanBehavior.randomWait(minMs: 200, maxMs: 500);
        await button.click();
      }
    }
    
    // 7. 等待结果加载
    await page.waitForSelector('.result-text', timeout: 15000);
    await humanBehavior.randomWait(minMs: 1000, maxMs: 2000);
    
    // 8. 提取商品信息
    final productInfo = await extractProductInfo(page);
    
    return productInfo;
    
  } catch (e) {
    await errorHandler.handleError(e, page);
    rethrow;
  } finally {
    if (page != null) await page.close();
    browserPool.release(browser);
  }
}
```

#### 4.2.2 批量商品获取（并发控制）
```dart
Future<List<Map<String, dynamic>>> getBatchProductInfo(
  List<String> skuIds, {
  int maxConcurrency = 3,
}) async {
  final semaphore = Semaphore(maxConcurrency);
  final results = <Map<String, dynamic>>[];
  
  await Future.wait(
    skuIds.map((skuId) async {
      await semaphore.acquire();
      try {
        final info = await getProductInfo(skuId);
        results.add(info);
      } catch (e) {
        // 记录错误但继续处理其他商品
        await errorHandler.logError(e, skuId);
      } finally {
        semaphore.release();
      }
    }),
  );
  
  return results;
}
```

### 4.3 Cookie过期检测

#### 4.3.1 检测机制
```dart
Future<bool> checkCookieExpired(Page page) async {
  try {
    // 访问联盟首页
    await page.goto('https://union.jd.com/', wait: WaitUntilState.domContentLoaded);
    
    // 检查是否跳转到登录页
    final url = page.url;
    if (url.contains('passport.jd.com') || url.contains('login')) {
      return true;
    }
    
    // 检查页面元素（登录按钮、用户名等）
    final loginButton = await page.querySelector('.login-btn');
    final userName = await page.querySelector('.user-name');
    
    if (loginButton != null || userName == null) {
      return true;
    }
    
    // 检查是否有"请登录"提示
    final content = await page.textContent('body');
    if (content?.contains('请登录') == true || 
        content?.contains('登录') == true) {
      return true;
    }
    
    return false;
  } catch (e) {
    // 如果访问失败，假设Cookie可能过期
    return true;
  }
}
```

#### 4.3.2 Cookie更新流程
```dart
Future<void> refreshCookie() async {
  // 1. 通知后端需要更新Cookie
  await errorHandler.notifyBackend(
    ScraperError.cookieExpired,
    'Cookie expired, manual login required',
  );
  
  // 2. 启动有头浏览器供用户手动登录
  final browser = await createStealthBrowser();
  final page = await browser.newPage();
  
  await page.goto('https://union.jd.com/');
  
  // 3. 等待用户登录（轮询检测）
  await waitForUserLogin(page, timeout: Duration(minutes: 5));
  
  // 4. 提取Cookie
  final cookies = await page.context.cookies();
  final cookieString = cookies.map((c) => '${c.name}=${c.value}').join('; ');
  
  // 5. 保存Cookie
  await cookieManager.saveCookie(cookieString);
  
  await browser.close();
}

Future<void> waitForUserLogin(Page page, {required Duration timeout}) async {
  final startTime = DateTime.now();
  
  while (DateTime.now().difference(startTime) < timeout) {
    await Future.delayed(Duration(seconds: 2));
    
    final url = page.url;
    if (!url.contains('login') && !url.contains('passport')) {
      // 检查是否已登录
      final userName = await page.querySelector('.user-name');
      if (userName != null) {
        return;
      }
    }
  }
  
  throw TimeoutException('User login timeout');
}
```

### 4.4 性能优化

#### 4.4.1 缓存策略
```dart
class ProductCache {
  final Map<String, CacheEntry> _cache = {};
  final Duration cacheDuration = Duration(minutes: 10);
  
  Future<Map<String, dynamic>?> get(String skuId) async {
    final entry = _cache[skuId];
    if (entry != null && !entry.isExpired) {
      return entry.data;
    }
    return null;
  }
  
  void set(String skuId, Map<String, dynamic> data) {
    _cache[skuId] = CacheEntry(
      data: data,
      expiryTime: DateTime.now().add(cacheDuration),
    );
  }
}

class CacheEntry {
  final Map<String, dynamic> data;
  final DateTime expiryTime;
  
  bool get isExpired => DateTime.now().isAfter(expiryTime);
}
```

#### 4.4.2 请求去重
```dart
class RequestDeduplicator {
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  
  Future<Map<String, dynamic>> getProductInfo(String skuId) async {
    // 如果已有相同请求在进行，等待其结果
    if (_pending.containsKey(skuId)) {
      return await _pending[skuId]!.future;
    }
    
    final completer = Completer<Map<String, dynamic>>();
    _pending[skuId] = completer;
    
    try {
      final result = await _fetchProductInfo(skuId);
      completer.complete(result);
      return result;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _pending.remove(skuId);
    }
  }
}
```

---

## 5. 开发路线图

### 阶段1：基础框架搭建（1-2周）
- [ ] 搭建Playwright环境
- [ ] 实现Cookie管理器
- [ ] 实现浏览器池管理器
- [ ] 实现基础的商品信息获取功能

### 阶段2：反检测机制（1周）
- [ ] 实现Stealth模式配置
- [ ] 实现指纹随机化
- [ ] 实现人类行为模拟器
- [ ] 测试反检测效果

### 阶段3：错误处理与恢复（1周）
- [ ] 实现Cookie过期检测
- [ ] 实现错误分类和日志记录
- [ ] 实现Cookie刷新流程
- [ ] 实现手动登录界面

### 阶段4：性能优化（1周）
- [ ] 实现缓存机制
- [ ] 实现请求去重
- [ ] 优化并发控制
- [ ] 性能测试和调优

### 阶段5：集成与测试（1周）
- [ ] 与现有后端集成
- [ ] 端到端测试
- [ ] 压力测试
- [ ] 文档编写

---

## 6. 文件结构

```
server/
├── bin/
│   ├── proxy_server.dart          # 主服务器
│   └── jd_scraper_service.dart    # 爬虫服务入口
├── lib/
│   └── jd_scraper/
│       ├── jd_scraper_service.dart        # 主服务类
│       ├── cookie_manager.dart            # Cookie管理
│       ├── browser_pool.dart              # 浏览器池管理
│       ├── human_behavior_simulator.dart  # 人类行为模拟
│       ├── error_handler.dart             # 错误处理
│       ├── fingerprint_randomizer.dart    # 指纹随机化
│       ├── product_extractor.dart         # 商品信息提取
│       ├── cache_manager.dart             # 缓存管理
│       └── models/
│           ├── product_info.dart          # 商品信息模型
│           ├── scraper_error.dart        # 错误类型定义
│           └── cookie_data.dart           # Cookie数据模型
├── data/
│   ├── jd_cookies.json            # Cookie存储文件
│   └── scraper_logs/              # 日志目录
└── test/
    └── jd_scraper/
        ├── cookie_manager_test.dart
        ├── browser_pool_test.dart
        └── integration_test.dart
```

---

## 7. API接口设计

### 7.1 爬虫服务API

#### 7.1.1 获取单个商品信息
```dart
// GET /api/jd/product/:skuId
// 或 POST /api/jd/product
// Body: { "skuId": "10183999034312" }

Response:
{
  "success": true,
  "data": {
    "skuId": "10183999034312",
    "title": "lotoo 乐图PAW S2小尾巴支持...",
    "price": 900.0,
    "originalPrice": 900.0,
    "commission": 45.0,
    "commissionRate": 0.05,
    "imageUrl": "https://...",
    "shopName": "lotoo数码官方旗舰店",
    "promotionLink": "https://...",
    "cached": false,
    "fetchTime": "2024-01-15T10:30:00Z"
  },
  "error": null
}
```

#### 7.1.2 批量获取商品信息
```dart
// POST /api/jd/products/batch
// Body: { "skuIds": ["10183999034312", "10089387665015"] }

Response:
{
  "success": true,
  "data": [
    { /* 商品1信息 */ },
    { /* 商品2信息 */ }
  ],
  "errors": [
    {
      "skuId": "invalid_id",
      "error": "Product not found"
    }
  ]
}
```

#### 7.1.3 Cookie管理接口
```dart
// GET /api/jd/cookie/status
// 检查Cookie状态

Response:
{
  "valid": true,
  "expiresAt": "2024-01-20T10:30:00Z",
  "lastChecked": "2024-01-15T10:30:00Z"
}

// POST /api/jd/cookie/update
// 更新Cookie（需要管理员权限）
// Body: { "cookie": "..." }

// POST /api/jd/cookie/refresh
// 触发手动登录流程
```

#### 7.1.4 错误日志查询
```dart
// GET /api/jd/errors?limit=100&type=cookieExpired
// 查询错误日志

Response:
{
  "errors": [
    {
      "id": "error_001",
      "type": "cookieExpired",
      "message": "Cookie expired, login required",
      "timestamp": "2024-01-15T10:30:00Z",
      "details": {}
    }
  ],
  "total": 1
}
```

### 7.2 与现有后端集成

在 `proxy_server.dart` 中添加路由：

```dart
// 在 proxy_server.dart 中添加
router.post('/api/jd/product', (Request request) async {
  final body = await request.readAsString();
  final data = jsonDecode(body);
  final skuId = data['skuId'] as String;
  
  try {
    final scraperService = JdScraperService.instance;
    final productInfo = await scraperService.getProductInfo(skuId);
    
    return Response.ok(
      jsonEncode({
        'success': true,
        'data': productInfo,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({
        'success': false,
        'error': e.toString(),
      }),
    );
  }
});
```

---

## 8. 详细实现代码示例

### 8.1 人类行为模拟器完整实现

```dart
import 'dart:math';
import 'package:playwright/playwright.dart';

class HumanBehaviorSimulator {
  final Random _random = Random();
  
  /// 模拟人类鼠标移动（贝塞尔曲线轨迹）
  Future<void> simulateMouseMove(
    Page page,
    Point from,
    Point to,
  ) async {
    final steps = 20 + _random.nextInt(10); // 20-30步
    final controlPoint1 = Point(
      x: from.x + (to.x - from.x) * (0.3 + _random.nextDouble() * 0.4),
      y: from.y + (to.y - from.y) * (0.3 + _random.nextDouble() * 0.4),
    );
    final controlPoint2 = Point(
      x: from.x + (to.x - from.x) * (0.6 + _random.nextDouble() * 0.2),
      y: from.y + (to.y - from.y) * (0.6 + _random.nextDouble() * 0.2),
    );
    
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final point = _bezierPoint(from, controlPoint1, controlPoint2, to, t);
      
      await page.mouse.move(point.x, point.y);
      await Future.delayed(Duration(milliseconds: 5 + _random.nextInt(10)));
    }
  }
  
  Point _bezierPoint(Point p0, Point p1, Point p2, Point p3, double t) {
    final u = 1 - t;
    final tt = t * t;
    final uu = u * u;
    final uuu = uu * u;
    final ttt = tt * t;
    
    return Point(
      x: (uuu * p0.x) + (3 * uu * t * p1.x) + (3 * u * tt * p2.x) + (ttt * p3.x),
      y: (uuu * p0.y) + (3 * uu * t * p1.y) + (3 * u * tt * p2.y) + (ttt * p3.y),
    );
  }
  
  /// 模拟人类输入（随机延迟）
  Future<void> typeLikeHuman(
    Page page,
    String selector,
    String text,
  ) async {
    final input = await page.locator(selector);
    await input.click();
    await randomWait(minMs: 100, maxMs: 300);
    
    for (int i = 0; i < text.length; i++) {
      await input.type(text[i], delay: Duration(
        milliseconds: 50 + _random.nextInt(150),
      ));
      
      // 偶尔暂停（模拟思考）
      if (_random.nextDouble() < 0.1) {
        await randomWait(minMs: 200, maxMs: 800);
      }
    }
  }
  
  /// 模拟滚动行为
  Future<void> simulateScroll(Page page) async {
    final scrollCount = 2 + _random.nextInt(3); // 2-4次滚动
    
    for (int i = 0; i < scrollCount; i++) {
      final scrollAmount = 200 + _random.nextInt(400);
      final scrollDirection = _random.nextBool() ? 1 : -1;
      
      await page.evaluate('''
        window.scrollBy({
          top: $scrollAmount * $scrollDirection,
          behavior: 'smooth'
        });
      ''');
      
      await randomWait(minMs: 300, maxMs: 800);
    }
  }
  
  /// 随机等待
  Future<void> randomWait({
    int minMs = 500,
    int maxMs = 2000,
  }) async {
    final delay = minMs + _random.nextInt(maxMs - minMs);
    await Future.delayed(Duration(milliseconds: delay));
  }
  
  /// 模拟点击前的犹豫（鼠标悬停）
  Future<void> hoverBeforeClick(Page page, String selector) async {
    final element = await page.locator(selector);
    final box = await element.boundingBox();
    
    if (box != null) {
      final centerX = box.x + box.width / 2;
      final centerY = box.y + box.height / 2;
      
      // 移动到元素附近
      await page.mouse.move(
        centerX + (_random.nextDouble() - 0.5) * 20,
        centerY + (_random.nextDouble() - 0.5) * 20,
      );
      
      await randomWait(minMs: 200, maxMs: 600);
      
      // 移动到元素中心
      await simulateMouseMove(
        page,
        Point(x: page.mouse.x, y: page.mouse.y),
        Point(x: centerX, y: centerY),
      );
      
      await randomWait(minMs: 100, maxMs: 300);
    }
  }
}

class Point {
  final double x;
  final double y;
  
  Point({required this.x, required this.y});
}
```

### 8.2 Cookie管理器完整实现

```dart
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:playwright/playwright.dart';

class CookieManager {
  static const String cookiePath = 'data/jd_cookies.json';
  static const String cookieBackupPath = 'data/jd_cookies_backup.json';
  
  /// 加载Cookie
  Future<String?> loadCookie() async {
    try {
      final file = File(cookiePath);
      if (!await file.exists()) {
        return null;
      }
      
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      
      return data['cookie'] as String?;
    } catch (e) {
      print('[CookieManager] Error loading cookie: $e');
      return null;
    }
  }
  
  /// 保存Cookie
  Future<void> saveCookie(String cookie) async {
    try {
      // 创建目录
      final dir = Directory(path.dirname(cookiePath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // 备份旧Cookie
      final oldFile = File(cookiePath);
      if (await oldFile.exists()) {
        await oldFile.copy(cookieBackupPath);
      }
      
      // 保存新Cookie
      final data = {
        'cookie': cookie,
        'savedAt': DateTime.now().toIso8601String(),
        'expiresAt': _estimateExpiry(),
      };
      
      await File(cookiePath).writeAsString(
        jsonEncode(data),
        encoding: utf8,
      );
      
      print('[CookieManager] Cookie saved successfully');
    } catch (e) {
      print('[CookieManager] Error saving cookie: $e');
      rethrow;
    }
  }
  
  /// 检测Cookie是否过期
  Future<bool> checkCookieExpired(Page page) async {
    try {
      // 访问联盟首页
      await page.goto(
        'https://union.jd.com/',
        waitUntil: WaitUntilState.domContentLoaded,
      );
      
      await Future.delayed(Duration(seconds: 2));
      
      // 检查URL
      final url = page.url;
      if (url.contains('passport.jd.com') || 
          url.contains('login') ||
          url.contains('auth')) {
        return true;
      }
      
      // 检查页面内容
      final bodyText = await page.textContent('body') ?? '';
      if (bodyText.contains('请登录') || 
          bodyText.contains('登录') ||
          bodyText.contains('未登录')) {
        return true;
      }
      
      // 检查关键元素
      final loginButton = await page.locator('.login-btn, .btn-login').count();
      final userName = await page.locator('.user-name, .username').count();
      
      if (loginButton > 0 || userName == 0) {
        return true;
      }
      
      return false;
    } catch (e) {
      print('[CookieManager] Error checking cookie: $e');
      // 出错时假设Cookie可能过期
      return true;
    }
  }
  
  /// 设置Cookie到页面
  Future<void> setCookies(Page page, String cookieString) async {
    try {
      final cookies = _parseCookieString(cookieString);
      
      await page.context.addCookies(cookies.map((c) => Cookie(
        name: c['name'] as String,
        value: c['value'] as String,
        domain: c['domain'] as String? ?? '.jd.com',
        path: c['path'] as String? ?? '/',
        expires: c['expires'] as double?,
        httpOnly: c['httpOnly'] as bool? ?? false,
        secure: c['secure'] as bool? ?? true,
        sameSite: SameSite.lax,
      )).toList());
      
      print('[CookieManager] Cookies set successfully');
    } catch (e) {
      print('[CookieManager] Error setting cookies: $e');
      rethrow;
    }
  }
  
  List<Map<String, dynamic>> _parseCookieString(String cookieString) {
    final cookies = <Map<String, dynamic>>[];
    
    for (final part in cookieString.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      
      final equalIndex = trimmed.indexOf('=');
      if (equalIndex == -1) continue;
      
      final name = trimmed.substring(0, equalIndex).trim();
      final value = trimmed.substring(equalIndex + 1).trim();
      
      cookies.add({
        'name': name,
        'value': value,
        'domain': '.jd.com',
        'path': '/',
      });
    }
    
    return cookies;
  }
  
  String _estimateExpiry() {
    // 京东Cookie通常有效期7-30天，这里估计14天
    return DateTime.now().add(Duration(days: 14)).toIso8601String();
  }
}
```

### 8.3 浏览器池管理器完整实现

```dart
import 'dart:async';
import 'dart:collection';
import 'package:playwright/playwright.dart';

class BrowserPool {
  final int maxBrowsers;
  final List<BrowserInstance> _browsers = [];
  final Queue<Completer<Browser>> _waitingQueue = Queue();
  final Duration browserTimeout;
  
  BrowserPool({
    this.maxBrowsers = 3,
    this.browserTimeout = const Duration(minutes: 30),
  });
  
  /// 获取浏览器实例
  Future<Browser> acquire() async {
    // 清理过期浏览器
    _cleanupExpiredBrowsers();
    
    // 查找可用浏览器
    for (final instance in _browsers) {
      if (instance.isAvailable) {
        instance.markInUse();
        return instance.browser;
      }
    }
    
    // 如果未达到上限，创建新浏览器
    if (_browsers.length < maxBrowsers) {
      final browser = await _createBrowser();
      final instance = BrowserInstance(browser, browserTimeout);
      instance.markInUse();
      _browsers.add(instance);
      return browser;
    }
    
    // 等待可用浏览器
    final completer = Completer<Browser>();
    _waitingQueue.add(completer);
    return completer.future;
  }
  
  /// 释放浏览器实例
  void release(Browser browser) {
    final instance = _browsers.firstWhere(
      (b) => b.browser == browser,
      orElse: () => throw StateError('Browser not found in pool'),
    );
    
    instance.markAvailable();
    
    // 如果有等待的请求，分配浏览器
    if (_waitingQueue.isNotEmpty) {
      final completer = _waitingQueue.removeFirst();
      instance.markInUse();
      completer.complete(browser);
    }
  }
  
  /// 创建浏览器
  Future<Browser> _createBrowser() async {
    final playwright = await Playwright.create();
    return await playwright.chromium.launch(
      headless: false,
      args: [
        '--disable-blink-features=AutomationControlled',
        '--disable-dev-shm-usage',
        '--no-sandbox',
      ],
    );
  }
  
  /// 清理过期浏览器
  void _cleanupExpiredBrowsers() {
    _browsers.removeWhere((instance) {
      if (instance.isExpired) {
        try {
          instance.browser.close();
        } catch (e) {
          print('[BrowserPool] Error closing expired browser: $e');
        }
        return true;
      }
      return false;
    });
  }
  
  /// 关闭所有浏览器
  Future<void> closeAll() async {
    for (final instance in _browsers) {
      try {
        await instance.browser.close();
      } catch (e) {
        print('[BrowserPool] Error closing browser: $e');
      }
    }
    _browsers.clear();
  }
}

class BrowserInstance {
  final Browser browser;
  final Duration timeout;
  DateTime? _lastUsed;
  bool _inUse = false;
  
  BrowserInstance(this.browser, this.timeout) {
    _lastUsed = DateTime.now();
  }
  
  bool get isAvailable => !_inUse && !isExpired;
  bool get isExpired {
    if (_lastUsed == null) return true;
    return DateTime.now().difference(_lastUsed!) > timeout;
  }
  
  void markInUse() {
    _inUse = true;
    _lastUsed = DateTime.now();
  }
  
  void markAvailable() {
    _inUse = false;
    _lastUsed = DateTime.now();
  }
}
```

---

## 9. 配置管理

### 9.1 配置文件结构

创建 `server/config/jd_scraper_config.yaml`:

```yaml
jd_scraper:
  # 浏览器配置
  browser:
    headless: false  # 生产环境可设为true
    max_browsers: 3
    browser_timeout_minutes: 30
    
  # Cookie配置
  cookie:
    storage_path: "data/jd_cookies.json"
    check_interval_minutes: 60
    auto_refresh: true
    
  # 行为模拟配置
  behavior:
    min_wait_ms: 500
    max_wait_ms: 2000
    enable_mouse_simulation: true
    enable_scroll_simulation: true
    
  # 性能配置
  performance:
    cache_duration_minutes: 10
    max_concurrent_requests: 3
    request_timeout_seconds: 30
    
  # 错误处理配置
  error_handling:
    max_retries: 3
    retry_delay_seconds: 5
    log_errors: true
    notify_on_cookie_expired: true
```

### 9.2 环境变量

```bash
# .env 文件
JD_SCRAPER_HEADLESS=false
JD_SCRAPER_MAX_BROWSERS=3
JD_SCRAPER_COOKIE_PATH=data/jd_cookies.json
JD_SCRAPER_LOG_LEVEL=info
```

---

## 10. 监控与日志

### 10.1 日志系统

```dart
enum LogLevel { debug, info, warning, error }

class ScraperLogger {
  final String logDir = 'data/scraper_logs';
  final LogLevel minLevel;
  
  ScraperLogger({this.minLevel = LogLevel.info}) {
    _ensureLogDirectory();
  }
  
  void _ensureLogDirectory() {
    final dir = Directory(logDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }
  
  void log(LogLevel level, String message, {Map<String, dynamic>? context}) {
    if (level.index < minLevel.index) return;
    
    final timestamp = DateTime.now().toIso8601String();
    final logEntry = {
      'timestamp': timestamp,
      'level': level.name,
      'message': message,
      if (context != null) 'context': context,
    };
    
    // 控制台输出
    print('[${level.name.toUpperCase()}] $timestamp: $message');
    
    // 文件输出
    final logFile = File('$logDir/scraper_${DateTime.now().toIso8601String().split('T')[0]}.log');
    logFile.writeAsStringSync(
      jsonEncode(logEntry) + '\n',
      mode: FileMode.append,
    );
  }
  
  void debug(String message, {Map<String, dynamic>? context}) =>
      log(LogLevel.debug, message, context: context);
  
  void info(String message, {Map<String, dynamic>? context}) =>
      log(LogLevel.info, message, context: context);
  
  void warning(String message, {Map<String, dynamic>? context}) =>
      log(LogLevel.warning, message, context: context);
  
  void error(String message, {Map<String, dynamic>? context, Object? error}) {
    final errorContext = {
      if (context != null) ...context,
      if (error != null) 'error': error.toString(),
      if (error is Exception) 'stackTrace': error.toString(),
    };
    log(LogLevel.error, message, context: errorContext);
  }
}
```

### 10.2 错误日志记录

```dart
class ErrorLogger {
  final ScraperLogger logger;
  final List<ErrorEntry> _errors = [];
  final int maxErrors = 1000;
  
  ErrorLogger(this.logger);
  
  Future<void> logError(
    ScraperError type,
    String message, {
    String? skuId,
    Map<String, dynamic>? details,
  }) async {
    final error = ErrorEntry(
      id: _generateErrorId(),
      type: type,
      message: message,
      skuId: skuId,
      timestamp: DateTime.now(),
      details: details ?? {},
    );
    
    _errors.add(error);
    if (_errors.length > maxErrors) {
      _errors.removeAt(0);
    }
    
    logger.error(
      'Scraper error: ${type.name} - $message',
      context: {
        'errorId': error.id,
        'skuId': skuId,
        'details': details,
      },
    );
    
    // 如果是Cookie过期，通知后端
    if (type == ScraperError.cookieExpired) {
      await _notifyBackend(error);
    }
  }
  
  List<ErrorEntry> getErrors({
    ScraperError? type,
    int? limit,
    DateTime? since,
  }) {
    var errors = _errors;
    
    if (type != null) {
      errors = errors.where((e) => e.type == type).toList();
    }
    
    if (since != null) {
      errors = errors.where((e) => e.timestamp.isAfter(since)).toList();
    }
    
    errors.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    if (limit != null) {
      errors = errors.take(limit).toList();
    }
    
    return errors;
  }
  
  Future<void> _notifyBackend(ErrorEntry error) async {
    try {
      final client = http.Client();
      await client.post(
        Uri.parse('http://localhost:9527/api/jd/errors'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'errorId': error.id,
          'type': error.type.name,
          'message': error.message,
          'timestamp': error.timestamp.toIso8601String(),
          'details': error.details,
        }),
      );
    } catch (e) {
      logger.warning('Failed to notify backend of error: $e');
    }
  }
  
  String _generateErrorId() {
    return 'error_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';
  }
}

class ErrorEntry {
  final String id;
  final ScraperError type;
  final String message;
  final String? skuId;
  final DateTime timestamp;
  final Map<String, dynamic> details;
  
  ErrorEntry({
    required this.id,
    required this.type,
    required this.message,
    this.skuId,
    required this.timestamp,
    required this.details,
  });
}
```

### 10.3 性能监控

```dart
class PerformanceMonitor {
  final Map<String, List<Duration>> _requestDurations = {};
  final Map<String, int> _requestCounts = {};
  final Map<String, int> _errorCounts = {};
  
  void recordRequest(String endpoint, Duration duration) {
    _requestDurations.putIfAbsent(endpoint, () => []).add(duration);
    _requestCounts[endpoint] = (_requestCounts[endpoint] ?? 0) + 1;
    
    // 只保留最近1000次请求的时长
    if (_requestDurations[endpoint]!.length > 1000) {
      _requestDurations[endpoint]!.removeAt(0);
    }
  }
  
  void recordError(String endpoint) {
    _errorCounts[endpoint] = (_errorCounts[endpoint] ?? 0) + 1;
  }
  
  Map<String, dynamic> getStats(String endpoint) {
    final durations = _requestDurations[endpoint] ?? [];
    if (durations.isEmpty) {
      return {
        'endpoint': endpoint,
        'count': 0,
        'avgDuration': 0,
        'minDuration': 0,
        'maxDuration': 0,
        'errorCount': _errorCounts[endpoint] ?? 0,
      };
    }
    
    durations.sort();
    final sum = durations.fold<int>(0, (sum, d) => sum + d.inMilliseconds);
    
    return {
      'endpoint': endpoint,
      'count': durations.length,
      'avgDuration': (sum / durations.length).round(),
      'minDuration': durations.first.inMilliseconds,
      'maxDuration': durations.last.inMilliseconds,
      'p50': durations[durations.length ~/ 2].inMilliseconds,
      'p95': durations[(durations.length * 0.95).round()].inMilliseconds,
      'p99': durations[(durations.length * 0.99).round()].inMilliseconds,
      'errorCount': _errorCounts[endpoint] ?? 0,
      'errorRate': (_errorCounts[endpoint] ?? 0) / durations.length,
    };
  }
  
  Map<String, dynamic> getAllStats() {
    final endpoints = {
      ..._requestDurations.keys,
      ..._requestCounts.keys,
      ..._errorCounts.keys,
    };
    
    return {
      'endpoints': endpoints.map((e) => getStats(e)).toList(),
      'totalRequests': _requestCounts.values.fold<int>(0, (sum, c) => sum + c),
      'totalErrors': _errorCounts.values.fold<int>(0, (sum, c) => sum + c),
    };
  }
}
```

---

## 11. 测试策略

### 11.1 单元测试

```dart
// test/jd_scraper/cookie_manager_test.dart
void main() {
  group('CookieManager', () {
    late CookieManager cookieManager;
    late Directory tempDir;
    
    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('cookie_test_');
      cookieManager = CookieManager(
        cookiePath: '${tempDir.path}/cookies.json',
      );
    });
    
    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });
    
    test('should save and load cookie', () async {
      const testCookie = 'test_cookie=value123; another=value456';
      
      await cookieManager.saveCookie(testCookie);
      final loaded = await cookieManager.loadCookie();
      
      expect(loaded, equals(testCookie));
    });
    
    test('should return null if cookie file does not exist', () async {
      final loaded = await cookieManager.loadCookie();
      expect(loaded, isNull);
    });
  });
}
```

### 11.2 集成测试

```dart
// test/jd_scraper/integration_test.dart
void main() {
  group('JdScraperService Integration', () {
    late JdScraperService scraperService;
    
    setUp(() {
      scraperService = JdScraperService.instance;
    });
    
    test('should fetch product info for valid SKU', () async {
      // 注意：需要有效的Cookie才能运行
      final productInfo = await scraperService.getProductInfo('10183999034312');
      
      expect(productInfo, isNotNull);
      expect(productInfo['skuId'], isNotEmpty);
      expect(productInfo['price'], greaterThan(0));
    }, skip: 'Requires valid cookie');
    
    test('should handle cookie expiration', () async {
      // 模拟Cookie过期场景
      await expectLater(
        scraperService.getProductInfo('10183999034312'),
        throwsA(isA<ScraperException>()),
      );
    });
  });
}
```

### 11.3 性能测试

```dart
// test/jd_scraper/performance_test.dart
void main() {
  group('Performance Tests', () {
    test('should handle concurrent requests', () async {
      final scraperService = JdScraperService.instance;
      final skuIds = List.generate(10, (i) => '1018399903431$i');
      
      final stopwatch = Stopwatch()..start();
      final results = await scraperService.getBatchProductInfo(skuIds);
      stopwatch.stop();
      
      expect(results.length, greaterThan(0));
      expect(stopwatch.elapsed.inSeconds, lessThan(60)); // 应在60秒内完成
    });
  });
}
```

---

## 12. 部署指南

### 12.1 环境要求

- **操作系统**: Windows 10+, Linux, macOS
- **Dart SDK**: >= 2.18.0
- **Playwright**: 需要安装浏览器驱动
  ```bash
  dart pub global activate playwright_dart
  playwright install chromium
  ```

### 12.2 安装步骤

1. **安装依赖**
   ```bash
   cd server
   dart pub get
   ```

2. **配置Cookie**
   - 首次运行需要手动登录获取Cookie
   - 或通过API接口更新Cookie

3. **启动服务**
   ```bash
   dart bin/proxy_server.dart
   ```

### 12.3 Docker部署

```dockerfile
# server/Dockerfile.scraper
FROM dart:stable AS build

WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

COPY . .
RUN dart pub get

FROM dart:stable
WORKDIR /app

# 安装Playwright
RUN apt-get update && apt-get install -y \
    libnss3 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libasound2

COPY --from=build /app /app
RUN dart pub global activate playwright_dart
RUN playwright install chromium

CMD ["dart", "bin/proxy_server.dart"]
```

### 12.4 系统服务配置（Linux）

```ini
# /etc/systemd/system/jd-scraper.service
[Unit]
Description=JD Union Scraper Service
After=network.target

[Service]
Type=simple
User=your-user
WorkingDirectory=/path/to/server
ExecStart=/usr/bin/dart bin/proxy_server.dart
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

---

## 13. 常见问题与解决方案

### 13.1 Cookie频繁过期

**问题**: Cookie在短时间内频繁过期

**解决方案**:
1. 检查Cookie是否完整（包含所有必要的字段）
2. 减少请求频率，避免触发风控
3. 使用有头浏览器模式，降低被检测概率
4. 增加随机等待时间

### 13.2 被风控系统拦截

**问题**: 访问时被提示"访问过于频繁"或需要验证码

**解决方案**:
1. 降低并发数（maxConcurrency = 1-2）
2. 增加请求间隔时间
3. 使用不同的User-Agent和指纹
4. 考虑使用代理IP（需要额外实现）

### 13.3 浏览器实例占用内存过高

**问题**: 长时间运行后内存占用持续增长

**解决方案**:
1. 定期重启浏览器实例（设置browserTimeout）
2. 限制浏览器池大小
3. 及时关闭不用的页面
4. 监控内存使用，超过阈值时重启

### 13.4 提取商品信息失败

**问题**: 无法正确提取商品价格或详情

**解决方案**:
1. 检查页面元素选择器是否仍然有效
2. 增加等待时间，确保页面完全加载
3. 添加多种提取策略（备用方案）
4. 记录失败页面截图，便于调试

---

## 14. 最佳实践

### 14.1 请求频率控制

- **单商品请求**: 间隔 1-3 秒
- **批量请求**: 并发数不超过 3
- **每日请求量**: 建议不超过 1000 次

### 14.2 Cookie管理

- **定期检查**: 每小时检查一次Cookie有效性
- **自动备份**: 更新Cookie前自动备份旧Cookie
- **多账号轮换**: 如有多个账号，可轮换使用

### 14.3 错误处理

- **重试机制**: 网络错误自动重试3次
- **降级策略**: 爬虫失败时回退到原有HTTP方式
- **监控告警**: Cookie过期时及时通知管理员

### 14.4 性能优化

- **缓存策略**: 商品信息缓存10分钟
- **请求去重**: 相同SKU的并发请求合并
- **浏览器复用**: 使用浏览器池避免频繁创建

---

## 15. 安全注意事项

### 15.1 Cookie安全

- **存储加密**: Cookie文件应加密存储
- **访问控制**: 限制Cookie文件的访问权限
- **定期更新**: 定期更换Cookie，避免长期使用

### 15.2 网络安全

- **HTTPS**: 所有请求使用HTTPS
- **证书验证**: 验证SSL证书有效性
- **敏感信息**: 不在日志中记录完整Cookie

### 15.3 合规性

- **遵守robots.txt**: 尊重网站的爬虫协议
- **合理使用**: 不进行恶意爬取或攻击
- **数据保护**: 妥善保管获取的数据

---

## 16. 未来可能优化方向

### 16.1 技术优化

- [ ] 使用机器学习优化行为模拟
- [ ] 支持分布式部署，横向扩展

### 16.2 功能扩展

- [ ] 支持自动爬取推广链接

### 16.3 监控增强

- [ ] 集成Prometheus监控指标
- [ ] 实现Grafana可视化面板
- [ ] 添加实时告警系统
- [ ] 支持日志聚合分析

---

## 17. 总结

本文档详细描述了京东联盟高级网页爬虫的完整设计方案，涵盖了从技术选型到具体实现的各个方面。

### 17.1 核心设计理念

本爬虫系统的设计遵循以下核心理念：

1. **人类行为模拟优先**: 通过精细的行为模拟（鼠标移动、滚动、输入延迟等）最大程度降低被风控系统检测的概率
2. **稳定性与效率平衡**: 在保证不被检测的前提下，通过浏览器池、缓存、请求去重等机制提升效率
3. **自动化与人工结合**: Cookie过期时自动检测并通知，支持管理员手动登录更新
4. **可观测性**: 完善的日志、监控和错误处理机制，便于问题定位和系统优化

### 17.2 技术亮点

- **Playwright + Dart**: 使用现代化的浏览器自动化工具，反检测能力强
- **浏览器池管理**: 复用浏览器实例，提升性能同时降低资源消耗
- **智能行为模拟**: 贝塞尔曲线鼠标移动、随机输入延迟、自然滚动等
- **完善的错误处理**: Cookie过期自动检测、错误分类、日志记录、后端通知
- **性能优化**: 多级缓存、请求去重、并发控制

### 17.3 关键成功因素

1. **Cookie管理**: 定期检查、自动备份、过期通知
2. **请求频率控制**: 合理的延迟和并发数，避免触发风控
3. **反检测策略**: Stealth模式、指纹随机化、人类行为模拟
4. **错误恢复**: 完善的错误处理和恢复机制
5. **监控告警**: 及时发现和处理问题

### 17.4 预期效果

- **成功率**: 在正常Cookie有效期内，商品信息获取成功率 > 95%
- **响应时间**: 单次商品信息获取 < 3秒（不含网络延迟）
- **稳定性**: 连续运行24小时无异常退出
- **风控规避**: 通过行为模拟和频率控制，显著降低被风控概率

### 17.5 实施建议

1. **分阶段实施**: 按照开发路线图分5个阶段逐步实现
2. **充分测试**: 每个阶段完成后进行充分测试，确保稳定性
3. **监控先行**: 部署后立即启用监控，及时发现问题
4. **持续优化**: 根据实际运行情况持续优化参数和策略
5. **文档维护**: 保持文档与代码同步更新

---

## 18. 参考资源

### 18.1 技术文档

- [Playwright Dart 官方文档](https://github.com/playwright-community/playwright-dart)
- [Dart 官方文档](https://dart.dev/)
- [京东联盟开放平台文档](https://union.jd.com/)
- [Shelf 框架文档](https://pub.dev/packages/shelf)

### 18.2 相关项目文档

- [后端架构文档](./backend-architecture.md) - 了解整体后端架构
- [产品需求文档](../PRD.md) - 了解业务需求
- [API 设计文档](./api-design.md) - 了解API接口设计

### 18.3 反爬虫技术参考

- [Playwright Stealth 插件](https://github.com/berstend/puppeteer-extra/tree/master/packages/puppeteer-extra-plugin-stealth)
- [浏览器指纹识别技术](https://github.com/fingerprintjs/fingerprintjs)
- [反爬虫对抗技术研究](https://github.com/topics/anti-scraping)

---

## 19. 术语表

| 术语 | 说明 |
|------|------|
| **SKU** | Stock Keeping Unit，商品库存单位，京东商品的唯一标识 |
| **Cookie** | 存储在浏览器中的用户认证信息，用于维持登录状态 |
| **Stealth模式** | 浏览器自动化工具的隐身模式，用于降低被检测概率 |
| **浏览器池** | 预先创建并复用的浏览器实例集合，用于提升性能 |
| **指纹识别** | 通过浏览器特征（User-Agent、屏幕分辨率等）识别设备的技术 |
| **风控系统** | 风险控制系统，用于检测和阻止异常访问行为 |
| **贝塞尔曲线** | 用于生成平滑曲线路径的数学曲线，常用于模拟鼠标移动 |
| **并发控制** | 通过信号量等机制限制同时进行的请求数量 |
| **请求去重** | 对相同请求进行合并，避免重复处理 |
| **降级策略** | 当主要方案失败时，回退到备用方案的策略 |

---

## 20. 版本历史

| 版本 | 日期 | 变更内容 | 作者 |
|------|------|----------|------|
| 1.0 | 2026-01 | 初始版本，完整设计文档 | AI Assistant |

---

## 21. 附录

### 21.1 完整依赖列表

```yaml
# server/pubspec.yaml
dependencies:
  shelf: ^1.4.0
  shelf_router: ^1.0.0
  http: ^0.13.0
  crypto: ^3.0.2
  playwright_dart: ^1.0.0  # 或 puppeteer: ^2.2.0
  path: ^1.8.0
  shared_preferences: ^2.0.0
```

### 21.2 环境变量完整列表

```bash
# 爬虫配置
JD_SCRAPER_HEADLESS=false
JD_SCRAPER_MAX_BROWSERS=3
JD_SCRAPER_COOKIE_PATH=data/jd_cookies.json
JD_SCRAPER_LOG_LEVEL=info

# 行为模拟配置
JD_SCRAPER_MIN_WAIT_MS=500
JD_SCRAPER_MAX_WAIT_MS=2000
JD_SCRAPER_ENABLE_MOUSE_SIMULATION=true
JD_SCRAPER_ENABLE_SCROLL_SIMULATION=true

# 性能配置
JD_SCRAPER_CACHE_DURATION_MINUTES=10
JD_SCRAPER_MAX_CONCURRENT_REQUESTS=3
JD_SCRAPER_REQUEST_TIMEOUT_SECONDS=30

# 错误处理配置
JD_SCRAPER_MAX_RETRIES=3
JD_SCRAPER_RETRY_DELAY_SECONDS=5
JD_SCRAPER_LOG_ERRORS=true
JD_SCRAPER_NOTIFY_ON_COOKIE_EXPIRED=true
```

### 21.3 快速开始检查清单

- [ ] 安装 Dart SDK (>= 2.18.0)
- [ ] 安装 Playwright 浏览器驱动
- [ ] 配置环境变量或创建 `.env` 文件
- [ ] 准备有效的京东联盟 Cookie
- [ ] 创建必要的目录结构（`data/`、`data/scraper_logs/`）
- [ ] 运行单元测试确保基础功能正常
- [ ] 进行小规模测试验证 Cookie 有效性
- [ ] 配置监控和日志系统
- [ ] 设置错误告警机制

### 21.4 常见问题快速参考

**Q: Cookie 多久会过期？**  
A: 京东联盟 Cookie 通常有效期 7-30 天，建议每天检查一次。

**Q: 如何判断被风控了？**  
A: 出现"访问过于频繁"提示、需要验证码、或频繁跳转到登录页。

**Q: 单次请求应该间隔多久？**  
A: 建议间隔 1-3 秒，批量请求时并发数不超过 3。

**Q: 如何更新 Cookie？**  
A: 调用 `/api/jd/cookie/refresh` 接口，或手动编辑 `data/jd_cookies.json` 文件。

**Q: 浏览器占用内存过高怎么办？**  
A: 降低 `max_browsers` 配置，或缩短 `browser_timeout_minutes`。

---

**文档维护者**: 开发团队  
**审核者**: 技术负责人  
**最后更新**: 2026-01

---

*本文档提供了京东联盟高级网页爬虫的完整设计方案，涵盖了技术选型、架构设计、实现细节、部署指南等各个方面，可作为开发团队的实施指南。*
import 'dart:math';

import 'package:puppeteer/puppeteer.dart';

/// 二维点类
class Point2D {
  final double x;
  final double y;

  const Point2D(this.x, this.y);

  @override
  String toString() => 'Point2D($x, $y)';
}

/// 人类行为模拟器配置
class BehaviorConfig {
  /// 最小等待时间（毫秒）
  final int minWaitMs;

  /// 最大等待时间（毫秒）
  final int maxWaitMs;

  /// 输入最小延迟（毫秒）
  final int minTypeDelayMs;

  /// 输入最大延迟（毫秒）
  final int maxTypeDelayMs;

  /// 鼠标移动步数范围
  final int minMouseSteps;
  final int maxMouseSteps;

  /// 滚动次数范围
  final int minScrollCount;
  final int maxScrollCount;

  /// 是否启用详细日志
  final bool verbose;

  const BehaviorConfig({
    this.minWaitMs = 500,
    this.maxWaitMs = 2000,
    this.minTypeDelayMs = 50,
    this.maxTypeDelayMs = 200,
    this.minMouseSteps = 20,
    this.maxMouseSteps = 30,
    this.minScrollCount = 2,
    this.maxScrollCount = 4,
    this.verbose = false,
  });

  /// 创建快速配置（用于测试）
  factory BehaviorConfig.fast() {
    return const BehaviorConfig(
      minWaitMs: 100,
      maxWaitMs: 300,
      minTypeDelayMs: 20,
      maxTypeDelayMs: 50,
      minMouseSteps: 10,
      maxMouseSteps: 15,
      minScrollCount: 1,
      maxScrollCount: 2,
    );
  }

  /// 创建自然配置（更像人类）
  factory BehaviorConfig.natural() {
    return const BehaviorConfig(
      minWaitMs: 800,
      maxWaitMs: 3000,
      minTypeDelayMs: 80,
      maxTypeDelayMs: 250,
      minMouseSteps: 25,
      maxMouseSteps: 40,
      minScrollCount: 2,
      maxScrollCount: 5,
      verbose: true,
    );
  }
}

/// 人类行为模拟器
///
/// 模拟真实人类的鼠标移动、输入、滚动等行为，
/// 用于避免被反爬虫系统检测
class HumanBehaviorSimulator {
  final Random _random = Random();
  final BehaviorConfig config;

  /// 当前鼠标位置
  Point2D _currentMousePosition = const Point2D(0, 0);

  HumanBehaviorSimulator({BehaviorConfig? config})
      : config = config ?? const BehaviorConfig();

  // ==================== 鼠标操作 ====================

  /// 模拟人类鼠标移动（贝塞尔曲线轨迹）
  ///
  /// 使用三阶贝塞尔曲线生成平滑的鼠标移动轨迹
  Future<void> simulateMouseMove(
    Page page,
    Point2D to, {
    Point2D? from,
  }) async {
    from ??= _currentMousePosition;

    final steps = _randomInt(config.minMouseSteps, config.maxMouseSteps);

    // 生成两个随机控制点，使曲线更自然
    final controlPoint1 = Point2D(
      from.x + (to.x - from.x) * (0.2 + _random.nextDouble() * 0.3),
      from.y + (to.y - from.y) * (0.1 + _random.nextDouble() * 0.4) +
          (_random.nextDouble() - 0.5) * 50,
    );
    final controlPoint2 = Point2D(
      from.x + (to.x - from.x) * (0.5 + _random.nextDouble() * 0.3),
      from.y + (to.y - from.y) * (0.6 + _random.nextDouble() * 0.3) +
          (_random.nextDouble() - 0.5) * 30,
    );

    _log('鼠标移动: $from -> $to (${steps}步)');

    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final point = _bezierPoint(from, controlPoint1, controlPoint2, to, t);

      await page.mouse.move(Point(point.x, point.y));

      // 随机延迟，模拟人类移动的不稳定性
      final delay = 5 + _random.nextInt(15);
      await Future.delayed(Duration(milliseconds: delay));
    }

    _currentMousePosition = to;
  }

  /// 计算三阶贝塞尔曲线上的点
  Point2D _bezierPoint(
    Point2D p0,
    Point2D p1,
    Point2D p2,
    Point2D p3,
    double t,
  ) {
    final u = 1 - t;
    final tt = t * t;
    final uu = u * u;
    final uuu = uu * u;
    final ttt = tt * t;

    return Point2D(
      uuu * p0.x + 3 * uu * t * p1.x + 3 * u * tt * p2.x + ttt * p3.x,
      uuu * p0.y + 3 * uu * t * p1.y + 3 * u * tt * p2.y + ttt * p3.y,
    );
  }

  /// 模拟点击前的悬停犹豫
  Future<void> hoverBeforeClick(
    Page page,
    ElementHandle element,
  ) async {
    final box = await element.boundingBox;
    if (box == null) return;

    // 计算元素中心
    final centerX = box.left + box.width / 2;
    final centerY = box.top + box.height / 2;

    // 先移动到元素附近（有一定偏移）
    final nearPoint = Point2D(
      centerX + (_random.nextDouble() - 0.5) * 30,
      centerY + (_random.nextDouble() - 0.5) * 20,
    );
    await simulateMouseMove(page, nearPoint);

    // 短暂停顿（模拟瞄准）
    await randomWait(minMs: 100, maxMs: 300);

    // 移动到精确位置
    final targetPoint = Point2D(
      centerX + (_random.nextDouble() - 0.5) * 5,
      centerY + (_random.nextDouble() - 0.5) * 5,
    );
    await simulateMouseMove(page, targetPoint);

    // 点击前的短暂犹豫
    await randomWait(minMs: 50, maxMs: 200);
  }

  /// 模拟人类点击（带悬停）
  Future<void> clickLikeHuman(
    Page page,
    ElementHandle element, {
    bool doubleClick = false,
  }) async {
    await hoverBeforeClick(page, element);

    final clickPoint = Point(_currentMousePosition.x, _currentMousePosition.y);

    if (doubleClick) {
      await page.mouse.click(clickPoint);
      await Future.delayed(Duration(milliseconds: 50 + _random.nextInt(100)));
      await page.mouse.click(clickPoint);
    } else {
      await page.mouse.click(clickPoint);
    }

    _log('点击位置: $_currentMousePosition');
  }

  // ==================== 输入操作 ====================

  /// 模拟人类输入（随机延迟）
  ///
  /// 每个字符之间有随机延迟，偶尔会有较长停顿（模拟思考）
  Future<void> typeLikeHuman(
    Page page,
    String text, {
    ElementHandle? element,
    String? selector,
  }) async {
    // 如果提供了元素或选择器，先点击聚焦
    if (element != null) {
      await clickLikeHuman(page, element);
    } else if (selector != null) {
      final el = await page.$(selector);
      if (el != null) {
        await clickLikeHuman(page, el);
      }
    }

    await randomWait(minMs: 100, maxMs: 300);

    _log('输入文本: "$text" (${text.length}字符)');

    for (int i = 0; i < text.length; i++) {
      final char = text[i];

      // 输入单个字符
      await page.keyboard.type(char);

      // 随机延迟
      final delay = _randomInt(config.minTypeDelayMs, config.maxTypeDelayMs);
      await Future.delayed(Duration(milliseconds: delay));

      // 偶尔有较长停顿（模拟思考，约10%概率）
      if (_random.nextDouble() < 0.1) {
        await randomWait(minMs: 200, maxMs: 800);
      }
    }
  }

  /// 清空输入框并输入新内容
  Future<void> clearAndType(
    Page page,
    String selector,
    String text,
  ) async {
    final element = await page.$(selector);
    if (element == null) {
      throw Exception('Element not found: $selector');
    }

    // 点击输入框
    await clickLikeHuman(page, element);

    // 全选并删除（Ctrl+A, Delete）
    await page.keyboard.down(Key.control);
    await page.keyboard.press(Key.keyA);
    await page.keyboard.up(Key.control);
    await randomWait(minMs: 50, maxMs: 150);
    await page.keyboard.press(Key.backspace);

    await randomWait(minMs: 100, maxMs: 300);

    // 输入新内容
    await typeLikeHuman(page, text);
  }

  // ==================== 滚动操作 ====================

  /// 模拟人类滚动行为
  ///
  /// 随机方向、随机距离、随机速度的滚动
  Future<void> simulateScroll(Page page, {bool scrollDown = true}) async {
    final scrollCount =
        _randomInt(config.minScrollCount, config.maxScrollCount);

    _log('开始滚动 (${scrollCount}次)');

    for (int i = 0; i < scrollCount; i++) {
      // 随机滚动距离
      final scrollAmount = 200 + _random.nextInt(400);
      final direction = scrollDown ? 1 : -1;

      // 使用 JavaScript 实现平滑滚动
      await page.evaluate('''
        window.scrollBy({
          top: ${scrollAmount * direction},
          behavior: 'smooth'
        });
      ''');

      // 随机等待
      await randomWait(minMs: 300, maxMs: 800);
    }
  }

  /// 滚动到元素可见
  Future<void> scrollToElement(
    Page page,
    ElementHandle element, {
    bool smooth = true,
  }) async {
    await page.evaluate('''
      (element) => {
        element.scrollIntoView({
          behavior: '${smooth ? 'smooth' : 'auto'}',
          block: 'center'
        });
      }
    ''', args: [element]);

    await randomWait(minMs: 300, maxMs: 600);
  }

  /// 随机滚动浏览（模拟用户浏览页面）
  Future<void> randomBrowse(Page page, {int duration = 3000}) async {
    final startTime = DateTime.now();
    final endTime = startTime.add(Duration(milliseconds: duration));

    _log('开始随机浏览 (${duration}ms)');

    while (DateTime.now().isBefore(endTime)) {
      // 随机决定滚动方向
      final scrollDown = _random.nextDouble() < 0.7; // 70%概率向下
      await simulateScroll(page, scrollDown: scrollDown);

      // 随机等待
      await randomWait(minMs: 500, maxMs: 1500);
    }
  }

  // ==================== 等待操作 ====================

  /// 随机等待
  Future<void> randomWait({
    int? minMs,
    int? maxMs,
  }) async {
    minMs ??= config.minWaitMs;
    maxMs ??= config.maxWaitMs;

    final delay = _randomInt(minMs, maxMs);
    await Future.delayed(Duration(milliseconds: delay));
  }

  /// 等待并随机移动鼠标（模拟用户阅读）
  Future<void> waitAndReadSimulation(
    Page page, {
    int durationMs = 2000,
  }) async {
    final movements = 2 + _random.nextInt(3);
    final interval = durationMs ~/ movements;

    for (int i = 0; i < movements; i++) {
      // 小范围随机移动鼠标
      final offset = Point2D(
        _currentMousePosition.x + (_random.nextDouble() - 0.5) * 100,
        _currentMousePosition.y + (_random.nextDouble() - 0.5) * 60,
      );
      await simulateMouseMove(page, offset);
      await Future.delayed(Duration(milliseconds: interval));
    }
  }

  // ==================== 组合操作 ====================

  /// 执行搜索操作（输入关键词 + 点击按钮）
  Future<void> performSearch(
    Page page, {
    required String inputSelector,
    required String buttonSelector,
    required String keyword,
  }) async {
    _log('执行搜索: "$keyword"');

    // 1. 随机滚动一下（模拟查看页面）
    await simulateScroll(page);
    await randomWait(minMs: 500, maxMs: 1000);

    // 2. 清空并输入关键词
    await clearAndType(page, inputSelector, keyword);
    await randomWait(minMs: 300, maxMs: 800);

    // 3. 点击搜索按钮
    final button = await page.$(buttonSelector);
    if (button != null) {
      await clickLikeHuman(page, button);
    } else {
      // 如果找不到按钮，按回车
      await page.keyboard.press(Key.enter);
    }

    _log('搜索完成');
  }

  /// 等待元素出现并点击
  Future<bool> waitAndClick(
    Page page,
    String selector, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      await page.waitForSelector(selector, timeout: timeout);
      await randomWait(minMs: 200, maxMs: 500);

      final element = await page.$(selector);
      if (element != null) {
        await clickLikeHuman(page, element);
        return true;
      }
    } catch (e) {
      _log('等待元素超时: $selector');
    }
    return false;
  }

  // ==================== 工具方法 ====================

  /// 生成指定范围内的随机整数
  int _randomInt(int min, int max) {
    return min + _random.nextInt(max - min + 1);
  }

  /// 重置鼠标位置
  void resetMousePosition() {
    _currentMousePosition = const Point2D(0, 0);
  }

  /// 获取当前鼠标位置
  Point2D get currentMousePosition => _currentMousePosition;

  /// 日志输出
  void _log(String message) {
    if (config.verbose) {
      print('[HumanBehavior] $message');
    }
  }
}

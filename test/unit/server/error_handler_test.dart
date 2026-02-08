import 'package:test/test.dart';

import '../../../server/lib/jd_scraper/error_handler.dart';
import '../../../server/lib/jd_scraper/models/scraper_error.dart';

void main() {
  // ============================================================
  // Module: ErrorEntry
  // What: 错误日志条目的数据模型
  // Why: 确保错误信息被正确结构化和序列化
  // Coverage: 构造、toJson、可选字段
  // ============================================================
  group('ErrorEntry', () {
    test('should create with required fields', () {
      final now = DateTime.now();
      final entry = ErrorEntry(
        id: 'err_001',
        type: ScraperErrorType.timeout,
        message: '请求超时',
        timestamp: now,
      );
      expect(entry.id, equals('err_001'));
      expect(entry.type, equals(ScraperErrorType.timeout));
      expect(entry.message, equals('请求超时'));
      expect(entry.timestamp, equals(now));
      expect(entry.skuId, isNull);
      expect(entry.details, isEmpty);
    });

    test('should create with optional fields', () {
      final entry = ErrorEntry(
        id: 'err_002',
        type: ScraperErrorType.cookieExpired,
        message: 'Cookie 已过期',
        skuId: 'SKU12345',
        timestamp: DateTime(2025, 1, 1),
        details: {'pageUrl': 'https://example.com'},
      );
      expect(entry.skuId, equals('SKU12345'));
      expect(entry.details['pageUrl'], equals('https://example.com'));
    });

    test('toJson should serialize basic fields', () {
      final entry = ErrorEntry(
        id: 'err_003',
        type: ScraperErrorType.networkError,
        message: '网络异常',
        timestamp: DateTime(2025, 6, 15, 10, 30, 0),
      );
      final json = entry.toJson();
      expect(json['id'], equals('err_003'));
      expect(json['type'], equals('networkError'));
      expect(json['message'], equals('网络异常'));
      expect(json['timestamp'], contains('2025-06-15'));
      expect(json.containsKey('skuId'), isFalse);
    });

    test('toJson should include skuId when present', () {
      final entry = ErrorEntry(
        id: 'err_004',
        type: ScraperErrorType.productNotFound,
        message: '产品未找到',
        skuId: 'SKU999',
        timestamp: DateTime.now(),
      );
      final json = entry.toJson();
      expect(json['skuId'], equals('SKU999'));
    });

    test('toJson should include details', () {
      final entry = ErrorEntry(
        id: 'err_005',
        type: ScraperErrorType.unknown,
        message: '未知错误',
        timestamp: DateTime.now(),
        details: {'key': 'value', 'count': 42},
      );
      final json = entry.toJson();
      expect(json['details']['key'], equals('value'));
      expect(json['details']['count'], equals(42));
    });
  });

  // ============================================================
  // Module: AlertEntry
  // What: 管理员告警条目的数据模型
  // Why: 确保告警信息完整且可序列化
  // Coverage: 构造、toJson、acknowledged 状态
  // ============================================================
  group('AlertEntry', () {
    test('should default acknowledged to false', () {
      final alert = AlertEntry(
        id: 'alert_001',
        type: AlertType.cookieExpired,
        message: 'Cookie 已过期',
        timestamp: DateTime.now(),
      );
      expect(alert.acknowledged, isFalse);
    });

    test('should accept custom acknowledged', () {
      final alert = AlertEntry(
        id: 'alert_002',
        type: AlertType.serviceError,
        message: '服务异常',
        timestamp: DateTime.now(),
        acknowledged: true,
      );
      expect(alert.acknowledged, isTrue);
    });

    test('toJson should serialize all fields', () {
      final ts = DateTime(2025, 3, 20, 14, 0, 0);
      final alert = AlertEntry(
        id: 'alert_003',
        type: AlertType.antiBotDetected,
        message: '反爬虫拦截',
        timestamp: ts,
        details: {'ip': '1.2.3.4'},
      );
      final json = alert.toJson();
      expect(json['id'], equals('alert_003'));
      expect(json['type'], equals('antiBotDetected'));
      expect(json['message'], equals('反爬虫拦截'));
      expect(json['timestamp'], contains('2025-03-20'));
      expect(json['details']['ip'], equals('1.2.3.4'));
      expect(json['acknowledged'], isFalse);
    });

    test('acknowledged should be mutable', () {
      final alert = AlertEntry(
        id: 'alert_004',
        type: AlertType.cookieExpired,
        message: 'test',
        timestamp: DateTime.now(),
      );
      expect(alert.acknowledged, isFalse);
      alert.acknowledged = true;
      expect(alert.acknowledged, isTrue);
      expect(alert.toJson()['acknowledged'], isTrue);
    });
  });

  // ============================================================
  // Module: AlertType
  // What: 管理员告警类型枚举
  // Why: 确保告警类型完整
  // Coverage: 枚举值验证
  // ============================================================
  group('AlertType', () {
    test('should have all expected types', () {
      expect(AlertType.values, contains(AlertType.cookieExpired));
      expect(AlertType.values, contains(AlertType.antiBotDetected));
      expect(AlertType.values, contains(AlertType.serviceError));
      expect(AlertType.values.length, equals(3));
    });
  });

  // ============================================================
  // Module: ScraperLogger
  // What: 爬虫日志记录器（纯逻辑部分）
  // Why: 确保日志级别过滤正确
  // Coverage: 日志级别过滤、便捷方法
  // ============================================================
  group('ScraperLogger', () {
    test('should create with default settings', () {
      // fileOutput=false to avoid filesystem side effects
      final logger = ScraperLogger(fileOutput: false, consoleOutput: false);
      expect(logger.minLevel, equals(LogLevel.info));
      expect(logger.consoleOutput, isFalse);
      expect(logger.fileOutput, isFalse);
    });

    test('should filter out logs below min level', () {
      // With minLevel = warning, debug and info should be skipped
      // We can't easily assert print() calls, but at least verify no crash
      final logger = ScraperLogger(
        minLevel: LogLevel.warning,
        fileOutput: false,
        consoleOutput: false,
      );
      // These should be silently ignored (no crash)
      logger.debug('debug msg');
      logger.info('info msg');
      // These should pass through (no crash)
      logger.warning('warning msg');
      logger.error('error msg');
    });

    test('should support module and context parameters', () {
      final logger = ScraperLogger(fileOutput: false, consoleOutput: false);
      // Should not throw
      logger.info('test', module: 'TestModule', context: {'key': 'value'});
    });

    test('error method should include error in context', () {
      final logger = ScraperLogger(fileOutput: false, consoleOutput: false);
      // Should not throw
      logger.error(
        'something failed',
        error: Exception('original error'),
        context: {'extra': 'info'},
        module: 'Test',
      );
    });

    test('LogLevel should have correct ordering', () {
      expect(LogLevel.debug.index, lessThan(LogLevel.info.index));
      expect(LogLevel.info.index, lessThan(LogLevel.warning.index));
      expect(LogLevel.warning.index, lessThan(LogLevel.error.index));
    });
  });

  // ============================================================
  // Module: ErrorHandler - identifyError
  // What: 错误类型识别逻辑
  // Why: 正确分类错误是触发正确告警和恢复动作的前提
  // Coverage: 各种错误模式匹配、ScraperException直传、URL检测
  // ============================================================
  group('ErrorHandler - identifyError', () {
    late ErrorHandler handler;

    setUp(() {
      handler = ErrorHandler(
        logger: ScraperLogger(fileOutput: false, consoleOutput: false),
      );
    });

    test('should return type from ScraperException directly', () {
      final ex = ScraperException.cookieExpired();
      expect(handler.identifyError(ex), equals(ScraperErrorType.cookieExpired));

      final ex2 = ScraperException.antiBotDetected();
      expect(
          handler.identifyError(ex2), equals(ScraperErrorType.antiBotDetected));

      final ex3 = ScraperException.timeout();
      expect(handler.identifyError(ex3), equals(ScraperErrorType.timeout));
    });

    test('should detect cookie expired from error string', () {
      expect(
        handler.identifyError(Exception('Cookie has expired')),
        equals(ScraperErrorType.cookieExpired),
      );
      expect(
        handler.identifyError(Exception('需要重新login')),
        equals(ScraperErrorType.cookieExpired),
      );
      expect(
        handler.identifyError(Exception('用户未登录')),
        equals(ScraperErrorType.cookieExpired),
      );
      expect(
        handler.identifyError('检测到登录状态失效'),
        equals(ScraperErrorType.cookieExpired),
      );
    });

    test('should detect anti-bot from error string', () {
      expect(
        handler.identifyError(Exception('请输入验证码')),
        equals(ScraperErrorType.antiBotDetected),
      );
      expect(
        handler.identifyError(Exception('captcha required')),
        equals(ScraperErrorType.antiBotDetected),
      );
      expect(
        handler.identifyError(Exception('访问过于频繁')),
        equals(ScraperErrorType.antiBotDetected),
      );
      expect(
        handler.identifyError(Exception('request blocked')),
        equals(ScraperErrorType.antiBotDetected),
      );
      expect(
        handler.identifyError(Exception('403 forbidden')),
        equals(ScraperErrorType.antiBotDetected),
      );
    });

    test('should detect network errors from error string', () {
      expect(
        handler.identifyError(Exception('network unreachable')),
        equals(ScraperErrorType.networkError),
      );
      expect(
        handler.identifyError(Exception('socket exception')),
        equals(ScraperErrorType.networkError),
      );
      expect(
        handler.identifyError(Exception('connection refused')),
        equals(ScraperErrorType.networkError),
      );
    });

    test('should detect timeout errors from error string', () {
      expect(
        handler.identifyError(Exception('request timeout')),
        equals(ScraperErrorType.timeout),
      );
      expect(
        handler.identifyError(Exception('操作已超时')),
        equals(ScraperErrorType.timeout),
      );
    });

    test('should detect cookie expired from passport URL', () {
      expect(
        handler.identifyError(
          Exception('some generic error'),
          pageUrl: 'https://passport.jd.com/login',
        ),
        equals(ScraperErrorType.cookieExpired),
      );
    });

    test('should detect cookie expired from login URL', () {
      expect(
        handler.identifyError(
          Exception('unknown'),
          pageUrl: 'https://union.jd.com/login?redirect=xxx',
        ),
        equals(ScraperErrorType.cookieExpired),
      );
    });

    test('should return unknown for unrecognized errors', () {
      expect(
        handler.identifyError(Exception('something unexpected')),
        equals(ScraperErrorType.unknown),
      );
    });

    test('error string matching should be case insensitive', () {
      expect(
        handler.identifyError(Exception('CONNECTION REFUSED')),
        equals(ScraperErrorType.networkError),
      );
      expect(
        handler.identifyError(Exception('TIMEOUT occurred')),
        equals(ScraperErrorType.timeout),
      );
    });

    test('keyword priority: cookie keywords take precedence', () {
      // If error contains both "cookie" and "network", cookie wins
      // because cookie check comes first
      expect(
        handler.identifyError(Exception('cookie network error')),
        equals(ScraperErrorType.cookieExpired),
      );
    });
  });

  // ============================================================
  // Module: ErrorHandler - logError & getErrors
  // What: 错误记录和查询
  // Why: 错误追踪是调试和监控的基础
  // Coverage: 添加错误、查询过滤、最大记录限制、排序
  // ============================================================
  group('ErrorHandler - logError & getErrors', () {
    late ErrorHandler handler;

    setUp(() {
      handler = ErrorHandler(
        logger: ScraperLogger(fileOutput: false, consoleOutput: false),
        maxErrors: 5,
      );
    });

    test('should record errors and retrieve them', () async {
      await handler.logError(
        ScraperErrorType.timeout,
        '超时错误',
        skuId: 'SKU001',
      );
      await handler.logError(
        ScraperErrorType.networkError,
        '网络错误',
      );

      final errors = handler.getErrors();
      expect(errors.length, equals(2));
    });

    test('should filter by type', () async {
      await handler.logError(ScraperErrorType.timeout, 'timeout 1');
      await handler.logError(ScraperErrorType.networkError, 'network 1');
      await handler.logError(ScraperErrorType.timeout, 'timeout 2');

      final timeoutErrors =
          handler.getErrors(type: ScraperErrorType.timeout);
      expect(timeoutErrors.length, equals(2));
      expect(
          timeoutErrors.every((e) => e.type == ScraperErrorType.timeout),
          isTrue);
    });

    test('should filter by since', () async {
      await handler.logError(ScraperErrorType.timeout, 'old error');
      // Small delay to ensure timestamp difference
      await Future.delayed(const Duration(milliseconds: 50));
      final cutoff = DateTime.now();
      await Future.delayed(const Duration(milliseconds: 50));
      await handler.logError(ScraperErrorType.timeout, 'new error');

      final recentErrors = handler.getErrors(since: cutoff);
      expect(recentErrors.length, equals(1));
      expect(recentErrors.first.message, equals('new error'));
    });

    test('should limit results', () async {
      await handler.logError(ScraperErrorType.timeout, 'e1');
      await handler.logError(ScraperErrorType.timeout, 'e2');
      await handler.logError(ScraperErrorType.timeout, 'e3');

      final limited = handler.getErrors(limit: 2);
      expect(limited.length, equals(2));
    });

    test('should return errors sorted by timestamp descending', () async {
      await handler.logError(ScraperErrorType.timeout, 'first');
      await Future.delayed(const Duration(milliseconds: 20));
      await handler.logError(ScraperErrorType.timeout, 'second');

      final errors = handler.getErrors();
      // Most recent first
      expect(errors.first.message, equals('second'));
      expect(errors.last.message, equals('first'));
    });

    test('should enforce maxErrors limit', () async {
      for (int i = 0; i < 8; i++) {
        await handler.logError(ScraperErrorType.timeout, 'error $i');
      }
      // maxErrors = 5, oldest should be evicted
      final errors = handler.getErrors();
      expect(errors.length, equals(5));
    });

    test('should include error details', () async {
      await handler.logError(
        ScraperErrorType.networkError,
        '连接失败',
        skuId: 'SKUABC',
        details: {'endpoint': '/api/test'},
      );

      final errors = handler.getErrors();
      expect(errors.first.skuId, equals('SKUABC'));
      expect(errors.first.details['endpoint'], equals('/api/test'));
    });

    test('clearErrors should remove all errors', () async {
      await handler.logError(ScraperErrorType.timeout, 'e1');
      await handler.logError(ScraperErrorType.timeout, 'e2');
      handler.clearErrors();
      expect(handler.getErrors(), isEmpty);
    });
  });

  // ============================================================
  // Module: ErrorHandler - handleError
  // What: 错误处理流程（识别 → 记录 → 触发回调/告警）
  // Why: 这是错误响应的核心链路
  // Coverage: 各类型错误的回调触发、告警创建
  // ============================================================
  group('ErrorHandler - handleError', () {
    test('should trigger onCookieExpired callback', () async {
      bool callbackCalled = false;
      final handler = ErrorHandler(
        logger: ScraperLogger(fileOutput: false, consoleOutput: false),
        onCookieExpired: () async {
          callbackCalled = true;
        },
      );

      await handler.handleError(
        ScraperException.cookieExpired(),
        skuId: 'SKU001',
      );
      expect(callbackCalled, isTrue);
    });

    test('should trigger onAntiBotDetected callback', () async {
      bool callbackCalled = false;
      final handler = ErrorHandler(
        logger: ScraperLogger(fileOutput: false, consoleOutput: false),
        onAntiBotDetected: () async {
          callbackCalled = true;
        },
      );

      await handler.handleError(ScraperException.antiBotDetected());
      expect(callbackCalled, isTrue);
    });

    test('should create cookie expired alert', () async {
      final handler = ErrorHandler(
        logger: ScraperLogger(fileOutput: false, consoleOutput: false),
      );

      await handler.handleError(ScraperException.cookieExpired());

      final alerts = handler.getAlerts(type: AlertType.cookieExpired);
      expect(alerts, isNotEmpty);
      expect(alerts.first.type, equals(AlertType.cookieExpired));
    });

    test('should create anti-bot alert', () async {
      final handler = ErrorHandler(
        logger: ScraperLogger(fileOutput: false, consoleOutput: false),
      );

      await handler.handleError(ScraperException.antiBotDetected());

      final alerts = handler.getAlerts(type: AlertType.antiBotDetected);
      expect(alerts, isNotEmpty);
    });

    test('should handle generic error by identifying type', () async {
      final handler = ErrorHandler(
        logger: ScraperLogger(fileOutput: false, consoleOutput: false),
      );

      await handler.handleError(Exception('network failure'));

      final errors = handler.getErrors();
      expect(errors.first.type, equals(ScraperErrorType.networkError));
    });

    test('should pass pageUrl and details through', () async {
      final handler = ErrorHandler(
        logger: ScraperLogger(fileOutput: false, consoleOutput: false),
      );

      await handler.handleError(
        Exception('some error'),
        pageUrl: 'https://passport.jd.com/login',
        details: {'extra': 'info'},
      );

      final errors = handler.getErrors();
      expect(errors.first.details['pageUrl'],
          equals('https://passport.jd.com/login'));
      expect(errors.first.details['extra'], equals('info'));
    });
  });

  // ============================================================
  // Module: ErrorHandler - Alert Cooldown
  // What: Cookie 过期告警冷却机制
  // Why: 防止高频重复告警淹没管理员
  // Coverage: 冷却时间内抑制、冷却后恢复
  // ============================================================
  group('ErrorHandler - Alert Cooldown', () {
    test('should suppress duplicate cookie alerts within cooldown', () async {
      final handler = ErrorHandler(
        logger: ScraperLogger(fileOutput: false, consoleOutput: false),
        alertCooldownMinutes: 5,
      );

      // First alert should go through
      await handler.handleError(ScraperException.cookieExpired());
      // Second alert within cooldown should be suppressed
      await handler.handleError(ScraperException.cookieExpired());

      final alerts = handler.getAlerts(type: AlertType.cookieExpired);
      // Only one cookie alert should exist
      expect(alerts.length, equals(1));
    });

    test('anti-bot alerts should not be affected by cooldown', () async {
      final handler = ErrorHandler(
        logger: ScraperLogger(fileOutput: false, consoleOutput: false),
      );

      await handler.handleError(ScraperException.antiBotDetected());
      await handler.handleError(ScraperException.antiBotDetected());

      final alerts = handler.getAlerts(type: AlertType.antiBotDetected);
      // Anti-bot alerts have no cooldown
      expect(alerts.length, equals(2));
    });
  });

  // ============================================================
  // Module: ErrorHandler - getAlerts
  // What: 告警查询功能
  // Why: 管理员需要按条件查看告警
  // Coverage: 类型过滤、未确认过滤、数量限制、排序
  // ============================================================
  group('ErrorHandler - getAlerts', () {
    late ErrorHandler handler;

    setUp(() async {
      handler = ErrorHandler(
        logger: ScraperLogger(fileOutput: false, consoleOutput: false),
        alertCooldownMinutes: 0, // Disable cooldown for testing
      );
    });

    test('should return all alerts', () async {
      await handler.handleError(ScraperException.cookieExpired());
      await handler.handleError(ScraperException.antiBotDetected());

      final alerts = handler.getAlerts();
      expect(alerts.length, equals(2));
    });

    test('should filter by type', () async {
      await handler.handleError(ScraperException.cookieExpired());
      await handler.handleError(ScraperException.antiBotDetected());

      final cookieAlerts = handler.getAlerts(type: AlertType.cookieExpired);
      expect(cookieAlerts.length, equals(1));
      expect(cookieAlerts.first.type, equals(AlertType.cookieExpired));
    });

    test('should filter unacknowledged only', () async {
      await handler.handleError(ScraperException.cookieExpired());
      await handler.handleError(ScraperException.antiBotDetected());

      // Acknowledge the first alert
      final alerts = handler.getAlerts();
      handler.acknowledgeAlert(alerts.first.id);

      final unacked = handler.getAlerts(unacknowledgedOnly: true);
      expect(unacked.length, equals(1));
      expect(unacked.every((a) => !a.acknowledged), isTrue);
    });

    test('should limit results', () async {
      await handler.handleError(ScraperException.antiBotDetected());
      await handler.handleError(ScraperException.antiBotDetected());
      await handler.handleError(ScraperException.antiBotDetected());

      final limited = handler.getAlerts(limit: 2);
      expect(limited.length, equals(2));
    });

    test('should return alerts sorted by timestamp descending', () async {
      await handler.handleError(ScraperException.antiBotDetected());
      await Future.delayed(const Duration(milliseconds: 20));
      await handler.handleError(ScraperException.antiBotDetected());

      final alerts = handler.getAlerts();
      // Most recent first
      expect(
          alerts.first.timestamp.isAfter(alerts.last.timestamp), isTrue);
    });
  });

  // ============================================================
  // Module: ErrorHandler - acknowledgeAlert
  // What: 告警确认功能
  // Why: 管理员需要标记告警已处理
  // Coverage: 正常确认、无效 ID
  // ============================================================
  group('ErrorHandler - acknowledgeAlert', () {
    test('should acknowledge existing alert', () async {
      final handler = ErrorHandler(
        logger: ScraperLogger(fileOutput: false, consoleOutput: false),
      );
      await handler.handleError(ScraperException.cookieExpired());

      final alerts = handler.getAlerts();
      final result = handler.acknowledgeAlert(alerts.first.id);
      expect(result, isTrue);

      final updated = handler.getAlerts();
      expect(updated.first.acknowledged, isTrue);
    });

    test('should return false for non-existent alert id', () {
      final handler = ErrorHandler(
        logger: ScraperLogger(fileOutput: false, consoleOutput: false),
      );
      final result = handler.acknowledgeAlert('non_existent_id');
      expect(result, isFalse);
    });
  });

  // ============================================================
  // Module: ErrorHandler - hasActiveCookieAlert & count
  // What: Cookie 告警状态查询
  // Why: 快速判断是否有活跃的 Cookie 问题
  // Coverage: 有无告警、已确认告警
  // ============================================================
  group('ErrorHandler - Cookie Alert Status', () {
    test('hasActiveCookieAlert should return false when no alerts', () {
      final handler = ErrorHandler(
        logger: ScraperLogger(fileOutput: false, consoleOutput: false),
      );
      expect(handler.hasActiveCookieAlert(), isFalse);
    });

    test('hasActiveCookieAlert should return true with recent unacked alert',
        () async {
      final handler = ErrorHandler(
        logger: ScraperLogger(fileOutput: false, consoleOutput: false),
      );
      await handler.handleError(ScraperException.cookieExpired());
      expect(handler.hasActiveCookieAlert(), isTrue);
    });

    test(
        'hasActiveCookieAlert should return false when all alerts acknowledged',
        () async {
      final handler = ErrorHandler(
        logger: ScraperLogger(fileOutput: false, consoleOutput: false),
      );
      await handler.handleError(ScraperException.cookieExpired());

      final alerts = handler.getAlerts(type: AlertType.cookieExpired);
      for (final a in alerts) {
        handler.acknowledgeAlert(a.id);
      }
      expect(handler.hasActiveCookieAlert(), isFalse);
    });

    test('getUnacknowledgedCookieAlertCount should return correct count',
        () async {
      final handler = ErrorHandler(
        logger: ScraperLogger(fileOutput: false, consoleOutput: false),
        alertCooldownMinutes: 0,
      );
      await handler.handleError(ScraperException.cookieExpired());
      await handler.handleError(ScraperException.cookieExpired());
      expect(handler.getUnacknowledgedCookieAlertCount(), equals(2));

      // Acknowledge one
      final alerts = handler.getAlerts(type: AlertType.cookieExpired);
      handler.acknowledgeAlert(alerts.first.id);
      expect(handler.getUnacknowledgedCookieAlertCount(), equals(1));
    });
  });

  // ============================================================
  // Module: ErrorHandler - getStatistics
  // What: 错误统计汇总
  // Why: 提供系统健康状况的量化指标
  // Coverage: 总数、按类型、时间窗口统计
  // ============================================================
  group('ErrorHandler - getStatistics', () {
    test('should return initial empty statistics', () {
      final handler = ErrorHandler(
        logger: ScraperLogger(fileOutput: false, consoleOutput: false),
      );
      final stats = handler.getStatistics();
      expect(stats['total'], equals(0));
      expect((stats['byType'] as Map), isEmpty);
      expect(stats['last24h'], equals(0));
      expect(stats['lastHour'], equals(0));
    });

    test('should include error counts by type', () async {
      final handler = ErrorHandler(
        logger: ScraperLogger(fileOutput: false, consoleOutput: false),
      );
      await handler.logError(ScraperErrorType.timeout, 't1');
      await handler.logError(ScraperErrorType.timeout, 't2');
      await handler.logError(ScraperErrorType.networkError, 'n1');

      final stats = handler.getStatistics();
      expect(stats['total'], equals(3));
      expect((stats['byType'] as Map)['timeout'], equals(2));
      expect((stats['byType'] as Map)['networkError'], equals(1));
      expect(stats['last24h'], equals(3));
      expect(stats['lastHour'], equals(3));
    });

    test('should include alert statistics', () async {
      final handler = ErrorHandler(
        logger: ScraperLogger(fileOutput: false, consoleOutput: false),
      );
      await handler.handleError(ScraperException.cookieExpired());
      await handler.handleError(ScraperException.antiBotDetected());

      final stats = handler.getStatistics();
      final alertStats = stats['alerts'] as Map<String, dynamic>;
      expect(alertStats['total'], equals(2));
      expect(alertStats['unacknowledged'], equals(2));
      expect(alertStats['cookieExpired'], equals(1));
      expect(alertStats['hasActiveCookieAlert'], isTrue);
    });
  });

  // ============================================================
  // Module: ErrorHandler - maxAlerts limit
  // What: 告警数量上限
  // Why: 防止内存无限增长
  // Coverage: 超过上限时移除最早的告警
  // ============================================================
  group('ErrorHandler - maxAlerts', () {
    test('should enforce maxAlerts limit', () async {
      final handler = ErrorHandler(
        logger: ScraperLogger(fileOutput: false, consoleOutput: false),
        maxAlerts: 3,
        alertCooldownMinutes: 0,
      );

      for (int i = 0; i < 5; i++) {
        // Using anti-bot alerts since they don't have cooldown
        await handler.handleError(ScraperException.antiBotDetected());
      }

      final alerts = handler.getAlerts();
      expect(alerts.length, lessThanOrEqualTo(3));
    });
  });

  // ============================================================
  // Module: PerformanceMonitor
  // What: 性能监控器
  // Why: 请求性能统计对识别瓶颈至关重要
  // Coverage: 记录请求、错误计数、统计计算、百分位数
  // ============================================================
  group('PerformanceMonitor', () {
    late PerformanceMonitor monitor;

    setUp(() {
      monitor = PerformanceMonitor(maxRecords: 100);
    });

    test('should record requests', () {
      monitor.recordRequest('/api/test', const Duration(milliseconds: 100));
      monitor.recordRequest('/api/test', const Duration(milliseconds: 200));

      final stats = monitor.getStats('/api/test');
      expect(stats['count'], equals(2));
      expect(stats['avgDuration'], equals(150));
    });

    test('should return zero stats for unknown endpoint', () {
      final stats = monitor.getStats('/unknown');
      expect(stats['count'], equals(0));
      expect(stats['avgDuration'], equals(0));
      expect(stats['minDuration'], equals(0));
      expect(stats['maxDuration'], equals(0));
    });

    test('should calculate min/max duration', () {
      monitor.recordRequest('/api/test', const Duration(milliseconds: 50));
      monitor.recordRequest('/api/test', const Duration(milliseconds: 300));
      monitor.recordRequest('/api/test', const Duration(milliseconds: 150));

      final stats = monitor.getStats('/api/test');
      expect(stats['minDuration'], equals(50));
      expect(stats['maxDuration'], equals(300));
    });

    test('should calculate p50 and p95', () {
      // Record many requests for meaningful percentiles
      for (int i = 1; i <= 20; i++) {
        monitor.recordRequest(
            '/api/perf', Duration(milliseconds: i * 10));
      }

      final stats = monitor.getStats('/api/perf');
      // p50 should be around 100ms (10th item out of 20)
      expect(stats['p50'], isA<int>());
      expect(stats['p95'], isA<int>());
      // p95 should be higher than p50
      expect(stats['p95'] as int, greaterThanOrEqualTo(stats['p50'] as int));
    });

    test('should record errors separately', () {
      monitor.recordRequest('/api/test', const Duration(milliseconds: 100));
      monitor.recordError('/api/test');
      monitor.recordError('/api/test');

      final stats = monitor.getStats('/api/test');
      expect(stats['errorCount'], equals(2));
      expect(stats['errorRate'], equals(2.0)); // 2 errors / 1 request
    });

    test('should calculate error rate', () {
      monitor.recordRequest('/api/calc', const Duration(milliseconds: 50));
      monitor.recordRequest('/api/calc', const Duration(milliseconds: 60));
      monitor.recordRequest('/api/calc', const Duration(milliseconds: 70));
      monitor.recordRequest('/api/calc', const Duration(milliseconds: 80));
      monitor.recordError('/api/calc');

      final stats = monitor.getStats('/api/calc');
      expect(stats['errorRate'], equals(0.25)); // 1 error / 4 requests
    });

    test('should track multiple endpoints independently', () {
      monitor.recordRequest('/api/a', const Duration(milliseconds: 100));
      monitor.recordRequest('/api/b', const Duration(milliseconds: 200));

      final statsA = monitor.getStats('/api/a');
      final statsB = monitor.getStats('/api/b');
      expect(statsA['avgDuration'], equals(100));
      expect(statsB['avgDuration'], equals(200));
    });

    test('getAllStats should aggregate all endpoints', () {
      monitor.recordRequest('/api/a', const Duration(milliseconds: 100));
      monitor.recordRequest('/api/b', const Duration(milliseconds: 200));
      monitor.recordError('/api/a');

      final allStats = monitor.getAllStats();
      expect(allStats['totalRequests'], equals(2));
      expect(allStats['totalErrors'], equals(1));
      expect((allStats['endpoints'] as List).length, equals(2));
    });

    test('reset should clear all data', () {
      monitor.recordRequest('/api/test', const Duration(milliseconds: 100));
      monitor.recordError('/api/test');
      monitor.reset();

      final stats = monitor.getStats('/api/test');
      expect(stats['count'], equals(0));
      expect(stats['errorCount'], equals(0));

      final allStats = monitor.getAllStats();
      expect(allStats['totalRequests'], equals(0));
      expect(allStats['totalErrors'], equals(0));
    });

    test('should enforce maxRecords per endpoint', () {
      final smallMonitor = PerformanceMonitor(maxRecords: 3);
      for (int i = 0; i < 5; i++) {
        smallMonitor.recordRequest(
            '/api/test', Duration(milliseconds: (i + 1) * 100));
      }

      final stats = smallMonitor.getStats('/api/test');
      expect(stats['count'], equals(3));
      // Should keep the most recent records (300, 400, 500)
      expect(stats['minDuration'], equals(300));
      expect(stats['maxDuration'], equals(500));
    });
  });
}

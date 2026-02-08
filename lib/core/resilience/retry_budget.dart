import 'dart:math';

/// 重试预算配置
class RetryBudgetConfig {
  /// 时间窗口内允许的最大重试比例（相对于成功请求）
  final double maxRetryRatio;

  /// 最小重试数（即使没有成功请求也允许的重试）
  final int minRetriesPerWindow;

  /// 时间窗口长度
  final Duration windowDuration;

  /// 是否允许透支（超出预算时是否仍允许重试）
  final bool allowOverdraft;

  /// 透支后的冷却时间
  final Duration overdraftCooldown;

  const RetryBudgetConfig({
    this.maxRetryRatio = 0.2, // 最多重试 20%
    this.minRetriesPerWindow = 10,
    this.windowDuration = const Duration(seconds: 10),
    this.allowOverdraft = false,
    this.overdraftCooldown = const Duration(seconds: 30),
  });

  /// 保守配置
  static const conservative = RetryBudgetConfig(
    maxRetryRatio: 0.1,
    minRetriesPerWindow: 5,
  );

  /// 激进配置
  static const aggressive = RetryBudgetConfig(
    maxRetryRatio: 0.3,
    minRetriesPerWindow: 20,
    allowOverdraft: true,
  );
}

/// 重试预算管理器
///
/// 防止重试风暴，通过限制系统级别的重试总量来保护后端服务
class RetryBudget {
  final RetryBudgetConfig config;
  final String name;

  final List<_RequestRecord> _requests = [];
  DateTime? _overdraftUntil;

  // 统计
  int _totalRequests = 0;
  int _totalRetries = 0;
  int _deniedRetries = 0;

  RetryBudget({
    required this.name,
    RetryBudgetConfig? config,
  }) : config = config ?? const RetryBudgetConfig();

  /// 记录请求（非重试）
  void recordRequest() {
    _totalRequests++;
    _addRecord(false);
  }

  /// 尝试获取重试许可
  bool tryAcquireRetryPermit() {
    _totalRetries++;

    // 检查冷却期
    if (_isInOverdraftCooldown()) {
      _deniedRetries++;
      return false;
    }

    _cleanOldRecords();

    final budget = _calculateBudget();
    final usedRetries = _countRetries();

    if (usedRetries < budget) {
      _addRecord(true);
      return true;
    }

    // 预算不足
    if (config.allowOverdraft) {
      _overdraftUntil = DateTime.now().add(config.overdraftCooldown);
      _addRecord(true);
      return true;
    }

    _deniedRetries++;
    return false;
  }

  /// 检查是否可以重试（不消耗预算）
  bool canRetry() {
    if (_isInOverdraftCooldown()) return false;

    _cleanOldRecords();
    final budget = _calculateBudget();
    final usedRetries = _countRetries();

    return usedRetries < budget;
  }

  /// 获取剩余重试预算
  int get remainingBudget {
    _cleanOldRecords();
    final budget = _calculateBudget();
    final usedRetries = _countRetries();
    return max(0, budget - usedRetries);
  }

  /// 获取当前重试率
  double get currentRetryRate {
    _cleanOldRecords();
    final total = _requests.length;
    if (total == 0) return 0.0;
    final retries = _countRetries();
    return retries / total;
  }

  /// 计算当前预算
  int _calculateBudget() {
    final successCount = _requests.where((r) => !r.isRetry).length;
    final calculatedBudget = (successCount * config.maxRetryRatio).ceil();
    return max(config.minRetriesPerWindow, calculatedBudget);
  }

  /// 统计重试次数
  int _countRetries() {
    return _requests.where((r) => r.isRetry).length;
  }

  /// 检查是否在透支冷却期
  bool _isInOverdraftCooldown() {
    if (_overdraftUntil == null) return false;
    if (DateTime.now().isAfter(_overdraftUntil!)) {
      _overdraftUntil = null;
      return false;
    }
    return true;
  }

  /// 添加记录
  void _addRecord(bool isRetry) {
    _requests.add(_RequestRecord(
      timestamp: DateTime.now(),
      isRetry: isRetry,
    ));
  }

  /// 清理过期记录
  void _cleanOldRecords() {
    final cutoff = DateTime.now().subtract(config.windowDuration);
    _requests.removeWhere((r) => r.timestamp.isBefore(cutoff));
  }

  /// 获取统计信息
  Map<String, dynamic> getStats() {
    _cleanOldRecords();
    return {
      'name': name,
      'windowRequests': _requests.length,
      'windowRetries': _countRetries(),
      'currentBudget': _calculateBudget(),
      'remainingBudget': remainingBudget,
      'currentRetryRate': '${(currentRetryRate * 100).toStringAsFixed(1)}%',
      'inCooldown': _isInOverdraftCooldown(),
      'cooldownRemaining': _overdraftUntil != null
          ? '${_overdraftUntil!.difference(DateTime.now()).inSeconds}s'
          : null,
      'total': {
        'requests': _totalRequests,
        'retries': _totalRetries,
        'deniedRetries': _deniedRetries,
      },
    };
  }

  /// 重置
  void reset() {
    _requests.clear();
    _overdraftUntil = null;
    _totalRequests = 0;
    _totalRetries = 0;
    _deniedRetries = 0;
  }
}

/// 请求记录
class _RequestRecord {
  final DateTime timestamp;
  final bool isRetry;

  _RequestRecord({required this.timestamp, required this.isRetry});
}

/// 重试预算注册表
class RetryBudgetRegistry {
  static final RetryBudgetRegistry _instance = RetryBudgetRegistry._();
  static RetryBudgetRegistry get instance => _instance;

  RetryBudgetRegistry._();

  final Map<String, RetryBudget> _budgets = {};

  /// 获取或创建预算管理器
  RetryBudget getOrCreate(String name, {RetryBudgetConfig? config}) {
    return _budgets.putIfAbsent(
      name,
      () => RetryBudget(name: name, config: config),
    );
  }

  /// 获取预算管理器
  RetryBudget? get(String name) => _budgets[name];

  /// 获取所有统计
  Map<String, dynamic> getAllStats() {
    return _budgets.map((name, budget) => MapEntry(name, budget.getStats()));
  }

  /// 重置所有
  void resetAll() {
    for (final budget in _budgets.values) {
      budget.reset();
    }
  }
}

/// 便捷函数：记录请求
void recordRequest(String budgetName) {
  RetryBudgetRegistry.instance.getOrCreate(budgetName).recordRequest();
}

/// 便捷函数：检查是否可以重试
bool canRetry(String budgetName) {
  return RetryBudgetRegistry.instance.getOrCreate(budgetName).canRetry();
}

/// 便捷函数：尝试获取重试许可
bool tryAcquireRetryPermit(String budgetName) {
  return RetryBudgetRegistry.instance.getOrCreate(budgetName).tryAcquireRetryPermit();
}

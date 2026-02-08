import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import '../../core/api_client.dart';

/// 可靠性仪表盘数据服务
class ReliabilityService {
  final ApiClient _client;
  final String _basePath = '/api/v1/reliability';

  /// 允许的指标类型
  static const Set<String> _validMetrics = {
    'errorRate',
    'latency',
    'requests',
    'throughput',
    'availability',
  };

  ReliabilityService(this._client);

  /// 获取系统健康概览
  Future<Map<String, dynamic>> getHealthOverview() async {
    try {
      final response = await _client.get('$_basePath/health');
      return _extractData(response) ?? _defaultHealthOverview();
    } catch (e) {
      _log('获取健康概览失败: $e', isError: true);
      rethrow;
    }
  }

  /// 获取所有服务状态
  Future<List<Map<String, dynamic>>> getServiceStatuses() async {
    try {
      final response = await _client.get('$_basePath/services');
      final data = _extractData(response);
      return _safeParseList(data);
    } catch (e) {
      _log('获取服务状态失败: $e', isError: true);
      rethrow;
    }
  }

  /// 获取单个服务状态
  Future<Map<String, dynamic>> getServiceStatus(String serviceName) async {
    if (serviceName.trim().isEmpty) {
      throw ArgumentError('服务名称不能为空');
    }

    try {
      final encodedName = Uri.encodeComponent(serviceName.trim());
      final response = await _client.get('$_basePath/services/$encodedName');
      return _extractData(response) ?? {};
    } catch (e) {
      _log('获取服务状态失败 ($serviceName): $e', isError: true);
      rethrow;
    }
  }

  /// 获取时间序列指标
  Future<List<Map<String, dynamic>>> getTimeSeries(
    String metric, {
    int windowMinutes = 60,
  }) async {
    // 验证指标类型
    final safeMetric = metric.toLowerCase().trim();
    if (!_validMetrics.contains(safeMetric)) {
      _log('未知指标类型: $metric，使用默认', isError: true);
    }

    // 验证时间窗口
    final safeWindow = windowMinutes.clamp(5, 1440); // 5分钟到24小时

    try {
      final response = await _client.get(
        '$_basePath/metrics/timeseries/$safeMetric?window=$safeWindow',
      );

      final result = _safeParseMap(response.data);
      if (result == null) return [];

      if (result['success'] == true) {
        return _safeParseList(result['data']);
      }

      final error = result['error']?.toString() ?? '获取时间序列失败';
      throw Exception(error);
    } catch (e) {
      _log('获取时间序列失败 ($metric): $e', isError: true);
      rethrow;
    }
  }

  /// 获取负载预测
  Future<Map<String, dynamic>> getLoadPrediction() async {
    try {
      final response = await _client.get('$_basePath/predictions/load');
      return _extractData(response) ?? _defaultLoadPrediction();
    } catch (e) {
      _log('获取负载预测失败: $e', isError: true);
      rethrow;
    }
  }

  /// 获取根因分析结果
  Future<List<Map<String, dynamic>>> getRootCauseResults({int limit = 10}) async {
    final safeLimit = limit.clamp(1, 100);

    try {
      final response = await _client.get('$_basePath/rca?limit=$safeLimit');
      final data = _extractData(response);
      return _safeParseList(data);
    } catch (e) {
      _log('获取根因分析结果失败: $e', isError: true);
      rethrow;
    }
  }

  /// 触发根因分析
  Future<Map<String, dynamic>> triggerRootCauseAnalysis() async {
    try {
      final response = await _client.post('$_basePath/rca/analyze');
      _log('根因分析已触发');
      return _extractData(response) ?? {'triggered': true};
    } catch (e) {
      _log('触发根因分析失败: $e', isError: true);
      rethrow;
    }
  }

  /// 获取告警列表
  Future<List<Map<String, dynamic>>> getAlerts({bool activeOnly = true}) async {
    try {
      final response = await _client.get('$_basePath/alerts?active=$activeOnly');
      final data = _extractData(response);
      return _safeParseList(data);
    } catch (e) {
      _log('获取告警列表失败: $e', isError: true);
      rethrow;
    }
  }

  /// 确认告警
  Future<bool> acknowledgeAlert(String alertId) async {
    if (alertId.trim().isEmpty) {
      throw ArgumentError('告警 ID 不能为空');
    }

    try {
      final encodedId = Uri.encodeComponent(alertId.trim());
      final response = await _client.post('$_basePath/alerts/$encodedId/acknowledge');
      final result = _safeParseMap(response.data);
      _log('告警已确认: $alertId');
      return result?['success'] == true;
    } catch (e) {
      _log('确认告警失败: $e', isError: true);
      rethrow;
    }
  }

  /// 获取依赖图
  Future<Map<String, dynamic>> getDependencyGraph() async {
    try {
      final response = await _client.get('$_basePath/dependencies');
      return _extractData(response) ?? _defaultDependencyGraph();
    } catch (e) {
      _log('获取依赖图失败: $e', isError: true);
      rethrow;
    }
  }

  /// 获取混沌工程状态
  Future<Map<String, dynamic>> getChaosStatus() async {
    try {
      final response = await _client.get('$_basePath/chaos/status');
      return _extractData(response) ?? _defaultChaosStatus();
    } catch (e) {
      _log('获取混沌状态失败: $e', isError: true);
      rethrow;
    }
  }

  /// 启用混沌工程
  Future<bool> enableChaos() async {
    try {
      final response = await _client.post('$_basePath/chaos/enable');
      final result = _safeParseMap(response.data);
      _log('混沌工程已启用');
      return result?['success'] == true;
    } catch (e) {
      _log('启用混沌工程失败: $e', isError: true);
      rethrow;
    }
  }

  /// 禁用混沌工程
  Future<bool> disableChaos() async {
    try {
      final response = await _client.post('$_basePath/chaos/disable');
      final result = _safeParseMap(response.data);
      _log('混沌工程已禁用');
      return result?['success'] == true;
    } catch (e) {
      _log('禁用混沌工程失败: $e', isError: true);
      rethrow;
    }
  }

  /// 启动混沌实验
  Future<bool> startChaosExperiment(String experimentId) async {
    if (experimentId.trim().isEmpty) {
      throw ArgumentError('实验 ID 不能为空');
    }

    try {
      final encodedId = Uri.encodeComponent(experimentId.trim());
      final response = await _client.post('$_basePath/chaos/experiments/$encodedId/start');
      final result = _safeParseMap(response.data);
      _log('混沌实验已启动: $experimentId');
      return result?['success'] == true;
    } catch (e) {
      _log('启动混沌实验失败: $e', isError: true);
      rethrow;
    }
  }

  /// 停止混沌实验
  Future<bool> stopChaosExperiment() async {
    try {
      final response = await _client.post('$_basePath/chaos/experiments/stop');
      final result = _safeParseMap(response.data);
      _log('混沌实验已停止');
      return result?['success'] == true;
    } catch (e) {
      _log('停止混沌实验失败: $e', isError: true);
      rethrow;
    }
  }

  /// 获取自愈动作历史
  Future<List<Map<String, dynamic>>> getSelfHealingActions() async {
    try {
      final response = await _client.get('$_basePath/actions/history');
      final data = _extractData(response);
      return _safeParseList(data);
    } catch (e) {
      _log('获取自愈动作历史失败: $e', isError: true);
      rethrow;
    }
  }

  /// 触发自愈动作
  Future<Map<String, dynamic>> triggerAction(String action) async {
    if (action.trim().isEmpty) {
      throw ArgumentError('动作名称不能为空');
    }

    try {
      final encodedAction = Uri.encodeComponent(action.trim());
      final response = await _client.post('$_basePath/actions/trigger/$encodedAction');
      _log('自愈动作已触发: $action');
      return _safeParseMap(response.data) ?? {'triggered': true};
    } catch (e) {
      _log('触发自愈动作失败: $e', isError: true);
      rethrow;
    }
  }

  /// 从响应中提取数据
  dynamic _extractData(Response response) {
    final result = _safeParseMap(response.data);
    if (result == null) return null;

    if (result['success'] == true) {
      return result['data'];
    }

    final error = result['error']?.toString() ?? '请求失败';
    throw Exception(error);
  }

  /// 安全解析 Map
  Map<String, dynamic>? _safeParseMap(dynamic data) {
    if (data == null) return null;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  /// 安全解析 List<Map>
  List<Map<String, dynamic>> _safeParseList(dynamic data) {
    if (data == null) return [];
    if (data is! List) return [];

    return data
        .map((item) => _safeParseMap(item))
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// 默认健康概览
  Map<String, dynamic> _defaultHealthOverview() => {
        'overallScore': 0,
        'grade': 'unknown',
        'services': {'healthy': 0, 'degraded': 0, 'unhealthy': 0},
        'metrics': {
          'errorRate': 0,
          'avgLatencyMs': 0,
          'p99LatencyMs': 0,
          'requestsPerMinute': 0,
        },
        'criticalIssues': <String>[],
        'warnings': <String>[],
      };

  /// 默认负载预测
  Map<String, dynamic> _defaultLoadPrediction() => {
        'predictedLoad': 0,
        'confidence': 0,
        'bounds': {'lower': 0, 'upper': 0},
        'trend': {'direction': 'stable', 'slope': 0},
        'recommendedAction': 'none',
      };

  /// 默认依赖图
  Map<String, dynamic> _defaultDependencyGraph() => {
        'nodes': <Map<String, dynamic>>[],
        'edges': <Map<String, dynamic>>[],
      };

  /// 默认混沌状态
  Map<String, dynamic> _defaultChaosStatus() => {
        'enabled': false,
        'experimentRunning': false,
        'currentExperimentId': null,
        'currentExperimentName': null,
        'registeredExperiments': <Map<String, dynamic>>[],
      };

  /// 获取压力测试结果
  Future<Map<String, dynamic>> getStressTestResults() async {
    try {
      final response = await _client.get('$_basePath/stress-test/results');
      return _extractData(response) ?? _defaultStressTestResults();
    } catch (e) {
      _log('获取压力测试结果失败: $e', isError: true);
      rethrow;
    }
  }

  /// 触发压力测试
  Future<Map<String, dynamic>> runStressTest() async {
    try {
      final response = await _client.post('$_basePath/stress-test/run');
      _log('压力测试已触发');
      return _extractData(response) ?? {'triggered': true};
    } catch (e) {
      _log('触发压力测试失败: $e', isError: true);
      rethrow;
    }
  }

  /// 触发混沌测试
  Future<Map<String, dynamic>> runChaosTest() async {
    try {
      final response = await _client.post('$_basePath/chaos-test/run');
      _log('混沌测试已触发');
      return _extractData(response) ?? {'triggered': true};
    } catch (e) {
      _log('触发混沌测试失败: $e', isError: true);
      rethrow;
    }
  }

  /// 默认压力测试结果
  Map<String, dynamic> _defaultStressTestResults() => {
        'loadSteps': <Map<String, dynamic>>[],
        'chaosExperiments': <Map<String, dynamic>>[],
        'stabilityAssessment': null,
      };

  void _log(String message, {bool isError = false}) {
    final prefix = isError ? '❌ Reliability' : '📊 Reliability';
    developer.log('$prefix: $message', name: 'ReliabilityService');
  }
}

import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import 'reliability_service.dart';
import 'widgets/health_score_card.dart';
import 'widgets/metrics_chart.dart';
import 'widgets/service_card.dart';
import 'widgets/dependency_graph.dart';
import 'widgets/incident_timeline.dart';
import 'widgets/chaos_control_panel.dart';
import 'widgets/load_prediction_card.dart';
import 'widgets/stress_test_results.dart';

/// 可靠性仪表盘页面
class ReliabilityPage extends StatefulWidget {
  const ReliabilityPage({super.key});

  @override
  State<ReliabilityPage> createState() => _ReliabilityPageState();
}

class _ReliabilityPageState extends State<ReliabilityPage>
    with SingleTickerProviderStateMixin {
  late final ReliabilityService _service;
  late final TabController _tabController;
  Timer? _refreshTimer;
  
  void _log(String message, {bool isError = false}) {
    final prefix = isError ? '❌ Reliability' : '📊 Reliability';
    developer.log('$prefix: $message', name: 'ReliabilityPage');
  }
  
  /// 安全地将 dynamic 转换为 `List<Map<String, dynamic>>`
  /// 过滤掉非 Map 类型的元素，防止类型转换异常
  List<Map<String, dynamic>> _safeParseList(dynamic data) {
    if (data == null) return [];
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((item) => item is Map<String, dynamic> 
            ? item 
            : Map<String, dynamic>.from(item))
        .toList();
  }
  
  /// 安全地将 dynamic 转换为 `Map<String, dynamic>`
  Map<String, dynamic> _safeParseMap(dynamic data) {
    if (data == null) return {};
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  /// 安全地将 dynamic 转换为 `List<String>`
  /// 过滤掉非字符串元素，防止 `List<String>.from` 抛出类型转换异常
  List<String> _safeParseStringList(dynamic data) {
    if (data == null) return [];
    if (data is! List) return [];
    return data.map((e) => e?.toString()).whereType<String>().toList();
  }

  // 数据状态
  Map<String, dynamic>? _healthOverview;
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _alerts = [];
  List<Map<String, dynamic>> _selfHealingActions = [];
  Map<String, dynamic>? _loadPrediction;
  Map<String, dynamic>? _dependencyGraph;
  Map<String, dynamic>? _chaosStatus;
  List<Map<String, dynamic>> _rootCauseResults = [];

  // 时间序列数据
  List<Map<String, dynamic>> _errorRateData = [];
  List<Map<String, dynamic>> _latencyData = [];
  List<Map<String, dynamic>> _requestsData = [];

  // 压力测试数据
  List<Map<String, dynamic>> _stressLoadSteps = [];
  List<Map<String, dynamic>> _stressChaosExperiments = [];
  Map<String, dynamic>? _stabilityAssessment;
  bool _isStressTestRunning = false;

  bool _isLoading = true;
  String? _error;
  DateTime? _lastRefresh;
  
  /// 防止并发加载的锁标志
  bool _isLoadingInProgress = false;

  /// 追踪后端是否可达（至少有一个 API 调用成功）
  bool _backendReachable = false;

  @override
  void initState() {
    super.initState();
    _service = ReliabilityService(ApiClient());
    _tabController = TabController(length: 5, vsync: this);
    _loadAllData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    // 先取消 timer 并置空，防止 timer 回调在 dispose 过程中执行
    final timer = _refreshTimer;
    _refreshTimer = null;
    timer?.cancel();
    
    _tabController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    // 取消任何现有的 timer，防止重复创建
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      // 双重检查：确保 widget 仍然挂载且 timer 未被取消
      // mounted 检查防止在 dispose 后执行数据加载
      if (mounted && _refreshTimer != null) {
        _loadAllData(silent: true);
      }
    });
  }

  Future<void> _loadAllData({bool silent = false}) async {
    // 防止并发请求：如果已有加载在进行中，跳过本次
    if (_isLoadingInProgress) {
      _log('Skipping load: another load is already in progress');
      return;
    }
    
    _isLoadingInProgress = true;
    
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      _log('Loading reliability data (silent: $silent)');
      
      // 追踪每个调用是否成功，用于判断后端是否可达
      int successCount = 0;
      int failCount = 0;

      Future<T> track<T>(Future<T> future, T fallback) async {
        try {
          final result = await future;
          successCount++;
          return result;
        } catch (e) {
          failCount++;
          return fallback;
        }
      }

      final results = await Future.wait([
        track(_service.getHealthOverview(), <String, dynamic>{}),
        track(_service.getServiceStatuses(), <Map<String, dynamic>>[]),
        track(_service.getAlerts(), <Map<String, dynamic>>[]),
        track(_service.getSelfHealingActions(), <Map<String, dynamic>>[]),
        track(_service.getLoadPrediction(), <String, dynamic>{}),
        track(_service.getDependencyGraph(), <String, dynamic>{}),
        track(_service.getChaosStatus(), <String, dynamic>{}),
        track(_service.getRootCauseResults(), <Map<String, dynamic>>[]),
        track(_service.getTimeSeries('errorRate'), <Map<String, dynamic>>[]),
        track(_service.getTimeSeries('latency'), <Map<String, dynamic>>[]),
        track(_service.getTimeSeries('requests'), <Map<String, dynamic>>[]),
        track(_service.getStressTestResults(), <String, dynamic>{}),
      ]);

      // 如果所有调用都失败，说明后端不可达
      final reachable = successCount > 0;

      if (mounted) {
        if (!reachable) {
          // 后端完全不可达 — 显示错误状态，不显示虚假零值
          _log('Backend unreachable: all $failCount calls failed', isError: true);
          if (!silent) {
            setState(() {
              _isLoading = false;
              _backendReachable = false;
              _error = '无法连接到后端服务';
            });
          }
        } else {
          setState(() {
            _backendReachable = true;
            _healthOverview = _safeParseMap(results[0]);
            _services = _safeParseList(results[1]);
            _alerts = _safeParseList(results[2]);
            _selfHealingActions = _safeParseList(results[3]);
            _loadPrediction = _safeParseMap(results[4]);
            _dependencyGraph = _safeParseMap(results[5]);
            _chaosStatus = _safeParseMap(results[6]);
            _rootCauseResults = _safeParseList(results[7]);
            _errorRateData = _safeParseList(results[8]);
            _latencyData = _safeParseList(results[9]);
            _requestsData = _safeParseList(results[10]);
            final stressResults = _safeParseMap(results[11]);
            _stressLoadSteps = _safeParseList(stressResults['loadSteps']);
            _stressChaosExperiments = _safeParseList(stressResults['chaosExperiments']);
            _stabilityAssessment = stressResults['stabilityAssessment'] is Map
                ? _safeParseMap(stressResults['stabilityAssessment'])
                : null;
            _isLoading = false;
            _error = null;
            _lastRefresh = DateTime.now();
          });
          _log('Reliability data loaded ($successCount ok, $failCount failed)');
        }
      }
    } on ApiException catch (e) {
      _log('Failed to load reliability data (API): ${e.message}', isError: true);
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _backendReachable = false;
          _error = e.message;
        });
      }
    } catch (e) {
      _log('Failed to load reliability data (unexpected): $e', isError: true);
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _backendReachable = false;
          _error = '加载可靠性数据失败';
        });
      }
    } finally {
      _isLoadingInProgress = false;
    }
  }

  Future<void> _acknowledgeAlert(String alertId) async {
    if (alertId.isEmpty) {
      _log('Cannot acknowledge alert: empty alertId', isError: true);
      return;
    }
    
    try {
      _log('Acknowledging alert: $alertId');
      await _service.acknowledgeAlert(alertId);
      _loadAllData(silent: true);
    } on ApiException catch (e) {
      _log('Failed to acknowledge alert (API): ${e.message}', isError: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('确认告警失败: ${e.message}')),
        );
      }
    } catch (e) {
      _log('Failed to acknowledge alert (unexpected): $e', isError: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('确认告警失败，请稍后重试')),
        );
      }
    }
  }

  Future<void> _triggerRootCauseAnalysis() async {
    try {
      _log('Triggering root cause analysis');
      await _service.triggerRootCauseAnalysis();
      _loadAllData(silent: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('根因分析已触发')),
        );
      }
    } on ApiException catch (e) {
      _log('Failed to trigger RCA (API): ${e.message}', isError: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('触发分析失败: ${e.message}')),
        );
      }
    } catch (e) {
      _log('Failed to trigger RCA (unexpected): $e', isError: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('触发分析失败，请稍后重试')),
        );
      }
    }
  }

  Future<void> _toggleChaos(bool enable) async {
    try {
      _log('Toggling chaos: $enable');
      if (enable) {
        await _service.enableChaos();
      } else {
        await _service.disableChaos();
      }
      _loadAllData(silent: true);
    } on ApiException catch (e) {
      _log('Failed to toggle chaos (API): ${e.message}', isError: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: ${e.message}')),
        );
      }
    } catch (e) {
      _log('Failed to toggle chaos (unexpected): $e', isError: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作失败，请稍后重试')),
        );
      }
    }
  }

  Future<void> _startExperiment(String experimentId) async {
    if (experimentId.isEmpty) {
      _log('Cannot start experiment: empty experimentId', isError: true);
      return;
    }
    
    try {
      _log('Starting experiment: $experimentId');
      await _service.startChaosExperiment(experimentId);
      _loadAllData(silent: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('实验已启动')),
        );
      }
    } on ApiException catch (e) {
      _log('Failed to start experiment (API): ${e.message}', isError: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动实验失败: ${e.message}')),
        );
      }
    } catch (e) {
      _log('Failed to start experiment (unexpected): $e', isError: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('启动实验失败，请稍后重试')),
        );
      }
    }
  }

  Future<void> _stopExperiment() async {
    try {
      _log('Stopping experiment');
      await _service.stopChaosExperiment();
      _loadAllData(silent: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('实验已停止')),
        );
      }
    } on ApiException catch (e) {
      _log('Failed to stop experiment (API): ${e.message}', isError: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('停止实验失败: ${e.message}')),
        );
      }
    } catch (e) {
      _log('Failed to stop experiment (unexpected): $e', isError: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('停止实验失败，请稍后重试')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTabBar(),
        Expanded(
          child: _isLoading && _healthOverview == null
              ? _buildLoadingState()
              : (_error != null && !_backendReachable)
                  ? _buildErrorState()
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildOverviewTab(),
                        _buildServicesTab(),
                        _buildAnalyticsTab(),
                        _buildChaosTab(),
                        _buildStressTestTab(),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF6366F1),
              unselectedLabelColor: const Color(0xFF64748B),
              indicatorColor: const Color(0xFF6366F1),
              indicatorWeight: 3,
              tabs: const [
                Tab(text: '概览', icon: Icon(Icons.dashboard_outlined, size: 20)),
                Tab(text: '服务', icon: Icon(Icons.dns_outlined, size: 20)),
                Tab(text: '分析', icon: Icon(Icons.analytics_outlined, size: 20)),
                Tab(text: '混沌', icon: Icon(Icons.bug_report_outlined, size: 20)),
                Tab(text: '压力测试', icon: Icon(Icons.speed_outlined, size: 20)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (_lastRefresh != null)
                  Text(
                    '更新于 ${_lastRefresh!.hour}:${_lastRefresh!.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: _isLoading ? null : () => _loadAllData(),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  tooltip: '刷新数据',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('加载可靠性数据...'),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text(
            '加载失败',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? '未知错误',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _loadAllData(),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    // 使用安全解析避免类型转换异常
    final services = _safeParseMap(_healthOverview?['services']);
    final metrics = _safeParseMap(_healthOverview?['metrics']);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 健康评分卡片
          HealthScoreCard(
            score: (_healthOverview?['overallScore'] as num?)?.toDouble() ?? 0,
            grade: _healthOverview?['grade'] ?? 'unknown',
            healthyServices: (services['healthy'] as num?)?.toInt() ?? 0,
            degradedServices: (services['degraded'] as num?)?.toInt() ?? 0,
            unhealthyServices: (services['unhealthy'] as num?)?.toInt() ?? 0,
            criticalIssues: _safeParseStringList(_healthOverview?['criticalIssues']),
            warnings: _safeParseStringList(_healthOverview?['warnings']),
            onRefresh: () => _loadAllData(),
          ),
          const SizedBox(height: 24),
          
          // 关键指标
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: '错误率',
                  value: '${(((metrics['errorRate'] as num?)?.toDouble() ?? 0) * 100).toStringAsFixed(2)}%',
                  icon: Icons.error_outline,
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  title: '平均延迟',
                  value: '${(metrics['avgLatencyMs'] as num?)?.toStringAsFixed(0) ?? '0'}ms',
                  icon: Icons.speed,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  title: 'P99 延迟',
                  value: '${(metrics['p99LatencyMs'] as num?)?.toStringAsFixed(0) ?? '0'}ms',
                  icon: Icons.timer,
                  color: Colors.purple,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  title: '请求/分钟',
                  value: '${(metrics['requestsPerMinute'] as num?)?.toInt() ?? 0}',
                  icon: Icons.trending_up,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 图表和告警
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    MetricsChart(
                      title: '错误率趋势',
                      metric: 'errorRate',
                      data: _errorRateData,
                      color: () {
                        final latest = (_errorRateData.isNotEmpty
                            ? (_errorRateData.last['value'] as num?)?.toDouble()
                            : null) ?? 0;
                        if (latest <= 0) return Colors.green;
                        if (latest < 0.05) return Colors.orange;
                        return Colors.red;
                      }(),
                      unit: '%',
                      threshold: 0.05,
                    ),
                    const SizedBox(height: 16),
                    MetricsChart(
                      title: '延迟趋势',
                      metric: 'latency',
                      data: _latencyData,
                      color: Colors.orange,
                      unit: 'ms',
                      threshold: 500,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: [
                    AlertList(
                      alerts: _alerts,
                      onAcknowledge: _acknowledgeAlert,
                    ),
                    const SizedBox(height: 16),
                    SelfHealingActionsCard(
                      actions: _selfHealingActions,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServicesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 服务依赖图
          SizedBox(
            height: 400,
            child: DependencyGraph(
              graphData: _dependencyGraph ?? {'nodes': [], 'edges': []},
              onNodeTap: (nodeId) {
                // 可以显示服务详情
              },
            ),
          ),
          const SizedBox(height: 24),
          
          // 服务列表
          const Text(
            '服务状态',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          ServiceList(
            services: _services,
            onServiceTap: (serviceName) {
              // 可以显示服务详情弹窗
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 负载预测
          if (_loadPrediction != null && _loadPrediction!.isNotEmpty)
            LoadPredictionCard(
              prediction: _loadPrediction!,
              onRefresh: () => _loadAllData(silent: true),
            ),
          const SizedBox(height: 24),

          // 根因分析
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '根因分析',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _triggerRootCauseAnalysis,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('触发分析'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          if (_rootCauseResults.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.search_off, size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    Text(
                      '暂无根因分析结果',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._rootCauseResults.map((result) => _buildRcaCard(result)),

          const SizedBox(height: 24),

          // 请求量趋势
          MetricsChart(
            title: '请求量趋势',
            metric: 'requests',
            data: _requestsData,
            color: Colors.blue,
          ),
        ],
      ),
    );
  }

  Widget _buildRcaCard(Map<String, dynamic> result) {
    // 安全解析列表，避免直接 as List 可能的类型异常
    final hypothesesRaw = result['hypotheses'];
    final hypotheses = hypothesesRaw is List ? hypothesesRaw : [];
    final timelineRaw = result['timeline'];
    final timeline = timelineRaw is List ? timelineRaw : [];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.psychology,
                  color: Color(0xFF6366F1),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '分析 #${result['incidentId'] ?? ''}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      result['summary'] ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hypotheses.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              '可能原因',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            ...hypotheses.take(3).map((h) => _buildHypothesisItem(h)),
          ],
          if (timeline.isNotEmpty) ...[
            const SizedBox(height: 16),
            IncidentTimeline(
              // 安全解析时间线事件列表
              events: _safeParseList(timeline),
              title: '事件时间线',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHypothesisItem(Map<String, dynamic> hypothesis) {
    final confidence = (hypothesis['confidence'] as num?)?.toDouble() ?? 0;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: confidence,
              child: Container(
                decoration: BoxDecoration(
                  color: _getConfidenceColor(confidence),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${(confidence * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _getConfidenceColor(confidence),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hypothesis['description'] ?? '',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.6) return Colors.orange;
    return Colors.grey;
  }

  Widget _buildChaosTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChaosControlPanel(
            chaosEnabled: _chaosStatus?['enabled'] ?? false,
            experimentRunning: _chaosStatus?['experimentRunning'] ?? false,
            currentExperimentId: _chaosStatus?['currentExperimentId'],
            currentExperimentName: _chaosStatus?['currentExperimentName'],
            // 使用安全解析避免 List.from 遇到非 Map 元素时抛出异常
            experiments: _safeParseList(_chaosStatus?['registeredExperiments']),
            onEnableChaos: () => _toggleChaos(true),
            onDisableChaos: () => _toggleChaos(false),
            onStartExperiment: _startExperiment,
            onStopExperiment: _stopExperiment,
          ),
        ],
      ),
    );
  }

  Widget _buildStressTestTab() {
    return StressTestResultsWidget(
      loadSteps: _stressLoadSteps,
      chaosExperiments: _stressChaosExperiments,
      stabilityAssessment: _stabilityAssessment,
      isRunning: _isStressTestRunning,
      onRunStressTest: _runStressTest,
      onRunChaosTest: _runChaosTestSuite,
    );
  }

  Future<void> _runStressTest() async {
    setState(() => _isStressTestRunning = true);
    try {
      _log('Running stress test');
      await _service.runStressTest();
      // Reload results after test completes
      await _loadAllData(silent: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('压力测试已完成')),
        );
      }
    } on ApiException catch (e) {
      _log('Stress test failed (API): ${e.message}', isError: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('压力测试失败: ${e.message}')),
        );
      }
    } catch (e) {
      _log('Stress test failed (unexpected): $e', isError: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('压力测试失败，请稍后重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _isStressTestRunning = false);
    }
  }

  Future<void> _runChaosTestSuite() async {
    setState(() => _isStressTestRunning = true);
    try {
      _log('Running chaos test suite');
      await _service.runChaosTest();
      await _loadAllData(silent: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('混沌测试已完成')),
        );
      }
    } on ApiException catch (e) {
      _log('Chaos test failed (API): ${e.message}', isError: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('混沌测试失败: ${e.message}')),
        );
      }
    } catch (e) {
      _log('Chaos test failed (unexpected): $e', isError: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('混沌测试失败，请稍后重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _isStressTestRunning = false);
    }
  }
}

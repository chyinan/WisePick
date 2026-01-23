import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import 'dashboard_service.dart';
import 'widgets/stats_dashboard.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _service = DashboardService(ApiClient());
  Map<String, dynamic>? _userStats;
  Map<String, dynamic>? _systemStats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userStats = await _service.getUserStats();
      final systemStats = await _service.getSystemStats();
      if (mounted) {
        setState(() {
          _userStats = userStats;
          _systemStats = systemStats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WisePick 管理后台'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('数据概览', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 16),
                  if (_userStats != null && _systemStats != null)
                    StatsDashboard(
                      userStats: _userStats!,
                      systemStats: _systemStats!,
                    ),
                ],
              ),
            ),
    );
  }
}

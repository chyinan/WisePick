import 'package:flutter/material.dart';

class StatsDashboard extends StatelessWidget {
  final Map<String, dynamic> userStats;
  final Map<String, dynamic> systemStats;

  const StatsDashboard({
    super.key,
    required this.userStats,
    required this.systemStats,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        final crossAxisCount = isWide ? 4 : 2;

        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.5,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildStatCard(
              context,
              '总用户数',
              '${userStats['totalUsers'] ?? 0}',
              Icons.people,
              Colors.blue,
            ),
            _buildStatCard(
              context,
              '日活跃',
              '${userStats['activeUsers']?['daily'] ?? 0}',
              Icons.today,
              Colors.green,
            ),
            _buildStatCard(
              context,
              'API 调用',
              '${systemStats['apiCalls'] ?? 0}',
              Icons.api,
              Colors.orange,
            ),
            _buildStatCard(
              context,
              '系统状态',
              '${systemStats['uptime'] ?? "Unknown"}',
              Icons.check_circle,
              Colors.purple,
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

class StatsDashboard extends StatelessWidget {
  final Map<String, dynamic> userStats;
  final Map<String, dynamic> systemStats;
  final List<Map<String, dynamic>>? recentUsers;
  final List<Map<String, dynamic>>? chartData;

  const StatsDashboard({
    super.key,
    required this.userStats,
    required this.systemStats,
    this.recentUsers,
    this.chartData,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 核心指标卡片
        _buildSectionTitle(context, '核心指标', Icons.dashboard_rounded),
        const SizedBox(height: 12),
        _buildMainStatsGrid(context),
        
        const SizedBox(height: 32),
        
        // 用户数据卡片
        _buildSectionTitle(context, '用户数据', Icons.people_rounded),
        const SizedBox(height: 12),
        _buildUserStatsGrid(context),

        const SizedBox(height: 32),

        // 系统数据卡片
        _buildSectionTitle(context, '业务数据', Icons.shopping_bag_rounded),
        const SizedBox(height: 12),
        _buildSystemStatsGrid(context),

        if (chartData != null && chartData!.isNotEmpty) ...[
          const SizedBox(height: 32),
          _buildSectionTitle(context, '7日趋势', Icons.trending_up_rounded),
          const SizedBox(height: 12),
          _buildActivityChart(context),
        ],

        if (recentUsers != null && recentUsers!.isNotEmpty) ...[
          const SizedBox(height: 32),
          _buildSectionTitle(context, '最近注册', Icons.person_add_rounded),
          const SizedBox(height: 12),
          _buildRecentUsersList(context),
        ],
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }

  Widget _buildMainStatsGrid(BuildContext context) {
    final activeUsers = userStats['activeUsers'] as Map<String, dynamic>?;
    final cartItems = systemStats['cartItems'] as Map<String, dynamic>?;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildGradientStatCard(
              context,
              title: '总用户',
              value: '${userStats['totalUsers'] ?? 0}',
              subtitle: '累计注册用户数',
              icon: Icons.people_alt_rounded,
              gradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              width: isWide ? (constraints.maxWidth - 48) / 4 : (constraints.maxWidth - 16) / 2,
            ),
            _buildGradientStatCard(
              context,
              title: '日活跃',
              value: '${activeUsers?['daily'] ?? 0}',
              subtitle: '今日活跃用户',
              icon: Icons.flash_on_rounded,
              gradient: const [Color(0xFF06B6D4), Color(0xFF0EA5E9)],
              width: isWide ? (constraints.maxWidth - 48) / 4 : (constraints.maxWidth - 16) / 2,
            ),
            _buildGradientStatCard(
              context,
              title: '购物车',
              value: '${cartItems?['total'] ?? 0}',
              subtitle: '商品总数量',
              icon: Icons.shopping_cart_rounded,
              gradient: const [Color(0xFFF59E0B), Color(0xFFF97316)],
              width: isWide ? (constraints.maxWidth - 48) / 4 : (constraints.maxWidth - 16) / 2,
            ),
            _buildGradientStatCard(
              context,
              title: '会话数',
              value: '${(systemStats['conversations'] as Map?)?['total'] ?? 0}',
              subtitle: 'AI对话会话',
              icon: Icons.chat_bubble_rounded,
              gradient: const [Color(0xFF10B981), Color(0xFF34D399)],
              width: isWide ? (constraints.maxWidth - 48) / 4 : (constraints.maxWidth - 16) / 2,
            ),
          ],
        );
      },
    );
  }

  Widget _buildGradientStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required List<Color> gradient,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradient[0].withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserStatsGrid(BuildContext context) {
    final activeUsers = userStats['activeUsers'] as Map<String, dynamic>?;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        final cardWidth = isWide 
            ? (constraints.maxWidth - 32) / 3 
            : (constraints.maxWidth - 16) / 2;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildStatCard(
              context,
              title: '今日新增',
              value: '${userStats['todayNewUsers'] ?? 0}',
              icon: Icons.person_add_alt_1_rounded,
              color: const Color(0xFF6366F1),
              width: cardWidth,
            ),
            _buildStatCard(
              context,
              title: '本周新增',
              value: '${userStats['weekNewUsers'] ?? 0}',
              icon: Icons.calendar_view_week_rounded,
              color: const Color(0xFF8B5CF6),
              width: cardWidth,
            ),
            _buildStatCard(
              context,
              title: '本月新增',
              value: '${userStats['monthNewUsers'] ?? 0}',
              icon: Icons.calendar_month_rounded,
              color: const Color(0xFFA855F7),
              width: cardWidth,
            ),
            _buildStatCard(
              context,
              title: '月活跃',
              value: '${activeUsers?['monthly'] ?? 0}',
              icon: Icons.trending_up_rounded,
              color: const Color(0xFF06B6D4),
              width: cardWidth,
            ),
            _buildStatCard(
              context,
              title: '已验证',
              value: '${userStats['verifiedUsers'] ?? 0}',
              icon: Icons.verified_user_rounded,
              color: const Color(0xFF10B981),
              width: cardWidth,
            ),
            _buildStatCard(
              context,
              title: '验证率',
              value: '${userStats['verificationRate'] ?? 0}%',
              icon: Icons.percent_rounded,
              color: const Color(0xFF14B8A6),
              width: cardWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _buildSystemStatsGrid(BuildContext context) {
    final cartItems = systemStats['cartItems'] as Map<String, dynamic>?;
    final conversations = systemStats['conversations'] as Map<String, dynamic>?;
    final messages = systemStats['messages'] as Map<String, dynamic>?;
    final devices = systemStats['devices'] as Map<String, dynamic>?;
    final platforms = cartItems?['byPlatform'] as Map<String, dynamic>?;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        final cardWidth = isWide 
            ? (constraints.maxWidth - 32) / 3 
            : (constraints.maxWidth - 16) / 2;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildStatCard(
              context,
              title: '今日购物车',
              value: '${cartItems?['today'] ?? 0}',
              icon: Icons.add_shopping_cart_rounded,
              color: const Color(0xFFF59E0B),
              width: cardWidth,
            ),
            _buildStatCard(
              context,
              title: '今日会话',
              value: '${conversations?['today'] ?? 0}',
              icon: Icons.chat_rounded,
              color: const Color(0xFF10B981),
              width: cardWidth,
            ),
            _buildStatCard(
              context,
              title: '消息总数',
              value: '${messages?['total'] ?? 0}',
              icon: Icons.message_rounded,
              color: const Color(0xFF3B82F6),
              width: cardWidth,
            ),
            _buildStatCard(
              context,
              title: '活跃设备',
              value: '${devices?['active'] ?? 0}',
              icon: Icons.devices_rounded,
              color: const Color(0xFF8B5CF6),
              width: cardWidth,
            ),
            if (platforms != null) ...[
              _buildStatCard(
                context,
                title: '淘宝商品',
                value: '${platforms['taobao'] ?? 0}',
                icon: Icons.store_rounded,
                color: const Color(0xFFFF6B00),
                width: cardWidth,
              ),
              _buildStatCard(
                context,
                title: '京东商品',
                value: '${platforms['jd'] ?? 0}',
                icon: Icons.storefront_rounded,
                color: const Color(0xFFE53935),
                width: cardWidth,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityChart(BuildContext context) {
    if (chartData == null || chartData!.isEmpty) {
      return const SizedBox.shrink();
    }

    // 找出最大值用于计算比例
    int maxValue = 1;
    for (final data in chartData!) {
      final newUsers = data['newUsers'] as int? ?? 0;
      final activeUsers = data['activeUsers'] as int? ?? 0;
      final cartItems = data['cartItems'] as int? ?? 0;
      final max = [newUsers, activeUsers, cartItems].reduce((a, b) => a > b ? a : b);
      if (max > maxValue) maxValue = max;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 图例
          Row(
            children: [
              _buildLegendItem('新增用户', const Color(0xFF6366F1)),
              const SizedBox(width: 24),
              _buildLegendItem('活跃用户', const Color(0xFF06B6D4)),
              const SizedBox(width: 24),
              _buildLegendItem('购物车', const Color(0xFFF59E0B)),
            ],
          ),
          const SizedBox(height: 24),
          // 图表
          SizedBox(
            height: 200,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: chartData!.map((data) {
                final newUsers = data['newUsers'] as int? ?? 0;
                final activeUsers = data['activeUsers'] as int? ?? 0;
                final cartItems = data['cartItems'] as int? ?? 0;
                final label = data['label'] as String? ?? '';

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildBar(newUsers / maxValue, const Color(0xFF6366F1)),
                              const SizedBox(width: 2),
                              _buildBar(activeUsers / maxValue, const Color(0xFF06B6D4)),
                              const SizedBox(width: 2),
                              _buildBar(cartItems / maxValue, const Color(0xFFF59E0B)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildBar(double ratio, Color color) {
    final height = ratio * 160;
    return Container(
      width: 8,
      height: height < 4 ? 4 : height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildRecentUsersList(BuildContext context) {
    if (recentUsers == null || recentUsers!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          // 表头
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('邮箱', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF64748B)))),
                Expanded(flex: 2, child: Text('昵称', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF64748B)))),
                Expanded(flex: 2, child: Text('注册时间', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF64748B)))),
                Expanded(flex: 1, child: Text('状态', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF64748B)))),
              ],
            ),
          ),
          // 列表
          ...recentUsers!.take(5).map((user) => _buildUserRow(context, user)),
        ],
      ),
    );
  }

  Widget _buildUserRow(BuildContext context, Map<String, dynamic> user) {
    final createdAt = user['createdAt'] as String?;
    String formattedDate = '未知';
    if (createdAt != null) {
      final date = DateTime.tryParse(createdAt);
      if (date != null) {
        formattedDate = '${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
      }
    }

    final isVerified = user['emailVerified'] == true;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF6366F1).withOpacity(0.1),
                  child: Text(
                    (user['email'] as String?)?.substring(0, 1).toUpperCase() ?? '?',
                    style: const TextStyle(
                      color: Color(0xFF6366F1),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    user['email'] as String? ?? '',
                    style: const TextStyle(color: Color(0xFF1E293B)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              user['nickname'] as String? ?? '未设置',
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              formattedDate,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isVerified 
                    ? const Color(0xFF10B981).withOpacity(0.1)
                    : const Color(0xFFF59E0B).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isVerified ? '已验证' : '未验证',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isVerified 
                      ? const Color(0xFF10B981)
                      : const Color(0xFFF59E0B),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

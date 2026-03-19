import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import 'search_hotwords_service.dart';

class SearchHotwordsPage extends StatefulWidget {
  const SearchHotwordsPage({super.key});

  @override
  State<SearchHotwordsPage> createState() => _SearchHotwordsPageState();
}

class _SearchHotwordsPageState extends State<SearchHotwordsPage> {
  late final SearchHotwordsService _service;

  List<Map<String, dynamic>> _hotwords = [];
  List<Map<String, dynamic>> _trend = [];
  int _totalSearches = 0;
  int _uniqueKeywords = 0;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = SearchHotwordsService(ApiClient());
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final data = await _service.getHotwords(limit: 20);
      if (mounted) {
        setState(() {
          _hotwords = List<Map<String, dynamic>>.from(data['hotwords'] as List);
          _trend = List<Map<String, dynamic>>.from(data['trend'] as List);
          _totalSearches = data['totalSearches'] as int;
          _uniqueKeywords = data['uniqueKeywords'] as int;
          _isLoading = false;
        });
      }
    } catch (e) {
      developer.log('❌ SearchHotwords: $e', name: 'SearchHotwordsPage');
      if (mounted) setState(() { _isLoading = false; _error = '加载失败，请稍后重试'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded, size: 64, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: Color(0xFF64748B))),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded), label: const Text('重试')),
        ]),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildHeader(),
        const SizedBox(height: 24),
        _buildStatCards(),
        const SizedBox(height: 24),
        _buildTrendCard(),
        const SizedBox(height: 24),
        _buildBottomSection(),
      ]),
    );
  }

  // ── 页头 ──────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Row(children: [
      const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('搜索热词', style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
        SizedBox(height: 4),
        Text('分析用户搜索行为与关键词趋势',
            style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
      ]),
      const Spacer(),
      OutlinedButton.icon(
        onPressed: _loadData,
        icon: const Icon(Icons.refresh_rounded, size: 16),
        label: const Text('刷新'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF6366F1),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
    ]);
  }

  // ── 统计卡片 ──────────────────────────────────────────────────────────────

  Widget _buildStatCards() {
    final todayCount = _trend.isNotEmpty ? (_trend.last['count'] as int) : 0;
    final avgCount = _trend.isEmpty ? 0
        : (_trend.map((e) => e['count'] as int).reduce((a, b) => a + b) /
                _trend.length)
            .round();

    return Row(children: [
      Expanded(child: _StatCard(
          icon: Icons.search_rounded, label: '总搜索次数',
          value: _formatNumber(_totalSearches),
          sub: '含关键词的消息数', color: const Color(0xFF6366F1))),
      const SizedBox(width: 16),
      Expanded(child: _StatCard(
          icon: Icons.tag_rounded, label: '独立关键词',
          value: _formatNumber(_uniqueKeywords),
          sub: '去重后关键词总数', color: const Color(0xFF8B5CF6))),
      const SizedBox(width: 16),
      Expanded(child: _StatCard(
          icon: Icons.today_rounded, label: '今日搜索',
          value: _formatNumber(todayCount),
          sub: '今天含关键词消息', color: const Color(0xFF06B6D4))),
      const SizedBox(width: 16),
      Expanded(child: _StatCard(
          icon: Icons.show_chart_rounded, label: '日均搜索',
          value: _formatNumber(avgCount),
          sub: '近7天平均', color: const Color(0xFF10B981))),
    ]);
  }

  // ── 趋势图（全宽）────────────────────────────────────────────────────────

  Widget _buildTrendCard() {
    final maxCount = _trend.isEmpty ? 1
        : _trend.map((e) => e['count'] as int).reduce((a, b) => a > b ? a : b);
    final safeMax = maxCount == 0 ? 1 : maxCount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.area_chart_rounded,
                color: Color(0xFF6366F1), size: 18)),
          const SizedBox(width: 10),
          const Text('近7天搜索趋势', style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
          const Spacer(),
          if (_trend.isNotEmpty)
            _TrendBadge(label: '峰值 $maxCount', color: const Color(0xFF6366F1)),
        ]),
        const SizedBox(height: 28),
        SizedBox(
          height: 200,
          child: _trend.isEmpty
              ? const Center(child: Text('暂无趋势数据',
                  style: TextStyle(color: Color(0xFF94A3B8))))
              : CustomPaint(
                  painter: _TrendPainter(_trend, safeMax),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: _trend.map((item) {
                      final count = item['count'] as int;
                      final label = item['label'] as String;
                      final isToday = _trend.last == item;
                      return Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const Spacer(),
                            Text('$count', style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600,
                                color: isToday
                                    ? const Color(0xFF6366F1)
                                    : const Color(0xFF94A3B8))),
                            const SizedBox(height: 6),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 600),
                              curve: Curves.easeOutCubic,
                              height: math.max(4, (count / safeMax) * 140),
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: isToday
                                      ? [const Color(0xFF6366F1), const Color(0xFF818CF8)]
                                      : [const Color(0xFFE2E8F0), const Color(0xFFF1F5F9)]),
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(6))),
                            ),
                            const SizedBox(height: 10),
                            Text(label, style: TextStyle(
                                fontSize: 11,
                                color: isToday
                                    ? const Color(0xFF6366F1)
                                    : const Color(0xFF94A3B8),
                                fontWeight: isToday
                                    ? FontWeight.w600 : FontWeight.normal)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
        ),
      ]),
    );
  }

  // ── 底部：排行榜 + 词云 ───────────────────────────────────────────────────

  Widget _buildBottomSection() {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 5, child: _buildRankList()),
      const SizedBox(width: 24),
      Expanded(flex: 3, child: _buildWordCloud()),
    ]);
  }

  Widget _buildRankList() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Row(children: [
            const Icon(Icons.local_fire_department_rounded,
                color: Color(0xFFF59E0B), size: 20),
            const SizedBox(width: 8),
            const Text('热词排行榜', style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
            const Spacer(),
            Text('Top 10 关键词',
                style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          ]),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(children: const [
            SizedBox(width: 32, child: Text('#', style: TextStyle(
                fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600))),
            Expanded(flex: 2, child: Text('关键词', style: TextStyle(
                fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600))),
            SizedBox(width: 12),
            Expanded(flex: 3, child: Text('占比', style: TextStyle(
                fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600))),
            SizedBox(width: 12),
            SizedBox(width: 52, child: Text('次数', textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600))),
          ]),
        ),
        const Divider(height: 1, color: Color(0xFFF1F5F9)),
        if (_hotwords.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: Text('暂无搜索数据',
                style: TextStyle(color: Color(0xFF94A3B8)))),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _hotwords.take(10).length,
            separatorBuilder: (_, __) => const Divider(
                height: 1, indent: 24, endIndent: 24, color: Color(0xFFF8FAFC)),
            itemBuilder: (context, index) {
              final top10 = _hotwords.take(10).toList();
              final item = top10[index];
              final keyword = item['keyword'] as String;
              final count = item['count'] as int;
              final maxCount = (_hotwords.first['count'] as int).toDouble();
              final ratio = maxCount > 0 ? count / maxCount : 0.0;

              final rankColors = [
                const Color(0xFFEF4444),
                const Color(0xFFF59E0B),
                const Color(0xFF10B981),
              ];
              final barColor = index < 3
                  ? rankColors[index]
                  : const Color(0xFF94A3B8).withOpacity(0.4);

              Widget rankWidget;
              if (index < 3) {
                rankWidget = Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                      color: rankColors[index],
                      borderRadius: BorderRadius.circular(6)),
                  child: Center(child: Text('${index + 1}',
                      style: const TextStyle(color: Colors.white,
                          fontSize: 11, fontWeight: FontWeight.w700))));
              } else {
                rankWidget = SizedBox(width: 22,
                    child: Text('${index + 1}', style: const TextStyle(
                        fontSize: 12, color: Color(0xFFCBD5E1),
                        fontWeight: FontWeight.w600)));
              }

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
                child: Row(children: [
                  SizedBox(width: 32, child: rankWidget),
                  Expanded(flex: 2, child: Text(keyword,
                      style: TextStyle(fontSize: 13,
                          color: index < 3
                              ? const Color(0xFF1E293B) : const Color(0xFF475569),
                          fontWeight: index < 3
                              ? FontWeight.w500 : FontWeight.normal),
                      overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 12),
                  Expanded(flex: 3, child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                          value: ratio, minHeight: 6,
                          backgroundColor: const Color(0xFFF1F5F9),
                          valueColor: AlwaysStoppedAnimation<Color>(barColor)))),
                  const SizedBox(width: 12),
                  SizedBox(width: 52, child: Text('$count',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: index < 3
                              ? const Color(0xFF1E293B) : const Color(0xFF94A3B8)))),
                ]),
              );
            },
          ),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _buildWordCloud() {
    final top20 = _hotwords.take(20).toList();
    if (top20.isEmpty) {
      return Container(
        height: 300,
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: const Center(child: Text('暂无数据',
            style: TextStyle(color: Color(0xFF94A3B8)))));
    }
    final maxCount = (top20.first['count'] as int).toDouble();
    const colors = [
      Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFF06B6D4),
      Color(0xFF10B981), Color(0xFFF59E0B), Color(0xFFEF4444),
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.cloud_rounded, color: Color(0xFF8B5CF6), size: 20),
          SizedBox(width: 8),
          Text('关键词词云', style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
        ]),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10, runSpacing: 10,
          children: top20.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final keyword = item['keyword'] as String;
            final count = item['count'] as int;
            final ratio = maxCount > 0 ? count / maxCount : 0.0;
            final fontSize = 11.0 + ratio * 10;
            final color = colors[index % colors.length];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.2))),
              child: Text(keyword, style: TextStyle(
                  fontSize: fontSize, color: color, fontWeight: FontWeight.w500)));
          }).toList(),
        ),
      ]),
    );
  }

  String _formatNumber(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}w';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

// ── 辅助 Widgets ──────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color color;

  const _StatCard({
    required this.icon, required this.label,
    required this.value, required this.sub, required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18)),
          const Spacer(),
          Container(width: 6, height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        ]),
        const SizedBox(height: 16),
        Text(value, style: const TextStyle(
            fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF0F172A),
            letterSpacing: -0.5)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF475569))),
        const SizedBox(height: 2),
        Text(sub, style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1))),
      ]),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _TrendBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(
          fontSize: 11, color: color, fontWeight: FontWeight.w600)));
  }
}

class _TrendPainter extends CustomPainter {
  final List<Map<String, dynamic>> trend;
  final int maxCount;
  _TrendPainter(this.trend, this.maxCount);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = size.height * 0.1 + (size.height * 0.7 / 4) * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.trend != trend;
}

import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import 'cart_service.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final _service = CartService(ApiClient());

  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _stats;
  int _total = 0;
  int _currentPage = 1;
  int _totalPages = 1;
  bool _isLoading = true;
  String? _error;
  String? _selectedPlatform;
  
  /// 防止并发加载的锁标志
  bool _isLoadingInProgress = false;
  
  void _log(String message, {bool isError = false}) {
    final prefix = isError ? '❌ Cart' : '🛒 Cart';
    developer.log('$prefix: $message', name: 'CartPage');
  }
  
  // 安全地从 Map 获取值
  T _safeGet<T>(Map<String, dynamic>? map, String key, T defaultValue) {
    if (map == null) return defaultValue;
    final value = map[key];
    if (value is T) return value;
    return defaultValue;
  }

  String _safeGetString(Map<String, dynamic>? map, String key, [String defaultValue = '']) {
    final value = map?[key];
    if (value == null) return defaultValue;
    return value.toString();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // 防止并发请求
    if (_isLoadingInProgress) return;
    _isLoadingInProgress = true;
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _log('Loading cart data (page: $_currentPage, platform: $_selectedPlatform)');
      final results = await Future.wait([
        _service.getCartItems(
          page: _currentPage,
          platform: _selectedPlatform,
        ),
        _service.getCartStats().catchError((e) {
          _log('Failed to load cart stats: $e', isError: true);
          return <String, dynamic>{};
        }),
      ]);

      if (mounted) {
        final itemsResult = results[0];
        setState(() {
          _items = List<Map<String, dynamic>>.from(itemsResult['items'] ?? []);
          _total = (itemsResult['total'] as num?)?.toInt() ?? 0;
          // 确保 totalPages 至少为 1，避免显示 "1/0"
          _totalPages = ((itemsResult['totalPages'] as num?)?.toInt() ?? 1).clamp(1, 10000);
          _stats = results[1] as Map<String, dynamic>?;
          _isLoading = false;
        });
        _log('Cart data loaded: ${_items.length} items');
      }
    } on ApiException catch (e) {
      _log('Cart loading failed (API): ${e.message}', isError: true);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.message;
        });
      }
    } catch (e) {
      _log('Cart loading failed (unexpected): $e', isError: true);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '加载购物车数据失败';
        });
      }
    } finally {
      _isLoadingInProgress = false;
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final itemId = item['id']?.toString();
    final itemTitle = _safeGetString(item, 'title', '未知商品');
    
    if (itemId == null || itemId.isEmpty) {
      _log('Cannot delete item: missing ID', isError: true);
      return;
    }
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除商品"$itemTitle"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        _log('Deleting cart item: $itemId');
        await _service.deleteCartItem(itemId);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('商品已删除'), backgroundColor: Colors.green),
          );
        }
      } on ApiException catch (e) {
        _log('Failed to delete cart item: ${e.message}', isError: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: ${e.message}'), backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        _log('Unexpected error deleting cart item: $e', isError: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('删除失败，请稍后重试'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 统计卡片
        if (_stats != null) _buildStatsCards(),
        const SizedBox(height: 24),
        // 商品列表
        Expanded(
          child: _buildItemsList(),
        ),
      ],
    );
  }

  Widget _buildStatsCards() {
    if (_stats == null) return const SizedBox.shrink();
    
    // 安全解析 List<Map>，避免使用 cast<> 导致运行时异常
    final rawPlatforms = _stats!['byPlatform'];
    final platforms = rawPlatforms is List
        ? rawPlatforms.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildStatCard(
            icon: Icons.shopping_cart_rounded,
            title: '总商品数',
            value: '${_safeGet<num>(_stats, 'total', 0)}',
            subtitle: '今日新增 ${_safeGet<num>(_stats, 'todayNew', 0)}',
            color: const Color(0xFF6366F1),
          ),
          const SizedBox(width: 16),
          _buildStatCard(
            icon: Icons.attach_money_rounded,
            title: '总价值',
            value: '¥${_safeGetString(_stats, 'totalValue', '0.00')}',
            subtitle: '本周新增 ${_safeGet<num>(_stats, 'weekNew', 0)} 件',
            color: const Color(0xFF10B981),
          ),
          ...platforms.take(3).map((p) {
            final platform = _safeGetString(p, 'platform');
            return Padding(
              padding: const EdgeInsets.only(left: 16),
              child: _buildStatCard(
                icon: _getPlatformIcon(platform),
                title: _getPlatformName(platform),
                value: '${_safeGet<num>(p, 'count', 0)}',
                subtitle: '¥${_safeGetString(p, 'totalValue', '0.00')}',
                color: _getPlatformColor(platform),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsList() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 表头
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.shopping_cart_rounded, color: Color(0xFF6366F1)),
                const SizedBox(width: 12),
                const Text(
                  '购物车数据',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const Spacer(),
                // 平台筛选
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedPlatform,
                      hint: const Text('全部平台'),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('全部平台')),
                        DropdownMenuItem(value: 'jd', child: Text('京东')),
                        DropdownMenuItem(value: 'taobao', child: Text('淘宝')),
                        DropdownMenuItem(value: 'pdd', child: Text('拼多多')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedPlatform = value;
                          _currentPage = 1;
                        });
                        _loadData();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '共 $_total 件商品',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: '刷新',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 列表内容
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : _items.isEmpty
                        ? _buildEmpty()
                        : _buildTable(),
          ),
          // 分页
          if (_totalPages > 1) _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
          dataRowMinHeight: 72,
          dataRowMaxHeight: 80,
          columnSpacing: 24,
          columns: const [
            DataColumn(label: SizedBox(width: 300, child: Text('商品信息'))),
            DataColumn(label: Text('平台')),
            DataColumn(label: Text('价格')),
            DataColumn(label: Text('用户')),
            DataColumn(label: Text('添加时间')),
            DataColumn(label: Text('操作')),
          ],
        rows: _items.map((item) {
          final imageUrl = _safeGetString(item, 'imageUrl');
          final title = _safeGetString(item, 'title', '未知商品');
          final shopTitle = _safeGetString(item, 'shopTitle');
          final platform = _safeGetString(item, 'platform');
          final finalPrice = item['finalPrice'] ?? item['price'] ?? '0';
          final originalPrice = item['originalPrice'];
          final userNickname = _safeGetString(item, 'userNickname', '未知');
          final userEmail = _safeGetString(item, 'userEmail');
          final createdAt = _safeGetString(item, 'createdAt');
          
          return DataRow(cells: [
            DataCell(
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            width: 50,
                            height: 50,
                            errorBuilder: (_, __, ___) => const Icon(Icons.image, color: Colors.grey),
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              );
                            },
                          )
                        : const Icon(Icons.image, color: Colors.grey),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        if (shopTitle.isNotEmpty)
                          Text(
                            shopTitle,
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            DataCell(_buildPlatformChip(platform)),
            DataCell(
              Builder(builder: (context) {
                final fp = double.tryParse('$finalPrice') ?? 0;
                final op = double.tryParse('${originalPrice ?? finalPrice}') ?? 0;
                final hasDiscount = originalPrice != null && op > fp && (op - fp).abs() > 0.01;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '¥$finalPrice',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: hasDiscount
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF1E293B),
                      ),
                    ),
                    if (hasDiscount)
                      Text(
                        '¥$originalPrice',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                  ],
                );
              }),
            ),
            DataCell(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(userNickname),
                  Text(
                    userEmail,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            DataCell(Text(_formatDate(createdAt))),
            DataCell(
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _deleteItem(item),
                tooltip: '删除',
              ),
            ),
          ]);
        }).toList(),
        ),
      ),
    );
  }

  Widget _buildPlatformChip(String platform) {
    final color = _getPlatformColor(platform);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _getPlatformName(platform),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _currentPage > 1
                ? () {
                    setState(() => _currentPage--);
                    _loadData();
                  }
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          const SizedBox(width: 8),
          Text('$_currentPage / $_totalPages'),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _currentPage < _totalPages
                ? () {
                    setState(() => _currentPage++);
                    _loadData();
                  }
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('暂无购物车数据', style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '-';
    final parsed = DateTime.tryParse(dateStr);
    if (parsed == null) return '-';
    // 统一转换为本地时间
    final date = parsed.toLocal();
    return '${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  IconData _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'jd':
        return Icons.store;
      case 'taobao':
        return Icons.shopping_bag;
      case 'pdd':
        return Icons.local_offer;
      default:
        return Icons.shopping_cart;
    }
  }

  String _getPlatformName(String platform) {
    switch (platform.toLowerCase()) {
      case 'jd':
        return '京东';
      case 'taobao':
        return '淘宝';
      case 'pdd':
        return '拼多多';
      default:
        return platform.isEmpty ? '未知' : platform;
    }
  }

  Color _getPlatformColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'jd':
        return const Color(0xFFE52B2B);
      case 'taobao':
        return const Color(0xFFFF5000);
      case 'pdd':
        return const Color(0xFFE02E24);
      default:
        return const Color(0xFF6366F1);
    }
  }
}

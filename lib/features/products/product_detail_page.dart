import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wisepick_dart_version/features/cart/cart_providers.dart';
import 'package:wisepick_dart_version/features/cart/cart_service.dart';
import 'package:flutter/services.dart';
import 'package:wisepick_dart_version/services/share_service.dart';
import 'product_model.dart';
import 'product_service.dart';
import 'package:wisepick_dart_version/features/products/jd_price_provider.dart';
import 'package:wisepick_dart_version/features/products/pdd_goods_detail_service.dart';
import 'package:wisepick_dart_version/features/products/taobao_item_detail_service.dart';
import 'package:wisepick_dart_version/features/chat/chat_service.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// 商品详情页，展示商品完整信息（响应式布局：窄屏竖排，宽屏左右并列）
class ProductDetailPage extends ConsumerStatefulWidget {
  final ProductModel product;
  final String? aiParsedRaw; // optional raw AI parsed JSON/text from chat message

  const ProductDetailPage({super.key, required this.product, this.aiParsedRaw});

  @override
  ConsumerState<ProductDetailPage> createState() => _ProductDetailPageState();
}
class _ProductDetailPageState extends ConsumerState<ProductDetailPage> {
  bool _isLoadingLink = false;
  bool _isFavorited = false;
  // New states for JD promotion data
  bool _isFetchingPromotion = false;
  bool _fetchFailed = false;
  Map<String, dynamic>? _promotionData;
  bool _isLoadingImages = false;
  String? _imageError;
  List<String> _galleryImages = const <String>[];
  int _currentImageIndex = 0;
  late final PageController _pageController;
  late final TaobaoItemDetailService _taobaoDetailService;
  late final PddGoodsDetailService _pddDetailService;
  Timer? _autoPlayTimer;
  static final Map<String, List<String>> _taobaoImageMemoryCache = {};
  static final Map<String, double> _taobaoPriceMemoryCache = {};
  static final Map<String, List<String>> _pddImageMemoryCache = {};
  static final Map<String, double> _pddPriceMemoryCache = {};
  double? _taobaoLatestPrice;
  double? _pddLatestPrice;
  double? _initialCartPrice;
  double? _lastCartPrice;
  bool _hasCartRecord = false;
  // AI 智能介绍相关状态
  bool _isLoadingAiIntro = false;
  String? _aiIntroContent;
  bool _aiIntroExpanded = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _taobaoDetailService = TaobaoItemDetailService();
    _pddDetailService = PddGoodsDetailService();
    _loadFavoriteState();
    _prepareInitialGallery();
    _loadCartPriceInfo();
    _loadCachedAiIntro();
  }

  @override
  void didUpdateWidget(ProductDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.product.id != widget.product.id) {
      _stopAutoPlay();
      _loadFavoriteState();
      setState(() {
        _galleryImages = const <String>[];
        _currentImageIndex = 0;
        _imageError = null;
        _taobaoLatestPrice = null;
        _pddLatestPrice = null;
        _initialCartPrice = null;
        _lastCartPrice = null;
        _hasCartRecord = false;
        _aiIntroContent = null;
        _isLoadingAiIntro = false;
        _aiIntroExpanded = false;
      });
      _prepareInitialGallery();
      _loadCartPriceInfo();
      _loadCachedAiIntro();
    }
  }

  @override
  void dispose() {
    _stopAutoPlay();
    _pageController.dispose();
    super.dispose();
  }

  // New function to fetch promotion data from our backend
  Future<void> _fetchPromotionData() async {
    if (widget.product.platform != 'jd' || widget.product.id.isEmpty) return;

    setState(() {
      _isFetchingPromotion = true;
      _fetchFailed = false;
    });

    try {
      // Replace with your actual server address
      final uri = Uri.parse(
        'http://127.0.0.1:9527/api/get-jd-promotion?sku=${widget.product.id}',
      );
      final response = await http.get(uri).timeout(const Duration(minutes: 2));

      final body = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        if (body['status'] == 'success' && body['data'] != null) {
          final data = body['data'];
          setState(() {
            _promotionData = data;
            // Mark as failed-for-link if no promotionUrl returned (merchant didn't set promotion)
            final String? pu = (data['promotionUrl'] as String?);
            if (pu == null || pu.trim().isEmpty) {
              _fetchFailed = true;
            }
          });
          // Notify the cache provider of the new price (if any)
          if (data['price'] != null) {
            ref
                .read(jdPriceCacheProvider.notifier)
                .updatePrice(
                  widget.product.id,
                  (data['price'] as num).toDouble(),
                );
          }
        } else {
          throw Exception('Backend failed to get promotion');
        }
      } else {
        // 服务器返回错误状态码，尝试解析用户友好的错误消息
        String errorMessage = '获取优惠失败，将使用原始链接';
        if (body is Map) {
          final userMessage = body['userMessage'] as String?;
          if (userMessage != null && userMessage.isNotEmpty) {
            errorMessage = userMessage;
          }
        }
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetchFailed = true;
      });
      
      // 显示错误消息
      String errorMessage = e.toString();
      // 清理 "Exception: " 前缀
      if (errorMessage.startsWith('Exception: ')) {
        errorMessage = errorMessage.substring('Exception: '.length);
      }
      
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage)));
    } finally {
      if (!mounted) return;
      setState(() {
        _isFetchingPromotion = false;
      });
    }
  }

  Future<void> _loadFavoriteState() async {
    try {
      final box = await Hive.openBox('favorites');
      final exists = box.containsKey(widget.product.id);
      if (!mounted) return;
      setState(() {
        _isFavorited = exists;
      });
    } catch (_) {}
  }

  Future<void> _loadCartPriceInfo() async {
    try {
      final box = await Hive.openBox(CartService.boxName);
      final raw = box.get(widget.product.id);
      if (raw is Map) {
        final map = Map<String, dynamic>.from(raw);
        final initPrice = _parseDouble(map['initial_price']);
        final lastPrice = _parseDouble(map['current_price'] ?? map['price']);
        if (!mounted) return;
        setState(() {
          _hasCartRecord = true;
          _initialCartPrice = initPrice;
          _lastCartPrice = lastPrice;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _hasCartRecord = false;
          _initialCartPrice = null;
          _lastCartPrice = null;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasCartRecord = false;
        _initialCartPrice = null;
        _lastCartPrice = null;
      });
    }
  }

  /// 加载缓存的 AI 商品介绍
  Future<void> _loadCachedAiIntro() async {
    try {
      const boxName = 'ai_intro_cache';
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox(boxName);
      }
      final box = Hive.box(boxName);
      final cacheKey = '${widget.product.platform}_${widget.product.id}';
      final cached = box.get(cacheKey);
      
      if (cached is Map) {
        final content = cached['content'] as String?;
        final timestamp = cached['timestamp'] as int?;
        
        if (content != null && content.isNotEmpty) {
          // 缓存有效期：7天
          final isExpired = timestamp != null &&
              DateTime.now().millisecondsSinceEpoch - timestamp > 7 * 24 * 60 * 60 * 1000;
          
          if (!isExpired && mounted) {
            setState(() {
              _aiIntroContent = content;
              _aiIntroExpanded = false; // 默认收起，让用户点击展开
            });
          }
        }
      }
    } catch (e) {
      // 缓存加载失败不影响正常使用
      debugPrint('加载 AI 介绍缓存失败: $e');
    }
  }

  /// 保存 AI 商品介绍到缓存
  Future<void> _saveAiIntroToCache(String content) async {
    try {
      const boxName = 'ai_intro_cache';
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox(boxName);
      }
      final box = Hive.box(boxName);
      final cacheKey = '${widget.product.platform}_${widget.product.id}';
      
      await box.put(cacheKey, {
        'content': content,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'productTitle': widget.product.title,
      });
    } catch (e) {
      debugPrint('保存 AI 介绍缓存失败: $e');
    }
  }

  /// 获取 AI 商品介绍
  Future<void> _fetchAiIntroduction() async {
    if (_isLoadingAiIntro) return;
    
    setState(() {
      _isLoadingAiIntro = true;
      _aiIntroExpanded = true;
    });

    try {
      final chatService = ChatService();
      final productTitle = widget.product.title;
      final platform = widget.product.platform;
      
      // 构建专门用于商品介绍的 prompt
      final prompt = '''请详细介绍以下商品的特点和优缺点：

商品名称：$productTitle
来源平台：${_getPlatformName(platform)}

请从以下几个方面进行介绍：
1. 产品概述（简要介绍这是什么产品）
2. 主要特点和优势
3. 可能的不足或需要注意的地方
4. 适合的用户群体
5. 购买建议

请用清晰易懂的中文回答，内容要客观公正。''';

      final reply = await chatService.getAiReply(prompt);
      
      if (!mounted) return;
      setState(() {
        _aiIntroContent = reply;
        _isLoadingAiIntro = false;
      });
      
      // 保存到缓存
      if (reply.isNotEmpty && !reply.startsWith('AI 服务调用失败')) {
        _saveAiIntroToCache(reply);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiIntroContent = '获取 AI 介绍失败：${e.toString()}';
        _isLoadingAiIntro = false;
      });
    }
  }

  String _getPlatformName(String platform) {
    switch (platform) {
      case 'jd':
        return '京东';
      case 'taobao':
        return '淘宝';
      case 'pdd':
        return '拼多多';
      default:
        return '未知平台';
    }
  }

  /// 构建 AI 智能介绍区域
  Widget _buildAiIntroSection(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 自定义 Markdown 样式
    final markdownStyleSheet = MarkdownStyleSheet(
      p: theme.textTheme.bodyMedium?.copyWith(
        height: 1.7,
        color: colorScheme.onSurface,
      ),
      h1: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      h2: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
        fontSize: 18,
      ),
      h3: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      strong: TextStyle(
        fontWeight: FontWeight.bold,
        color: colorScheme.primary,
      ),
      em: TextStyle(
        fontStyle: FontStyle.italic,
        color: colorScheme.onSurfaceVariant,
      ),
      listBullet: theme.textTheme.bodyMedium?.copyWith(
        color: colorScheme.primary,
      ),
      blockquote: theme.textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          left: BorderSide(
            color: colorScheme.primary,
            width: 4,
          ),
        ),
      ),
      blockquotePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      code: TextStyle(
        backgroundColor: colorScheme.surfaceContainerHighest,
        color: colorScheme.secondary,
        fontFamily: 'monospace',
        fontSize: 13,
      ),
      codeblockDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏和按钮
          InkWell(
            onTap: () {
              if (_aiIntroContent == null && !_isLoadingAiIntro) {
                _fetchAiIntroduction();
              } else {
                setState(() {
                  _aiIntroExpanded = !_aiIntroExpanded;
                });
              }
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      color: colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI 智能介绍',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        if (_aiIntroContent == null && !_isLoadingAiIntro)
                          Text(
                            '点击获取 AI 生成的商品详细介绍',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_isLoadingAiIntro)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  else if (_aiIntroContent == null)
                    FilledButton.icon(
                      onPressed: _fetchAiIntroduction,
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('获取介绍'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                    )
                  else
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _aiIntroExpanded = !_aiIntroExpanded;
                        });
                      },
                      icon: Icon(
                        _aiIntroExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // AI 介绍内容
          if (_aiIntroExpanded && (_isLoadingAiIntro || _aiIntroContent != null))
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: 1),
                  if (_isLoadingAiIntro)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
                      child: Column(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            '正在生成 AI 智能介绍...',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '请稍候，AI 正在分析商品信息',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Markdown 渲染区域 - 内容居中，最大宽度限制
                        Center(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 800),
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                            child: MarkdownBody(
                              data: _aiIntroContent ?? '',
                              styleSheet: markdownStyleSheet,
                              selectable: true,
                              onTapLink: (text, href, title) {
                                if (href != null) {
                                  launchUrl(Uri.parse(href));
                                }
                              },
                            ),
                          ),
                        ),
                        // 底部操作栏：免责声明 + 重新获取按钮
                        Center(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 800),
                            width: double.infinity,
                            margin: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 14,
                                  color: colorScheme.onSurfaceVariant.withOpacity(0.8),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'AI 生成内容不保证真实准确性，请自行仔细核对',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant.withOpacity(0.8),
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: _isLoadingAiIntro ? null : _fetchAiIntroduction,
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('重新获取'),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    textStyle: theme.textTheme.labelSmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _prepareInitialGallery() {
    final primary = widget.product.imageUrl;
    if (primary.isNotEmpty) {
      _setGalleryImages(<String>[primary], startAutoPlay: false);
    } else {
      _setGalleryImages(const <String>[], startAutoPlay: false);
    }

    if (widget.product.platform == 'taobao' && widget.product.id.isNotEmpty) {
      _loadCachedTaobaoPrice(widget.product.id).then((value) {
        if (value != null && mounted) {
          setState(() {
            _taobaoLatestPrice = value;
          });
        }
      });
      _loadTaobaoGallery();
    } else if (widget.product.platform == 'pdd' &&
        widget.product.id.isNotEmpty) {
      _loadCachedPddPrice(widget.product.id).then((value) {
        if (value != null && mounted) {
          setState(() => _pddLatestPrice = value);
        }
      });
      _loadPddDetail();
    }
  }

  void _setGalleryImages(List<String> images, {bool startAutoPlay = true}) {
    final sanitized = images
        .map(_normalizeImageUrl)
        .where((url) => url.isNotEmpty)
        .toList();
    setState(() {
      _galleryImages = sanitized;
      _currentImageIndex = 0;
      _isLoadingImages = false;
      if (sanitized.isNotEmpty) {
        _imageError = null;
      }
    });

    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.jumpToPage(0);
      });
    }

    if (!startAutoPlay) {
      _stopAutoPlay();
      return;
    }

    if (sanitized.length > 1) {
      _startAutoPlay();
    } else {
      _stopAutoPlay();
    }
  }

  List<String> _mergeWithPrimaryImage(List<String>? apiImages) {
    final merged = <String>[];
    void add(String? url) {
      final normalized = _normalizeImageUrl(url);
      if (normalized.isEmpty) return;
      if (!merged.contains(normalized)) merged.add(normalized);
    }

    if (apiImages != null) {
      for (final url in apiImages) {
        add(url);
      }
    }
    add(widget.product.imageUrl);
    return merged;
  }

  String _normalizeImageUrl(String? url) {
    if (url == null) return '';
    var normalized = url.trim();
    if (normalized.isEmpty) return '';
    if (normalized.startsWith('//')) {
      normalized = 'https:$normalized';
    }
    return normalized;
  }

  Future<void> _loadTaobaoGallery({bool forceRefresh = false}) async {
    if (widget.product.platform != 'taobao' || widget.product.id.isEmpty)
      return;

    if (!forceRefresh) {
      final cached = await _loadCachedTaobaoImages(widget.product.id);
      final cachedPrice = await _loadCachedTaobaoPrice(widget.product.id);
      if (cachedPrice != null && mounted) {
        setState(() => _taobaoLatestPrice = cachedPrice);
      }
      if (cached != null && cached.isNotEmpty) {
        if (!mounted) return;
        _setGalleryImages(_mergeWithPrimaryImage(cached));
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _isLoadingImages = true;
      _imageError = null;
    });

    try {
      final detail = await _taobaoDetailService.fetchDetail(widget.product.id);
      final fetched = detail.images;
      if (detail.preferredPrice != null && mounted) {
        setState(() => _taobaoLatestPrice = detail.preferredPrice);
        await _persistTaobaoPrice(widget.product.id, detail.preferredPrice!);
      }
      if (fetched.isNotEmpty) {
        await _persistTaobaoImages(widget.product.id, fetched);
      }
      if (!mounted) return;
      _setGalleryImages(_mergeWithPrimaryImage(fetched));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _imageError = e.toString();
        _isLoadingImages = false;
      });
    }
  }

  Future<List<String>?> _loadCachedTaobaoImages(String productId) async {
    final memory = _taobaoImageMemoryCache[productId];
    if (memory != null && memory.isNotEmpty) {
      return List<String>.from(memory);
    }
    try {
      if (!Hive.isBoxOpen('taobao_item_cache'))
        await Hive.openBox('taobao_item_cache');
      final box = Hive.box('taobao_item_cache');
      final stored = box.get('${productId}_images');
      if (stored is List) {
        final list = stored
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList();
        if (list.isNotEmpty) {
          _taobaoImageMemoryCache[productId] = list;
          return list;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _persistTaobaoImages(
    String productId,
    List<String> images,
  ) async {
    final sanitized = images
        .map(_normalizeImageUrl)
        .where((url) => url.isNotEmpty)
        .toList();
    if (sanitized.isEmpty) return;
    _taobaoImageMemoryCache[productId] = sanitized;
    try {
      if (!Hive.isBoxOpen('taobao_item_cache'))
        await Hive.openBox('taobao_item_cache');
      final box = Hive.box('taobao_item_cache');
      await box.put('${productId}_images', sanitized);
    } catch (_) {}
  }

  Future<double?> _loadCachedTaobaoPrice(String productId) async {
    final memory = _taobaoPriceMemoryCache[productId];
    if (memory != null) return memory;
    try {
      if (!Hive.isBoxOpen('taobao_item_cache'))
        await Hive.openBox('taobao_item_cache');
      final box = Hive.box('taobao_item_cache');
      final cached = box.get('${productId}_price');
      final value = _parseDouble(cached);
      if (value != null) {
        _taobaoPriceMemoryCache[productId] = value;
        return value;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _persistTaobaoPrice(String productId, double price) async {
    _taobaoPriceMemoryCache[productId] = price;
    try {
      if (!Hive.isBoxOpen('taobao_item_cache'))
        await Hive.openBox('taobao_item_cache');
      final box = Hive.box('taobao_item_cache');
      await box.put('${productId}_price', price);
      await box.put(
        '${productId}_price_updated_at',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  Future<void> _loadPddDetail({bool forceRefresh = false}) async {
    if (widget.product.platform != 'pdd' || widget.product.id.isEmpty) return;

    if (!forceRefresh) {
      final cachedImages = await _loadCachedPddImages(widget.product.id);
      final cachedPrice = await _loadCachedPddPrice(widget.product.id);
      if (cachedPrice != null && mounted) {
        setState(() => _pddLatestPrice = cachedPrice);
      }
      if (cachedImages != null && cachedImages.isNotEmpty) {
        if (!mounted) return;
        _setGalleryImages(_mergeWithPrimaryImage(cachedImages));
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _isLoadingImages = true;
      _imageError = null;
    });

    try {
      final detail = await _pddDetailService.fetchDetail(widget.product.id);
      final fetched = detail?.images ?? const <String>[];
      final newPrice = detail?.preferredPrice;
      if (newPrice != null && mounted) {
        setState(() => _pddLatestPrice = newPrice);
        await _persistPddPrice(widget.product.id, newPrice);
      }
      if (fetched.isNotEmpty) {
        await _persistPddImages(widget.product.id, fetched);
      }
      if (!mounted) return;
      _setGalleryImages(_mergeWithPrimaryImage(fetched));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _imageError = e.toString();
        _isLoadingImages = false;
      });
    }
  }

  Future<List<String>?> _loadCachedPddImages(String productId) async {
    final memory = _pddImageMemoryCache[productId];
    if (memory != null && memory.isNotEmpty) {
      return List<String>.from(memory);
    }
    try {
      if (!Hive.isBoxOpen('pdd_item_cache'))
        await Hive.openBox('pdd_item_cache');
      final box = Hive.box('pdd_item_cache');
      final stored = box.get('${productId}_images');
      if (stored is List) {
        final list = stored
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList();
        if (list.isNotEmpty) {
          _pddImageMemoryCache[productId] = list;
          return list;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _persistPddImages(
    String productId,
    List<String> images,
  ) async {
    final sanitized = images
        .map(_normalizeImageUrl)
        .where((url) => url.isNotEmpty)
        .toList();
    if (sanitized.isEmpty) return;
    _pddImageMemoryCache[productId] = sanitized;
    try {
      if (!Hive.isBoxOpen('pdd_item_cache'))
        await Hive.openBox('pdd_item_cache');
      final box = Hive.box('pdd_item_cache');
      await box.put('${productId}_images', sanitized);
    } catch (_) {}
  }

  Future<double?> _loadCachedPddPrice(String productId) async {
    final memory = _pddPriceMemoryCache[productId];
    if (memory != null) return memory;
    try {
      if (!Hive.isBoxOpen('pdd_item_cache'))
        await Hive.openBox('pdd_item_cache');
      final box = Hive.box('pdd_item_cache');
      final cached = box.get('${productId}_price');
      final value = _parseDouble(cached);
      if (value != null) {
        _pddPriceMemoryCache[productId] = value;
        return value;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _persistPddPrice(String productId, double price) async {
    _pddPriceMemoryCache[productId] = price;
    try {
      if (!Hive.isBoxOpen('pdd_item_cache'))
        await Hive.openBox('pdd_item_cache');
      final box = Hive.box('pdd_item_cache');
      await box.put('${productId}_price', price);
      await box.put(
        '${productId}_price_updated_at',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  double? _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  Widget _buildPriceDiffLabel(BuildContext context, double? currentPrice) {
    if (!_hasCartRecord || _initialCartPrice == null || currentPrice == null) {
      return const SizedBox.shrink();
    }
    // 如果初始价格为 0 或非常小，视为无效记录（商品加入时价格未获取）
    if (_initialCartPrice! < 0.01) {
      return const SizedBox.shrink();
    }
    // 如果当前价格为 0 或非常小，也不显示比价
    if (currentPrice < 0.01) {
      return const SizedBox.shrink();
    }
    final delta = currentPrice - _initialCartPrice!;
    if (delta.abs() < 0.01) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '与加入购物车时价格一致',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    final bool cheaper = delta < 0;
    final text = cheaper
        ? '该商品比加入购物车时降价¥${delta.abs().toStringAsFixed(2)}'
        : '该商品比加入购物车时涨价¥${delta.abs().toStringAsFixed(2)}';
    final color =
        cheaper ? Colors.green : Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }

  void _startAutoPlay() {
    _autoPlayTimer?.cancel();
    if (_galleryImages.length <= 1) return;
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _galleryImages.length <= 1 || !_pageController.hasClients)
        return;
      final nextIndex = (_currentImageIndex + 1) % _galleryImages.length;
      _pageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOut,
      );
    });
  }

  void _stopAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
  }

  Widget _buildImageCarousel(BuildContext context, bool wide) {
    final double width = wide ? 360 : double.infinity;
    final double height = wide ? 360 : 240;
    final borderRadius = BorderRadius.circular(12);
    Widget content;

    if (_galleryImages.isEmpty) {
      content = Center(
        child: _isLoadingImages
            ? const CircularProgressIndicator()
            : Icon(
                Icons.image_not_supported,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
      );
    } else {
      content = PageView.builder(
        key: ValueKey(_galleryImages.length),
        controller: _pageController,
        onPageChanged: (index) {
          if (!mounted) return;
          setState(() => _currentImageIndex = index);
        },
        itemCount: _galleryImages.length,
        itemBuilder: (ctx, index) =>
            _buildImageSlide(_galleryImages[index], index),
      );
    }

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: borderRadius,
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: content,
            ),
          ),
          if (_galleryImages.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_galleryImages.length, (idx) {
                  final active = idx == _currentImageIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 6,
                    width: active ? 16 : 6,
                    decoration: BoxDecoration(
                      color: active
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white70,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  );
                }),
              ),
            ),
          if (_isLoadingImages)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          if (_imageError != null)
            Positioned(
              top: 12,
              left: 12,
              child: Tooltip(
                message: _imageError!,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.error_outline,
                        color: Colors.orangeAccent,
                        size: 14,
                      ),
                      SizedBox(width: 4),
                      Text(
                        '图片加载失败',
                        style: TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageSlide(String url, int index) {
    final heroTag = _heroTagForIndex(index);
    return GestureDetector(
      onTap: () => _openFullScreenGallery(index),
      child: Hero(
        tag: heroTag,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded /
                          progress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) => Center(
            child: Icon(
              Icons.broken_image,
              size: 42,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  String _heroTagForIndex(int index) =>
      'product_detail_image_${widget.product.id}_$index';

  Future<void> _openFullScreenGallery(int initialIndex) async {
    if (!mounted || _galleryImages.isEmpty) return;
    final controller = PageController(initialPage: initialIndex);
    int currentIndex = initialIndex;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.92),
      barrierLabel: '关闭预览',
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return Material(
              color: Colors.black,
              child: SafeArea(
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: controller,
                      itemCount: _galleryImages.length,
                      onPageChanged: (value) {
                        setState(() => currentIndex = value);
                      },
                      itemBuilder: (context, index) {
                        final imageUrl = _galleryImages[index];
                        return InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 4.0,
                          child: Center(
                            child: Hero(
                              tag: _heroTagForIndex(index),
                              child: Image.network(
                                imageUrl,
                                fit: BoxFit.contain,
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return Center(
                                    child: CircularProgressIndicator(
                                      value: progress.expectedTotalBytes != null
                                          ? progress.cumulativeBytesLoaded /
                                                progress.expectedTotalBytes!
                                          : null,
                                      color: Colors.white,
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(
                                      Icons.broken_image,
                                      color: Colors.white54,
                                      size: 56,
                                    ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: IconButton(
                        onPressed: () => Navigator.of(ctx).maybePop(),
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 28,
                        ),
                        tooltip: '关闭',
                      ),
                    ),
                    if (_galleryImages.length > 1)
                      Positioned(
                        bottom: 20,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${currentIndex + 1} / ${_galleryImages.length}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    if (_galleryImages.length > 1) ...[
                      Positioned(
                        left: 12,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: IconButton(
                            onPressed: currentIndex > 0
                                ? () {
                                    controller.previousPage(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                : null,
                            icon: Icon(
                              Icons.chevron_left,
                              color: currentIndex > 0
                                  ? Colors.white
                                  : Colors.white30,
                              size: 48,
                            ),
                            tooltip: '上一张',
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: IconButton(
                            onPressed: currentIndex < _galleryImages.length - 1
                                ? () {
                                    controller.nextPage(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                : null,
                            icon: Icon(
                              Icons.chevron_right,
                              color: currentIndex < _galleryImages.length - 1
                                  ? Colors.white
                                  : Colors.white30,
                              size: 48,
                            ),
                            tooltip: '下一张',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Try to recover recommendation entries from loose / malformed AI JSON-like text.
  List<Map<String, dynamic>> _extractRecommendationsFromLooseJson(String raw) {
    final List<Map<String, dynamic>> out = [];
    if (raw.trim().isEmpty) return out;

    // normalize quotes
    String s = raw.replaceAll(RegExp(r'[“”«»„‟‘’`´]'), '"');
    // collapse multiple whitespace
    s = s.replaceAll(RegExp(r'\s+'), ' ');

    // split by occurrences that likely indicate separate recommendation objects
    final parts = <String>[];
    if (s.toLowerCase().contains('recommendations')) {
      // try to isolate array body
      final idx = s.toLowerCase().indexOf('recommendations');
      final body = s.substring(idx);
      // split by 'goods' or '},' as heuristics
      parts.addAll(
        RegExp(
          r'goods\b',
          caseSensitive: false,
        ).allMatches(body).map((m) => m.group(0) ?? ''),
      );
      // fallback to splitting by '},{' or '],[' or just split by '},"goods' patterns
      parts.addAll(body.split(RegExp(r'\},\s*\{')));
    } else {
      // generic split by occurrences of 'goods' or 'title'
      parts.addAll(
        s.split(RegExp(r'\bgoods\b|\btitle\b', caseSensitive: false)),
      );
    }

    // if splitting produced nothing useful, use the whole string as single part
    final candidates = (parts.isEmpty || parts.every((p) => p.trim().isEmpty))
        ? [s]
        : parts;

    final titleRe = RegExp(
      r'(?i)(?:title|tith[e!]*|tihe)\s*[:=]\s*"([^\"]{1,300})"',
    );
    final descRe = RegExp(
      r'(?i)(?:description|desc)\s*[:=]\s*"([^\"]{1,500})"',
    );
    final ratingRe = RegExp(r'(?i)(?:rating)\s*[:=]\s*([0-9]+(?:\.[0-9]+)?)');

    for (final part in candidates) {
      try {
        final Map<String, dynamic> item = {};
        final t = titleRe.firstMatch(part);
        if (t != null) item['title'] = t.group(1)!.trim();

        final d = descRe.firstMatch(part);
        if (d != null) item['description'] = d.group(1)!.trim();

        final r = ratingRe.firstMatch(part);
        if (r != null) item['rating'] = double.tryParse(r.group(1)!) ?? null;

        // if we found at least a title or description, keep it
        if (item.containsKey('title') || item.containsKey('description')) {
          out.add(item);
        }
      } catch (_) {}
    }

    return out;
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    return Scaffold(
      appBar: AppBar(title: Text(product.title)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool wide = constraints.maxWidth >= 700;

          Widget image = _buildImageCarousel(context, wide);

          Widget details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                product.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
              // debug: show product JSON for quick inspection, controlled by admin setting
              Align(
                alignment: Alignment.topRight,
                child: FutureBuilder<bool>(
                  future: () async {
                    try {
                      if (!Hive.isBoxOpen('settings'))
                        await Hive.openBox('settings');
                      final box = Hive.box('settings');
                      return box.get('show_product_json') as bool? ?? false;
                    } catch (_) {
                      return false;
                    }
                  }(),
                  builder: (context, snap) {
                    final show = snap.data ?? false;
                    if (!show) return const SizedBox.shrink();
                    return TextButton(
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (ctx) {
                            return AlertDialog(
                              title: const Text('Product JSON'),
                              content: SingleChildScrollView(
                                child: SelectableText(
                                  jsonEncode(product.toMap()),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('关闭'),
                                ),
                              ],
                            );
                          },
                        );
                      },
                      child: const Text(
                        '查看 JSON',
                        style: TextStyle(fontSize: 12),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Builder(
                builder: (context) {
                  if (widget.product.platform == 'jd') {
                    final cachedPrices = ref.watch(jdPriceCacheProvider);
                    final cachedPrice = cachedPrices[widget.product.id];
                    final num? effectivePrice =
                        _promotionData?['price'] as num? ?? cachedPrice;
                    final bool hasPrice =
                        (_promotionData?['price'] != null) ||
                        (cachedPrice != null);
                    // 检查是否下架（后端返回 isOffShelf 或价格为 0）
                    final bool isOffShelf = _promotionData?['isOffShelf'] == true ||
                        (effectivePrice != null && effectivePrice < 0.01);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: <Widget>[
                            Text(
                              '价格：',
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            if (isOffShelf)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.errorContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '商品处于下架/无货状态',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              )
                            else
                              Text(
                                effectivePrice != null
                                    ? '\u00a5${effectivePrice.toStringAsFixed(2)}'
                                    : '\u00a5--.--',
                                style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.primary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            const SizedBox(width: 12),
                            if (!hasPrice && !isOffShelf)
                              _isFetchingPromotion
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : TextButton(
                                      onPressed: _fetchPromotionData,
                                      child: const Text('\u83b7\u53d6\u4f18\u60e0'),
                                    ),
                          ],
                        ),
                        if (!isOffShelf)
                          _buildPriceDiffLabel(
                              context, effectivePrice?.toDouble()),
                      ],
                    );
                  } else if (widget.product.platform == 'taobao') {
                    final latest = _taobaoLatestPrice ?? product.price;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: <Widget>[
                            Text(
                              '价格：',
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            Text(
                              '\u00a5${latest.toStringAsFixed(2)}',
                              style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.primary,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        _buildPriceDiffLabel(context, latest),
                      ],
                    );
                  } else if (widget.product.platform == 'pdd') {
                    final latest = _pddLatestPrice ?? product.price;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: <Widget>[
                            Text(
                              '价格：',
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            Text(
                              '\u00a5${latest.toStringAsFixed(2)}',
                              style: TextStyle(
                                color:
                                    Theme.of(context).colorScheme.primary,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        _buildPriceDiffLabel(context, latest),
                      ],
                    );
                  } else {
                    final price = product.price;
                    final bool isOffShelf = price < 0.01;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: <Widget>[
                            Text(
                              '价格：',
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            if (isOffShelf)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.errorContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '商品处于下架/无货状态',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              )
                            else
                              Text(
                                '\u00a5${price.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.primary,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                        if (!isOffShelf)
                          _buildPriceDiffLabel(context, price),
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.store,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(width: 6),
                  // 优先显示店铺名（shopTitle），若为空则回退到原来的评分显示
                  Text(
                    (product.shopTitle.isNotEmpty)
                        ? product.shopTitle
                        : (product.rating > 0
                              ? '${product.rating.toStringAsFixed(1)}'
                              : '暂无店铺详情'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(width: 8),
                  // Platform Badge
                  Builder(
                    builder: (context) {
                      Color color;
                      String text;
                      switch (product.platform) {
                        case 'pdd':
                          color = const Color(0xFFE02E24);
                          text = '拼多多';
                          break;
                        case 'taobao':
                          color = const Color(0xFFFF5000);
                          text = '淘宝';
                          break;
                        case 'jd':
                          color = const Color(0xFFE4393C);
                          text = '京东';
                          break;
                        default:
                          return const SizedBox.shrink();
                      }
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: color.withOpacity(0.3)),
                        ),
                        child: Text(
                          '来自 $text',
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }
                  ),
                ],
              ),
              // AI 推荐内容在此版本被移除（不在商品详情页展示 AI 推荐理由/评分）
              const SizedBox(height: 12),
              // 优先显示产品自身的 description 字段（若 AI 未提供则显示该字段），
              // 若没有 description，则不直接把购买链接展示为商品简介（避免长 URL 占位）。购买链接仍绑定到“前往购买”按钮。
              if ((product.description).isNotEmpty)
                Text(
                  product.description,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(height: 1.4),
                )
              else
                Text(
                  '暂无商品简介',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(height: 1.4),
                ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () async {
                      // 切换收藏并持久化到 Hive，同时同步到购物车（收藏时添加、取消收藏时移除）
                      try {
                        final box = await Hive.openBox('favorites');
                        final cartSvc = ref.read(cartServiceProvider);

                        final bool currentlyFavorited = _isFavorited;

                        if (currentlyFavorited) {
                          await box.delete(widget.product.id);
                        } else {
                          await box.put(
                            widget.product.id,
                            widget.product.toMap(),
                          );
                        }

                        // 同步购物车：如果刚收藏则加入购物车（若购物车中不存在），取消收藏则从购物车移除
                        try {
                          if (!currentlyFavorited) {
                            final items = await cartSvc.getAllItems();
                            final existsInCart = items.any(
                              (m) => (m['id'] as String) == widget.product.id,
                            );
                            if (!existsInCart) {
                              await cartSvc.addOrUpdateItem(
                                widget.product,
                                qty: 1,
                                rawJson: jsonEncode(widget.product.toMap()),
                              );
                            }
                          } else {
                            await cartSvc.removeItem(widget.product.id);
                          }
                          // 刷新购物车 Provider
                          final _ = ref.refresh(cartItemsProvider);
                        } catch (_) {
                          // 同步购物车失败不影响收藏结果
                        }

                        if (!mounted) return;
                        setState(() {
                          _isFavorited = !currentlyFavorited;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_isFavorited ? '已加入收藏' : '已取消收藏'),
                          ),
                        );
                      } catch (_) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(const SnackBar(content: Text('收藏操作失败')));
                      }
                    },
                    icon: AnimatedScale(
                      duration: const Duration(milliseconds: 160),
                      scale: _isFavorited ? 1.08 : 1.0,
                      child: Icon(
                        _isFavorited ? Icons.favorite : Icons.favorite_border,
                        color: _isFavorited
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    label: Text(
                      _isFavorited ? '已收藏' : '加入收藏',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  // 分享按钮
                  OutlinedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => ShareOptionsDialog(product: widget.product),
                      );
                    },
                    icon: const Icon(Icons.share),
                    label: Text(
                      '分享',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  _isLoadingLink
                      ? const SizedBox(
                          width: 160,
                          height: 48,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : FilledButton.icon(
                          onPressed: () async {
                            setState(() => _isLoadingLink = true);

                            String finalUrl;

                            // JD Product Logic
                            if (product.platform == 'jd') {
                              // If we already have a promotion url, use it
                              if (_promotionData?['promotionUrl'] != null &&
                                  (_promotionData!['promotionUrl'] as String)
                                      .isNotEmpty) {
                                finalUrl = _promotionData!['promotionUrl'];
                              }
                              // If fetching failed, fallback to original URL
                              else if (_fetchFailed) {
                                finalUrl =
                                    'https://item.jd.com/${product.id}.html';
                              }
                              // If we haven't tried fetching, fetch now
                              else {
                                await _fetchPromotionData();
                                // After fetching, check again
                                if (_promotionData?['promotionUrl'] != null &&
                                    (_promotionData!['promotionUrl'] as String)
                                        .isNotEmpty) {
                                  finalUrl = _promotionData!['promotionUrl'];
                                } else {
                                  // If it still fails, fallback to original
                                  finalUrl =
                                      'https://item.jd.com/${product.id}.html';
                                }
                              }
                            }
                            // Non-JD Product Logic
                            else {
                              finalUrl = product.link.isNotEmpty
                                  ? product.link
                                  : '';
                              try {
                                if (finalUrl.isEmpty) {
                                  final svc = ProductService();
                                  final ln = await svc.generatePromotionLink(
                                    product,
                                  );
                                  if (ln != null && ln.isNotEmpty)
                                    finalUrl = ln;
                                }
                              } catch (_) {}
                              try {
                                final box = await Hive.openBox('settings');
                                final String? tpl =
                                    box.get('affiliate_api') as String? ??
                                    box.get('veapi_key') as String?;
                                if (tpl != null &&
                                    tpl.isNotEmpty &&
                                    finalUrl.isNotEmpty) {
                                  if (tpl.contains('{url}')) {
                                    finalUrl = tpl.replaceAll(
                                      '{url}',
                                      Uri.encodeComponent(finalUrl),
                                    );
                                  } else if (tpl.contains('{{url}}')) {
                                    finalUrl = tpl.replaceAll(
                                      '{{url}}',
                                      Uri.encodeComponent(finalUrl),
                                    );
                                  }
                                }
                              } catch (_) {}
                            }

                            if (finalUrl.isNotEmpty) {
                              // For JD and PDD products prefer showing an internal dialog with the link
                              if (product.platform == 'jd' ||
                                  product.platform == 'pdd') {
                                await showDialog<void>(
                                  context: context,
                                  builder: (ctx) {
                                    String normalized = finalUrl.trim();
                                    if (normalized.startsWith('//'))
                                      normalized = 'https:' + normalized;
                                    return AlertDialog(
                                      title: const Text('商品链接'),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SelectableText(normalized),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              ElevatedButton.icon(
                                                onPressed: () async {
                                                  try {
                                                    final uri = Uri.tryParse(
                                                      normalized,
                                                    );
                                                    if (uri != null &&
                                                        (uri.scheme == 'http' ||
                                                            uri.scheme ==
                                                                'https')) {
                                                      await launchUrl(
                                                        uri,
                                                        mode: LaunchMode
                                                            .externalApplication,
                                                      );
                                                    } else {
                                                      await Clipboard.setData(
                                                        ClipboardData(
                                                          text: normalized,
                                                        ),
                                                      );
                                                      if (!mounted) return;
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            '已复制链接到剪贴板',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  } catch (_) {
                                                    await Clipboard.setData(
                                                      ClipboardData(
                                                        text: normalized,
                                                      ),
                                                    );
                                                    if (!mounted) return;
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          '已复制链接到剪贴板',
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                },
                                                icon: const Icon(
                                                  Icons.open_in_browser,
                                                ),
                                                label: const Text('在浏览器中打开'),
                                              ),
                                              const SizedBox(width: 12),
                                              OutlinedButton(
                                                onPressed: () async {
                                                  await Clipboard.setData(
                                                    ClipboardData(
                                                      text: finalUrl,
                                                    ),
                                                  );
                                                  Navigator.of(ctx).pop();
                                                  if (!mounted) return;
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text('已复制到剪贴板'),
                                                    ),
                                                  );
                                                },
                                                child: const Text('复制'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(),
                                          child: const Text('关闭'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              } else {
                                final uri = Uri.tryParse(finalUrl);
                                if (uri != null &&
                                    (uri.scheme == 'http' ||
                                        uri.scheme == 'https')) {
                                  try {
                                    final launched = await launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                    if (!launched)
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(content: Text('无法打开链接')),
                                      );
                                  } catch (_) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('打开链接出错')),
                                    );
                                  }
                                } else {
                                  await showDialog<void>(
                                    context: context,
                                    builder: (ctx) {
                                      String normalized = finalUrl.trim();
                                      if (normalized.startsWith('//')) {
                                        normalized = 'https:$normalized';
                                      }
                                      return AlertDialog(
                                        title: const Text('商品链接'),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SelectableText(normalized),
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                ElevatedButton.icon(
                                                  onPressed: () async {
                                                    try {
                                                      final uri = Uri.tryParse(
                                                        normalized,
                                                      );
                                                      if (uri != null &&
                                                          (uri.scheme ==
                                                                  'http' ||
                                                              uri.scheme ==
                                                                  'https')) {
                                                        await launchUrl(
                                                          uri,
                                                          mode: LaunchMode
                                                              .externalApplication,
                                                        );
                                                      } else {
                                                        await Clipboard.setData(
                                                          ClipboardData(
                                                            text: normalized,
                                                          ),
                                                        );
                                                        if (!mounted) return;
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                              '已复制链接到剪贴板',
                                                            ),
                                                          ),
                                                        );
                                                      }
                                                    } catch (_) {
                                                      await Clipboard.setData(
                                                        ClipboardData(
                                                          text: normalized,
                                                        ),
                                                      );
                                                      if (!mounted) return;
                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            '已复制链接到剪贴板',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  },
                                                  icon: const Icon(
                                                    Icons.open_in_browser,
                                                  ),
                                                  label: const Text('在浏览器中打开'),
                                                ),
                                                const SizedBox(width: 12),
                                                OutlinedButton(
                                                  onPressed: () async {
                                                    await Clipboard.setData(
                                                      ClipboardData(
                                                        text: finalUrl,
                                                      ),
                                                    );
                                                    Navigator.of(ctx).pop();
                                                    if (!mounted) return;
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          '已复制到剪贴板',
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                  child: const Text('复制'),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(),
                                            child: const Text('关闭'),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                }
                              }
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('未能获取推广链接')),
                              );
                            }

                            setState(() => _isLoadingLink = false);
                          },
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('前往购买'),
                        ),
                ],
              ),
            ],
          );

          // AI 智能介绍作为独立区块，边框与上方内容对齐
          Widget aiIntroSection = _buildAiIntroSection(context);

          if (wide) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  // 上方：图片 + 详情并排
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // 左侧图片
                      image,
                      const SizedBox(width: 24),
                      // 右侧详情卡
                      Expanded(
                        child: Card(
                          elevation: 0,
                          color: Colors.transparent,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: details,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // 下方：AI 智能介绍，居中显示
                  const SizedBox(height: 24),
                  aiIntroSection,
                ],
              ),
            );
          }

          // 窄屏竖向布局
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(child: image),
                const SizedBox(height: 12),
                details,
                // AI 智能介绍
                const SizedBox(height: 24),
                aiIntroSection,
              ],
            ),
          );
        },
      ),
    );
  }
}

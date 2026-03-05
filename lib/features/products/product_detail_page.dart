import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wisepick_dart_version/core/storage/hive_config.dart';
import 'package:wisepick_dart_version/features/cart/cart_providers.dart';
import 'package:wisepick_dart_version/features/cart/cart_service.dart';
import 'package:flutter/services.dart';
import 'package:wisepick_dart_version/services/share_service.dart';
import 'product_model.dart';
import 'product_service.dart';
import 'package:wisepick_dart_version/features/products/pdd_goods_detail_service.dart';
import 'package:wisepick_dart_version/features/products/taobao_item_detail_service.dart';
import 'package:wisepick_dart_version/features/chat/chat_service.dart';
import 'package:wisepick_dart_version/features/price_history/price_history_page.dart';
import 'widgets/image_cache_manager.dart';
import 'widgets/product_image_gallery.dart';
import 'widgets/ai_introduction_section.dart';
import 'widgets/price_diff_label.dart';
import 'package:wisepick_dart_version/features/decision/decision_providers.dart';
import 'package:wisepick_dart_version/core/error/app_error.dart';
import 'package:wisepick_dart_version/core/error/app_error_mapper.dart';
import 'package:wisepick_dart_version/widgets/error_snackbar.dart';

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
  bool _isLoadingImages = false;
  String? _imageError;
  List<String> _galleryImages = const <String>[];
  int _currentImageIndex = 0;
  late final TaobaoItemDetailService _taobaoDetailService;
  late final PddGoodsDetailService _pddDetailService;
  double? _taobaoLatestPrice;
  double? _pddLatestPrice;
  double? _initialCartPrice;
  // ignore: unused_field
  double? _lastCartPrice; // 保留供后续价格跟踪功能使用
  bool _hasCartRecord = false;
  // AI 智能介绍相关状态
  bool _isLoadingAiIntro = false;
  String? _aiIntroContent;
  bool _aiIntroExpanded = false;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  // 使用新的双源爬取 API 获取京东商品推广数据（已移除）

  Future<void> _loadFavoriteState() async {
    try {
      final box = await HiveConfig.getBox(HiveConfig.favoritesBox);
      final exists = box.containsKey(widget.product.id);
      if (!mounted) return;
      setState(() {
        _isFavorited = exists;
      });
    } catch (e, st) {
      dev.log('Failed to load favorite state: $e', name: 'ProductDetail', error: e, stackTrace: st);
    }
  }

  Future<void> _loadCartPriceInfo() async {
    try {
      final box = await HiveConfig.getBox(CartService.boxName);
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
    } catch (e, st) {
      dev.log('Error loading cart record: $e', name: 'ProductDetail', error: e, stackTrace: st);
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
      final box = await HiveConfig.getBox(boxName);
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
      final box = await HiveConfig.getBox(boxName);
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

      final reply = await chatService.getAiReply(prompt, isProductDetail: true);
      
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



  void _prepareInitialGallery() {
    final primary = widget.product.imageUrl;
    if (primary.isNotEmpty) {
      _setGalleryImages(<String>[primary], startAutoPlay: false);
    } else {
      _setGalleryImages(const <String>[], startAutoPlay: false);
    }

    if (widget.product.platform == 'taobao' && widget.product.id.isNotEmpty) {
      ImageCacheManager.loadCachedTaobaoPrice(widget.product.id).then((value) {
        if (value != null && mounted) setState(() => _taobaoLatestPrice = value);
      });
      _loadTaobaoGallery();
    } else if (widget.product.platform == 'pdd' && widget.product.id.isNotEmpty) {
      ImageCacheManager.loadCachedPddPrice(widget.product.id).then((value) {
        if (value != null && mounted) setState(() => _pddLatestPrice = value);
      });
      _loadPddDetail();
    }
  }

  void _setGalleryImages(List<String> images, {bool startAutoPlay = true}) {
    final sanitized = images
        .map(ImageCacheManager.normalizeImageUrl)
        .where((url) => url.isNotEmpty)
        .toList();
    setState(() {
      _galleryImages = sanitized;
      _currentImageIndex = 0;
      _isLoadingImages = false;
      if (sanitized.isNotEmpty) _imageError = null;
    });
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



  Future<void> _loadTaobaoGallery({bool forceRefresh = false}) async {
    if (widget.product.platform != 'taobao' || widget.product.id.isEmpty) return;

    if (!forceRefresh) {
      final cached = await ImageCacheManager.loadCachedTaobaoImages(widget.product.id);
      final cachedPrice = await ImageCacheManager.loadCachedTaobaoPrice(widget.product.id);
      if (cachedPrice != null && mounted) setState(() => _taobaoLatestPrice = cachedPrice);
      if (cached != null && cached.isNotEmpty) {
        if (!mounted) return;
        _setGalleryImages(_mergeWithPrimaryImage(cached));
        return;
      }
    }

    if (!mounted) return;
    setState(() { _isLoadingImages = true; _imageError = null; });

    try {
      final detail = await _taobaoDetailService.fetchDetail(widget.product.id);
      final fetched = detail.images;
      if (detail.preferredPrice != null && mounted) {
        setState(() => _taobaoLatestPrice = detail.preferredPrice);
        await ImageCacheManager.persistTaobaoPrice(widget.product.id, detail.preferredPrice ?? 0.0);
      }
      if (fetched.isNotEmpty) {
        await ImageCacheManager.persistTaobaoImages(widget.product.id, fetched);
      }
      if (!mounted) return;
      _setGalleryImages(_mergeWithPrimaryImage(fetched));
    } catch (e) {
      if (!mounted) return;
      setState(() { _imageError = e.toString(); _isLoadingImages = false; });
    }
  }

  Future<void> _loadPddDetail({bool forceRefresh = false}) async {
    if (widget.product.platform != 'pdd' || widget.product.id.isEmpty) return;

    if (!forceRefresh) {
      final cachedImages = await ImageCacheManager.loadCachedPddImages(widget.product.id);
      final cachedPrice = await ImageCacheManager.loadCachedPddPrice(widget.product.id);
      if (cachedPrice != null && mounted) setState(() => _pddLatestPrice = cachedPrice);
      if (cachedImages != null && cachedImages.isNotEmpty) {
        if (!mounted) return;
        _setGalleryImages(_mergeWithPrimaryImage(cachedImages));
        return;
      }
    }

    if (!mounted) return;
    setState(() { _isLoadingImages = true; _imageError = null; });

    try {
      final detail = await _pddDetailService.fetchDetail(widget.product.id);
      final fetched = detail?.images ?? const <String>[];
      final newPrice = detail?.preferredPrice;
      if (newPrice != null && mounted) {
        setState(() => _pddLatestPrice = newPrice);
        await ImageCacheManager.persistPddPrice(widget.product.id, newPrice);
      }
      if (fetched.isNotEmpty) {
        await ImageCacheManager.persistPddImages(widget.product.id, fetched);
      }
      if (!mounted) return;
      _setGalleryImages(_mergeWithPrimaryImage(fetched));
    } catch (e) {
      if (!mounted) return;
      setState(() { _imageError = e.toString(); _isLoadingImages = false; });
    }
  }

  double? _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  String _normalizeImageUrl(String? url) =>
      ImageCacheManager.normalizeImageUrl(url);

  Widget _buildPriceDiffLabel(BuildContext context, double? currentPrice) {
    return PriceDiffLabel(
      hasCartRecord: _hasCartRecord,
      initialCartPrice: _initialCartPrice,
      currentPrice: currentPrice,
    );
  }

  Widget _buildAiIntroSection(BuildContext context) {
    return AiIntroductionSection(
      isLoading: _isLoadingAiIntro,
      content: _aiIntroContent,
      expanded: _aiIntroExpanded,
      onFetch: _fetchAiIntroduction,
      onToggleExpand: () => setState(() => _aiIntroExpanded = !_aiIntroExpanded),
    );
  }

  void _startAutoPlay() {}
  void _stopAutoPlay() {}

  Widget _buildImageCarousel(BuildContext context, bool wide) {
    return ProductImageGallery(
      images: _galleryImages,
      isLoading: _isLoadingImages,
      imageError: _imageError,
      wide: wide,
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
      } catch (e, st) {
        dev.log('Error parsing AI intro item: $e', name: 'ProductDetail', error: e, stackTrace: st);
      }
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
                      final box = await HiveConfig.getBox(HiveConfig.settingsBox);
                      return box.get('show_product_json') as bool? ?? false;
                    } catch (e, st) {
                      dev.log('Error reading show_product_json setting: $e', name: 'ProductDetail', error: e, stackTrace: st);
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
                    final effectivePrice = widget.product.price > 0
                        ? widget.product.price
                        : widget.product.finalPrice > 0
                            ? widget.product.finalPrice
                            : widget.product.originalPrice;
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
                              effectivePrice > 0
                                  ? '\u00a5${effectivePrice.toStringAsFixed(2)}'
                                  : '\u00a5--.--',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (effectivePrice > 0)
                          _buildPriceDiffLabel(
                              context, effectivePrice),
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
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: color.withValues(alpha: 0.3)),
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
              // 前往购买按钮 - 单独一行，更大更醒目
              SizedBox(
                width: double.infinity,
                height: 52,
                child: _isLoadingLink
                    ? const Center(child: CircularProgressIndicator())
                    : FilledButton.icon(
                        style: FilledButton.styleFrom(
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                          onPressed: () async {
                            setState(() => _isLoadingLink = true);
                            try {

                            String finalUrl;

                            // JD Product Logic
                            if (product.platform == 'jd') {
                              finalUrl = product.link.isNotEmpty
                                  ? product.link
                                  : 'https://item.jd.com/${product.id}.html';
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
                              } catch (e, st) {
                                dev.log('Error generating promotion link: $e', name: 'ProductDetail', error: e, stackTrace: st);
                              }
                              try {
                                final box = await HiveConfig.getBox(HiveConfig.settingsBox);
                                // veapi_key 已弃用，仅读取 affiliate_api
                                final String? tpl =
                                    box.get('affiliate_api') as String?;
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
                              } catch (e, st) {
                                dev.log('Error applying affiliate API template: $e', name: 'ProductDetail', error: e, stackTrace: st);
                              }
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
                                                      showInfoSnackBar(context, '已复制链接到剪贴板');
                                                    }
                                                  } catch (e, st) {
                                                    dev.log('Error launching URL (JD/PDD dialog): ${AppErrorMapper.mapException(e).technicalDetail}', name: 'ProductDetail', error: e, stackTrace: st);
                                                    await Clipboard.setData(
                                                      ClipboardData(
                                                        text: normalized,
                                                      ),
                                                    );
                                                    if (!mounted) return;
                                                    showInfoSnackBar(context, '已复制链接到剪贴板');
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
                                                  showInfoSnackBar(context, '已复制到剪贴板');
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
                                    if (!launched) {
                                      showErrorSnackBar(
                                        context,
                                        const AppError(type: AppErrorType.unknown, userMessage: '无法打开链接', canRetry: false),
                                      );
                                    }
                                  } catch (e, st) {
                                    final appError = AppErrorMapper.mapException(e);
                                    dev.log('Error launching URL: ${appError.technicalDetail}', name: 'ProductDetail', error: e, stackTrace: st);
                                    showErrorSnackBar(context, appError);
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
                                                        showInfoSnackBar(context, '已复制链接到剪贴板');
                                                      }
                                                    } catch (e, st) {
                                                      dev.log('Error launching URL (non-JD dialog): ${AppErrorMapper.mapException(e).technicalDetail}', name: 'ProductDetail', error: e, stackTrace: st);
                                                      await Clipboard.setData(
                                                        ClipboardData(
                                                          text: normalized,
                                                        ),
                                                      );
                                                      if (!mounted) return;
                                                      showInfoSnackBar(context, '已复制链接到剪贴板');
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
                                                    showInfoSnackBar(context, '已复制到剪贴板');
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
                              showErrorSnackBar(
                                context,
                                const AppError(type: AppErrorType.serverError, userMessage: '未能获取推广链接'),
                              );
                            }

                            } finally {
                              if (mounted) setState(() => _isLoadingLink = false);
                            }
                          },
                          icon: const Icon(Icons.open_in_new, size: 22),
                          label: const Text('前往购买'),
                        ),
              ),
              const SizedBox(height: 16),
              // 其他操作按钮
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () async {
                      // 切换收藏并持久化到 Hive，同时同步到购物车（收藏时添加、取消收藏时移除）
                      try {
                        final box = await HiveConfig.getBox(HiveConfig.favoritesBox);
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
                        } catch (e, st) {
                          dev.log('Cart sync after favorite toggle failed: $e', name: 'ProductDetail', error: e, stackTrace: st);
                          // 同步购物车失败不影响收藏结果
                        }

                        if (!mounted) return;
                        setState(() {
                          _isFavorited = !currentlyFavorited;
                        });
                        showInfoSnackBar(context, _isFavorited ? '已加入收藏' : '已取消收藏');
                      } catch (e, st) {
                        final appError = AppErrorMapper.mapException(e);
                        dev.log('Favorite toggle failed: ${appError.technicalDetail}', name: 'ProductDetail', error: e, stackTrace: st);
                        if (!mounted) return;
                        showErrorSnackBar(context, appError);
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
                        builder: (ctx) => ShareOptionsDialog(product: widget.product, parentContext: context),
                      );
                    },
                    icon: const Icon(Icons.share),
                    label: Text(
                      '分享',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  // 查看价格历史按钮
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PriceHistoryPage(
                            productId: product.id,
                            productTitle: product.title,
                            productImage: product.imageUrl,
                            currentPrice: product.price,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.show_chart),
                    label: Text(
                      '价格历史',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  // 加入对比按钮
                  OutlinedButton.icon(
                    onPressed: () {
                      final productMap = product.toMap();
                      
                      // 确保传入当前显示的最新价格
                      double currentPrice = product.price;
                      if (product.platform == 'taobao') {
                        if (_taobaoLatestPrice != null) currentPrice = _taobaoLatestPrice!;
                      } else if (product.platform == 'pdd') {
                        if (_pddLatestPrice != null) currentPrice = _pddLatestPrice!;
                      }
                      
                      if (currentPrice > 0) {
                        productMap['price'] = currentPrice;
                        // 如果 final_price 无效，也更新它
                        final fp = productMap['final_price'] as num?;
                        if (fp == null || fp <= 0) {
                          productMap['final_price'] = currentPrice;
                        }
                      }

                      addToComparisonList(ref, productMap);
                      showInfoSnackBar(
                        context,
                        '已添加 "${product.title}" 到对比列表',
                        action: SnackBarAction(
                          label: '查看对比',
                          onPressed: () {
                            if (!mounted) return;
                            Navigator.pushNamed(context, '/comparison');
                          },
                        ),
                      );
                    },
                    icon: const Icon(Icons.compare_arrows),
                    label: Text(
                      '加入对比',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
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

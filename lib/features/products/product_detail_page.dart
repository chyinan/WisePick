import 'package:flutter/material.dart';
import 'package:http/http.dart' as http; // Add http package
import 'package:url_launcher/url_launcher.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wisepick_dart_version/features/cart/cart_providers.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'product_model.dart';
import 'product_service.dart';
import 'package:wisepick_dart_version/features/products/jd_price_provider.dart';

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


  @override
  void initState() {
    super.initState();
    _loadFavoriteState();
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
      final uri = Uri.parse('http://127.0.0.1:8080/api/get-jd-promotion?sku=${widget.product.id}');
      final response = await http.get(uri).timeout(const Duration(minutes: 2));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
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
            ref.read(jdPriceCacheProvider.notifier).updatePrice(widget.product.id, (data['price'] as num).toDouble());
          }
        } else {
          throw Exception('Backend failed to get promotion');
        }
      } else {
        throw Exception('Server returned status ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetchFailed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('获取优惠失败，将使用原始链接')),
      );
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
      parts.addAll(RegExp(r'goods\b', caseSensitive: false).allMatches(body).map((m) => m.group(0) ?? ''));
      // fallback to splitting by '},{' or '],[' or just split by '},"goods' patterns
      parts.addAll(body.split(RegExp(r'\},\s*\{')));
    } else {
      // generic split by occurrences of 'goods' or 'title'
      parts.addAll(s.split(RegExp(r'\bgoods\b|\btitle\b', caseSensitive: false)));
    }

    // if splitting produced nothing useful, use the whole string as single part
    final candidates = (parts.isEmpty || parts.every((p) => p.trim().isEmpty)) ? [s] : parts;

    final titleRe = RegExp(r'(?i)(?:title|tith[e!]*|tihe)\s*[:=]\s*"([^\"]{1,300})"');
    final descRe = RegExp(r'(?i)(?:description|desc)\s*[:=]\s*"([^\"]{1,500})"');
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
      body: LayoutBuilder(builder: (context, constraints) {
        final bool wide = constraints.maxWidth >= 700;

        Widget image = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            product.imageUrl,
            width: wide ? 360 : double.infinity,
            height: wide ? 360 : 240,
            fit: BoxFit.cover,
            errorBuilder: (c, e, st) => Container(
              width: wide ? 360 : double.infinity,
              height: wide ? 360 : 240,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Icon(Icons.image_not_supported, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        );

        Widget details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(product.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 22)),
            // debug: show product JSON for quick inspection, controlled by admin setting
            Align(
              alignment: Alignment.topRight,
              child: FutureBuilder<bool>(
                future: () async {
                  try {
                    if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
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
                      showDialog<void>(context: context, builder: (ctx) {
                        return AlertDialog(
                          title: const Text('Product JSON'),
                          content: SingleChildScrollView(child: SelectableText(jsonEncode(product.toMap()))),
                          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('关闭'))],
                        );
                      });
                    },
                    child: const Text('查看 JSON', style: TextStyle(fontSize: 12)),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Row(children: <Widget>[
              Text('价格：', style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              if (widget.product.platform == 'jd')
                Builder(builder: (context) {
                  // Prefer fetched price, else fallback to cached price
                  final cachedPrices = ref.watch(jdPriceCacheProvider);
                  final cachedPrice = cachedPrices[widget.product.id];
                  final num? effectivePrice = _promotionData?['price'] as num? ?? cachedPrice;
                  return Text(
                    effectivePrice != null ? '\u00a5${effectivePrice.toStringAsFixed(2)}' : '\u00a5--.--',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 20, fontWeight: FontWeight.bold),
                  );
                })
              else
                // Non-JD product: Show static price
                Text('\u00a5${product.price.toStringAsFixed(2)}', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 20, fontWeight: FontWeight.bold)),
              
              const SizedBox(width: 12),

              // JD specific "Get Promotion" button
              if (widget.product.platform == 'jd')
                Builder(builder: (context) {
                  final cachedPrices = ref.watch(jdPriceCacheProvider);
                  final cachedPrice = cachedPrices[widget.product.id];
                  final bool hasPrice = (_promotionData?['price'] != null) || (cachedPrice != null);
                  if (hasPrice) return const SizedBox.shrink();
                  return _isFetchingPromotion
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : TextButton(onPressed: _fetchPromotionData, child: const Text('\u83b7\u53d6\u4f18\u60e0'));
                }),
            ]),
            const SizedBox(height: 16),
            Row(children: <Widget>[
              Icon(Icons.store, color: Theme.of(context).colorScheme.secondary),
              const SizedBox(width: 6),
              // 优先显示店铺名（shopTitle），若为空则回退到原来的评分显示
              Text(
                (product.shopTitle.isNotEmpty) ? product.shopTitle : (product.rating > 0 ? '${product.rating.toStringAsFixed(1)}' : '暂无店铺详情'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(width: 8),
              // 显示平台来源徽章，例如 PDD/TAOBAO/JD
              if (product.platform == 'pdd')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(6)),
                  child: const Text('来自 拼多多', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              if (product.platform == 'taobao')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(6)),
                  child: const Text('来自 淘宝', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              if (product.platform == 'jd')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                  child: const Text('来自 京东', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
            ]),
            // AI 推荐内容在此版本被移除（不在商品详情页展示 AI 推荐理由/评分）
            const SizedBox(height: 12),
            // 优先显示产品自身的 description 字段（若 AI 未提供则显示该字段），
            // 若没有 description，则不直接把购买链接展示为商品简介（避免长 URL 占位）。购买链接仍绑定到“前往购买”按钮。
            if ((product.description).isNotEmpty)
              Text(product.description, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4))
            else
              Text('暂无商品简介', style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4)),
            const SizedBox(height: 20),
            Wrap(spacing: 12, children: <Widget>[
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
                      await box.put(widget.product.id, widget.product.toMap());
                    }

                    // 同步购物车：如果刚收藏则加入购物车（若购物车中不存在），取消收藏则从购物车移除
                    try {
                      if (!currentlyFavorited) {
                        final items = await cartSvc.getAllItems();
                        final existsInCart = items.any((m) => (m['id'] as String) == widget.product.id);
                        if (!existsInCart) {
                          await cartSvc.addOrUpdateItem(widget.product, qty: 1, rawJson: jsonEncode(widget.product.toMap()));
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
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isFavorited ? '已加入收藏' : '已取消收藏')));
                  } catch (_) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('收藏操作失败')));
                  }
                },
                icon: AnimatedScale(
                  duration: const Duration(milliseconds: 160),
                  scale: _isFavorited ? 1.08 : 1.0,
                  child: Icon(_isFavorited ? Icons.favorite : Icons.favorite_border, color: _isFavorited ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.primary),
                ),
                label: Text(_isFavorited ? '已收藏' : '加入收藏', style: Theme.of(context).textTheme.labelLarge),
              ),
              _isLoadingLink
                  ? const SizedBox(width: 160, height: 48, child: Center(child: CircularProgressIndicator()))
                  : ElevatedButton.icon(
                      onPressed: () async {
                        setState(() => _isLoadingLink = true);
                        
                        String finalUrl;

                        // JD Product Logic
                        if (product.platform == 'jd') {
                          // If we already have a promotion url, use it
                          if (_promotionData?['promotionUrl'] != null && (_promotionData!['promotionUrl'] as String).isNotEmpty) {
                            finalUrl = _promotionData!['promotionUrl'];
                          } 
                          // If fetching failed, fallback to original URL
                          else if (_fetchFailed) {
                            finalUrl = 'https://item.jd.com/${product.id}.html';
                          }
                          // If we haven't tried fetching, fetch now
                          else {
                            await _fetchPromotionData();
                            // After fetching, check again
                            if (_promotionData?['promotionUrl'] != null && (_promotionData!['promotionUrl'] as String).isNotEmpty) {
                              finalUrl = _promotionData!['promotionUrl'];
                            } else {
                              // If it still fails, fallback to original
                              finalUrl = 'https://item.jd.com/${product.id}.html';
                            }
                          }
                        } 
                        // Non-JD Product Logic
                        else {
                          finalUrl = product.link.isNotEmpty ? product.link : '';
                           try {
                            if (finalUrl.isEmpty) {
                              final svc = ProductService();
                              final ln = await svc.generatePromotionLink(product);
                              if (ln != null && ln.isNotEmpty) finalUrl = ln;
                            }
                          } catch (_) {}
                          try {
                            final box = await Hive.openBox('settings');
                            final String? tpl = box.get('affiliate_api') as String? ?? box.get('veapi_key') as String?;
                            if (tpl != null && tpl.isNotEmpty && finalUrl.isNotEmpty) {
                              if (tpl.contains('{url}')) {
                                finalUrl = tpl.replaceAll('{url}', Uri.encodeComponent(finalUrl));
                              } else if (tpl.contains('{{url}}')) {
                                finalUrl = tpl.replaceAll('{{url}}', Uri.encodeComponent(finalUrl));
                              }
                            }
                          } catch (_) {}
                        }

                        if (finalUrl.isNotEmpty) {
                          // For JD and PDD products prefer showing an internal dialog with the link
                          if (product.platform == 'jd' || product.platform == 'pdd') {
                            await showDialog<void>(context: context, builder: (ctx) {
                              String normalized = finalUrl.trim();
                              if (normalized.startsWith('//')) normalized = 'https:' + normalized;
                              return AlertDialog(
                                title: const Text('商品链接'),
                                content: Column(mainAxisSize: MainAxisSize.min, children: [
                                  SelectableText(normalized),
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        try {
                                          final uri = Uri.tryParse(normalized);
                                          if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
                                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                                          } else {
                                            await Clipboard.setData(ClipboardData(text: normalized));
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制链接到剪贴板')));
                                          }
                                        } catch (_) {
                                          await Clipboard.setData(ClipboardData(text: normalized));
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制链接到剪贴板')));
                                        }
                                      },
                                      icon: const Icon(Icons.open_in_browser),
                                      label: const Text('在浏览器中打开'),
                                    ),
                                    const SizedBox(width: 12),
                                    OutlinedButton(
                                      onPressed: () async {
                                        await Clipboard.setData(ClipboardData(text: finalUrl));
                                        Navigator.of(ctx).pop();
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
                                      },
                                      child: const Text('复制'),
                                    )
                                  ])
                                ]),
                                actions: [
                                  TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('关闭')),
                                ],
                              );
                            });
                          } else {
                            final uri = Uri.tryParse(finalUrl);
                            if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
                              try {
                                final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
                                if (!launched) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法打开链接')));
                              } catch (_) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('打开链接出错')));
                              }
                            } else {
                              await showDialog<void>(context: context, builder: (ctx) {
                                String normalized = finalUrl.trim();
                                if (normalized.startsWith('//')) normalized = 'https:' + normalized;
                                return AlertDialog(
                                  title: const Text('商品链接'),
                                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                                    SelectableText(finalUrl),
                                    const SizedBox(height: 12),
                                    Row(children: [
                                      ElevatedButton.icon(
                                        onPressed: () async {
                                          try {
                                            final uri = Uri.tryParse(normalized);
                                            if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
                                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                                            } else {
                                              await Clipboard.setData(ClipboardData(text: normalized));
                                              if (!mounted) return;
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制链接到剪贴板')));
                                            }
                                          } catch (_) {
                                            await Clipboard.setData(ClipboardData(text: normalized));
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制链接到剪贴板')));
                                          }
                                        },
                                        icon: const Icon(Icons.open_in_browser),
                                        label: const Text('在浏览器中打开'),
                                      ),
                                      const SizedBox(width: 12),
                                      OutlinedButton(
                                        onPressed: () async {
                                          await Clipboard.setData(ClipboardData(text: finalUrl));
                                          Navigator.of(ctx).pop();
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
                                        },
                                        child: const Text('复制'),
                                      )
                                    ])
                                  ]),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('关闭')),
                                  ],
                                );
                              });
                            }
                          }
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未能获取推广链接')));
                        }

                        setState(() => _isLoadingLink = false);
                      },
                      icon: Icon(Icons.open_in_new, color: Theme.of(context).colorScheme.onPrimary),
                      label: Text('前往购买', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white)),
                    ),
            ])
          ],
        );

        if (wide) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Row(
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
                    child: Padding(padding: const EdgeInsets.all(4), child: details),
                  ),
                ),
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
            ],
          ),
        );
      }),
    );
  }
}


import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;

import '../features/products/product_model.dart';
import '../features/products/product_service.dart';

/// 分享服务：生成分享图片和文本
class ShareService {
  static const int _maxTitleLength = 40;
  static const String _sharePrefix = '我在快淘帮发现了好物~';

  /// 获取商品推广链接
  static Future<String?> getPromotionLink(ProductModel product) async {
    // 优先使用商品自带的推广链接
    if (product.link.isNotEmpty) {
      return product.link;
    }

    // 尝试通过 ProductService 生成推广链接
    try {
      final productService = ProductService();
      final link = await productService.generatePromotionLink(product);
      if (link != null && link.isNotEmpty) {
        return link;
      }
    } catch (_) {}

    // 根据平台生成默认链接
    switch (product.platform) {
      case 'jd':
        return 'https://item.jd.com/${product.id}.html';
      case 'taobao':
        return 'https://item.taobao.com/item.htm?id=${product.id}';
      case 'pdd':
        return 'https://mobile.yangkeduo.com/goods.html?goods_id=${product.id}';
      default:
        return null;
    }
  }

  /// 截取标题（过长则截取前面部分）
  static String truncateTitle(String title) {
    if (title.length <= _maxTitleLength) {
      return title;
    }
    return '${title.substring(0, _maxTitleLength - 3)}...';
  }

  /// 生成文本分享内容
  static Future<String> generateShareText(ProductModel product) async {
    final link = await getPromotionLink(product);
    final title = truncateTitle(product.title);
    
    if (link != null && link.isNotEmpty) {
      // 处理淘宝等平台链接可能缺少 https: 前缀的情况
      final normalizedLink = link.startsWith('//') ? 'https:$link' : link;
      return '$_sharePrefix\n【$title】\n$normalizedLink';
    }
    return '$_sharePrefix\n【$title】';
  }

  /// 复制文本到剪贴板
  static Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// 分享文本
  static Future<void> shareText(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }

  /// 下载网络图片并返回字节数据
  static Future<Uint8List?> downloadImage(String imageUrl) async {
    try {
      String normalizedUrl = imageUrl.trim();
      if (normalizedUrl.startsWith('//')) {
        normalizedUrl = 'https:$normalizedUrl';
      }
      
      final response = await http.get(Uri.parse(normalizedUrl));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (e) {
      debugPrint('下载图片失败: $e');
    }
    return null;
  }

  /// 保存图片到本地
  static Future<String?> saveImageToLocal(Uint8List imageBytes, String fileName) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final sharePath = Directory('${directory.path}/share_images');
      if (!await sharePath.exists()) {
        await sharePath.create(recursive: true);
      }
      
      final filePath = '${sharePath.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);
      return filePath;
    } catch (e) {
      debugPrint('保存图片失败: $e');
    }
    return null;
  }

  /// 分享图片文件
  static Future<void> shareImageFile(String filePath) async {
    await SharePlus.instance.share(ShareParams(files: [XFile(filePath)]));
  }
}

/// 生成分享图片的 Widget
class ShareImageWidget extends StatelessWidget {
  final ProductModel product;
  final String promotionLink;
  final Uint8List? productImageBytes;

  const ShareImageWidget({
    super.key,
    required this.product,
    required this.promotionLink,
    this.productImageBytes,
  });

  @override
  Widget build(BuildContext context) {
    final truncatedTitle = ShareService.truncateTitle(product.title);
    
    return Container(
      width: 360,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 商品头图
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              height: 280,
              color: Colors.grey[100],
              child: productImageBytes != null
                  ? Image.memory(
                      productImageBytes!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 280,
                    )
                  : product.imageUrl.isNotEmpty
                      ? Image.network(
                          product.imageUrl.startsWith('//')
                              ? 'https:${product.imageUrl}'
                              : product.imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: 280,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.image_not_supported, size: 48),
                          ),
                        )
                      : const Center(
                          child: Icon(Icons.image_not_supported, size: 48),
                        ),
            ),
          ),
          const SizedBox(height: 12),
          // 商品标题和二维码
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 商品标题
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      truncatedTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // 价格
                    if (product.price > 0)
                      Text(
                        '¥${product.price.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE02E24),
                        ),
                      ),
                    const SizedBox(height: 4),
                    // 来源平台
                    Text(
                      _getPlatformText(product.platform),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 二维码
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                padding: const EdgeInsets.all(4),
                child: QrImageView(
                  data: promotionLink,
                  version: QrVersions.auto,
                  size: 80,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 底部品牌标识
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shopping_bag, size: 14, color: Colors.grey[400]),
              const SizedBox(width: 4),
              Text(
                '来自快淘帮',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[400],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getPlatformText(String platform) {
    switch (platform) {
      case 'jd':
        return '来自京东';
      case 'taobao':
        return '来自淘宝';
      case 'pdd':
        return '来自拼多多';
      default:
        return '';
    }
  }
}

/// 分享图片预览对话框
class ShareImagePreviewDialog extends StatefulWidget {
  final ProductModel product;

  const ShareImagePreviewDialog({
    super.key,
    required this.product,
  });

  @override
  State<ShareImagePreviewDialog> createState() => _ShareImagePreviewDialogState();
}

class _ShareImagePreviewDialogState extends State<ShareImagePreviewDialog> {
  final GlobalKey _repaintBoundaryKey = GlobalKey();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _promotionLink;
  Uint8List? _productImageBytes;
  Uint8List? _generatedImageBytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 并行获取推广链接和商品图片
      final results = await Future.wait([
        ShareService.getPromotionLink(widget.product),
        widget.product.imageUrl.isNotEmpty
            ? ShareService.downloadImage(widget.product.imageUrl)
            : Future.value(null),
      ]);

      final link = results[0] as String?;
      final imageBytes = results[1] as Uint8List?;

      if (link == null || link.isEmpty) {
        throw Exception('无法获取推广链接');
      }

      if (!mounted) return;
      setState(() {
        _promotionLink = link;
        _productImageBytes = imageBytes;
        _isLoading = false;
      });

      // 等待 Widget 渲染完成后生成图片
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _captureImage();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _captureImage() async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      
      final boundary = _repaintBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      if (!mounted) return;
      setState(() {
        _generatedImageBytes = byteData.buffer.asUint8List();
      });
    } catch (e) {
      debugPrint('生成图片失败: $e');
    }
  }

  Future<void> _saveImage() async {
    if (_generatedImageBytes == null) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final fileName = 'share_${widget.product.id}_${DateTime.now().millisecondsSinceEpoch}.png';
      final filePath = await ShareService.saveImageToLocal(_generatedImageBytes!, fileName);

      if (!mounted) return;

      if (filePath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片已保存到: $filePath')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存图片失败')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _shareImage() async {
    if (_generatedImageBytes == null) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final fileName = 'share_${widget.product.id}_${DateTime.now().millisecondsSinceEpoch}.png';
      final filePath = await ShareService.saveImageToLocal(_generatedImageBytes!, fileName);

      if (filePath != null) {
        await ShareService.shareImageFile(filePath);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text(
                    '分享图片预览',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 内容区
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _buildContent(),
              ),
            ),
            // 底部按钮
            if (!_isLoading && _error == null && _promotionLink != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isSaving || _generatedImageBytes == null
                            ? null
                            : _saveImage,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save_alt),
                        label: const Text('保存图片'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isSaving || _generatedImageBytes == null
                            ? null
                            : _shareImage,
                        icon: const Icon(Icons.share),
                        label: const Text('分享'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在生成分享图片...'),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('生成失败: $_error'),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _loadData,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return RepaintBoundary(
      key: _repaintBoundaryKey,
      child: ShareImageWidget(
        product: widget.product,
        promotionLink: _promotionLink!,
        productImageBytes: _productImageBytes,
      ),
    );
  }
}

/// 分享选项对话框
class ShareOptionsDialog extends StatelessWidget {
  final ProductModel product;

  const ShareOptionsDialog({
    super.key,
    required this.product,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('分享商品'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.image),
            title: const Text('图片分享'),
            subtitle: const Text('生成包含商品图片和二维码的分享图'),
            onTap: () {
              Navigator.of(context).pop();
              showDialog(
                context: context,
                builder: (ctx) => ShareImagePreviewDialog(product: product),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('文本链接分享'),
            subtitle: const Text('复制商品标题和推广链接'),
            onTap: () async {
              Navigator.of(context).pop();
              await _shareTextLink(context);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }

  Future<void> _shareTextLink(BuildContext context) async {
    // 显示加载中
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在生成分享链接...'),
          ],
        ),
      ),
    );

    try {
      final shareText = await ShareService.generateShareText(product);
      
      // 关闭加载对话框
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      // 显示结果对话框
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('分享文本'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    shareText,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await ShareService.copyToClipboard(shareText);
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制到剪贴板')),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('复制'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // 关闭加载对话框
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成分享链接失败: $e')),
        );
      }
    }
  }
}

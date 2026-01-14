/// 京东商品信息模型
class JdProductInfo {
  /// SKU ID
  final String skuId;

  /// 商品标题
  final String title;

  /// 当前价格
  final double price;

  /// 原价（划线价）
  final double? originalPrice;

  /// 佣金金额
  final double? commission;

  /// 佣金比例
  final double? commissionRate;

  /// 商品图片 URL
  final String? imageUrl;

  /// 店铺名称
  final String? shopName;

  /// 推广链接
  final String? promotionLink;

  /// 短链接
  final String? shortLink;

  /// 是否来自缓存
  final bool cached;

  /// 是否下架/无货状态
  final bool isOffShelf;

  /// 获取时间
  final DateTime fetchTime;

  /// 原始数据（用于调试）
  final Map<String, dynamic>? rawData;

  JdProductInfo({
    required this.skuId,
    required this.title,
    required this.price,
    this.originalPrice,
    this.commission,
    this.commissionRate,
    this.imageUrl,
    this.shopName,
    this.promotionLink,
    this.shortLink,
    this.cached = false,
    this.isOffShelf = false,
    DateTime? fetchTime,
    this.rawData,
  }) : fetchTime = fetchTime ?? DateTime.now();

  /// 从 JSON Map 创建实例
  factory JdProductInfo.fromJson(Map<String, dynamic> json) {
    return JdProductInfo(
      skuId: json['skuId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      price: _parseDouble(json['price']) ?? 0.0,
      originalPrice: _parseDouble(json['originalPrice']),
      commission: _parseDouble(json['commission']),
      commissionRate: _parseDouble(json['commissionRate']),
      imageUrl: json['imageUrl']?.toString(),
      shopName: json['shopName']?.toString(),
      promotionLink: json['promotionLink']?.toString(),
      shortLink: json['shortLink']?.toString(),
      cached: json['cached'] == true,
      isOffShelf: json['isOffShelf'] == true,
      fetchTime: json['fetchTime'] != null
          ? DateTime.parse(json['fetchTime'] as String)
          : DateTime.now(),
      rawData: json['rawData'] as Map<String, dynamic>?,
    );
  }

  /// 从京东联盟推广文案中解析
  factory JdProductInfo.fromPromotionText(String text, String skuId) {
    // 打印原始文本用于调试
    print('[ProductInfo] 原始文本内容:\n$text');
    print('[ProductInfo] -------- 文本结束 --------');
    
    // 解析京东价（支持多种格式）
    double price = 0.0;
    final pricePatterns = [
      RegExp(r'京东价[：:]\s*[¥￥]?\s*([0-9]+(?:\.[0-9]+)?)'),
      RegExp(r'价格[：:]\s*[¥￥]?\s*([0-9]+(?:\.[0-9]+)?)'),
      RegExp(r'[¥￥]\s*([0-9]+(?:\.[0-9]+)?)'),
    ];
    
    for (final pattern in pricePatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        price = double.tryParse(match.group(1)!) ?? 0.0;
        print('[ProductInfo] 解析到价格: $price (模式: ${pattern.pattern})');
        break;
      }
    }
    
    // 解析到手价
    double? finalPrice;
    final finalPriceMatch = RegExp(r'到手价[：:]\s*[¥￥]?\s*([0-9]+(?:\.[0-9]+)?)').firstMatch(text);
    if (finalPriceMatch != null) {
      finalPrice = double.tryParse(finalPriceMatch.group(1)!);
      print('[ProductInfo] 解析到到手价: $finalPrice');
    }

    // 解析推广链接（支持多种格式）
    String? promotionLink;
    final linkPatterns = [
      RegExp(r'https?://u\.jd\.com/[A-Za-z0-9]+'),
      RegExp(r'抢购链接[：:]\s*(https?://[^\s]+)'),
      RegExp(r'(https?://[^\s]*jd[^\s]*)'),
    ];
    
    for (final pattern in linkPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        promotionLink = match.group(match.groupCount > 0 ? 1 : 0);
        print('[ProductInfo] 解析到链接: $promotionLink (模式: ${pattern.pattern})');
        break;
      }
    }

    // 解析标题（查找【京东】开头的行，或者第一个非空行）
    String title = '';
    final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
    
    // 优先查找【京东】开头的行
    for (final line in lines) {
      if (line.contains('【京东】') || line.contains('【JD】')) {
        title = line.trim();
        break;
      }
    }
    // 如果没找到，使用第一行
    if (title.isEmpty && lines.isNotEmpty) {
      title = lines.first.trim();
    }
    print('[ProductInfo] 解析到标题: $title');

    // 判断是否下架：有链接但没有价格信息
    final effectivePrice = finalPrice ?? price;
    final bool isOffShelf = promotionLink != null && 
                            promotionLink.isNotEmpty && 
                            effectivePrice < 0.01;
    if (isOffShelf) {
      print('[ProductInfo] 商品处于下架/无货状态（有链接但无价格）');
    }

    return JdProductInfo(
      skuId: skuId,
      title: title,
      price: effectivePrice,
      originalPrice: finalPrice != null ? price : null,
      promotionLink: promotionLink,
      shortLink: promotionLink,
      isOffShelf: isOffShelf,
      rawData: {'originalText': text},
    );
  }

  /// 转换为 JSON Map
  Map<String, dynamic> toJson() => {
        'skuId': skuId,
        'title': title,
        'price': price,
        if (originalPrice != null) 'originalPrice': originalPrice,
        if (commission != null) 'commission': commission,
        if (commissionRate != null) 'commissionRate': commissionRate,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (shopName != null) 'shopName': shopName,
        if (promotionLink != null) 'promotionLink': promotionLink,
        if (shortLink != null) 'shortLink': shortLink,
        'cached': cached,
        'isOffShelf': isOffShelf,
        'fetchTime': fetchTime.toIso8601String(),
      };

  /// 创建一个标记为缓存的副本
  JdProductInfo markAsCached() {
    return JdProductInfo(
      skuId: skuId,
      title: title,
      price: price,
      originalPrice: originalPrice,
      commission: commission,
      commissionRate: commissionRate,
      imageUrl: imageUrl,
      shopName: shopName,
      promotionLink: promotionLink,
      shortLink: shortLink,
      cached: true,
      isOffShelf: isOffShelf,
      fetchTime: fetchTime,
      rawData: rawData,
    );
  }

  @override
  String toString() {
    return 'JdProductInfo(skuId: $skuId, title: $title, price: ¥$price)';
  }

  /// 辅助方法：安全解析 double
  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}







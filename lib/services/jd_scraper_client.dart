import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 京东爬虫客户端
///
/// 调用后端新的双源爬取 API，获取完整的商品信息：
/// - 京东联盟：推广链接、佣金、短链接
/// - 京东首页：店铺名、商品图片、最新价格
class JdScraperClient {
  final Dio _dio;

  JdScraperClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(minutes: 3),
            ));

  /// 获取后端服务地址
  Future<String> _getBackendBase() async {
    String backend = 'http://localhost:9527';
    try {
      if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');
      final box = Hive.box('settings');
      final String? b = box.get('backend_base') as String?;
      if (b != null && b.trim().isNotEmpty) {
        backend = b.trim();
      } else {
        backend = Platform.environment['BACKEND_BASE'] ?? backend;
      }
    } catch (_) {}
    return backend;
  }

  /// 获取单个商品的完整信息（双源爬取，推荐使用）
  ///
  /// [skuId] 商品 SKU ID
  /// [forceRefresh] 是否强制刷新（忽略缓存）
  /// [includePromotion] 是否获取推广链接（默认 true）
  /// [includeDetail] 是否获取详细信息（默认 true）
  Future<JdProductResult> getProductEnhanced(
    String skuId, {
    bool forceRefresh = false,
    bool includePromotion = true,
    bool includeDetail = true,
  }) async {
    final backend = await _getBackendBase();
    final url = '$backend/api/jd/scraper/product/$skuId/enhanced';

    try {
      final response = await _dio.get(
        url,
        queryParameters: {
          if (forceRefresh) 'forceRefresh': 'true',
          if (!includePromotion) 'includePromotion': 'false',
          if (!includeDetail) 'includeDetail': 'false',
        },
      );

      if (response.data == null) {
        return JdProductResult.error('服务器返回空响应');
      }

      final data = response.data as Map<String, dynamic>;

      if (data['success'] == true && data['data'] != null) {
        return JdProductResult.success(
          JdProductInfo.fromJson(data['data'] as Map<String, dynamic>),
        );
      } else {
        final error = data['error'] as String? ?? 'unknown';
        final message = data['message'] as String? ?? '未知错误';
        final userMessage = data['userMessage'] as String? ?? _getUserFriendlyMessage(error);
        return JdProductResult.error(userMessage, errorType: error, rawMessage: message);
      }
    } on DioException catch (e) {
      return _handleDioError(e);
    } catch (e) {
      return JdProductResult.error('请求失败: $e');
    }
  }

  /// 批量获取商品的完整信息（双源爬取）
  ///
  /// [skuIds] 商品 SKU ID 列表
  /// [maxConcurrency] 最大并发数（默认 2）
  Future<JdBatchResult> getBatchProductsEnhanced(
    List<String> skuIds, {
    int maxConcurrency = 2,
    bool includePromotion = true,
    bool includeDetail = true,
  }) async {
    final backend = await _getBackendBase();
    final url = '$backend/api/jd/scraper/products/batch/enhanced';

    try {
      final response = await _dio.post(
        url,
        data: jsonEncode({
          'skuIds': skuIds,
          'maxConcurrency': maxConcurrency,
          'includePromotion': includePromotion,
          'includeDetail': includeDetail,
        }),
        options: Options(contentType: 'application/json'),
      );

      if (response.data == null) {
        return JdBatchResult.error('服务器返回空响应');
      }

      final data = response.data as Map<String, dynamic>;

      if (data['success'] == true && data['data'] != null) {
        final List<dynamic> items = data['data'] as List<dynamic>;
        final products = items
            .map((e) => JdProductInfo.fromJson(e as Map<String, dynamic>))
            .toList();
        return JdBatchResult.success(
          products,
          total: data['total'] as int? ?? skuIds.length,
          successCount: data['success_count'] as int? ?? products.length,
        );
      } else {
        final error = data['error'] as String? ?? 'unknown';
        final userMessage = data['userMessage'] as String? ?? _getUserFriendlyMessage(error);
        return JdBatchResult.error(userMessage);
      }
    } on DioException catch (e) {
      final result = _handleDioError(e);
      return JdBatchResult.error(result.errorMessage ?? '请求失败');
    } catch (e) {
      return JdBatchResult.error('请求失败: $e');
    }
  }

  /// 仅获取商品推广信息（从京东联盟）
  Future<JdProductResult> getProductPromotion(String skuId) async {
    final backend = await _getBackendBase();
    final url = '$backend/api/jd/scraper/product/$skuId';

    try {
      final response = await _dio.get(url);

      if (response.data == null) {
        return JdProductResult.error('服务器返回空响应');
      }

      final data = response.data as Map<String, dynamic>;

      if (data['success'] == true && data['data'] != null) {
        return JdProductResult.success(
          JdProductInfo.fromJson(data['data'] as Map<String, dynamic>),
        );
      } else {
        final error = data['error'] as String? ?? 'unknown';
        final userMessage = data['userMessage'] as String? ?? _getUserFriendlyMessage(error);
        return JdProductResult.error(userMessage, errorType: error);
      }
    } on DioException catch (e) {
      return _handleDioError(e);
    } catch (e) {
      return JdProductResult.error('请求失败: $e');
    }
  }

  /// 仅获取商品详情（从京东首页）
  Future<JdProductResult> getProductDetail(String skuId) async {
    final backend = await _getBackendBase();
    final url = '$backend/api/jd/scraper/product/$skuId/detail';

    try {
      final response = await _dio.get(url);

      if (response.data == null) {
        return JdProductResult.error('服务器返回空响应');
      }

      final data = response.data as Map<String, dynamic>;

      if (data['success'] == true && data['data'] != null) {
        return JdProductResult.success(
          JdProductInfo.fromJson(data['data'] as Map<String, dynamic>),
        );
      } else {
        final error = data['error'] as String? ?? 'unknown';
        final userMessage = data['userMessage'] as String? ?? _getUserFriendlyMessage(error);
        return JdProductResult.error(userMessage, errorType: error);
      }
    } on DioException catch (e) {
      return _handleDioError(e);
    } catch (e) {
      return JdProductResult.error('请求失败: $e');
    }
  }

  /// 处理 Dio 异常
  JdProductResult _handleDioError(DioException e) {
    String? errorType;
    String userMessage;

    if (e.response?.data != null && e.response!.data is Map) {
      final errorData = e.response!.data as Map<String, dynamic>;
      errorType = errorData['error'] as String?;
      userMessage = errorData['userMessage'] as String? ?? 
                    _getUserFriendlyMessage(errorType ?? 'unknown');
    } else {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          userMessage = '服务器响应超时，请稍后再试~';
          errorType = 'timeout';
          break;
        case DioExceptionType.connectionError:
          userMessage = '网络连接异常，请稍后再试~';
          errorType = 'networkError';
          break;
        default:
          userMessage = '服务器出了一点小问题，请稍后再试~';
          errorType = 'unknown';
      }
    }

    return JdProductResult.error(userMessage, errorType: errorType);
  }

  /// 获取用户友好的错误消息
  String _getUserFriendlyMessage(String errorType) {
    switch (errorType) {
      case 'cookieExpired':
      case 'loginRequired':
        return '服务器出了一点小问题，请稍后再试~';
      case 'antiBotDetected':
        return '当前访问频率过高，请稍后再试~';
      case 'productNotFound':
        return '未找到该商品信息';
      case 'timeout':
        return '服务器响应超时，请稍后再试~';
      case 'networkError':
        return '网络连接异常，请稍后再试~';
      case 'badRequest':
        return '请求参数有误';
      default:
        return '服务器出了一点小问题，请稍后再试~';
    }
  }
}

/// 京东商品信息
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
  final DateTime? fetchTime;

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
    this.fetchTime,
  });

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
          ? DateTime.tryParse(json['fetchTime'] as String)
          : null,
    );
  }

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
        if (fetchTime != null) 'fetchTime': fetchTime!.toIso8601String(),
      };

  /// 获取有效的推广链接（优先短链接）
  String? get effectivePromotionLink => shortLink ?? promotionLink;

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

/// 单个商品查询结果
class JdProductResult {
  final bool isSuccess;
  final JdProductInfo? data;
  final String? errorMessage;
  final String? errorType;
  final String? rawMessage;

  JdProductResult._({
    required this.isSuccess,
    this.data,
    this.errorMessage,
    this.errorType,
    this.rawMessage,
  });

  factory JdProductResult.success(JdProductInfo data) {
    return JdProductResult._(isSuccess: true, data: data);
  }

  factory JdProductResult.error(String message, {String? errorType, String? rawMessage}) {
    return JdProductResult._(
      isSuccess: false,
      errorMessage: message,
      errorType: errorType,
      rawMessage: rawMessage,
    );
  }

  /// 是否是商品未找到的错误
  bool get isProductNotFound => errorType == 'productNotFound';

  /// 是否是服务端错误（需要告警）
  bool get isServiceError =>
      errorType == 'cookieExpired' ||
      errorType == 'loginRequired' ||
      errorType == 'antiBotDetected';
}

/// 批量商品查询结果
class JdBatchResult {
  final bool isSuccess;
  final List<JdProductInfo>? data;
  final String? errorMessage;
  final int total;
  final int successCount;

  JdBatchResult._({
    required this.isSuccess,
    this.data,
    this.errorMessage,
    this.total = 0,
    this.successCount = 0,
  });

  factory JdBatchResult.success(
    List<JdProductInfo> data, {
    required int total,
    required int successCount,
  }) {
    return JdBatchResult._(
      isSuccess: true,
      data: data,
      total: total,
      successCount: successCount,
    );
  }

  factory JdBatchResult.error(String message) {
    return JdBatchResult._(isSuccess: false, errorMessage: message);
  }
}

import 'dart:developer';
import 'chat_message.dart';
import '../products/product_model.dart';

/// ConversationModel 用于持久化会话（包含标题与消息列表）
class ConversationModel {
  final String id;
  final String title;
  final List<ChatMessage> messages;
  final DateTime timestamp;

  ConversationModel({required this.id, required this.title, required this.messages, DateTime? timestamp}) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'timestamp': timestamp.toIso8601String(),
      'messages': messages.map((m) {
        // sanitize debug-only lines from saved text to avoid persisting PARSE_ markers
        String text = m.text;
        try {
          text = text.split('\n').where((line) => !line.startsWith('PARSE_') && !line.startsWith('FIRST_REC_KEYS:') && !line.startsWith('PARSE_KEYS:') && !line.startsWith('解析到 ') && !line.contains('原始请求(JSON)') && !line.contains('原始AI返回(JSON)')).join('\n');
        } catch (e, st) { log('ConversationModel debug filter error: $e', name: 'ConversationModel', error: e, stackTrace: st); }

        return {
          'id': m.id,
          'text': text,
          'isUser': m.isUser,
          'aiParsedRaw': m.aiParsedRaw,
          'keywords': m.keywords,
          'failed': m.failed,
          'retryForText': m.retryForText,
          'timestamp': m.timestamp.toIso8601String(),
          'product': m.product == null
              ? null
              : {
                  'id': m.product!.id,
                  'platform': m.product!.platform,
                  'title': m.product!.title,
                  'price': m.product!.price,
                  'original_price': m.product!.originalPrice,
                  'coupon': m.product!.coupon,
                  'final_price': m.product!.finalPrice,
                  'imageUrl': m.product!.imageUrl,
                  'shop_title': m.product!.shopTitle,
                  'description': m.product!.description,
                  'link': m.product!.link,
                  'rating': m.product!.rating,
                  'sales': m.product!.sales,
                  'commission': m.product!.commission,
                },
          'products': m.products == null
              ? null
              : m.products!.map((p) => {
                    'id': p.id,
                    'platform': p.platform,
                    'title': p.title,
                    'price': p.price,
                    'original_price': p.originalPrice,
                    'coupon': p.coupon,
                    'final_price': p.finalPrice,
                    'imageUrl': p.imageUrl,
                    'shop_title': p.shopTitle,
                    'description': p.description,
                    'link': p.link,
                    'rating': p.rating,
                    'sales': p.sales,
                    'commission': p.commission,
                  }).toList(),
        };
      }).toList(),
    };
  }

  factory ConversationModel.fromMap(Map m) {
    final List msgs = (m['messages'] as List?) ?? [];
    return ConversationModel(
      id: m['id'] as String,
      title: m['title'] as String,
      timestamp: DateTime.tryParse(m['timestamp'] as String? ?? '') ?? DateTime.now(),
      messages: msgs.map<ChatMessage>((it) {
        final Map mm = it as Map;
        final prod = mm['product'] as Map?;
        final prods = mm['products'] as List<dynamic>?;
        List<ProductModel>? products;
        if (prods != null) {
          products = prods.map((p) {
            final Map pm = p as Map;
            return ProductModel(
              id: pm['id'] as String? ?? '',
              platform: pm['platform'] as String? ?? 'taobao',
              title: pm['title'] as String? ?? '',
              price: (pm['price'] as num?)?.toDouble() ?? 0.0,
              originalPrice: (pm['original_price'] as num?)?.toDouble(),
              coupon: (pm['coupon'] as num?)?.toDouble(),
              finalPrice: (pm['final_price'] as num?)?.toDouble(),
              imageUrl: pm['imageUrl'] as String? ?? '',
              sales: (pm['sales'] as num?)?.toInt(),
              rating: (pm['rating'] as num?)?.toDouble() ?? 0.0,
              link: pm['link'] as String? ?? pm['sourceUrl'] as String? ?? '',
              commission: (pm['commission'] as num?)?.toDouble(),
              shopTitle: pm['shop_title'] as String? ?? pm['shopTitle'] as String? ?? '',
              description: pm['description'] as String? ?? '',
            );
          }).toList();
        }
        // sanitize any debug-only lines from stored text when loading
        String loadedText = mm['text'] as String;
        try {
          loadedText = loadedText.split('\n').where((line) => !line.startsWith('PARSE_') && !line.startsWith('FIRST_REC_KEYS:') && !line.startsWith('PARSE_KEYS:') && !line.startsWith('解析到 ') && !line.contains('原始请求(JSON)') && !line.contains('原始AI返回(JSON)')).join('\n');
        } catch (e, st) { log('ConversationModel debug filter error: $e', name: 'ConversationModel', error: e, stackTrace: st); }

        return ChatMessage(
          id: mm['id'] as String,
          text: loadedText,
          isUser: mm['isUser'] as bool,
          aiParsedRaw: mm['aiParsedRaw'] as String?,
          keywords: (mm['keywords'] as List<dynamic>?)?.whereType<String>().toList(),
          failed: mm['failed'] as bool? ?? false,
          retryForText: mm['retryForText'] as String?,
          product: prod == null
              ? null
              : ProductModel(
                  id: prod['id'] as String? ?? '',
                  platform: prod['platform'] as String? ?? 'taobao',
                  title: prod['title'] as String? ?? '',
                  price: (prod['price'] as num?)?.toDouble() ?? 0.0,
                  originalPrice: (prod['original_price'] as num?)?.toDouble(),
                  coupon: (prod['coupon'] as num?)?.toDouble(),
                  finalPrice: (prod['final_price'] as num?)?.toDouble(),
                  imageUrl: prod['imageUrl'] as String? ?? '',
                  sales: (prod['sales'] as num?)?.toInt(),
                  rating: (prod['rating'] as num?)?.toDouble() ?? 0.0,
                  link: prod['link'] as String? ?? prod['sourceUrl'] as String? ?? '',
                  commission: (prod['commission'] as num?)?.toDouble(),
                  shopTitle: prod['shop_title'] as String? ?? prod['shopTitle'] as String? ?? '',
                  description: prod['description'] as String? ?? '',
                ),
          products: products,
          timestamp: DateTime.tryParse(mm['timestamp'] as String? ?? '') ?? DateTime.now(),
        );
      }).toList(),
    );
  }
}


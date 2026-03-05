import '../products/product_model.dart';

/// Explicit message lifecycle status for UI state management.
///
/// This is a **transient** field – it is NOT persisted to Hive or synced
/// to the server.  Loaded conversations default to [completed].
enum MessageStatus {
  /// AI is actively streaming tokens for this message.
  streaming,

  /// Message has been fully received and processed.
  completed,

  /// The AI request failed – see [ChatMessage.errorType] for category.
  error,
}

/// ChatMessage 用于 chat 模块，包装通用的 Message 或扩展字段
class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final ProductModel? product;
  final List<ProductModel>? products;
  final List<String>? keywords;
  final List<dynamic>? attempts; // 后端返回的尝试元信息（可用于调试或展示兜底提示）
  final String? aiParsedRaw; // 原始 AI 解析后的结构化 JSON 字符串（可选，用于商品详情页显示 AI 推荐理由）
  final bool failed;
  final String? retryForText;
  final DateTime timestamp;

  /// Explicit message status for UI state management (transient, not persisted).
  final MessageStatus status;

  /// Error type name (e.g. 'network', 'auth') for categorised error display (transient).
  final String? errorType;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    this.product,
    this.products,
    this.keywords,
    this.attempts,
    this.aiParsedRaw,
    this.failed = false,
    this.retryForText,
    DateTime? timestamp,
    this.status = MessageStatus.completed,
    this.errorType,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Convenience: create a copy with selected fields replaced.
  ChatMessage copyWith({
    String? id,
    String? text,
    bool? isUser,
    ProductModel? product,
    List<ProductModel>? products,
    List<String>? keywords,
    List<dynamic>? attempts,
    String? aiParsedRaw,
    bool? failed,
    String? retryForText,
    DateTime? timestamp,
    MessageStatus? status,
    String? errorType,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      product: product ?? this.product,
      products: products ?? this.products,
      keywords: keywords ?? this.keywords,
      attempts: attempts ?? this.attempts,
      aiParsedRaw: aiParsedRaw ?? this.aiParsedRaw,
      failed: failed ?? this.failed,
      retryForText: retryForText ?? this.retryForText,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      errorType: errorType ?? this.errorType,
    );
  }
}

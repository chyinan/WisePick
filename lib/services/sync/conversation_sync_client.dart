import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../features/auth/token_manager.dart';

/// 会话同步请求
class ConversationSyncRequest {
  final int lastSyncVersion;
  final List<ConversationChange> conversationChanges;
  final List<MessageChange> messageChanges;

  ConversationSyncRequest({
    required this.lastSyncVersion,
    required this.conversationChanges,
    required this.messageChanges,
  });

  Map<String, dynamic> toJson() {
    return {
      'last_sync_version': lastSyncVersion,
      'conversation_changes': conversationChanges.map((e) => e.toJson()).toList(),
      'message_changes': messageChanges.map((e) => e.toJson()).toList(),
    };
  }
}

/// 会话变更
class ConversationChange {
  final String clientId;
  final String? title;
  final bool isDeleted;
  final int localVersion;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ConversationChange({
    required this.clientId,
    this.title,
    this.isDeleted = false,
    this.localVersion = 0,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'client_id': clientId,
      if (title != null) 'title': title,
      'is_deleted': isDeleted,
      'local_version': localVersion,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  factory ConversationChange.fromJson(Map<String, dynamic> json) {
    return ConversationChange(
      clientId: json['client_id'] as String,
      title: json['title'] as String?,
      isDeleted: json['is_deleted'] as bool? ?? false,
      localVersion: json['local_version'] as int? ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }
}

/// 消息变更
class MessageChange {
  final String conversationClientId;
  final String clientId;
  final String role;
  final String content;
  final List<Map<String, dynamic>>? products;
  final List<String>? keywords;
  final String? aiParsedRaw;
  final bool failed;
  final String? retryForText;
  final int localVersion;
  final DateTime? createdAt;

  MessageChange({
    required this.conversationClientId,
    required this.clientId,
    required this.role,
    required this.content,
    this.products,
    this.keywords,
    this.aiParsedRaw,
    this.failed = false,
    this.retryForText,
    this.localVersion = 0,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'conversation_client_id': conversationClientId,
      'client_id': clientId,
      'role': role,
      'content': content,
      if (products != null) 'products': products,
      if (keywords != null) 'keywords': keywords,
      if (aiParsedRaw != null) 'ai_parsed_raw': aiParsedRaw,
      'failed': failed,
      if (retryForText != null) 'retry_for_text': retryForText,
      'local_version': localVersion,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
    };
  }

  factory MessageChange.fromJson(Map<String, dynamic> json) {
    return MessageChange(
      conversationClientId: json['conversation_client_id'] as String,
      clientId: json['client_id'] as String,
      role: json['role'] as String,
      content: json['content'] as String,
      products: (json['products'] as List<dynamic>?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      keywords: (json['keywords'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      aiParsedRaw: json['ai_parsed_raw'] as String?,
      failed: json['failed'] as bool? ?? false,
      retryForText: json['retry_for_text'] as String?,
      localVersion: json['local_version'] as int? ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }
}

/// 会话同步响应
class ConversationSyncResponse {
  final bool success;
  final int currentVersion;
  final List<Map<String, dynamic>> conversations;
  final List<Map<String, dynamic>> messages;
  final List<String> deletedConversationIds;
  final String? message;

  ConversationSyncResponse({
    required this.success,
    required this.currentVersion,
    required this.conversations,
    required this.messages,
    required this.deletedConversationIds,
    this.message,
  });

  factory ConversationSyncResponse.fromJson(Map<String, dynamic> json) {
    return ConversationSyncResponse(
      success: json['success'] as bool? ?? false,
      currentVersion: json['current_version'] as int? ?? 0,
      conversations: (json['conversations'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      messages: (json['messages'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      deletedConversationIds: (json['deleted_conversation_ids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      message: json['message'] as String?,
    );
  }

  factory ConversationSyncResponse.error(String message) {
    return ConversationSyncResponse(
      success: false,
      currentVersion: 0,
      conversations: [],
      messages: [],
      deletedConversationIds: [],
      message: message,
    );
  }
}

/// 会话同步客户端
class ConversationSyncClient {
  static const String _syncVersionKey = 'conversation_sync_version';
  static const String _pendingConvChangesKey = 'conversation_pending_changes';
  static const String _pendingMsgChangesKey = 'message_pending_changes';

  final Dio _dio;
  final TokenManager _tokenManager;

  String get _baseUrl {
    try {
      if (Hive.isBoxOpen('settings')) {
        final box = Hive.box('settings');
        final proxyUrl = box.get('proxy_url') as String?;
        if (proxyUrl != null && proxyUrl.isNotEmpty) {
          return proxyUrl;
        }
      }
    } catch (_) {}
    return 'http://localhost:9527';
  }

  String get _syncBaseUrl => '$_baseUrl/api/v1/sync';

  ConversationSyncClient({Dio? dio, TokenManager? tokenManager})
      : _dio = dio ?? Dio(),
        _tokenManager = tokenManager ?? TokenManager.instance {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  /// 获取请求头
  Map<String, String> _getHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final token = _tokenManager.accessToken;
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// 获取本地保存的同步版本号
  Future<int> getLocalSyncVersion() async {
    final box = await Hive.openBox('sync_meta');
    return box.get(_syncVersionKey, defaultValue: 0) as int;
  }

  /// 保存本地同步版本号
  Future<void> saveLocalSyncVersion(int version) async {
    final box = await Hive.openBox('sync_meta');
    await box.put(_syncVersionKey, version);
  }

  /// 获取待同步的会话变更
  Future<List<Map<String, dynamic>>> getPendingConversationChanges() async {
    final box = await Hive.openBox('sync_meta');
    final changes = box.get(_pendingConvChangesKey, defaultValue: <dynamic>[]) as List<dynamic>;
    return changes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// 添加待同步的会话变更
  Future<void> addPendingConversationChange(Map<String, dynamic> change) async {
    final box = await Hive.openBox('sync_meta');
    final changes = await getPendingConversationChanges();

    final existingIndex = changes.indexWhere(
      (c) => c['client_id'] == change['client_id'],
    );

    if (existingIndex >= 0) {
      changes[existingIndex] = change;
    } else {
      changes.add(change);
    }

    await box.put(_pendingConvChangesKey, changes);
  }

  /// 获取待同步的消息变更
  Future<List<Map<String, dynamic>>> getPendingMessageChanges() async {
    final box = await Hive.openBox('sync_meta');
    final changes = box.get(_pendingMsgChangesKey, defaultValue: <dynamic>[]) as List<dynamic>;
    return changes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// 添加待同步的消息变更
  Future<void> addPendingMessageChange(Map<String, dynamic> change) async {
    final box = await Hive.openBox('sync_meta');
    final changes = await getPendingMessageChanges();

    final existingIndex = changes.indexWhere(
      (c) => c['client_id'] == change['client_id'],
    );

    if (existingIndex >= 0) {
      changes[existingIndex] = change;
    } else {
      changes.add(change);
    }

    await box.put(_pendingMsgChangesKey, changes);
  }

  /// 清除所有待同步的变更
  Future<void> clearPendingChanges() async {
    final box = await Hive.openBox('sync_meta');
    await box.put(_pendingConvChangesKey, <dynamic>[]);
    await box.put(_pendingMsgChangesKey, <dynamic>[]);
  }

  /// 同步会话和消息
  Future<ConversationSyncResponse> sync({
    List<ConversationChange>? conversationChanges,
    List<MessageChange>? messageChanges,
  }) async {
    if (!_tokenManager.isLoggedIn) {
      return ConversationSyncResponse.error('用户未登录');
    }

    try {
      final lastVersion = await getLocalSyncVersion();

      // 合并传入的变更和待同步的变更
      final allConvChanges = <ConversationChange>[];
      final allMsgChanges = <MessageChange>[];

      if (conversationChanges != null) {
        allConvChanges.addAll(conversationChanges);
      }
      if (messageChanges != null) {
        allMsgChanges.addAll(messageChanges);
      }

      // 加载待同步的变更
      final pendingConvChanges = await getPendingConversationChanges();
      for (final pending in pendingConvChanges) {
        allConvChanges.add(ConversationChange.fromJson(pending));
      }

      final pendingMsgChanges = await getPendingMessageChanges();
      for (final pending in pendingMsgChanges) {
        allMsgChanges.add(MessageChange.fromJson(pending));
      }

      final request = ConversationSyncRequest(
        lastSyncVersion: lastVersion,
        conversationChanges: allConvChanges,
        messageChanges: allMsgChanges,
      );

      final response = await _dio.post(
        '$_syncBaseUrl/conversations/sync',
        data: jsonEncode(request.toJson()),
        options: Options(headers: _getHeaders()),
      );

      final result = ConversationSyncResponse.fromJson(response.data as Map<String, dynamic>);

      if (result.success) {
        // 更新本地同步版本号
        await saveLocalSyncVersion(result.currentVersion);
        // 清除待同步的变更
        await clearPendingChanges();
      }

      return result;
    } on DioException catch (e) {
      return _handleDioError(e);
    } catch (e) {
      return ConversationSyncResponse.error('同步失败: ${e.toString()}');
    }
  }

  /// 获取云端所有会话
  Future<ConversationSyncResponse> getCloudConversations() async {
    if (!_tokenManager.isLoggedIn) {
      return ConversationSyncResponse.error('用户未登录');
    }

    try {
      final response = await _dio.get(
        '$_syncBaseUrl/conversations',
        options: Options(headers: _getHeaders()),
      );

      final data = response.data as Map<String, dynamic>;
      if (data['success'] == true) {
        return ConversationSyncResponse(
          success: true,
          currentVersion: data['current_version'] as int? ?? 0,
          conversations: (data['conversations'] as List<dynamic>?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList() ??
              [],
          messages: [],
          deletedConversationIds: [],
        );
      }
      return ConversationSyncResponse.error(data['message'] as String? ?? '获取失败');
    } on DioException catch (e) {
      return _handleDioError(e);
    } catch (e) {
      return ConversationSyncResponse.error('获取失败: ${e.toString()}');
    }
  }

  /// 获取云端会话的消息
  Future<List<Map<String, dynamic>>> getCloudMessages(String conversationClientId) async {
    if (!_tokenManager.isLoggedIn) {
      return [];
    }

    try {
      final response = await _dio.get(
        '$_syncBaseUrl/conversations/$conversationClientId/messages',
        options: Options(headers: _getHeaders()),
      );

      final data = response.data as Map<String, dynamic>;
      if (data['success'] == true) {
        return (data['messages'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// 获取云端当前版本号
  Future<int> getCloudVersion() async {
    if (!_tokenManager.isLoggedIn) {
      return 0;
    }

    try {
      final response = await _dio.get(
        '$_syncBaseUrl/conversations/version',
        options: Options(headers: _getHeaders()),
      );

      final data = response.data as Map<String, dynamic>;
      return data['current_version'] as int? ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// 处理 Dio 错误
  ConversationSyncResponse _handleDioError(DioException e) {
    if (e.response != null) {
      try {
        final data = e.response!.data;
        if (data is Map<String, dynamic>) {
          return ConversationSyncResponse.fromJson(data);
        }
      } catch (_) {}

      switch (e.response!.statusCode) {
        case 401:
          return ConversationSyncResponse.error('认证失败，请重新登录');
        case 403:
          return ConversationSyncResponse.error('没有权限');
        case 500:
          return ConversationSyncResponse.error('服务器错误');
        default:
          return ConversationSyncResponse.error('请求失败 (${e.response!.statusCode})');
      }
    }

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return ConversationSyncResponse.error('连接超时');
    }

    if (e.type == DioExceptionType.connectionError) {
      return ConversationSyncResponse.error('无法连接服务器');
    }

    return ConversationSyncResponse.error('网络错误: ${e.message}');
  }
}

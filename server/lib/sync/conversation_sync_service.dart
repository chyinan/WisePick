import 'dart:convert';
import '../database/database.dart';

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

  factory ConversationSyncRequest.fromJson(Map<String, dynamic> json) {
    return ConversationSyncRequest(
      lastSyncVersion: json['last_sync_version'] as int? ?? 0,
      conversationChanges: (json['conversation_changes'] as List<dynamic>?)
              ?.map((e) => ConversationChange.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      messageChanges: (json['message_changes'] as List<dynamic>?)
              ?.map((e) => MessageChange.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
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

  factory MessageChange.fromJson(Map<String, dynamic> json) {
    return MessageChange(
      conversationClientId: json['conversation_client_id'] as String,
      clientId: json['client_id'] as String,
      role: json['role'] as String,
      content: json['content'] as String,
      products: (json['products'] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>)
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

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'current_version': currentVersion,
      'conversations': conversations,
      'messages': messages,
      'deleted_conversation_ids': deletedConversationIds,
      if (message != null) 'message': message,
    };
  }
}

/// 会话同步服务
class ConversationSyncService {
  final Database _db;

  ConversationSyncService({Database? db}) : _db = db ?? Database.instance;

  /// 同步会话和消息
  Future<ConversationSyncResponse> sync(
    String userId,
    ConversationSyncRequest request,
  ) async {
    try {
      return await _db.transaction((session) async {
        // 1. 获取当前服务器版本
        final versionResult = await _db.queryOne(
          '''
          SELECT current_version FROM sync_versions 
          WHERE user_id = @user_id AND entity_type = 'conversations'
          ''',
          parameters: {'user_id': userId},
        );

        int serverVersion = (versionResult?['current_version'] as int?) ?? 0;

        // 2. 获取服务器上比客户端版本新的会话
        final serverConversations = await _db.queryAll(
          '''
          SELECT 
            client_id, title, created_at, updated_at, deleted_at, sync_version
          FROM conversations
          WHERE user_id = @user_id 
            AND sync_version > @last_sync_version
          ORDER BY sync_version ASC
          ''',
          parameters: {
            'user_id': userId,
            'last_sync_version': request.lastSyncVersion,
          },
        );

        // 分离活跃会话和已删除会话
        final activeConversations = <Map<String, dynamic>>[];
        final deletedIds = <String>[];

        for (final conv in serverConversations) {
          if (conv['deleted_at'] != null) {
            deletedIds.add(conv['client_id'] as String);
          } else {
            activeConversations.add(_formatConversation(conv));
          }
        }

        // 3. 获取新消息
        final serverMessages = await _db.queryAll(
          '''
          SELECT 
            m.client_id, c.client_id as conversation_client_id,
            m.role, m.content, m.products, m.keywords, m.ai_parsed_raw,
            m.failed, m.retry_for_text, m.created_at, m.sync_version
          FROM messages m
          JOIN conversations c ON m.conversation_id = c.id
          WHERE c.user_id = @user_id 
            AND m.sync_version > @last_sync_version
          ORDER BY m.sync_version ASC
          ''',
          parameters: {
            'user_id': userId,
            'last_sync_version': request.lastSyncVersion,
          },
        );

        final formattedMessages =
            serverMessages.map(_formatMessage).toList();

        // 4. 应用客户端会话变更
        for (final change in request.conversationChanges) {
          serverVersion = await _applyConversationChange(
            userId,
            change,
            serverVersion,
          );
        }

        // 5. 应用客户端消息变更
        for (final change in request.messageChanges) {
          serverVersion = await _applyMessageChange(
            userId,
            change,
            serverVersion,
          );
        }

        return ConversationSyncResponse(
          success: true,
          currentVersion: serverVersion,
          conversations: activeConversations,
          messages: formattedMessages,
          deletedConversationIds: deletedIds,
        );
      });
    } catch (e) {
      print('[ConversationSyncService] Sync error: $e');
      return ConversationSyncResponse(
        success: false,
        currentVersion: 0,
        conversations: [],
        messages: [],
        deletedConversationIds: [],
        message: 'Sync failed: ${e.toString()}',
      );
    }
  }

  /// 应用会话变更
  Future<int> _applyConversationChange(
    String userId,
    ConversationChange change,
    int currentVersion,
  ) async {
    // 获取下一个同步版本号
    final versionResult = await _db.queryOne(
      'SELECT get_next_sync_version(@user_id, @entity_type) as version',
      parameters: {'user_id': userId, 'entity_type': 'conversations'},
    );
    final newVersion = (versionResult?['version'] as int?) ?? currentVersion + 1;

    if (change.isDeleted) {
      // 软删除会话（级联删除消息通过数据库外键处理）
      await _db.execute(
        '''
        UPDATE conversations 
        SET deleted_at = NOW(), sync_version = @version, updated_at = NOW()
        WHERE user_id = @user_id AND client_id = @client_id
        ''',
        parameters: {
          'user_id': userId,
          'client_id': change.clientId,
          'version': newVersion,
        },
      );
    } else {
      // Upsert 会话
      await _db.execute(
        '''
        INSERT INTO conversations (
          user_id, client_id, title, sync_version, deleted_at,
          created_at, updated_at
        ) VALUES (
          @user_id, @client_id, @title, @version, NULL,
          COALESCE(@created_at, NOW()), NOW()
        )
        ON CONFLICT (user_id, client_id) 
        DO UPDATE SET
          title = COALESCE(EXCLUDED.title, conversations.title),
          sync_version = EXCLUDED.sync_version,
          deleted_at = NULL,
          updated_at = NOW()
        ''',
        parameters: {
          'user_id': userId,
          'client_id': change.clientId,
          'title': change.title ?? '新对话',
          'version': newVersion,
          'created_at': change.createdAt,
        },
      );
    }

    return newVersion;
  }

  /// 应用消息变更
  Future<int> _applyMessageChange(
    String userId,
    MessageChange change,
    int currentVersion,
  ) async {
    // 首先确保会话存在
    final convResult = await _db.queryOne(
      '''
      SELECT id FROM conversations 
      WHERE user_id = @user_id AND client_id = @client_id AND deleted_at IS NULL
      ''',
      parameters: {
        'user_id': userId,
        'client_id': change.conversationClientId,
      },
    );

    if (convResult == null) {
      // 会话不存在，先创建
      await _db.execute(
        '''
        INSERT INTO conversations (user_id, client_id, title, sync_version)
        VALUES (@user_id, @client_id, @title, 1)
        ON CONFLICT (user_id, client_id) DO NOTHING
        ''',
        parameters: {
          'user_id': userId,
          'client_id': change.conversationClientId,
          'title': '新对话',
        },
      );
    }

    // 获取会话 ID
    final convId = await _db.queryOne(
      'SELECT id FROM conversations WHERE user_id = @user_id AND client_id = @client_id',
      parameters: {
        'user_id': userId,
        'client_id': change.conversationClientId,
      },
    );

    if (convId == null) {
      print('[ConversationSyncService] Failed to get conversation id');
      return currentVersion;
    }

    // 获取下一个同步版本号
    final versionResult = await _db.queryOne(
      'SELECT get_next_sync_version(@user_id, @entity_type) as version',
      parameters: {'user_id': userId, 'entity_type': 'conversations'},
    );
    final newVersion = (versionResult?['version'] as int?) ?? currentVersion + 1;

    // Upsert 消息
    await _db.execute(
      '''
      INSERT INTO messages (
        conversation_id, client_id, role, content, products, keywords,
        ai_parsed_raw, failed, retry_for_text, sync_version, created_at
      ) VALUES (
        @conversation_id, @client_id, @role, @content, @products, @keywords,
        @ai_parsed_raw, @failed, @retry_for_text, @version,
        COALESCE(@created_at, NOW())
      )
      ON CONFLICT (conversation_id, client_id) 
      DO UPDATE SET
        content = EXCLUDED.content,
        products = COALESCE(EXCLUDED.products, messages.products),
        keywords = COALESCE(EXCLUDED.keywords, messages.keywords),
        ai_parsed_raw = COALESCE(EXCLUDED.ai_parsed_raw, messages.ai_parsed_raw),
        failed = EXCLUDED.failed,
        retry_for_text = EXCLUDED.retry_for_text,
        sync_version = EXCLUDED.sync_version
      ''',
      parameters: {
        'conversation_id': convId['id'],
        'client_id': change.clientId,
        'role': change.role,
        'content': change.content,
        'products': change.products != null ? jsonEncode(change.products) : null,
        'keywords': change.keywords != null ? jsonEncode(change.keywords) : null,
        'ai_parsed_raw': change.aiParsedRaw,
        'failed': change.failed,
        'retry_for_text': change.retryForText,
        'version': newVersion,
        'created_at': change.createdAt,
      },
    );

    // 更新会话的 updated_at
    await _db.execute(
      '''
      UPDATE conversations SET updated_at = NOW() 
      WHERE id = @id
      ''',
      parameters: {'id': convId['id']},
    );

    return newVersion;
  }

  /// 获取用户的所有会话
  Future<List<Map<String, dynamic>>> getConversations(String userId) async {
    final conversations = await _db.queryAll(
      '''
      SELECT 
        client_id, title, created_at, updated_at, sync_version
      FROM conversations
      WHERE user_id = @user_id AND deleted_at IS NULL
      ORDER BY updated_at DESC
      ''',
      parameters: {'user_id': userId},
    );

    return conversations.map(_formatConversation).toList();
  }

  /// 获取会话的所有消息
  Future<List<Map<String, dynamic>>> getMessages(
    String userId,
    String conversationClientId,
  ) async {
    final messages = await _db.queryAll(
      '''
      SELECT 
        m.client_id, m.role, m.content, m.products, m.keywords,
        m.ai_parsed_raw, m.failed, m.retry_for_text, m.created_at, m.sync_version
      FROM messages m
      JOIN conversations c ON m.conversation_id = c.id
      WHERE c.user_id = @user_id 
        AND c.client_id = @conversation_client_id
        AND c.deleted_at IS NULL
      ORDER BY m.created_at ASC
      ''',
      parameters: {
        'user_id': userId,
        'conversation_client_id': conversationClientId,
      },
    );

    return messages.map(_formatMessage).toList();
  }

  /// 获取当前同步版本
  Future<int> getCurrentVersion(String userId) async {
    final result = await _db.queryOne(
      '''
      SELECT current_version FROM sync_versions 
      WHERE user_id = @user_id AND entity_type = 'conversations'
      ''',
      parameters: {'user_id': userId},
    );
    return (result?['current_version'] as int?) ?? 0;
  }

  /// 格式化会话为 JSON 格式
  Map<String, dynamic> _formatConversation(Map<String, dynamic> conv) {
    return {
      'client_id': conv['client_id'],
      'title': conv['title'],
      'sync_version': conv['sync_version'],
      'created_at': (conv['created_at'] as DateTime?)?.toIso8601String(),
      'updated_at': (conv['updated_at'] as DateTime?)?.toIso8601String(),
    };
  }

  /// 格式化消息为 JSON 格式
  Map<String, dynamic> _formatMessage(Map<String, dynamic> msg) {
    return {
      'client_id': msg['client_id'],
      'conversation_client_id': msg['conversation_client_id'],
      'role': msg['role'],
      'content': msg['content'],
      'products': msg['products'],
      'keywords': msg['keywords'],
      'ai_parsed_raw': msg['ai_parsed_raw'],
      'failed': msg['failed'],
      'retry_for_text': msg['retry_for_text'],
      'sync_version': msg['sync_version'],
      'created_at': (msg['created_at'] as DateTime?)?.toIso8601String(),
    };
  }
}

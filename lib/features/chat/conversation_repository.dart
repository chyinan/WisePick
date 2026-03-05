import 'dart:developer';

import 'package:hive_flutter/hive_flutter.dart';

import '../../core/storage/hive_config.dart';
import 'conversation_model.dart';

class ConversationRepository {

  Future<Box> _openBox() async {
    return HiveConfig.getBox(HiveConfig.conversationsBox);
  }

  Future<List<ConversationModel>> listConversations() async {
    final box = await _openBox();
    final List<ConversationModel> list = [];
    for (final key in box.keys) {
      try {
        final v = box.get(key);
        final m = v as Map;
        list.add(ConversationModel.fromMap(Map<String, dynamic>.from(m)));
      } catch (e) {
        // Log corrupted entries so data loss is observable in diagnostics.
        log('Skipping corrupted conversation entry (key=$key): $e',
            name: 'ConversationRepository');
      }
    }
    // sort by timestamp desc
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  Future<ConversationModel?> getConversation(String id) async {
    final box = await _openBox();
    final v = box.get(id);
    if (v == null) return null;
    return ConversationModel.fromMap(Map<String, dynamic>.from(v as Map));
  }

  Future<void> saveConversation(ConversationModel conv) async {
    final box = await _openBox();
    await box.put(conv.id, conv.toMap());
  }

  Future<void> deleteConversation(String id) async {
    final box = await _openBox();
    await box.delete(id);
  }
}
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/ai_reply_task_v2.dart';

abstract interface class AiReplyTaskStoreV2 {
  Future<AiReplyTaskV2?> read(String entryId);

  Future<void> write(AiReplyTaskV2 task);

  Future<void> delete(String entryId);
}

class SharedPreferencesAiReplyTaskStoreV2 implements AiReplyTaskStoreV2 {
  static const _key = 'v2_ai_reply_tasks';

  @override
  Future<AiReplyTaskV2?> read(String entryId) async {
    final values = await _readAll();
    return AiReplyTaskV2.tryFromJson(values[entryId]);
  }

  @override
  Future<void> write(AiReplyTaskV2 task) async {
    final preferences = await SharedPreferences.getInstance();
    final values = await _readAll(preferences);
    values[task.entryId] = task.toJson();
    await preferences.setString(_key, jsonEncode(values));
  }

  @override
  Future<void> delete(String entryId) async {
    final preferences = await SharedPreferences.getInstance();
    final values = await _readAll(preferences);
    if (values.remove(entryId) != null) {
      await preferences.setString(_key, jsonEncode(values));
    }
  }

  Future<Map<String, Object?>> _readAll([
    SharedPreferences? preferences,
  ]) async {
    final stored = (preferences ?? await SharedPreferences.getInstance())
        .getString(_key);
    if (stored == null || stored.isEmpty) return {};
    try {
      final decoded = jsonDecode(stored);
      return decoded is Map<String, dynamic>
          ? Map<String, Object?>.from(decoded)
          : <String, Object?>{};
    } catch (_) {
      return {};
    }
  }
}

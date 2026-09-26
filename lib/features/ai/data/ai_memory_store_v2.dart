import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/ai_memory_v2.dart';

class AiMemoryStoreV2 {
  static const _key = 'v2_confirmed_ai_memories';

  Future<List<AiMemoryV2>> load() async {
    try {
      return await loadStrict();
    } catch (_) {
      return const [];
    }
  }

  /// Backup and restore must fail closed instead of treating corrupt user data
  /// as an empty memory list.
  Future<List<AiMemoryV2>> loadStrict() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Invalid confirmed AI memory data.');
    }
    return decoded
        .map((item) {
          if (item is! Map) {
            throw const FormatException('Invalid confirmed AI memory record.');
          }
          final map = Map<String, dynamic>.from(item);
          return AiMemoryV2(
            id: map['id'] as String,
            text: map['text'] as String,
            enabled: map['enabled'] != false,
            createdAt: DateTime.parse(map['createdAt'] as String),
          );
        })
        .toList(growable: false);
  }

  Future<void> save(AiMemoryV2 memory) async {
    final values = [...await load()];
    final index = values.indexWhere((item) => item.id == memory.id);
    index < 0 ? values.add(memory) : values[index] = memory;
    await _write(values);
  }

  Future<void> delete(String id) async {
    final values = [...await load()]..removeWhere((item) => item.id == id);
    await _write(values);
  }

  Future<void> _write(List<AiMemoryV2> values) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _key,
      jsonEncode(
        values
            .map(
              (item) => {
                'id': item.id,
                'text': item.text,
                'enabled': item.enabled,
                'createdAt': item.createdAt.toUtc().toIso8601String(),
              },
            )
            .toList(growable: false),
      ),
    );
    if (!saved) throw StateError('Could not persist AI memory.');
  }
}

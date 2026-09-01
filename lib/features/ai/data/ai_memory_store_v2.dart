import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/ai_memory_v2.dart';

class AiMemoryStoreV2 {
  static const _key = 'v2_confirmed_ai_memories';

  Future<List<AiMemoryV2>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) {
            final map = Map<String, dynamic>.from(item);
            return AiMemoryV2(
              id: map['id'] as String,
              text: map['text'] as String,
              enabled: map['enabled'] != false,
              createdAt: DateTime.parse(map['createdAt'] as String),
            );
          })
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
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
    await preferences.setString(
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
  }
}

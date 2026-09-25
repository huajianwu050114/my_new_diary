import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/daily_encouragement_v2.dart';

abstract interface class DailyEncouragementStoreV2 {
  Future<DailyEncouragementV2?> read(String dateKey);

  Future<List<DailyEncouragementV2>> recent({int limit = 14});

  Future<void> write(DailyEncouragementV2 value);
}

class SharedPreferencesDailyEncouragementStoreV2
    implements DailyEncouragementStoreV2 {
  static const _key = 'v2_daily_quotes';
  static const _maximumStoredDays = 30;

  @override
  Future<DailyEncouragementV2?> read(String dateKey) async {
    final values = await _readAll();
    return DailyEncouragementV2.tryFromJson(values[dateKey]);
  }

  @override
  Future<List<DailyEncouragementV2>> recent({int limit = 14}) async {
    final values = await _readAll();
    final result =
        values.values
            .map(DailyEncouragementV2.tryFromJson)
            .whereType<DailyEncouragementV2>()
            .toList()
          ..sort((a, b) => b.dateKey.compareTo(a.dateKey));
    return result.take(limit).toList(growable: false);
  }

  @override
  Future<void> write(DailyEncouragementV2 value) async {
    final preferences = await SharedPreferences.getInstance();
    final values = await _readAll(preferences);
    values[value.dateKey] = value.toJson();
    final keys = values.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final key in keys.skip(_maximumStoredDays)) {
      values.remove(key);
    }
    await preferences.setString(_key, jsonEncode(values));
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

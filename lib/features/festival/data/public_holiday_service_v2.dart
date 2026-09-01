import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/festival_v2.dart';

class PublicHolidayServiceV2 {
  PublicHolidayServiceV2({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<FestivalOccurrenceV2>> loadYear(int year) async {
    final preferences = await SharedPreferences.getInstance();
    final cacheKey = 'v2_public_holidays_cn_$year';
    final timestampKey = '${cacheKey}_timestamp';
    final cached = preferences.getString(cacheKey);
    final timestamp = DateTime.tryParse(
      preferences.getString(timestampKey) ?? '',
    );

    if (cached != null &&
        timestamp != null &&
        DateTime.now().difference(timestamp) < const Duration(hours: 24)) {
      return _decode(cached);
    }

    try {
      final response = await _client
          .get(
            Uri.parse('https://date.nager.at/api/v3/PublicHolidays/$year/CN'),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        await preferences.setString(cacheKey, response.body);
        await preferences.setString(
          timestampKey,
          DateTime.now().toIso8601String(),
        );
        return _decode(response.body);
      }
    } catch (_) {
      // Stale cached data is the offline fallback.
    }
    return cached == null ? const [] : _decode(cached);
  }

  List<FestivalOccurrenceV2> _decode(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) {
      return const [];
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map((value) {
          final date = DateTime.parse(value['date']! as String);
          return FestivalOccurrenceV2(
            id: 'public:${date.toIso8601String()}:${value['name']}',
            name: value['localName'] as String? ?? value['name']! as String,
            date: date,
            isCustom: false,
          );
        })
        .toList(growable: false);
  }
}

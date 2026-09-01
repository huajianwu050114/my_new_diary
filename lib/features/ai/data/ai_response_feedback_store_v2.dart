import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/ai_response_feedback_v2.dart';

class AiResponseFeedbackStoreV2 {
  static const _key = 'v2_ai_response_feedback';

  Future<List<AiResponseFeedbackV2>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return const [];
    try {
      final values = jsonDecode(raw);
      if (values is! List) return const [];
      return values
          .whereType<Map>()
          .map((item) {
            final map = Map<String, dynamic>.from(item);
            return AiResponseFeedbackV2(
              responseId: map['responseId'] as String,
              helpful: map['helpful'] == true,
              reason: map['reason'] as String? ?? '',
              createdAt: DateTime.parse(map['createdAt'] as String),
            );
          })
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<AiResponseFeedbackV2?> read(String responseId) async {
    for (final item in await load()) {
      if (item.responseId == responseId) return item;
    }
    return null;
  }

  Future<void> save(AiResponseFeedbackV2 feedback) async {
    final values = [...await load()];
    values.removeWhere((item) => item.responseId == feedback.responseId);
    values.add(feedback);
    if (values.length > 100) values.removeRange(0, values.length - 100);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _key,
      jsonEncode(
        values
            .map(
              (item) => {
                'responseId': item.responseId,
                'helpful': item.helpful,
                'reason': item.reason,
                'createdAt': item.createdAt.toUtc().toIso8601String(),
              },
            )
            .toList(growable: false),
      ),
    );
  }

  static String responseId(String entryId, String response) {
    var hash = 0xcbf29ce484222325;
    for (final unit in '$entryId\u001f$response'.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16);
  }
}

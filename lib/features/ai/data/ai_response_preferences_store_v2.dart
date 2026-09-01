import 'package:shared_preferences/shared_preferences.dart';

import '../domain/ai_response_preferences_v2.dart';

class AiResponsePreferencesStoreV2 {
  static const _styleKey = 'v2_ai_response_style';
  static const _lengthKey = 'v2_ai_response_length';
  static const _questionsKey = 'v2_ai_allow_questions';
  static const _platitudesKey = 'v2_ai_avoid_platitudes';

  Future<AiResponsePreferencesV2> load() async {
    final preferences = await SharedPreferences.getInstance();
    return AiResponsePreferencesV2(
      style: AiCompanionStyleV2.values.firstWhere(
        (value) => value.name == preferences.getString(_styleKey),
        orElse: () => AiCompanionStyleV2.balanced,
      ),
      length: AiReplyLengthV2.values.firstWhere(
        (value) => value.name == preferences.getString(_lengthKey),
        orElse: () => AiReplyLengthV2.medium,
      ),
      allowQuestions: preferences.getBool(_questionsKey) ?? true,
      avoidPlatitudes: preferences.getBool(_platitudesKey) ?? true,
    );
  }

  Future<void> save(AiResponsePreferencesV2 value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_styleKey, value.style.name);
    await preferences.setString(_lengthKey, value.length.name);
    await preferences.setBool(_questionsKey, value.allowQuestions);
    await preferences.setBool(_platitudesKey, value.avoidPlatitudes);
  }
}

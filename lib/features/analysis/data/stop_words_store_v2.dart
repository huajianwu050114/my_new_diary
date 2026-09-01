import 'package:shared_preferences/shared_preferences.dart';

class StopWordsStoreV2 {
  static const _key = 'v2_custom_stop_words';

  Future<Set<String>> load() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(_key) ?? const []).toSet();
  }

  Future<void> save(Set<String> words) async {
    final preferences = await SharedPreferences.getInstance();
    final sorted = words.toList()..sort();
    await preferences.setStringList(_key, sorted);
  }
}

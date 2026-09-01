import 'dart:convert';

class AiMemorySuggestionsV2 {
  static List<String> parse(String response) {
    var text = response.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      text = text.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic> || decoded['suggestions'] is! List) {
      throw const FormatException('AI记忆建议格式不正确');
    }
    return (decoded['suggestions'] as List)
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .take(5)
        .toList(growable: false);
  }
}

import 'dart:convert';

class LifeFragmentDraftV2 {
  const LifeFragmentDraftV2({
    required this.suitable,
    required this.reason,
    required this.title,
    required this.coreInsight,
    required this.context,
    required this.evidence,
    required this.futureUse,
    required this.messageToFutureSelf,
    required this.tags,
  });

  final bool suitable;
  final String reason;
  final String title;
  final String coreInsight;
  final String context;
  final String evidence;
  final String futureUse;
  final String messageToFutureSelf;
  final List<String> tags;

  static LifeFragmentDraftV2 parse(String response) {
    var text = response.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      text = text.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('AI 返回的草稿格式不正确');
    }
    String string(String key) =>
        decoded[key] is String ? (decoded[key] as String).trim() : '';
    return LifeFragmentDraftV2(
      suitable: decoded['suitable'] == true,
      reason: string('reason'),
      title: string('title'),
      coreInsight: string('coreInsight'),
      context: string('context'),
      evidence: string('evidence'),
      futureUse: string('futureUse'),
      messageToFutureSelf: string('messageToFutureSelf'),
      tags: decoded['tags'] is List
          ? List.unmodifiable((decoded['tags'] as List).whereType<String>())
          : const [],
    );
  }
}

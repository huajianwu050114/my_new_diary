import 'dart:convert';

import 'ai_chat_session_v2.dart';

enum GuidedJournalCadenceV2 {
  quiet('安静听我说'),
  natural('自然聊天'),
  curious('多问问我');

  const GuidedJournalCadenceV2(this.label);

  final String label;
}

class GuidedJournalReplyDecisionV2 {
  const GuidedJournalReplyDecisionV2({required this.respond, this.reply = ''});

  final bool respond;
  final String reply;

  static GuidedJournalReplyDecisionV2 parse(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      text = text.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('陪写回应格式不正确');
    }
    final respond = decoded['respond'] == true;
    final reply = decoded['reply'] is String
        ? (decoded['reply'] as String).trim()
        : '';
    if (respond && reply.isEmpty) {
      throw const FormatException('陪写回应为空');
    }
    return GuidedJournalReplyDecisionV2(respond: respond, reply: reply);
  }
}

class GuidedJournalDraftV2 {
  const GuidedJournalDraftV2({required this.body, required this.session});

  final String body;
  final AiChatSessionV2 session;
}

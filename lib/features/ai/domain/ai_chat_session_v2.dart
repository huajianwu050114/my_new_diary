import 'dart:convert';

import 'ai_models_v2.dart';

class AiChatSessionV2 {
  const AiChatSessionV2({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  static const storagePrefix = '【AI 会话】';

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<AiSessionMessageV2> messages;

  AiChatSessionV2 copyWith({
    String? title,
    DateTime? updatedAt,
    List<AiSessionMessageV2>? messages,
  }) {
    return AiChatSessionV2(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: List.unmodifiable(messages ?? this.messages),
    );
  }

  String encode() =>
      '$storagePrefix${jsonEncode({'id': id, 'title': title, 'createdAt': createdAt.toUtc().toIso8601String(), 'updatedAt': updatedAt.toUtc().toIso8601String(), 'messages': messages.map((message) => message.toJson()).toList()})}';

  static AiChatSessionV2? tryDecode(String value) {
    if (!value.startsWith(storagePrefix)) return null;
    try {
      final decoded = jsonDecode(value.substring(storagePrefix.length));
      if (decoded is! Map<String, dynamic>) return null;
      final messages = (decoded['messages'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AiSessionMessageV2.fromJson)
          .toList(growable: false);
      return AiChatSessionV2(
        id: decoded['id'] as String,
        title: decoded['title'] as String? ?? '未命名对话',
        createdAt: DateTime.parse(decoded['createdAt'] as String),
        updatedAt: DateTime.parse(decoded['updatedAt'] as String),
        messages: messages,
      );
    } catch (_) {
      return null;
    }
  }
}

class AiSessionMessageV2 {
  const AiSessionMessageV2({
    required this.role,
    required this.text,
    required this.createdAt,
  });

  final AiChatRoleV2 role;
  final String text;
  final DateTime createdAt;

  AiChatMessageV2 toChatMessage() => AiChatMessageV2(role: role, text: text);

  Map<String, Object?> toJson() => {
    'role': role.name,
    'text': text,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory AiSessionMessageV2.fromJson(Map<String, dynamic> json) {
    return AiSessionMessageV2(
      role: json['role'] == AiChatRoleV2.model.name
          ? AiChatRoleV2.model
          : AiChatRoleV2.user,
      text: json['text'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

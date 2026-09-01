enum AiReplyTaskStatusV2 { pending, generating, completed, failed }

class AiReplyTaskV2 {
  const AiReplyTaskV2({
    required this.entryId,
    required this.contentFingerprint,
    required this.status,
    required this.attempts,
    required this.updatedAt,
    this.nextAttemptAt,
  });

  final String entryId;
  final String contentFingerprint;
  final AiReplyTaskStatusV2 status;
  final int attempts;
  final DateTime updatedAt;
  final DateTime? nextAttemptAt;

  bool isDue(DateTime now) =>
      nextAttemptAt == null || !nextAttemptAt!.isAfter(now);

  AiReplyTaskV2 copyWith({
    String? contentFingerprint,
    AiReplyTaskStatusV2? status,
    int? attempts,
    DateTime? updatedAt,
    DateTime? nextAttemptAt,
    bool clearNextAttemptAt = false,
  }) {
    return AiReplyTaskV2(
      entryId: entryId,
      contentFingerprint: contentFingerprint ?? this.contentFingerprint,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      updatedAt: updatedAt ?? this.updatedAt,
      nextAttemptAt: clearNextAttemptAt
          ? null
          : nextAttemptAt ?? this.nextAttemptAt,
    );
  }

  Map<String, Object?> toJson() => {
    'entryId': entryId,
    'contentFingerprint': contentFingerprint,
    'status': status.name,
    'attempts': attempts,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'nextAttemptAt': nextAttemptAt?.toUtc().toIso8601String(),
  };

  static AiReplyTaskV2? tryFromJson(Object? value) {
    if (value is! Map) return null;
    try {
      final statusName = value['status'];
      return AiReplyTaskV2(
        entryId: value['entryId'] as String,
        contentFingerprint: value['contentFingerprint'] as String,
        status: AiReplyTaskStatusV2.values.firstWhere(
          (status) => status.name == statusName,
        ),
        attempts: value['attempts'] as int,
        updatedAt: DateTime.parse(value['updatedAt'] as String).toUtc(),
        nextAttemptAt: value['nextAttemptAt'] == null
            ? null
            : DateTime.parse(value['nextAttemptAt'] as String).toUtc(),
      );
    } catch (_) {
      return null;
    }
  }
}

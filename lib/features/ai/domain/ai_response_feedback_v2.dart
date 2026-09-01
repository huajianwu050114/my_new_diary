class AiResponseFeedbackV2 {
  const AiResponseFeedbackV2({
    required this.responseId,
    required this.helpful,
    required this.reason,
    required this.createdAt,
  });

  final String responseId;
  final bool helpful;
  final String reason;
  final DateTime createdAt;
}

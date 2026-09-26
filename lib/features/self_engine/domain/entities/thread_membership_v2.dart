enum ThreadMembershipOriginV2 { automatic, user }

class ThreadMembershipV2 {
  const ThreadMembershipV2({
    required this.threadId,
    required this.atomId,
    required this.relevance,
    required this.origin,
    required this.generation,
    required this.createdAt,
    this.removedAt,
  });

  final String threadId;
  final String atomId;
  final double relevance;
  final ThreadMembershipOriginV2 origin;
  final int generation;
  final DateTime createdAt;
  final DateTime? removedAt;
}

class SelfThreadSummaryV2 {
  const SelfThreadSummaryV2({
    required this.id,
    required this.title,
    required this.description,
    required this.firstSeen,
    required this.lastSeen,
    required this.distinctDiaryCount,
    required this.evidenceCount,
  });

  final String id;
  final String title;
  final String description;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final int distinctDiaryCount;
  final int evidenceCount;
}

class SelfThreadEvidenceV2 {
  const SelfThreadEvidenceV2({
    required this.atomId,
    required this.diaryId,
    required this.occurredAt,
    required this.statement,
    required this.sourceQuote,
  });

  final String atomId;
  final String diaryId;
  final DateTime occurredAt;
  final String statement;
  final String sourceQuote;
}

class SelfThreadDetailV2 {
  const SelfThreadDetailV2({required this.summary, required this.evidence});

  final SelfThreadSummaryV2 summary;
  final List<SelfThreadEvidenceV2> evidence;
}

class SelfEngineReadStateV2 {
  const SelfEngineReadStateV2({
    required this.hasLiveWork,
    required this.hasFailedWork,
  });

  final bool hasLiveWork;
  final bool hasFailedWork;
}

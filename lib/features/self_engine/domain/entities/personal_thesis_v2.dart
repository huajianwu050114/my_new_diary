enum PersonalThesisStatusV2 { active, invalidated }

enum PersonalThesisMaturityV2 { candidate, emerging, established }

enum PersonalThesisTrendV2 {
  strengthening,
  stable,
  weakening,
  contradicted,
  dormant,
}

enum PersonalThesisEvidenceRoleV2 { support, counter }

class PersonalThesisV2 {
  const PersonalThesisV2({
    required this.id,
    required this.sourceThreadId,
    required this.status,
    required this.generation,
    required this.createdAt,
    required this.updatedAt,
    this.threadId,
    this.currentVersionId,
  });

  final String id;
  final String sourceThreadId;
  final String? threadId;
  final PersonalThesisStatusV2 status;
  final String? currentVersionId;
  final int generation;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class PersonalThesisVersionV2 {
  const PersonalThesisVersionV2({
    required this.id,
    required this.thesisId,
    required this.versionNo,
    required this.statement,
    required this.rationale,
    required this.maturity,
    required this.trend,
    required this.generation,
    required this.createdAt,
  });

  final String id;
  final String thesisId;
  final int versionNo;
  final String statement;
  final String rationale;
  final PersonalThesisMaturityV2 maturity;
  final PersonalThesisTrendV2 trend;
  final int generation;
  final DateTime createdAt;
}

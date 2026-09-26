enum MemoryAtomKindV2 {
  event,
  person,
  place,
  preference,
  dislike,
  fear,
  hope,
  goal,
  regret,
  belief,
  opinion,
  valueJudgement,
  copingStrategy,
  importantQuote,
  question,
  decision,
  lifeChange,
  other,
}

enum MemoryAtomScopeV2 { state, recurring, unknown }

class MemoryAtomV2 {
  const MemoryAtomV2({
    required this.id,
    required this.revisionId,
    required this.kind,
    required this.statement,
    required this.sourceQuote,
    required this.scope,
    required this.pipelineVersion,
    required this.generation,
    required this.createdAt,
    this.sourceStart,
    this.sourceEnd,
    this.observedAt,
    this.supersededAt,
  });

  final String id;
  final String revisionId;
  final MemoryAtomKindV2 kind;
  final String statement;
  final String sourceQuote;
  final int? sourceStart;
  final int? sourceEnd;
  final DateTime? observedAt;
  final MemoryAtomScopeV2 scope;
  final int pipelineVersion;
  final int generation;
  final DateTime createdAt;
  final DateTime? supersededAt;
}

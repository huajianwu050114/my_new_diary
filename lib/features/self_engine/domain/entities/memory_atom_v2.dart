enum MemoryAtomKindV2 {
  event,
  feeling,
  preference,
  dislike,
  desire,
  belief,
  decision,
  coping,
  relationship,
  quoteOrExpression,
}

enum MemoryAtomScopeV2 { state, explicitLongTerm, unknown }

/// A validated extraction result that is independent from a historical
/// revision. It can therefore be cached by computation identity and later
/// materialized as a new [MemoryAtomV2] for every matching revision.
class MemoryAtomDraftV2 {
  const MemoryAtomDraftV2({
    required this.kind,
    required this.statement,
    required this.sourceQuote,
    required this.sourceStart,
    required this.sourceEnd,
    required this.scope,
  });

  final MemoryAtomKindV2 kind;
  final String statement;
  final String sourceQuote;
  final int sourceStart;
  final int sourceEnd;
  final MemoryAtomScopeV2 scope;
}

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

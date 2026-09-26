import '../domain/entities/diary_revision_v2.dart';
import '../domain/entities/memory_atom_v2.dart';
import '../domain/entities/memory_extraction_v2.dart';

class MemoryAtomValidatorV2 {
  const MemoryAtomValidatorV2({
    this.maxAtoms = 6,
    this.maxStatementLength = 240,
    this.maxQuoteLength = 500,
  });

  final int maxAtoms;
  final int maxStatementLength;
  final int maxQuoteLength;

  List<MemoryAtomDraftV2> validate(
    DiaryRevisionV2 revision,
    MemoryExtractionBatchV2 batch,
  ) {
    if (batch.extractorVersion <= 0 ||
        batch.promptVersion <= 0 ||
        batch.modelIdentifier.trim().isEmpty) {
      throw const MemoryExtractionValidationFailureV2(
        'Extraction metadata is incomplete.',
      );
    }
    if (batch.candidates.length > maxAtoms) {
      throw MemoryExtractionValidationFailureV2(
        'Extraction returned ${batch.candidates.length} atoms; maximum is '
        '$maxAtoms.',
      );
    }

    final statements = <String>{};
    final evidence = <String>{};
    final valid = <MemoryAtomDraftV2>[];
    for (final candidate in batch.candidates) {
      final statement = candidate.statement.trim();
      final quote = candidate.sourceQuote;
      if (statement.isEmpty ||
          statement.length > maxStatementLength ||
          quote.isEmpty ||
          quote.length > maxQuoteLength) {
        continue;
      }
      final kind = _kind(candidate.kind);
      final scope = _scope(candidate.scope);
      if (kind == null || scope == null) continue;

      final offsets = _offsets(revision.body, quote, candidate);
      if (offsets == null) continue;
      final statementKey = statement.toLowerCase();
      final evidenceKey = '${kind.name}\u0000$quote';
      if (!statements.add(statementKey) || !evidence.add(evidenceKey)) {
        continue;
      }
      valid.add(
        MemoryAtomDraftV2(
          kind: kind,
          statement: statement,
          sourceQuote: quote,
          sourceStart: offsets.$1,
          sourceEnd: offsets.$2,
          scope: scope,
        ),
      );
    }
    return List.unmodifiable(valid);
  }

  List<MemoryAtomDraftV2> validateCached(
    DiaryRevisionV2 revision,
    List<MemoryAtomDraftV2> atoms,
  ) => validate(
    revision,
    MemoryExtractionBatchV2(
      candidates: atoms
          .map(
            (atom) => MemoryExtractionCandidateV2(
              kind: atom.kind.name,
              statement: atom.statement,
              sourceQuote: atom.sourceQuote,
              sourceStart: atom.sourceStart,
              sourceEnd: atom.sourceEnd,
              scope: atom.scope.name,
            ),
          )
          .toList(growable: false),
      extractorVersion: 1,
      promptVersion: 1,
      modelIdentifier: 'cached',
    ),
  );

  (int, int)? _offsets(
    String body,
    String quote,
    MemoryExtractionCandidateV2 candidate,
  ) {
    final start = candidate.sourceStart;
    final end = candidate.sourceEnd;
    if ((start == null) != (end == null)) return null;
    if (start == null) {
      final found = body.indexOf(quote);
      return found < 0 ? null : (found, found + quote.length);
    }
    if (start < 0 || end! < start || end > body.length) return null;
    return body.substring(start, end) == quote ? (start, end) : null;
  }

  MemoryAtomKindV2? _kind(String value) {
    try {
      return MemoryAtomKindV2.values.byName(value);
    } on ArgumentError {
      return null;
    }
  }

  MemoryAtomScopeV2? _scope(String value) {
    try {
      return MemoryAtomScopeV2.values.byName(value);
    } on ArgumentError {
      return null;
    }
  }
}

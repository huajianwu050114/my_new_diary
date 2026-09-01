/// Adds a newly extracted insight without overwriting words the user already
/// confirmed in an existing fragment.
LifeFragmentV2 mergeLifeFragmentsV2(
  LifeFragmentV2 existing,
  LifeFragmentV2 addition, {
  required DateTime updatedAt,
}) {
  String append(String oldValue, String newValue) {
    final oldText = oldValue.trim();
    final newText = newValue.trim();
    if (newText.isEmpty || oldText == newText) return oldText;
    if (oldText.isEmpty) return newText;
    return '$oldText\n\n$newText';
  }

  return existing.copyWith(
    coreInsight: append(existing.coreInsight, addition.coreInsight),
    context: append(existing.context, addition.context),
    evidence: append(existing.evidence, addition.evidence),
    futureUse: append(existing.futureUse, addition.futureUse),
    messageToFutureSelf: append(
      existing.messageToFutureSelf,
      addition.messageToFutureSelf,
    ),
    tags: {...existing.tags, ...addition.tags}.toList(growable: false),
    sourceDiaryIds: {
      ...existing.sourceDiaryIds,
      ...addition.sourceDiaryIds,
    }.toList(growable: false),
    isRope: existing.isRope || addition.isRope,
    updatedAt: updatedAt,
  );
}

enum LifeFragmentStatusV2 { draft, confirmed }

class LifeFragmentV2 {
  const LifeFragmentV2({
    required this.id,
    required this.title,
    required this.coreInsight,
    required this.context,
    required this.evidence,
    required this.futureUse,
    required this.messageToFutureSelf,
    required this.theme,
    required this.createdAt,
    required this.updatedAt,
    this.tags = const [],
    this.sourceDiaryIds = const [],
    this.isRope = false,
    this.status = LifeFragmentStatusV2.draft,
  });

  final String id;
  final String title;
  final String coreInsight;
  final String context;
  final String evidence;
  final String futureUse;
  final String messageToFutureSelf;
  final String theme;
  final List<String> tags;
  final List<String> sourceDiaryIds;
  final bool isRope;
  final LifeFragmentStatusV2 status;
  final DateTime createdAt;
  final DateTime updatedAt;

  LifeFragmentV2 copyWith({
    String? title,
    String? coreInsight,
    String? context,
    String? evidence,
    String? futureUse,
    String? messageToFutureSelf,
    String? theme,
    List<String>? tags,
    List<String>? sourceDiaryIds,
    bool? isRope,
    LifeFragmentStatusV2? status,
    DateTime? updatedAt,
  }) {
    return LifeFragmentV2(
      id: id,
      title: title ?? this.title,
      coreInsight: coreInsight ?? this.coreInsight,
      context: context ?? this.context,
      evidence: evidence ?? this.evidence,
      futureUse: futureUse ?? this.futureUse,
      messageToFutureSelf: messageToFutureSelf ?? this.messageToFutureSelf,
      theme: theme ?? this.theme,
      tags: List.unmodifiable(tags ?? this.tags),
      sourceDiaryIds: List.unmodifiable(sourceDiaryIds ?? this.sourceDiaryIds),
      isRope: isRope ?? this.isRope,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

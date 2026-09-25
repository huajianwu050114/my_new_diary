class DailyEncouragementV2 {
  const DailyEncouragementV2({
    required this.dateKey,
    required this.text,
    required this.createdAt,
    this.author,
    this.work,
    this.provider,
    this.sourceUrl,
  });

  final String dateKey;
  final String text;
  final DateTime createdAt;
  final String? author;
  final String? work;
  final String? provider;
  final String? sourceUrl;

  String? get attribution {
    final values = [
      if (author?.trim().isNotEmpty == true) author!.trim(),
      if (work?.trim().isNotEmpty == true) '《${work!.trim()}》',
    ];
    return values.isEmpty ? null : values.join(' · ');
  }

  Map<String, Object?> toJson() => {
    'dateKey': dateKey,
    'text': text,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'author': author,
    'work': work,
    'provider': provider,
    'sourceUrl': sourceUrl,
  };

  static DailyEncouragementV2? tryFromJson(Object? value) {
    if (value is! Map) return null;
    try {
      return DailyEncouragementV2(
        dateKey: value['dateKey'] as String,
        text: value['text'] as String,
        createdAt: DateTime.parse(value['createdAt'] as String).toUtc(),
        author: value['author'] as String?,
        work: value['work'] as String?,
        provider: value['provider'] as String?,
        sourceUrl: value['sourceUrl'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

class DailyEncouragementDraftV2 {
  const DailyEncouragementDraftV2({
    required this.text,
    this.author,
    this.work,
    this.provider,
    this.sourceUrl,
  });

  final String text;
  final String? author;
  final String? work;
  final String? provider;
  final String? sourceUrl;
}

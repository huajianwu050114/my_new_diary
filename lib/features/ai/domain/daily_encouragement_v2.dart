class DailyEncouragementV2 {
  const DailyEncouragementV2({
    required this.dateKey,
    required this.text,
    required this.createdAt,
  });

  final String dateKey;
  final String text;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'dateKey': dateKey,
    'text': text,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  static DailyEncouragementV2? tryFromJson(Object? value) {
    if (value is! Map) return null;
    try {
      return DailyEncouragementV2(
        dateKey: value['dateKey'] as String,
        text: value['text'] as String,
        createdAt: DateTime.parse(value['createdAt'] as String).toUtc(),
      );
    } catch (_) {
      return null;
    }
  }
}

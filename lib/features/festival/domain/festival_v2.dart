class CustomFestivalV2 {
  const CustomFestivalV2({
    required this.id,
    required this.name,
    required this.month,
    required this.day,
    required this.createdAt,
  });

  final String id;
  final String name;
  final int month;
  final int day;
  final DateTime createdAt;

  DateTime nextOccurrence(DateTime from) {
    var occurrence = DateTime(from.year, month, day);
    final today = DateTime(from.year, from.month, from.day);
    if (occurrence.isBefore(today)) {
      occurrence = DateTime(from.year + 1, month, day);
    }
    return occurrence;
  }
}

class FestivalOccurrenceV2 {
  const FestivalOccurrenceV2({
    required this.id,
    required this.name,
    required this.date,
    required this.isCustom,
  });

  final String id;
  final String name;
  final DateTime date;
  final bool isCustom;

  int daysUntil(DateTime from) {
    final today = DateTime(from.year, from.month, from.day);
    return date.difference(today).inDays;
  }
}

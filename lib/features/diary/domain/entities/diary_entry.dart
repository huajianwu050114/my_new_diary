/// A storage-independent diary entry used by the v2 application.
///
/// This model deliberately contains no SQLite, Firebase, Flutter, or file
/// system types. Data-layer models are responsible for converting persisted
/// values to and from this entity.
class DiaryEntryV2 {
  const DiaryEntryV2({
    required this.id,
    required this.body,
    required this.entryDate,
    required this.createdAt,
    required this.updatedAt,
    this.imageIds = const [],
    this.mood,
    this.tags = const [],
    this.location,
    this.aiAnalyses = const [],
    this.isFavorite = false,
    this.deletedAt,
  });

  final String id;
  final String body;
  final DateTime entryDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> imageIds;
  final String? mood;
  final List<String> tags;
  final DiaryLocation? location;
  final List<String> aiAnalyses;
  final bool isFavorite;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  DiaryEntryV2 copyWith({
    String? id,
    String? body,
    DateTime? entryDate,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? imageIds,
    String? mood,
    bool clearMood = false,
    List<String>? tags,
    DiaryLocation? location,
    bool clearLocation = false,
    List<String>? aiAnalyses,
    bool? isFavorite,
    DateTime? deletedAt,
    bool restore = false,
  }) {
    return DiaryEntryV2(
      id: id ?? this.id,
      body: body ?? this.body,
      entryDate: entryDate ?? this.entryDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      imageIds: List.unmodifiable(imageIds ?? this.imageIds),
      mood: clearMood ? null : mood ?? this.mood,
      tags: List.unmodifiable(tags ?? this.tags),
      location: clearLocation ? null : location ?? this.location,
      aiAnalyses: List.unmodifiable(aiAnalyses ?? this.aiAnalyses),
      isFavorite: isFavorite ?? this.isFavorite,
      deletedAt: restore ? null : deletedAt ?? this.deletedAt,
    );
  }
}

class DiaryLocation {
  const DiaryLocation({
    required this.latitude,
    required this.longitude,
    this.address,
  });

  final double latitude;
  final double longitude;
  final String? address;
}

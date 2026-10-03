import '../../diary/domain/entities/diary_entry.dart';

class DiarySyncRecordV2 {
  const DiarySyncRecordV2({
    this.schemaVersion = 1,
    required this.id,
    required this.body,
    required this.entryDate,
    required this.createdAt,
    required this.updatedAt,
    this.contentDelta,
    this.imageIds = const [],
    this.mood,
    this.tags = const [],
    this.latitude,
    this.longitude,
    this.address,
    this.aiAnalyses = const [],
    this.isFavorite = false,
    this.deletedAt,
    this.purged = false,
  });

  final int schemaVersion;
  final String id;
  final String body;
  final String? contentDelta;
  final DateTime entryDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> imageIds;
  final String? mood;
  final List<String> tags;
  final double? latitude;
  final double? longitude;
  final String? address;
  final List<String> aiAnalyses;
  final bool isFavorite;
  final DateTime? deletedAt;
  final bool purged;

  factory DiarySyncRecordV2.fromEntry(DiaryEntryV2 entry) {
    return DiarySyncRecordV2(
      id: entry.id,
      body: entry.body,
      contentDelta: entry.contentDelta,
      entryDate: entry.entryDate,
      createdAt: entry.createdAt,
      updatedAt: entry.updatedAt,
      imageIds: List.unmodifiable(entry.imageIds),
      mood: entry.mood,
      tags: List.unmodifiable(entry.tags),
      latitude: entry.location?.latitude,
      longitude: entry.location?.longitude,
      address: entry.location?.address,
      aiAnalyses: List.unmodifiable(entry.aiAnalyses),
      isFavorite: entry.isFavorite,
      deletedAt: entry.deletedAt,
    );
  }

  factory DiarySyncRecordV2.purged({
    required String id,
    required DateTime updatedAt,
  }) {
    final utc = updatedAt.toUtc();
    return DiarySyncRecordV2(
      id: id,
      body: '',
      entryDate: utc,
      createdAt: utc,
      updatedAt: utc,
      deletedAt: utc,
      purged: true,
    );
  }

  DiaryEntryV2 toEntry() {
    if (purged) {
      throw StateError('A purge tombstone is not a diary entry.');
    }
    final hasLocation = latitude != null && longitude != null;
    return DiaryEntryV2(
      id: id,
      body: body,
      contentDelta: contentDelta,
      entryDate: entryDate,
      createdAt: createdAt,
      updatedAt: updatedAt,
      imageIds: List.unmodifiable(imageIds),
      mood: mood,
      tags: List.unmodifiable(tags),
      location: hasLocation
          ? DiaryLocation(
              latitude: latitude!,
              longitude: longitude!,
              address: address,
            )
          : null,
      aiAnalyses: List.unmodifiable(aiAnalyses),
      isFavorite: isFavorite,
      deletedAt: deletedAt,
    );
  }
}

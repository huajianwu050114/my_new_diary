import '../entities/diary_entry.dart';

/// Storage contract for diary entries.
///
/// Implementations may use SQLite, memory, or a future sync-aware data source,
/// but callers only work with domain values.
abstract interface class DiaryRepositoryV2 {
  Stream<List<DiaryEntryV2>> watchEntries({
    DiaryQuery query = const DiaryQuery(),
  });

  Future<DiaryEntryV2?> getById(String id);

  Future<void> save(DiaryEntryV2 entry);

  /// Inserts a backup record without creating a synthetic revision.
  /// Existing IDs are rejected; callers must resolve conflicts first.
  Future<void> restoreFromBackup(DiaryEntryV2 entry);

  Future<void> moveToTrash(String id, {required DateTime deletedAt});

  Future<void> restore(String id);

  Future<void> setFavorite(String id, {required bool isFavorite});

  Future<void> deletePermanently(String id);
}

class DiaryQuery {
  const DiaryQuery({
    this.text,
    this.tags = const [],
    this.from,
    this.to,
    this.includeDeleted = false,
    this.onlyDeleted = false,
    this.onlyFavorites = false,
  }) : assert(!(includeDeleted && onlyDeleted));

  final String? text;
  final List<String> tags;
  final DateTime? from;
  final DateTime? to;
  final bool includeDeleted;
  final bool onlyDeleted;
  final bool onlyFavorites;
}

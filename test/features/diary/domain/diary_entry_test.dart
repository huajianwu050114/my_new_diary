import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/diary/domain/entities/diary_entry.dart';

void main() {
  group('DiaryEntryV2', () {
    final createdAt = DateTime.utc(2026, 1, 2, 3, 4);
    final entry = DiaryEntryV2(
      id: 'entry-1',
      body: 'A quiet day',
      contentDelta: '[{"insert":"A quiet day\\n"}]',
      entryDate: DateTime.utc(2026, 1, 2),
      createdAt: createdAt,
      updatedAt: createdAt,
      imageIds: const ['image-1'],
      mood: 'calm',
      tags: const ['daily'],
      location: const DiaryLocation(
        latitude: 22.3193,
        longitude: 114.1694,
        address: 'Hong Kong',
      ),
    );

    test('copyWith preserves fields that are not changed', () {
      final updated = entry.copyWith(
        body: 'An edited quiet day',
        updatedAt: createdAt.add(const Duration(minutes: 5)),
      );

      expect(updated.id, entry.id);
      expect(updated.body, 'An edited quiet day');
      expect(updated.contentDelta, entry.contentDelta);
      expect(updated.imageIds, entry.imageIds);
      expect(updated.location?.address, 'Hong Kong');
      expect(updated.updatedAt.isAfter(entry.updatedAt), isTrue);
    });

    test('soft deletion can be restored', () {
      final deleted = entry.copyWith(
        deletedAt: createdAt.add(const Duration(days: 1)),
      );
      final restored = deleted.copyWith(restore: true);

      expect(deleted.isDeleted, isTrue);
      expect(restored.isDeleted, isFalse);
    });

    test('nullable values can be explicitly cleared', () {
      final cleared = entry.copyWith(
        clearMood: true,
        clearLocation: true,
        clearContentDelta: true,
      );

      expect(cleared.mood, isNull);
      expect(cleared.location, isNull);
      expect(cleared.contentDelta, isNull);
    });
  });
}

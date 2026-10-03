import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/diary/domain/entities/diary_entry.dart';
import 'package:my_new_diary/features/sync/data/diary_sync_codec_v2.dart';
import 'package:my_new_diary/features/sync/domain/diary_sync_record_v2.dart';

void main() {
  const codec = DiarySyncCodecV2();
  final instant = DateTime.utc(2026, 10, 2, 12, 31, 22);

  test('Diary -> sync JSON -> Diary preserves complete source data', () {
    final entry = DiaryEntryV2(
      id: 'entry-1',
      body: '今天练琴了。 🎸\n第二行',
      contentDelta: '[{"insert":"rich\\n"}]',
      entryDate: instant.subtract(const Duration(hours: 1)),
      createdAt: instant.subtract(const Duration(minutes: 40)),
      updatedAt: instant,
      imageIds: const ['A.jpg', 'B.png'],
      mood: 'happy',
      tags: const ['生活', '吉他'],
      location: const DiaryLocation(
        latitude: 31.2304,
        longitude: 121.4737,
        address: '上海',
      ),
      aiAnalyses: const ['用户可见的 AI 回应'],
      isFavorite: true,
      deletedAt: instant.add(const Duration(minutes: 1)),
    );

    final json = codec.encode(DiarySyncRecordV2.fromEntry(entry));
    final restored = codec.decode(json).toEntry();

    expect(restored.id, entry.id);
    expect(restored.body, entry.body);
    expect(restored.contentDelta, entry.contentDelta);
    expect(restored.entryDate, entry.entryDate);
    expect(restored.createdAt, entry.createdAt);
    expect(restored.updatedAt, entry.updatedAt);
    expect(restored.imageIds, entry.imageIds);
    expect(restored.mood, entry.mood);
    expect(restored.tags, entry.tags);
    expect(restored.location?.latitude, entry.location?.latitude);
    expect(restored.location?.longitude, entry.location?.longitude);
    expect(restored.location?.address, entry.location?.address);
    expect(restored.aiAnalyses, entry.aiAnalyses);
    expect(restored.isFavorite, isTrue);
    expect(restored.deletedAt, entry.deletedAt);
    expect(json, contains('2026-10-02T12:31:22.000Z'));
  });

  test('nullable fields round trip', () {
    final entry = DiaryEntryV2(
      id: 'nullable',
      body: '',
      entryDate: instant,
      createdAt: instant,
      updatedAt: instant,
    );
    final restored = codec.decode(
      codec.encode(DiarySyncRecordV2.fromEntry(entry)),
    );
    expect(restored.contentDelta, isNull);
    expect(restored.mood, isNull);
    expect(restored.latitude, isNull);
    expect(restored.deletedAt, isNull);
  });

  test('encoding is canonical and deterministic', () {
    final record = DiarySyncRecordV2(
      id: 'stable',
      body: 'body',
      entryDate: instant.toLocal(),
      createdAt: instant.toLocal(),
      updatedAt: instant.toLocal(),
      tags: const ['b', 'a'],
      imageIds: const ['2.png', '1.png'],
    );
    expect(
      codec.encode(record),
      codec.encode(codec.decode(codec.encode(record))),
    );
    expect(codec.decode(codec.encode(record)).tags, const ['b', 'a']);
    expect(codec.decode(codec.encode(record)).imageIds, const [
      '2.png',
      '1.png',
    ]);
  });

  test(
    'rejects unsupported schema, malformed JSON, missing ID and bad time',
    () {
      expect(
        () => codec.decode(
          '{"schemaVersion":2,"id":"x","updatedAt":"2026-01-01T00:00:00Z"}',
        ),
        throwsA(isA<UnsupportedDiarySyncSchemaException>()),
      );
      expect(() => codec.decode('{'), throwsA(isA<DiarySyncFormatException>()));
      expect(
        () => codec.decode(
          '{"schemaVersion":1,"updatedAt":"2026-01-01T00:00:00Z"}',
        ),
        throwsA(isA<DiarySyncFormatException>()),
      );
      final map =
          jsonDecode(
                codec.encode(
                  DiarySyncRecordV2(
                    id: 'bad-time',
                    body: '',
                    entryDate: instant,
                    createdAt: instant,
                    updatedAt: instant,
                  ),
                ),
              )
              as Map<String, dynamic>;
      map['updatedAt'] = 'yesterday';
      expect(
        () => codec.decode(jsonEncode(map)),
        throwsA(isA<DiarySyncFormatException>()),
      );
    },
  );

  test('purge tombstone uses minimal durable schema', () {
    final json = codec.encode(
      DiarySyncRecordV2.purged(id: 'gone', updatedAt: instant),
    );
    final map = jsonDecode(json) as Map<String, dynamic>;
    expect(map['purged'], isTrue);
    expect(map['deletedAt'], isNotNull);
    expect(map.containsKey('body'), isFalse);
  });
}

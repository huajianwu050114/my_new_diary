import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_new_diary/features/diary/data/local/diary_metadata_template_store_v2.dart';
import 'package:my_new_diary/features/diary/domain/entities/diary_entry.dart';
import 'package:my_new_diary/features/diary/domain/entities/diary_metadata_template_v2.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saves, reloads, updates, and deletes metadata templates', () async {
    final store = DiaryMetadataTemplateStoreV2();
    const original = DiaryMetadataTemplateV2(
      id: 'school',
      name: '学校',
      mood: '期待又紧张 🌧️',
      tags: ['学习', '校园'],
      location: DiaryLocation(
        latitude: 31.2304,
        longitude: 121.4737,
        address: '学校',
      ),
    );

    await store.save(original);
    final loaded = (await store.load()).single;
    expect(loaded.name, original.name);
    expect(loaded.mood, original.mood);
    expect(loaded.tags, original.tags);
    expect(loaded.location?.latitude, original.location?.latitude);
    expect(loaded.location?.address, original.location?.address);

    await store.save(
      const DiaryMetadataTemplateV2(id: 'school', name: '晚自习', tags: ['学习']),
    );
    expect((await store.load()).single.name, '晚自习');

    await store.delete('school');
    expect(await store.load(), isEmpty);
  });
}

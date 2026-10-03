import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_new_diary/features/sync/data/file_diary_sync_store_v2.dart';

void main() {
  late Directory temporary;

  setUp(
    () async =>
        temporary = await Directory.systemTemp.createTemp('sync-store-'),
  );
  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test(
    'JSON and image writes are atomic and unchanged data is not rewritten',
    () async {
      final store = FileDiarySyncStoreV2(temporary);
      final jsonBytes = Uint8List.fromList(utf8.encode('{"id":"A"}'));
      expect(await store.writeEntryAtomic('A.json', jsonBytes), isTrue);
      final entry = File(
        '${store.entriesDirectory.path}${Platform.pathSeparator}A.json',
      );
      final firstModified = await entry.lastModified();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await store.writeEntryAtomic('A.json', jsonBytes), isFalse);
      expect(await entry.lastModified(), firstModified);
      expect(await File('${entry.path}.tmp').exists(), isFalse);

      expect(
        await store.writeImageAtomic('A.jpg', Uint8List.fromList([1, 2, 3])),
        isTrue,
      );
      expect(
        await store.writeImageAtomic('A.jpg', Uint8List.fromList([1, 2, 3])),
        isFalse,
      );
      expect(
        await File(
          '${store.imagesDirectory.path}${Platform.pathSeparator}A.jpg.tmp',
        ).exists(),
        isFalse,
      );
    },
  );

  test('scan ignores tmp and Syncthing conflict files', () async {
    final store = FileDiarySyncStoreV2(temporary);
    await store.ensureReady();
    await File(
      '${store.entriesDirectory.path}${Platform.pathSeparator}A.json',
    ).writeAsString('{}');
    await File(
      '${store.entriesDirectory.path}${Platform.pathSeparator}B.json.tmp',
    ).writeAsString('{}');
    await File(
      '${store.entriesDirectory.path}${Platform.pathSeparator}A.sync-conflict-1.json',
    ).writeAsString('{}');
    final files = await store.listEntryFiles();
    expect(files, containsAll(<String>['A.json', 'A.sync-conflict-1.json']));
    expect(files, isNot(contains('B.json.tmp')));
  });
}

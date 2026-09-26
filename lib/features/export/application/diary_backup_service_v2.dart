import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../../analysis/data/stop_words_store_v2.dart';
import '../../ai/data/ai_memory_store_v2.dart';
import '../../ai/domain/ai_memory_v2.dart';
import '../../diary/application/ports/diary_image_store_v2.dart';
import '../../diary/domain/entities/diary_entry.dart';
import '../../diary/domain/repositories/diary_repository_v2.dart';
import '../../festival/domain/festival_repository_v2.dart';
import '../../festival/domain/festival_v2.dart';
import '../../life_library/domain/life_document_repository_v2.dart';
import '../../life_library/domain/life_document_v2.dart';
import '../../life_library/domain/life_space_v2.dart';
import '../../life_guide/domain/life_fragment_repository_v2.dart';
import '../../life_guide/domain/life_fragment_revision_v2.dart';
import '../../life_guide/domain/life_fragment_v2.dart';
import '../../self_engine/domain/entities/diary_revision_v2.dart';
import '../../self_engine/domain/diary_source_fingerprint_v2.dart';
import '../../self_engine/domain/repositories/self_engine_repository_v2.dart';
import 'backup_sqlite_snapshot_reader_v2.dart';
import 'backup_restore_journal_v2.dart';

class DiaryBackupServiceV2 {
  DiaryBackupServiceV2({
    required this.diaryRepository,
    required this.imageStore,
    required this.festivalRepository,
    required this.stopWordsStore,
    required this.lifeDocumentRepository,
    required this.lifeFragmentRepository,
    required this.selfEngineRepository,
    required this.aiMemoryStore,
    required this.snapshotReader,
    BackupRestoreJournalV2? restoreJournal,
  }) : restoreJournal = restoreJournal ?? BackupRestoreJournalV2();

  final DiaryRepositoryV2 diaryRepository;
  final DiaryImageStoreV2 imageStore;
  final FestivalRepositoryV2 festivalRepository;
  final StopWordsStoreV2 stopWordsStore;
  final LifeDocumentRepositoryV2 lifeDocumentRepository;
  final LifeFragmentRepositoryV2 lifeFragmentRepository;
  final SelfEngineRepositoryV2 selfEngineRepository;
  final AiMemoryStoreV2 aiMemoryStore;
  final BackupSqliteSnapshotReaderV2 snapshotReader;
  final BackupRestoreJournalV2 restoreJournal;

  Future<Uint8List> exportZip() async {
    final snapshot = await snapshotReader.read();
    final stopWords = await stopWordsStore.load();
    final aiMemories = await aiMemoryStore.loadStrict();
    _validateManifestGraph(
      version: 2,
      entries: snapshot.entries,
      festivals: snapshot.festivals,
      spaces: snapshot.lifeSpaces,
      documents: snapshot.lifeDocuments,
      fragments: snapshot.lifeFragments,
      fragmentRevisions: snapshot.lifeFragmentRevisions,
      revisions: snapshot.diaryRevisions,
      memories: aiMemories,
    );
    final archive = Archive();
    final manifest = {
      'format': 'my_new_diary_v2',
      'version': 2,
      'fingerprintVersion': DiarySourceFingerprintV2.version,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'entries': snapshot.entries.map(_entryToJson).toList(),
      'festivals': snapshot.festivals.map(_festivalToJson).toList(),
      'stopWords': stopWords.toList()..sort(),
      'lifeDocuments': snapshot.lifeDocuments.map(_lifeDocumentToJson).toList(),
      'lifeSpaces': snapshot.lifeSpaces.map(_lifeSpaceToJson).toList(),
      'lifeFragments': snapshot.lifeFragments.map(_lifeFragmentToJson).toList(),
      'lifeFragmentRevisions': snapshot.lifeFragmentRevisions
          .map(_lifeFragmentRevisionToJson)
          .toList(),
      'diaryRevisions': snapshot.diaryRevisions
          .map(_diaryRevisionToJson)
          .toList(),
      'aiMemories': aiMemories.map(_aiMemoryToJson).toList(),
    };
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );
    final imageIds = snapshot.entries.expand((entry) => entry.imageIds).toSet();
    for (final imageId in imageIds) {
      final bytes = await imageStore.read(imageId);
      if (bytes == null) {
        throw StateError('Diary image $imageId is missing; backup aborted.');
      }
      archive.addFile(ArchiveFile('images/$imageId', bytes.length, bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Future<BackupImportReportV2> importZip(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) {
      throw const FormatException('备份中缺少 manifest.json');
    }
    final manifest = jsonDecode(utf8.decode(manifestFile.content as List<int>));
    if (manifest is! Map<String, dynamic> ||
        manifest['format'] != 'my_new_diary_v2' ||
        (manifest['version'] != 1 && manifest['version'] != 2)) {
      throw const FormatException('不支持的备份格式');
    }
    if (manifest['version'] == 2 &&
        manifest['fingerprintVersion'] != DiarySourceFingerprintV2.version) {
      throw const FormatException('不支持或缺少 fingerprintVersion');
    }

    final entryValues = _objectList(manifest, 'entries');
    final festivalValues = _objectList(manifest, 'festivals');
    final spaceValues = _objectList(manifest, 'lifeSpaces');
    final documentValues = _objectList(manifest, 'lifeDocuments');
    final fragmentValues = _objectList(manifest, 'lifeFragments');
    final fragmentRevisionValues = _objectList(
      manifest,
      'lifeFragmentRevisions',
    );
    final revisionValues = _objectList(manifest, 'diaryRevisions');
    final memoryValues = _objectList(manifest, 'aiMemories');

    // Parse and cross-check the complete manifest before staging a file or
    // mutating any repository. A malformed backup must fail closed.
    final entries = entryValues
        .map(
          (value) => _entryFromJson(
            value,
            _stringList(value['imageIds'], 'entries.imageIds'),
          ),
        )
        .toList(growable: false);
    final festivals = festivalValues
        .map(_festivalFromJson)
        .toList(growable: false);
    final spaces = spaceValues.map(_lifeSpaceFromJson).toList(growable: false);
    final documents = documentValues
        .map(_lifeDocumentFromJson)
        .toList(growable: false);
    final fragments = fragmentValues
        .map(_lifeFragmentFromJson)
        .toList(growable: false);
    final fragmentRevisions = fragmentRevisionValues
        .map(_lifeFragmentRevisionFromJson)
        .toList(growable: false);
    final revisions = revisionValues
        .map(_diaryRevisionFromJson)
        .toList(growable: false);
    final memories = memoryValues
        .map(_aiMemoryFromJson)
        .toList(growable: false);
    final restoredStopWords = _stringList(
      manifest['stopWords'],
      'stopWords',
    ).toSet();
    _validateManifestGraph(
      version: manifest['version'] as int,
      entries: entries,
      festivals: festivals,
      spaces: spaces,
      documents: documents,
      fragments: fragments,
      fragmentRevisions: fragmentRevisions,
      revisions: revisions,
      memories: memories,
    );

    final imageBytes = <String, Uint8List>{};
    for (final oldId in entries.expand((entry) => entry.imageIds).toSet()) {
      final file = archive.findFile('images/$oldId');
      if (file == null) {
        throw FormatException('备份图片 $oldId 缺失或不可读');
      }
      imageBytes[oldId] = Uint8List.fromList(file.content as List<int>);
    }

    final digest = sha256.convert(bytes).toString();
    final activeJournal = await restoreJournal.load();
    if (activeJournal == null) {
      await _requireEmptyDestination();
    }
    var journal = await restoreJournal.begin(digest);
    if (activeJournal != null) {
      await _requireResumeCompatible(
        version: manifest['version'] as int,
        entries: entries,
        festivals: festivals,
        spaces: spaces,
        documents: documents,
        fragments: fragments,
        fragmentRevisions: fragmentRevisions,
        revisions: revisions,
        memories: memories,
      );
    }

    for (final entry in imageBytes.entries) {
      final existingId = journal.imageIds[entry.key];
      if (existingId != null) {
        if (await imageStore.read(existingId) == null) {
          throw StateError('暂存图片 $existingId 已丢失');
        }
        continue;
      }
      final restoredId = await imageStore.save(
        bytes: entry.value,
        extension: entry.key.split('.').last,
      );
      journal = await restoreJournal.recordImage(
        journal,
        sourceId: entry.key,
        restoredId: restoredId,
      );
    }

    for (final entry in entries) {
      final restored = entry.copyWith(
        imageIds: entry.imageIds
            .map((id) => journal.imageIds[id]!)
            .toList(growable: false),
      );
      final existing = await diaryRepository.getById(restored.id);
      if (existing == null) {
        await diaryRepository.restoreFromBackup(restored);
      } else if (!_sameEntry(existing, restored)) {
        throw BackupRestoreConflictV2('Diary ${restored.id} 在恢复期间发生冲突');
      }
    }

    final grouped = <String, List<DiaryRevisionV2>>{};
    for (final revision in revisions) {
      grouped.putIfAbsent(revision.diaryId, () => []).add(revision);
    }
    for (final entry in grouped.entries) {
      await selfEngineRepository.restoreRevisionsForDiary(
        entry.key,
        entry.value,
      );
    }
    await selfEngineRepository.backfillMissingRevisions(
      limit: entryValues.length + 1,
    );

    final existingFestivals = {
      for (final value in await festivalRepository.watchCustomFestivals().first)
        value.id: value,
    };
    for (final value in festivals) {
      final existing = existingFestivals[value.id];
      if (existing == null) {
        await festivalRepository.save(value);
      } else if (!_sameFestival(existing, value)) {
        throw BackupRestoreConflictV2('Festival ${value.id} 冲突');
      }
    }

    final existingStopWords = await stopWordsStore.load();
    if (existingStopWords.isEmpty) {
      await stopWordsStore.save(restoredStopWords);
    } else if (!_sameSet(existingStopWords, restoredStopWords)) {
      throw const BackupRestoreConflictV2('停用词冲突');
    }

    for (final value in spaces) {
      final existing = await lifeDocumentRepository.getSpaceById(value.id);
      if (existing == null) {
        await lifeDocumentRepository.saveSpace(value);
      } else if (!_sameSpace(
        existing,
        value,
        ignoreTimestamps: value.isSystem,
      )) {
        throw BackupRestoreConflictV2('Life space ${value.id} 冲突');
      }
    }
    for (final value in documents) {
      final existing = await lifeDocumentRepository.getById(value.id);
      if (existing == null) {
        await lifeDocumentRepository.save(value);
      } else if (!_sameDocument(existing, value)) {
        throw BackupRestoreConflictV2('Life document ${value.id} 冲突');
      }
    }

    for (final value in fragments) {
      final existing = await lifeFragmentRepository.getById(value.id);
      if (existing == null) {
        await lifeFragmentRepository.save(value);
      } else if (!_sameFragment(existing, value)) {
        throw BackupRestoreConflictV2('Life fragment ${value.id} 冲突');
      }
    }
    for (final value in fragmentRevisions) {
      await lifeFragmentRepository.restoreRevision(value);
    }

    final existingMemories = {
      for (final value in await aiMemoryStore.loadStrict()) value.id: value,
    };
    for (final value in memories) {
      final existing = existingMemories[value.id];
      if (existing == null) {
        await aiMemoryStore.save(value);
      } else if (!_sameMemory(existing, value)) {
        throw BackupRestoreConflictV2('AI memory ${value.id} 冲突');
      }
    }
    await restoreJournal.complete(digest);
    return BackupImportReportV2(
      importedEntries: entries.length,
      importedFestivals: festivals.length,
      importedLifeDocuments: documents.length,
      importedLifeSpaces: spaces.length,
      importedLifeFragments: fragments.length,
      importedLifeFragmentRevisions: fragmentRevisions.length,
      importedDiaryRevisions: revisions.length,
      importedAiMemories: memories.length,
    );
  }

  List<Map<String, dynamic>> _objectList(
    Map<String, dynamic> manifest,
    String key,
  ) {
    final value = manifest[key];
    if (value == null) return const [];
    if (value is! List) throw FormatException('$key 必须是数组');
    return value
        .map((item) {
          if (item is! Map) throw FormatException('$key 包含无效记录');
          return Map<String, dynamic>.from(item);
        })
        .toList(growable: false);
  }

  List<String> _stringList(Object? value, String field) {
    if (value == null) return const [];
    if (value is! List || value.any((item) => item is! String)) {
      throw FormatException('$field must be an array of strings.');
    }
    return List<String>.unmodifiable(value.cast<String>());
  }

  void _validateManifestGraph({
    required int version,
    required List<DiaryEntryV2> entries,
    required List<CustomFestivalV2> festivals,
    required List<LifeSpaceV2> spaces,
    required List<LifeDocumentV2> documents,
    required List<LifeFragmentV2> fragments,
    required List<LifeFragmentRevisionV2> fragmentRevisions,
    required List<DiaryRevisionV2> revisions,
    required List<AiMemoryV2> memories,
  }) {
    _requireUniqueIds('Diary', entries.map((value) => value.id));
    _requireUniqueIds('Festival', festivals.map((value) => value.id));
    _requireUniqueIds('Life space', spaces.map((value) => value.id));
    _requireUniqueIds('Life document', documents.map((value) => value.id));
    _requireUniqueIds('Life fragment', fragments.map((value) => value.id));
    _requireUniqueIds(
      'Life fragment revision',
      fragmentRevisions.map((value) => value.id),
    );
    _requireUniqueIds('Diary revision', revisions.map((value) => value.id));
    _requireUniqueIds('AI memory', memories.map((value) => value.id));

    final entryIds = entries.map((value) => value.id).toSet();
    final spaceIds = spaces.map((value) => value.id).toSet();
    final fragmentIds = fragments.map((value) => value.id).toSet();
    for (final entry in entries) {
      // Also validates paired, finite, in-range coordinates.
      DiarySourceFingerprintV2.calculate(entry);
    }
    for (final document in documents) {
      if (!spaceIds.contains(document.space)) {
        throw FormatException(
          'Life document ${document.id} references missing space '
          '${document.space}.',
        );
      }
    }
    for (final revision in fragmentRevisions) {
      if (!fragmentIds.contains(revision.fragmentId) ||
          revision.snapshot.id != revision.fragmentId) {
        throw FormatException(
          'Life fragment revision ${revision.id} has an invalid parent.',
        );
      }
    }

    final revisionsByDiary = <String, List<DiaryRevisionV2>>{};
    final revisionNumbers = <String>{};
    for (final revision in revisions) {
      if (!entryIds.contains(revision.diaryId)) {
        throw FormatException(
          'Revision ${revision.id} references missing Diary '
          '${revision.diaryId}.',
        );
      }
      if (!revisionNumbers.add('${revision.diaryId}:${revision.revisionNo}')) {
        throw FormatException(
          'Duplicate revision number ${revision.revisionNo} for '
          '${revision.diaryId}.',
        );
      }
      if (revision.fingerprintVersion != DiarySourceFingerprintV2.version ||
          DiarySourceFingerprintV2.calculateRevision(revision) !=
              revision.sourceHash) {
        throw FormatException('Revision ${revision.id} has an invalid hash.');
      }
      revisionsByDiary.putIfAbsent(revision.diaryId, () => []).add(revision);
    }
    if (version == 2) {
      for (final entry in entries) {
        final history = revisionsByDiary[entry.id];
        if (history == null || history.isEmpty) {
          throw FormatException('Diary ${entry.id} has no revision history.');
        }
        history.sort((a, b) => a.revisionNo.compareTo(b.revisionNo));
        for (var index = 0; index < history.length; index++) {
          if (history[index].revisionNo != index + 1) {
            throw FormatException(
              'Diary ${entry.id} has a non-contiguous revision history.',
            );
          }
        }
        if (history.last.sourceHash !=
            DiarySourceFingerprintV2.calculate(entry)) {
          throw FormatException(
            'Diary ${entry.id} does not match its latest revision.',
          );
        }
      }
    }
  }

  void _requireUniqueIds(String label, Iterable<String> ids) {
    final seen = <String>{};
    for (final id in ids) {
      if (id.isEmpty || !seen.add(id)) {
        throw FormatException('$label ID is empty or duplicated: $id');
      }
    }
  }

  Future<void> _requireEmptyDestination() async {
    final entries = await diaryRepository
        .watchEntries(query: const DiaryQuery(includeDeleted: true))
        .first;
    final festivals = await festivalRepository.watchCustomFestivals().first;
    final documents = await lifeDocumentRepository.getAllDocuments(
      includeDeleted: true,
    );
    final customSpaces = (await lifeDocumentRepository.watchSpaces().first)
        .where((space) => !space.isSystem);
    final fragments = await lifeFragmentRepository.watchFragments().first;
    final revisions = await selfEngineRepository.getAllRevisions();
    final memories = await aiMemoryStore.loadStrict();
    final stopWords = await stopWordsStore.load();
    if (entries.isNotEmpty ||
        festivals.isNotEmpty ||
        documents.isNotEmpty ||
        customSpaces.isNotEmpty ||
        fragments.isNotEmpty ||
        revisions.isNotEmpty ||
        memories.isNotEmpty ||
        stopWords.isNotEmpty) {
      throw BackupRestoreConflictV2(
        '完整备份只能恢复到空数据库；现有数据：diaries=${entries.length}, '
        'festivals=${festivals.length}, documents=${documents.length}, '
        'spaces=${customSpaces.length}, fragments=${fragments.length}, '
        'revisions=${revisions.length}, memories=${memories.length}, '
        'stopWords=${stopWords.length}。',
      );
    }
  }

  Future<void> _requireResumeCompatible({
    required int version,
    required List<DiaryEntryV2> entries,
    required List<CustomFestivalV2> festivals,
    required List<LifeSpaceV2> spaces,
    required List<LifeDocumentV2> documents,
    required List<LifeFragmentV2> fragments,
    required List<LifeFragmentRevisionV2> fragmentRevisions,
    required List<DiaryRevisionV2> revisions,
    required List<AiMemoryV2> memories,
  }) async {
    final existingEntries = await diaryRepository
        .watchEntries(query: const DiaryQuery(includeDeleted: true))
        .first;
    final existingFestivals = await festivalRepository
        .watchCustomFestivals()
        .first;
    final existingDocuments = await lifeDocumentRepository.getAllDocuments(
      includeDeleted: true,
    );
    final existingSpaces = (await lifeDocumentRepository.watchSpaces().first)
        .where((space) => !space.isSystem);
    final existingFragments = await lifeFragmentRepository
        .watchFragments()
        .first;
    final existingFragmentRevisions = <LifeFragmentRevisionV2>[];
    for (final fragment in existingFragments) {
      existingFragmentRevisions.addAll(
        await lifeFragmentRepository.getRevisions(fragment.id),
      );
    }
    final existingRevisions = await selfEngineRepository.getAllRevisions();
    final existingMemories = await aiMemoryStore.loadStrict();

    _requireIdSubset(
      'Diary',
      existingEntries.map((value) => value.id),
      entries.map((value) => value.id),
    );
    _requireIdSubset(
      'Festival',
      existingFestivals.map((value) => value.id),
      festivals.map((value) => value.id),
    );
    _requireIdSubset(
      'Life document',
      existingDocuments.map((value) => value.id),
      documents.map((value) => value.id),
    );
    _requireIdSubset(
      'Life space',
      existingSpaces.map((value) => value.id),
      spaces.where((value) => !value.isSystem).map((value) => value.id),
    );
    _requireIdSubset(
      'Life fragment',
      existingFragments.map((value) => value.id),
      fragments.map((value) => value.id),
    );
    _requireIdSubset(
      'Life fragment revision',
      existingFragmentRevisions.map((value) => value.id),
      fragmentRevisions.map((value) => value.id),
    );
    if (version == 2) {
      _requireIdSubset(
        'Diary revision',
        existingRevisions.map((value) => value.id),
        revisions.map((value) => value.id),
      );
    } else {
      _requireIdSubset(
        'Diary revision parent',
        existingRevisions.map((value) => value.diaryId),
        entries.map((value) => value.id),
      );
    }
    _requireIdSubset(
      'AI memory',
      existingMemories.map((value) => value.id),
      memories.map((value) => value.id),
    );
  }

  void _requireIdSubset(
    String label,
    Iterable<String> existing,
    Iterable<String> allowed,
  ) {
    final unexpected = existing.toSet().difference(allowed.toSet());
    if (unexpected.isNotEmpty) {
      throw BackupRestoreConflictV2(
        '$label data appeared during restore: $unexpected',
      );
    }
  }

  bool _sameEntry(DiaryEntryV2 left, DiaryEntryV2 right) =>
      jsonEncode(_entryToJson(left)) == jsonEncode(_entryToJson(right));

  bool _sameFestival(CustomFestivalV2 left, CustomFestivalV2 right) =>
      jsonEncode(_festivalToJson(left)) == jsonEncode(_festivalToJson(right));

  bool _sameDocument(LifeDocumentV2 left, LifeDocumentV2 right) =>
      jsonEncode(_lifeDocumentToJson(left)) ==
      jsonEncode(_lifeDocumentToJson(right));

  bool _sameSpace(
    LifeSpaceV2 left,
    LifeSpaceV2 right, {
    required bool ignoreTimestamps,
  }) {
    final leftJson = _lifeSpaceToJson(left);
    final rightJson = _lifeSpaceToJson(right);
    if (ignoreTimestamps) {
      leftJson.remove('createdAt');
      leftJson.remove('updatedAt');
      rightJson.remove('createdAt');
      rightJson.remove('updatedAt');
    }
    return jsonEncode(leftJson) == jsonEncode(rightJson);
  }

  bool _sameFragment(LifeFragmentV2 left, LifeFragmentV2 right) =>
      jsonEncode(_lifeFragmentToJson(left)) ==
      jsonEncode(_lifeFragmentToJson(right));

  bool _sameMemory(AiMemoryV2 left, AiMemoryV2 right) =>
      jsonEncode(_aiMemoryToJson(left)) == jsonEncode(_aiMemoryToJson(right));

  bool _sameSet(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);

  Map<String, Object?> _entryToJson(DiaryEntryV2 entry) => {
    'id': entry.id,
    'body': entry.body,
    'contentDelta': entry.contentDelta,
    'entryDate': entry.entryDate.toUtc().toIso8601String(),
    'createdAt': entry.createdAt.toUtc().toIso8601String(),
    'updatedAt': entry.updatedAt.toUtc().toIso8601String(),
    'imageIds': entry.imageIds,
    'mood': entry.mood,
    'tags': entry.tags,
    'latitude': entry.location?.latitude,
    'longitude': entry.location?.longitude,
    'address': entry.location?.address,
    'aiAnalyses': entry.aiAnalyses,
    'isFavorite': entry.isFavorite,
    'deletedAt': entry.deletedAt?.toUtc().toIso8601String(),
  };

  DiaryEntryV2 _entryFromJson(
    Map<String, dynamic> value,
    List<String> imageIds,
  ) {
    final latitude = value['latitude'];
    final longitude = value['longitude'];
    if ((latitude == null) != (longitude == null) ||
        (latitude != null && (latitude is! num || longitude is! num))) {
      throw const FormatException('Diary location coordinates are invalid.');
    }
    return DiaryEntryV2(
      id: value['id'] as String,
      body: value['body'] as String,
      contentDelta: value['contentDelta'] as String?,
      entryDate: DateTime.parse(value['entryDate'] as String),
      createdAt: DateTime.parse(value['createdAt'] as String),
      updatedAt: DateTime.parse(value['updatedAt'] as String),
      imageIds: imageIds,
      mood: value['mood'] as String?,
      tags: _stringList(value['tags'], 'entries.tags'),
      location: latitude is num && longitude is num
          ? DiaryLocation(
              latitude: latitude.toDouble(),
              longitude: longitude.toDouble(),
              address: value['address'] as String?,
            )
          : null,
      aiAnalyses: _stringList(value['aiAnalyses'], 'entries.aiAnalyses'),
      isFavorite: value['isFavorite'] == true,
      deletedAt: value['deletedAt'] == null
          ? null
          : DateTime.parse(value['deletedAt'] as String),
    );
  }

  Map<String, Object?> _festivalToJson(CustomFestivalV2 festival) => {
    'id': festival.id,
    'name': festival.name,
    'month': festival.month,
    'day': festival.day,
    'createdAt': festival.createdAt.toUtc().toIso8601String(),
  };

  CustomFestivalV2 _festivalFromJson(Map<String, dynamic> value) {
    return CustomFestivalV2(
      id: value['id'] as String,
      name: value['name'] as String,
      month: value['month'] as int,
      day: value['day'] as int,
      createdAt: DateTime.parse(value['createdAt'] as String),
    );
  }

  Map<String, Object?> _lifeDocumentToJson(LifeDocumentV2 value) => {
    'id': value.id,
    'space': value.space,
    'title': value.title,
    'markdown': value.markdown,
    'type': value.type.name,
    'documentDate': value.documentDate?.toUtc().toIso8601String(),
    'templateId': value.templateId,
    'tags': value.tags,
    'isPinned': value.isPinned,
    'createdAt': value.createdAt.toUtc().toIso8601String(),
    'updatedAt': value.updatedAt.toUtc().toIso8601String(),
    'deletedAt': value.deletedAt?.toUtc().toIso8601String(),
  };

  LifeDocumentV2 _lifeDocumentFromJson(Map<String, dynamic> value) {
    return LifeDocumentV2(
      id: value['id'] as String,
      space: value['space'] as String,
      title: value['title'] as String,
      markdown: value['markdown'] as String,
      type: LifeDocumentTypeV2.values.firstWhere(
        (type) => type.name == value['type'],
      ),
      documentDate: _optionalDate(value['documentDate']),
      templateId: value['templateId'] as String?,
      tags: _stringList(value['tags'], 'lifeDocuments.tags'),
      isPinned: value['isPinned'] == true,
      createdAt: _requiredDate(value['createdAt'], 'lifeDocuments.createdAt'),
      updatedAt: _requiredDate(value['updatedAt'], 'lifeDocuments.updatedAt'),
      deletedAt: _optionalDate(value['deletedAt']),
    );
  }

  Map<String, Object?> _lifeSpaceToJson(LifeSpaceV2 value) => {
    'id': value.id,
    'name': value.name,
    'iconCodePoint': value.iconCodePoint,
    'colorValue': value.colorValue,
    'sortOrder': value.sortOrder,
    'isSystem': value.isSystem,
    'createdAt': value.createdAt.toUtc().toIso8601String(),
    'updatedAt': value.updatedAt.toUtc().toIso8601String(),
  };

  LifeSpaceV2 _lifeSpaceFromJson(Map<String, dynamic> value) {
    return LifeSpaceV2(
      id: value['id'] as String,
      name: value['name'] as String,
      iconCodePoint: value['iconCodePoint'] as int,
      colorValue: value['colorValue'] as int,
      sortOrder: value['sortOrder'] as int,
      isSystem: value['isSystem'] == true,
      createdAt: _requiredDate(value['createdAt'], 'lifeSpaces.createdAt'),
      updatedAt: _requiredDate(value['updatedAt'], 'lifeSpaces.updatedAt'),
    );
  }

  Map<String, Object?> _lifeFragmentToJson(LifeFragmentV2 value) => {
    'id': value.id,
    'title': value.title,
    'coreInsight': value.coreInsight,
    'context': value.context,
    'evidence': value.evidence,
    'futureUse': value.futureUse,
    'messageToFutureSelf': value.messageToFutureSelf,
    'theme': value.theme,
    'tags': value.tags,
    'sourceDiaryIds': value.sourceDiaryIds,
    'isRope': value.isRope,
    'status': value.status.name,
    'createdAt': value.createdAt.toUtc().toIso8601String(),
    'updatedAt': value.updatedAt.toUtc().toIso8601String(),
  };

  LifeFragmentV2 _lifeFragmentFromJson(Map<String, dynamic> value) {
    return LifeFragmentV2(
      id: value['id'] as String,
      title: value['title'] as String,
      coreInsight: value['coreInsight'] as String,
      context: value['context'] as String,
      evidence: value['evidence'] as String,
      futureUse: value['futureUse'] as String,
      messageToFutureSelf: value['messageToFutureSelf'] as String,
      theme: value['theme'] as String,
      tags: _stringList(value['tags'], 'lifeFragments.tags'),
      sourceDiaryIds: _stringList(
        value['sourceDiaryIds'],
        'lifeFragments.sourceDiaryIds',
      ),
      isRope: value['isRope'] == true,
      status: LifeFragmentStatusV2.values.firstWhere(
        (status) => status.name == value['status'],
      ),
      createdAt: _requiredDate(value['createdAt'], 'lifeFragments.createdAt'),
      updatedAt: _requiredDate(value['updatedAt'], 'lifeFragments.updatedAt'),
    );
  }

  Map<String, Object?> _lifeFragmentRevisionToJson(
    LifeFragmentRevisionV2 value,
  ) => {
    'id': value.id,
    'fragmentId': value.fragmentId,
    'snapshot': _lifeFragmentToJson(value.snapshot),
    'createdAt': value.createdAt.toUtc().toIso8601String(),
  };

  LifeFragmentRevisionV2 _lifeFragmentRevisionFromJson(
    Map<String, dynamic> value,
  ) => LifeFragmentRevisionV2(
    id: value['id'] as String,
    fragmentId: value['fragmentId'] as String,
    snapshot: _lifeFragmentFromJson(
      Map<String, dynamic>.from(value['snapshot'] as Map),
    ),
    createdAt: _requiredDate(
      value['createdAt'],
      'lifeFragmentRevisions.createdAt',
    ),
  );

  Map<String, Object?> _diaryRevisionToJson(DiaryRevisionV2 value) => {
    'id': value.id,
    'diaryId': value.diaryId,
    'revisionNo': value.revisionNo,
    'body': value.body,
    'contentDelta': value.contentDelta,
    'sourceHash': value.sourceHash,
    'fingerprintVersion': value.fingerprintVersion,
    'entryDate': value.entryDate.toUtc().toIso8601String(),
    'mood': value.mood,
    'tags': value.tags,
    'latitude': value.latitude,
    'longitude': value.longitude,
    'address': value.address,
    'createdAt': value.createdAt.toUtc().toIso8601String(),
  };

  DiaryRevisionV2 _diaryRevisionFromJson(Map<String, dynamic> value) =>
      DiaryRevisionV2(
        id: value['id'] as String,
        diaryId: value['diaryId'] as String,
        revisionNo: value['revisionNo'] as int,
        body: value['body'] as String? ?? '',
        contentDelta: value['contentDelta'] as String?,
        sourceHash: value['sourceHash'] as String,
        fingerprintVersion:
            value['fingerprintVersion'] as int? ??
            DiarySourceFingerprintV2.version,
        entryDate: DateTime.parse(value['entryDate'] as String),
        mood: value['mood'] as String?,
        tags: _stringList(value['tags'], 'diaryRevisions.tags'),
        latitude: (value['latitude'] as num?)?.toDouble(),
        longitude: (value['longitude'] as num?)?.toDouble(),
        address: value['address'] as String?,
        createdAt: DateTime.parse(value['createdAt'] as String),
      );

  Map<String, Object?> _aiMemoryToJson(AiMemoryV2 value) => {
    'id': value.id,
    'text': value.text,
    'enabled': value.enabled,
    'createdAt': value.createdAt.toUtc().toIso8601String(),
  };

  AiMemoryV2 _aiMemoryFromJson(Map<String, dynamic> value) => AiMemoryV2(
    id: value['id'] as String,
    text: value['text'] as String,
    enabled: value['enabled'] != false,
    createdAt: _requiredDate(value['createdAt'], 'aiMemories.createdAt'),
  );

  DateTime _requiredDate(Object? value, String field) {
    if (value is! String || value.isEmpty) {
      throw FormatException('$field must be an ISO-8601 timestamp.');
    }
    return DateTime.parse(value);
  }

  DateTime? _optionalDate(Object? value) {
    if (value == null || value == '') return null;
    if (value is! String) {
      throw const FormatException('Optional timestamp must be a string.');
    }
    return DateTime.parse(value);
  }
}

class BackupImportReportV2 {
  const BackupImportReportV2({
    required this.importedEntries,
    required this.importedFestivals,
    this.importedLifeDocuments = 0,
    this.importedLifeSpaces = 0,
    this.importedLifeFragments = 0,
    this.importedLifeFragmentRevisions = 0,
    this.importedDiaryRevisions = 0,
    this.importedAiMemories = 0,
  });

  final int importedEntries;
  final int importedFestivals;
  final int importedLifeDocuments;
  final int importedLifeSpaces;
  final int importedLifeFragments;
  final int importedLifeFragmentRevisions;
  final int importedDiaryRevisions;
  final int importedAiMemories;
}

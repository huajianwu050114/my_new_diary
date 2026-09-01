import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:uuid/uuid.dart';

import '../../analysis/data/stop_words_store_v2.dart';
import '../../diary/application/ports/diary_image_store_v2.dart';
import '../../diary/domain/entities/diary_entry.dart';
import '../../diary/domain/repositories/diary_repository_v2.dart';
import '../../festival/domain/festival_repository_v2.dart';
import '../../festival/domain/festival_v2.dart';
import '../../life_library/domain/life_document_repository_v2.dart';
import '../../life_library/domain/life_document_v2.dart';

class DiaryBackupServiceV2 {
  const DiaryBackupServiceV2({
    required this.diaryRepository,
    required this.imageStore,
    required this.festivalRepository,
    required this.stopWordsStore,
    this.lifeDocumentRepository,
  });

  final DiaryRepositoryV2 diaryRepository;
  final DiaryImageStoreV2 imageStore;
  final FestivalRepositoryV2 festivalRepository;
  final StopWordsStoreV2 stopWordsStore;
  final LifeDocumentRepositoryV2? lifeDocumentRepository;

  Future<Uint8List> exportZip() async {
    final entries = await diaryRepository
        .watchEntries(query: const DiaryQuery(includeDeleted: true))
        .first;
    final festivals = await festivalRepository.watchCustomFestivals().first;
    final stopWords = await stopWordsStore.load();
    final lifeDocuments =
        await lifeDocumentRepository?.watchDocuments().first ??
        const <LifeDocumentV2>[];
    final archive = Archive();
    final manifest = {
      'format': 'my_new_diary_v2',
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'entries': entries.map(_entryToJson).toList(),
      'festivals': festivals.map(_festivalToJson).toList(),
      'stopWords': stopWords.toList()..sort(),
      'lifeDocuments': lifeDocuments.map(_lifeDocumentToJson).toList(),
    };
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );
    final imageIds = entries.expand((entry) => entry.imageIds).toSet();
    for (final imageId in imageIds) {
      final bytes = await imageStore.read(imageId);
      if (bytes != null) {
        archive.addFile(ArchiveFile('images/$imageId', bytes.length, bytes));
      }
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
        manifest['version'] != 1) {
      throw const FormatException('不支持的备份格式');
    }

    var importedEntries = 0;
    final entries = (manifest['entries'] as List? ?? const []);
    for (final value in entries.whereType<Map<String, dynamic>>()) {
      final newImageIds = <String>[];
      try {
        for (final oldId
            in (value['imageIds'] as List? ?? const []).whereType<String>()) {
          final imageFile = archive.findFile('images/$oldId');
          if (imageFile == null) {
            continue;
          }
          newImageIds.add(
            await imageStore.save(
              bytes: Uint8List.fromList(imageFile.content as List<int>),
              extension: oldId.split('.').last,
            ),
          );
        }
        final restored = _entryFromJson(value, newImageIds);
        final existing = await diaryRepository.getById(restored.id);
        await diaryRepository.save(restored);
        for (final oldImageId in existing?.imageIds ?? const <String>[]) {
          if (!newImageIds.contains(oldImageId)) {
            await imageStore.delete(oldImageId);
          }
        }
        importedEntries++;
      } catch (_) {
        for (final imageId in newImageIds) {
          await imageStore.delete(imageId);
        }
        rethrow;
      }
    }
    var importedFestivals = 0;
    for (final value
        in (manifest['festivals'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()) {
      await festivalRepository.save(_festivalFromJson(value));
      importedFestivals++;
    }
    await stopWordsStore.save(
      (manifest['stopWords'] as List? ?? const []).whereType<String>().toSet(),
    );
    var importedLifeDocuments = 0;
    final lifeRepository = lifeDocumentRepository;
    if (lifeRepository != null) {
      for (final value
          in (manifest['lifeDocuments'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()) {
        await lifeRepository.save(_lifeDocumentFromJson(value));
        importedLifeDocuments++;
      }
    }
    return BackupImportReportV2(
      importedEntries: importedEntries,
      importedFestivals: importedFestivals,
      importedLifeDocuments: importedLifeDocuments,
    );
  }

  Map<String, Object?> _entryToJson(DiaryEntryV2 entry) => {
    'id': entry.id,
    'body': entry.body,
    'entryDate': entry.entryDate.toIso8601String(),
    'createdAt': entry.createdAt.toIso8601String(),
    'updatedAt': entry.updatedAt.toIso8601String(),
    'imageIds': entry.imageIds,
    'mood': entry.mood,
    'tags': entry.tags,
    'latitude': entry.location?.latitude,
    'longitude': entry.location?.longitude,
    'address': entry.location?.address,
    'aiAnalyses': entry.aiAnalyses,
    'isFavorite': entry.isFavorite,
    'deletedAt': entry.deletedAt?.toIso8601String(),
  };

  DiaryEntryV2 _entryFromJson(
    Map<String, dynamic> value,
    List<String> imageIds,
  ) {
    final latitude = value['latitude'];
    final longitude = value['longitude'];
    return DiaryEntryV2(
      id: value['id'] as String? ?? const Uuid().v4(),
      body: value['body'] as String? ?? '',
      entryDate: DateTime.parse(value['entryDate'] as String),
      createdAt: DateTime.parse(value['createdAt'] as String),
      updatedAt: DateTime.parse(value['updatedAt'] as String),
      imageIds: imageIds,
      mood: value['mood'] as String?,
      tags: (value['tags'] as List? ?? const []).whereType<String>().toList(),
      location: latitude is num && longitude is num
          ? DiaryLocation(
              latitude: latitude.toDouble(),
              longitude: longitude.toDouble(),
              address: value['address'] as String?,
            )
          : null,
      aiAnalyses: (value['aiAnalyses'] as List? ?? const [])
          .whereType<String>()
          .toList(),
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
    'createdAt': festival.createdAt.toIso8601String(),
  };

  CustomFestivalV2 _festivalFromJson(Map<String, dynamic> value) {
    return CustomFestivalV2(
      id: value['id'] as String? ?? const Uuid().v4(),
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
    'documentDate': value.documentDate?.toIso8601String(),
    'templateId': value.templateId,
    'isPinned': value.isPinned,
    'createdAt': value.createdAt.toIso8601String(),
    'updatedAt': value.updatedAt.toIso8601String(),
  };

  LifeDocumentV2 _lifeDocumentFromJson(Map<String, dynamic> value) {
    final now = DateTime.now().toUtc();
    return LifeDocumentV2(
      id: value['id'] as String? ?? const Uuid().v4(),
      space: value['space'] as String? ?? LifeSpacesV2.cooking,
      title: value['title'] as String? ?? '未命名文档',
      markdown: value['markdown'] as String? ?? '',
      type: LifeDocumentTypeV2.values.firstWhere(
        (type) => type.name == value['type'],
        orElse: () => LifeDocumentTypeV2.note,
      ),
      documentDate: _optionalDate(value['documentDate']),
      templateId: value['templateId'] as String?,
      isPinned: value['isPinned'] == true,
      createdAt: _optionalDate(value['createdAt']) ?? now,
      updatedAt: _optionalDate(value['updatedAt']) ?? now,
    );
  }

  DateTime? _optionalDate(Object? value) =>
      value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;
}

class BackupImportReportV2 {
  const BackupImportReportV2({
    required this.importedEntries,
    required this.importedFestivals,
    this.importedLifeDocuments = 0,
  });

  final int importedEntries;
  final int importedFestivals;
  final int importedLifeDocuments;
}

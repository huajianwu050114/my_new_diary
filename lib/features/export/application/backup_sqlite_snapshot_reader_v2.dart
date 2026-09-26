import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../diary/data/local/diary_entry_mapper_v2.dart';
import '../../diary/domain/entities/diary_entry.dart';
import '../../festival/domain/festival_v2.dart';
import '../../life_guide/domain/life_fragment_revision_v2.dart';
import '../../life_guide/domain/life_fragment_v2.dart';
import '../../life_library/domain/life_document_v2.dart';
import '../../life_library/domain/life_space_v2.dart';
import '../../self_engine/domain/entities/diary_revision_v2.dart';

class BackupSqliteSnapshotV2 {
  const BackupSqliteSnapshotV2({
    required this.entries,
    required this.festivals,
    required this.lifeSpaces,
    required this.lifeDocuments,
    required this.lifeFragments,
    required this.lifeFragmentRevisions,
    required this.diaryRevisions,
  });

  final List<DiaryEntryV2> entries;
  final List<CustomFestivalV2> festivals;
  final List<LifeSpaceV2> lifeSpaces;
  final List<LifeDocumentV2> lifeDocuments;
  final List<LifeFragmentV2> lifeFragments;
  final List<LifeFragmentRevisionV2> lifeFragmentRevisions;
  final List<DiaryRevisionV2> diaryRevisions;
}

/// Reads every SQLite-backed item in a v2 backup inside one database
/// transaction. Writes queued while the snapshot is being read cannot create a
/// manifest assembled from different points in time.
class BackupSqliteSnapshotReaderV2 {
  BackupSqliteSnapshotReaderV2(
    this._database, {
    Future<void> Function()? afterDiaryRead,
  }) : _afterDiaryRead = afterDiaryRead;

  final Database _database;
  final Future<void> Function()? _afterDiaryRead;
  static const _diaryMapper = DiaryEntryMapperV2();

  Future<BackupSqliteSnapshotV2> read() {
    return _database.transaction((transaction) async {
      final entries = (await transaction.query(
        'diary_entries',
        orderBy: 'id ASC',
      )).map(_diaryMapper.fromRow).toList(growable: false);
      await _afterDiaryRead?.call();
      final festivals = (await transaction.query(
        'custom_festivals',
        orderBy: 'id ASC',
      )).map(_festivalFromRow).toList(growable: false);
      final spaces = (await transaction.query(
        'life_spaces',
        orderBy: 'id ASC',
      )).map(_spaceFromRow).toList(growable: false);
      final documents = (await transaction.query(
        'life_documents',
        orderBy: 'id ASC',
      )).map(_documentFromRow).toList(growable: false);
      final fragments = (await transaction.query(
        'life_fragments',
        orderBy: 'id ASC',
      )).map(_fragmentFromRow).toList(growable: false);
      final fragmentRevisions = (await transaction.query(
        'life_fragment_revisions',
        orderBy: 'fragment_id ASC, created_at ASC, id ASC',
      )).map(_fragmentRevisionFromRow).toList(growable: false);
      final diaryRevisions = (await transaction.query(
        'diary_revisions',
        orderBy: 'diary_id ASC, revision_no ASC',
      )).map(_diaryRevisionFromRow).toList(growable: false);
      return BackupSqliteSnapshotV2(
        entries: entries,
        festivals: festivals,
        lifeSpaces: spaces,
        lifeDocuments: documents,
        lifeFragments: fragments,
        lifeFragmentRevisions: fragmentRevisions,
        diaryRevisions: diaryRevisions,
      );
    });
  }

  CustomFestivalV2 _festivalFromRow(Map<String, Object?> row) =>
      CustomFestivalV2(
        id: row['id']! as String,
        name: row['name']! as String,
        month: row['month']! as int,
        day: row['day']! as int,
        createdAt: DateTime.parse(row['created_at']! as String),
      );

  LifeSpaceV2 _spaceFromRow(Map<String, Object?> row) => LifeSpaceV2(
    id: row['id']! as String,
    name: row['name']! as String,
    iconCodePoint: row['icon_code_point']! as int,
    colorValue: row['color_value']! as int,
    sortOrder: row['sort_order']! as int,
    isSystem: row['is_system'] == 1,
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
  );

  LifeDocumentV2 _documentFromRow(Map<String, Object?> row) => LifeDocumentV2(
    id: row['id']! as String,
    space: row['space']! as String,
    title: row['title']! as String,
    markdown: row['markdown']! as String,
    type: LifeDocumentTypeV2.values.byName(row['document_type']! as String),
    documentDate: _date(row['document_date']),
    templateId: row['template_id'] as String?,
    tags: _stringList(row['tags'], 'life_documents.tags'),
    isPinned: row['is_pinned'] == 1,
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
    deletedAt: _date(row['deleted_at']),
  );

  LifeFragmentV2 _fragmentFromRow(Map<String, Object?> row) => LifeFragmentV2(
    id: row['id']! as String,
    title: row['title']! as String,
    coreInsight: row['core_insight']! as String,
    context: row['context']! as String,
    evidence: row['evidence']! as String,
    futureUse: row['future_use']! as String,
    messageToFutureSelf: row['message_to_future_self']! as String,
    theme: row['theme']! as String,
    tags: _stringList(row['tags'], 'life_fragments.tags'),
    sourceDiaryIds: _stringList(
      row['source_diary_ids'],
      'life_fragments.source_diary_ids',
    ),
    isRope: row['is_rope'] == 1,
    status: LifeFragmentStatusV2.values.byName(row['status']! as String),
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
  );

  LifeFragmentRevisionV2 _fragmentRevisionFromRow(Map<String, Object?> row) {
    final decoded = jsonDecode(row['snapshot_json']! as String);
    if (decoded is! Map) {
      throw const FormatException('Invalid Life Guide revision snapshot.');
    }
    return LifeFragmentRevisionV2(
      id: row['id']! as String,
      fragmentId: row['fragment_id']! as String,
      snapshot: _fragmentFromRow(Map<String, Object?>.from(decoded)),
      createdAt: DateTime.parse(row['created_at']! as String),
    );
  }

  DiaryRevisionV2 _diaryRevisionFromRow(Map<String, Object?> row) =>
      DiaryRevisionV2(
        id: row['id']! as String,
        diaryId: row['diary_id']! as String,
        revisionNo: row['revision_no']! as int,
        body: row['body']! as String,
        contentDelta: row['content_delta'] as String?,
        sourceHash: row['source_hash']! as String,
        fingerprintVersion: row['fingerprint_version']! as int,
        entryDate: DateTime.parse(row['entry_date']! as String),
        mood: row['mood'] as String?,
        tags: _stringList(row['tags'], 'diary_revisions.tags'),
        latitude: (row['latitude'] as num?)?.toDouble(),
        longitude: (row['longitude'] as num?)?.toDouble(),
        address: row['address'] as String?,
        createdAt: DateTime.parse(row['created_at']! as String),
      );

  List<String> _stringList(Object? value, String field) {
    if (value is! String) throw FormatException('$field is not JSON text.');
    final decoded = jsonDecode(value);
    if (decoded is! List || decoded.any((item) => item is! String)) {
      throw FormatException('$field is not a string list.');
    }
    return List<String>.unmodifiable(decoded.cast<String>());
  }

  DateTime? _date(Object? value) =>
      value is String && value.isNotEmpty ? DateTime.parse(value) : null;
}

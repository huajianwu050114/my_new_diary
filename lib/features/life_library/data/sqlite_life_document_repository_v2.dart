import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../domain/life_document_repository_v2.dart';
import '../domain/life_document_v2.dart';

class SqliteLifeDocumentRepositoryV2 implements LifeDocumentRepositoryV2 {
  SqliteLifeDocumentRepositoryV2(this._database);

  static const tableName = 'life_documents';
  final Database _database;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<List<LifeDocumentV2>> watchDocuments({String? space}) async* {
    yield await _find(space);
    await for (final _ in _changes.stream) {
      yield await _find(space);
    }
  }

  Future<List<LifeDocumentV2>> _find(String? space) async {
    final rows = await _database.query(
      tableName,
      where: space == null
          ? 'deleted_at IS NULL'
          : 'deleted_at IS NULL AND space = ?',
      whereArgs: space == null ? null : [space],
      orderBy: 'is_pinned DESC, updated_at DESC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<LifeDocumentV2?> getById(String id) async {
    final rows = await _database.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  @override
  Future<void> save(LifeDocumentV2 document) async {
    await _database.insert(
      tableName,
      _toRow(document),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _changes.add(null);
  }

  @override
  Future<void> delete(String id) async {
    await _database.update(
      tableName,
      {'deleted_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    _changes.add(null);
  }

  Map<String, Object?> _toRow(LifeDocumentV2 value) => {
    'id': value.id,
    'space': value.space,
    'title': value.title,
    'markdown': value.markdown,
    'document_type': value.type.name,
    'document_date': value.documentDate?.toUtc().toIso8601String(),
    'template_id': value.templateId,
    'is_pinned': value.isPinned ? 1 : 0,
    'created_at': value.createdAt.toUtc().toIso8601String(),
    'updated_at': value.updatedAt.toUtc().toIso8601String(),
    'deleted_at': value.deletedAt?.toUtc().toIso8601String(),
  };

  LifeDocumentV2 _fromRow(Map<String, Object?> row) => LifeDocumentV2(
    id: row['id']! as String,
    space: row['space']! as String,
    title: row['title']! as String,
    markdown: row['markdown']! as String,
    type: LifeDocumentTypeV2.values.firstWhere(
      (value) => value.name == row['document_type'],
      orElse: () => LifeDocumentTypeV2.note,
    ),
    documentDate: _date(row['document_date']),
    templateId: row['template_id'] as String?,
    isPinned: row['is_pinned'] == 1,
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
    deletedAt: _date(row['deleted_at']),
  );

  DateTime? _date(Object? value) =>
      value is String && value.isNotEmpty ? DateTime.parse(value) : null;

  Future<void> dispose() => _changes.close();
}

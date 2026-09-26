import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/life_document_repository_v2.dart';
import '../domain/life_document_v2.dart';
import '../domain/life_space_v2.dart';

class SqliteLifeDocumentRepositoryV2 implements LifeDocumentRepositoryV2 {
  SqliteLifeDocumentRepositoryV2(this._database);

  static const tableName = 'life_documents';
  static const spacesTableName = 'life_spaces';
  final Database _database;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<List<LifeDocumentV2>> watchDocuments({String? space}) async* {
    yield await _find(space);
    await for (final _ in _changes.stream) {
      yield await _find(space);
    }
  }

  @override
  Future<List<LifeDocumentV2>> getAllDocuments({
    bool includeDeleted = false,
  }) async {
    final rows = await _database.query(
      tableName,
      where: includeDeleted ? null : 'deleted_at IS NULL',
      orderBy: 'is_pinned DESC, updated_at DESC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Stream<List<LifeSpaceV2>> watchSpaces() async* {
    yield await _findSpaces();
    await for (final _ in _changes.stream) {
      yield await _findSpaces();
    }
  }

  Future<List<LifeSpaceV2>> _findSpaces() async {
    final rows = await _database.query(
      spacesTableName,
      orderBy: 'is_system DESC, sort_order ASC, created_at ASC',
    );
    return rows.map(_spaceFromRow).toList(growable: false);
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
  Future<LifeSpaceV2?> getSpaceById(String id) async {
    final rows = await _database.query(
      spacesTableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _spaceFromRow(rows.single);
  }

  @override
  Future<void> save(LifeDocumentV2 document) async {
    await _ensureSpace(document.space);
    await _database.transaction((transaction) async {
      final changed = await transaction.update(
        tableName,
        _toRow(document),
        where: 'id = ?',
        whereArgs: [document.id],
      );
      if (changed == 0) await transaction.insert(tableName, _toRow(document));
    });
    _changes.add(null);
  }

  @override
  Future<void> saveSpace(LifeSpaceV2 space) async {
    await _database.transaction((transaction) async {
      final changed = await transaction.update(
        spacesTableName,
        _spaceToRow(space),
        where: 'id = ?',
        whereArgs: [space.id],
      );
      if (changed == 0) {
        await transaction.insert(spacesTableName, _spaceToRow(space));
      }
    });
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

  @override
  Future<void> deleteSpace(String id) async {
    if (id == LifeSpaceDefaultsV2.inboxId) return;
    await _database.transaction((transaction) async {
      await transaction.update(
        tableName,
        {'space': LifeSpaceDefaultsV2.inboxId},
        where: 'space = ?',
        whereArgs: [id],
      );
      await transaction.delete(
        spacesTableName,
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    _changes.add(null);
  }

  Future<void> _ensureSpace(String id) async {
    if (await getSpaceById(id) != null) return;
    final now = DateTime.now().toUtc();
    await _database.insert(
      spacesTableName,
      _spaceToRow(
        LifeSpaceV2(
          id: id,
          name: LifeSpaceDefaultsV2.legacyName(id),
          iconCodePoint: 0xe2c8,
          colorValue: 0xff607d8b,
          sortOrder: 999,
          createdAt: now,
          updatedAt: now,
        ),
      ),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Map<String, Object?> _toRow(LifeDocumentV2 value) => {
    'id': value.id,
    'space': value.space,
    'title': value.title,
    'markdown': value.markdown,
    'document_type': value.type.name,
    'document_date': value.documentDate?.toUtc().toIso8601String(),
    'template_id': value.templateId,
    'tags': jsonEncode(value.tags),
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
    tags: _decodeTags(row['tags']),
    isPinned: row['is_pinned'] == 1,
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
    deletedAt: _date(row['deleted_at']),
  );

  Map<String, Object?> _spaceToRow(LifeSpaceV2 value) => {
    'id': value.id,
    'name': value.name,
    'icon_code_point': value.iconCodePoint,
    'color_value': value.colorValue,
    'sort_order': value.sortOrder,
    'is_system': value.isSystem ? 1 : 0,
    'created_at': value.createdAt.toUtc().toIso8601String(),
    'updated_at': value.updatedAt.toUtc().toIso8601String(),
  };

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

  DateTime? _date(Object? value) =>
      value is String && value.isNotEmpty ? DateTime.parse(value) : null;

  List<String> _decodeTags(Object? value) {
    if (value is! String || value.isEmpty) return const [];
    final decoded = jsonDecode(value);
    return decoded is List
        ? decoded.whereType<String>().toList(growable: false)
        : const [];
  }

  Future<void> dispose() => _changes.close();
}

import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/life_fragment_repository_v2.dart';
import '../domain/life_fragment_revision_v2.dart';
import '../domain/life_fragment_v2.dart';

class SqliteLifeFragmentRepositoryV2 implements LifeFragmentRepositoryV2 {
  SqliteLifeFragmentRepositoryV2(this._database);

  static const tableName = 'life_fragments';

  final Database _database;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Future<void> delete(String id) async {
    await _database.delete(tableName, where: 'id = ?', whereArgs: [id]);
    _changes.add(null);
  }

  @override
  Future<LifeFragmentV2?> getById(String id) async {
    final rows = await _database.query(
      tableName,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  @override
  Future<void> save(LifeFragmentV2 fragment) async {
    await _database.insert(
      tableName,
      _toRow(fragment),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _changes.add(null);
  }

  @override
  Future<void> updateWithRevision(
    LifeFragmentV2 fragment, {
    required LifeFragmentV2 previous,
  }) async {
    final savedAt = DateTime.now().toUtc();
    await _database.transaction((transaction) async {
      await transaction.insert('life_fragment_revisions', {
        'id': '${previous.id}-${savedAt.microsecondsSinceEpoch}',
        'fragment_id': previous.id,
        'snapshot_json': jsonEncode(_toRow(previous)),
        'created_at': savedAt.toIso8601String(),
      });
      final changed = await transaction.update(
        tableName,
        _toRow(fragment),
        where: 'id = ?',
        whereArgs: [fragment.id],
      );
      if (changed == 0) {
        await transaction.insert(tableName, _toRow(fragment));
      }
    });
    _changes.add(null);
  }

  @override
  Future<List<LifeFragmentRevisionV2>> getRevisions(String fragmentId) async {
    final rows = await _database.query(
      'life_fragment_revisions',
      where: 'fragment_id = ?',
      whereArgs: [fragmentId],
      orderBy: 'created_at DESC',
    );
    return rows
        .map((row) {
          final decoded = jsonDecode(row['snapshot_json']! as String);
          return LifeFragmentRevisionV2(
            id: row['id']! as String,
            fragmentId: row['fragment_id']! as String,
            snapshot: _fromRow(Map<String, Object?>.from(decoded as Map)),
            createdAt: DateTime.parse(row['created_at']! as String),
          );
        })
        .toList(growable: false);
  }

  @override
  Stream<List<LifeFragmentV2>> watchFragments({
    LifeFragmentStatusV2? status,
    bool onlyRopes = false,
  }) async* {
    Future<List<LifeFragmentV2>> find() =>
        _find(status: status, onlyRopes: onlyRopes);
    yield await find();
    await for (final _ in _changes.stream) {
      yield await find();
    }
  }

  Future<List<LifeFragmentV2>> _find({
    LifeFragmentStatusV2? status,
    required bool onlyRopes,
  }) async {
    final clauses = <String>[];
    final arguments = <Object?>[];
    if (status != null) {
      clauses.add('status = ?');
      arguments.add(status.name);
    }
    if (onlyRopes) clauses.add('is_rope = 1');
    final rows = await _database.query(
      tableName,
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: arguments.isEmpty ? null : arguments,
      orderBy: 'is_rope DESC, updated_at DESC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Map<String, Object?> _toRow(LifeFragmentV2 fragment) => {
    'id': fragment.id,
    'title': fragment.title,
    'core_insight': fragment.coreInsight,
    'context': fragment.context,
    'evidence': fragment.evidence,
    'future_use': fragment.futureUse,
    'message_to_future_self': fragment.messageToFutureSelf,
    'theme': fragment.theme,
    'tags': jsonEncode(fragment.tags),
    'source_diary_ids': jsonEncode(fragment.sourceDiaryIds),
    'is_rope': fragment.isRope ? 1 : 0,
    'status': fragment.status.name,
    'created_at': fragment.createdAt.toUtc().toIso8601String(),
    'updated_at': fragment.updatedAt.toUtc().toIso8601String(),
  };

  LifeFragmentV2 _fromRow(Map<String, Object?> row) {
    return LifeFragmentV2(
      id: row['id']! as String,
      title: row['title']! as String,
      coreInsight: row['core_insight']! as String,
      context: row['context']! as String,
      evidence: row['evidence']! as String,
      futureUse: row['future_use']! as String,
      messageToFutureSelf: row['message_to_future_self']! as String,
      theme: _customTheme(row['theme']),
      tags: _stringList(row['tags']),
      sourceDiaryIds: _stringList(row['source_diary_ids']),
      isRope: row['is_rope'] == 1,
      status: LifeFragmentStatusV2.values.firstWhere(
        (status) => status.name == row['status'],
        orElse: () => LifeFragmentStatusV2.draft,
      ),
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
    );
  }

  List<String> _stringList(Object? value) {
    if (value is! String || value.isEmpty) return const [];
    try {
      final decoded = jsonDecode(value);
      return decoded is List
          ? List.unmodifiable(decoded.whereType<String>())
          : const [];
    } catch (_) {
      return const [];
    }
  }

  String _customTheme(Object? value) {
    if (value is! String) return '';
    // Values from the short-lived preset-theme version are treated as
    // unclassified. The user can name them later in their own words.
    const legacyPresets = {
      'identity',
      'uncertainty',
      'relationships',
      'choices',
      'coreValues',
      'helpfulWays',
      'reasonsToLive',
      'futureSelf',
    };
    return legacyPresets.contains(value) ? '' : value.trim();
  }

  Future<void> dispose() => _changes.close();
}

import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../domain/entities/diary_entry.dart';
import '../../domain/repositories/diary_repository_v2.dart';
import '../../../self_engine/data/local/self_engine_outbox_writer_v2.dart';
import 'diary_entry_mapper_v2.dart';

class SqliteDiaryRepositoryV2 implements DiaryRepositoryV2 {
  SqliteDiaryRepositoryV2(
    this._database, {
    DiaryEntryMapperV2 mapper = const DiaryEntryMapperV2(),
    SelfEngineOutboxWriterV2? selfEngineOutbox,
    void Function()? onSourceSaved,
  }) : _mapper = mapper,
       _selfEngineOutbox = selfEngineOutbox ?? SelfEngineOutboxWriterV2(),
       _onSourceSaved = onSourceSaved;

  static const _table = 'diary_entries';

  final Database _database;
  final DiaryEntryMapperV2 _mapper;
  final SelfEngineOutboxWriterV2 _selfEngineOutbox;
  final void Function()? _onSourceSaved;
  final _changes = StreamController<void>.broadcast();

  @override
  Future<DiaryEntryV2?> getById(String id) async {
    final rows = await _database.query(
      _table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _mapper.fromRow(rows.single);
  }

  @override
  Future<void> save(DiaryEntryV2 entry) async {
    await _database.transaction((transaction) async {
      final existingRows = await transaction.query(
        _table,
        where: 'id = ?',
        whereArgs: [entry.id],
        limit: 1,
      );
      if (existingRows.isNotEmpty) {
        // A database upgraded from v10 has no revision yet. Capture the old
        // source before applying the first edit so its evidence is not lost.
        await _selfEngineOutbox.recordSourceChange(
          transaction,
          _mapper.fromRow(existingRows.single),
        );
        await transaction.update(
          _table,
          _mapper.toRow(entry),
          where: 'id = ?',
          whereArgs: [entry.id],
        );
      } else {
        await transaction.insert(_table, _mapper.toRow(entry));
      }
      await _selfEngineOutbox.recordSourceChange(transaction, entry);
    });
    _changes.add(null);
    _onSourceSaved?.call();
  }

  @override
  Future<void> restoreFromBackup(DiaryEntryV2 entry) async {
    await _database.insert(_table, _mapper.toRow(entry));
    _changes.add(null);
  }

  @override
  Future<void> moveToTrash(String id, {required DateTime deletedAt}) async {
    await _database.update(
      _table,
      {
        'deleted_at': deletedAt.toUtc().toIso8601String(),
        'updated_at': deletedAt.toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _changes.add(null);
  }

  @override
  Future<void> restore(String id) async {
    await _database.update(
      _table,
      {'deleted_at': null},
      where: 'id = ?',
      whereArgs: [id],
    );
    _changes.add(null);
  }

  @override
  Future<void> setFavorite(String id, {required bool isFavorite}) async {
    await _database.update(
      _table,
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    _changes.add(null);
  }

  @override
  Future<void> deletePermanently(String id) async {
    await _database.delete(_table, where: 'id = ?', whereArgs: [id]);
    _changes.add(null);
  }

  @override
  Stream<List<DiaryEntryV2>> watchEntries({
    DiaryQuery query = const DiaryQuery(),
  }) async* {
    yield await _find(query);
    await for (final _ in _changes.stream) {
      yield await _find(query);
    }
  }

  Future<List<DiaryEntryV2>> _find(DiaryQuery query) async {
    final clauses = <String>[];
    final arguments = <Object?>[];

    if (query.onlyDeleted) {
      clauses.add('deleted_at IS NOT NULL');
    } else if (!query.includeDeleted) {
      clauses.add('deleted_at IS NULL');
    }
    if (query.onlyFavorites) {
      clauses.add('is_favorite = 1');
    }

    final searchText = query.text?.trim();
    if (searchText != null && searchText.isNotEmpty) {
      clauses.add('body LIKE ?');
      arguments.add('%$searchText%');
    }
    if (query.from != null) {
      clauses.add('entry_date >= ?');
      arguments.add(query.from!.toUtc().toIso8601String());
    }
    if (query.to != null) {
      clauses.add('entry_date < ?');
      arguments.add(query.to!.toUtc().toIso8601String());
    }

    final rows = await _database.query(
      _table,
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: arguments.isEmpty ? null : arguments,
      orderBy: 'entry_date DESC, created_at DESC',
    );

    final entries = rows.map(_mapper.fromRow);
    if (query.tags.isEmpty) {
      return entries.toList(growable: false);
    }
    return entries
        .where((entry) => query.tags.every(entry.tags.contains))
        .toList(growable: false);
  }

  Future<void> dispose() => _changes.close();
}

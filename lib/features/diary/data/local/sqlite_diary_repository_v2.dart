import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../domain/entities/diary_entry.dart';
import '../../domain/repositories/diary_repository_v2.dart';
import '../../../self_engine/data/local/self_engine_outbox_writer_v2.dart';
import '../../../self_engine/data/local/thread_link_work_v2.dart';
import '../../../self_engine/domain/entities/self_engine_job_v2.dart';
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
          origin: SelfEngineJobOriginV2.historical,
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
    await _database.transaction((transaction) async {
      final generation = await _generation(transaction);
      await ThreadLinkWorkV2.invalidateThreadsUsingDiary(
        transaction,
        diaryId: id,
        generation: generation,
        now: deletedAt,
      );
      await transaction.update(
        _table,
        {
          'deleted_at': deletedAt.toUtc().toIso8601String(),
          'updated_at': deletedAt.toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    _changes.add(null);
    _onSourceSaved?.call();
  }

  @override
  Future<void> restore(String id) async {
    await _database.transaction((transaction) async {
      await transaction.update(
        _table,
        {'deleted_at': null},
        where: 'id = ?',
        whereArgs: [id],
      );
      final generation = await _generation(transaction);
      final revisions = await transaction.rawQuery(
        '''
        SELECT r.id, j.origin
        FROM diary_revisions r
        JOIN self_engine_jobs j ON j.revision_id = r.id
        WHERE r.diary_id = ?
          AND r.revision_no = (
            SELECT MAX(latest.revision_no)
            FROM diary_revisions latest
            WHERE latest.diary_id = r.diary_id
          )
          AND EXISTS (
            SELECT 1 FROM memory_atoms a
            WHERE a.revision_id = r.id
              AND a.generation = ?
              AND a.superseded_at IS NULL
          )
        LIMIT 1
        ''',
        [id, generation],
      );
      if (revisions.isNotEmpty) {
        await ThreadLinkWorkV2.enqueueRevision(
          transaction,
          revisionId: revisions.single['id']! as String,
          origin: SelfEngineJobOriginV2.values.byName(
            revisions.single['origin']! as String,
          ),
          generation: generation,
          now: DateTime.now().toUtc(),
          reset: true,
        );
      }
    });
    _changes.add(null);
    _onSourceSaved?.call();
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
    await _database.transaction((transaction) async {
      final generation = await _generation(transaction);
      await ThreadLinkWorkV2.invalidateThreadsUsingDiary(
        transaction,
        diaryId: id,
        generation: generation,
        now: DateTime.now().toUtc(),
      );
      await transaction.delete(_table, where: 'id = ?', whereArgs: [id]);
      // Jobs are the durable references from historical revisions to a
      // revision-neutral computation. Delete private cached quotes as soon as
      // the last such reference disappears.
      await transaction.rawDelete('''
        DELETE FROM self_engine_computations
        WHERE NOT EXISTS (
          SELECT 1
          FROM self_engine_jobs j
          WHERE j.computation_id = self_engine_computations.id
        )
      ''');
    });
    _changes.add(null);
    _onSourceSaved?.call();
  }

  Future<int> _generation(DatabaseExecutor database) async {
    final rows = await database.query(
      'self_engine_state',
      columns: const ['generation'],
      where: 'id = 1',
      limit: 1,
    );
    if (rows.length != 1) {
      throw StateError('Self Engine generation state is missing.');
    }
    return rows.single['generation']! as int;
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

import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../domain/festival_repository_v2.dart';
import '../domain/festival_v2.dart';

class SqliteFestivalRepositoryV2 implements FestivalRepositoryV2 {
  SqliteFestivalRepositoryV2(this._database);

  final Database _database;
  final _changes = StreamController<void>.broadcast();

  @override
  Future<void> delete(String id) async {
    await _database.delete(
      'custom_festivals',
      where: 'id = ?',
      whereArgs: [id],
    );
    _changes.add(null);
  }

  @override
  Future<void> save(CustomFestivalV2 festival) async {
    await _database.insert('custom_festivals', {
      'id': festival.id,
      'name': festival.name,
      'month': festival.month,
      'day': festival.day,
      'created_at': festival.createdAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _changes.add(null);
  }

  @override
  Stream<List<CustomFestivalV2>> watchCustomFestivals() async* {
    yield await _findAll();
    await for (final _ in _changes.stream) {
      yield await _findAll();
    }
  }

  Future<List<CustomFestivalV2>> _findAll() async {
    final rows = await _database.query(
      'custom_festivals',
      orderBy: 'month, day, name',
    );
    return rows
        .map(
          (row) => CustomFestivalV2(
            id: row['id']! as String,
            name: row['name']! as String,
            month: row['month']! as int,
            day: row['day']! as int,
            createdAt: DateTime.parse(row['created_at']! as String),
          ),
        )
        .toList(growable: false);
  }

  Future<void> dispose() => _changes.close();
}

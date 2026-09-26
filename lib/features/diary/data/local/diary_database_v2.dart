import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../../self_engine/data/local/self_engine_schema_v2.dart';

class DiaryDatabaseV2 {
  DiaryDatabaseV2({
    DatabaseFactory? factory,
    Future<String> Function()? databasePath,
  }) : _databaseFactory = factory ?? databaseFactory,
       _databasePath = databasePath ?? _defaultDatabasePath;

  static const databaseName = 'diary_v2.db';
  static const schemaVersion = 13;

  final DatabaseFactory _databaseFactory;
  final Future<String> Function() _databasePath;

  Database? _database;

  Future<Database> open() async {
    final existing = _database;
    if (existing != null && existing.isOpen) {
      return existing;
    }

    _database = await _databaseFactory.openDatabase(
      await _databasePath(),
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
        onOpen: _validateSchema,
      ),
    );
    return _database!;
  }

  static Future<String> _defaultDatabasePath() async {
    return path.join(await getDatabasesPath(), databaseName);
  }

  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }

  static Future<void> _createSchema(Database database, int version) async {
    await database.execute('''
      CREATE TABLE diary_entries (
        id TEXT PRIMARY KEY NOT NULL,
        body TEXT NOT NULL,
        content_delta TEXT,
        entry_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        image_ids TEXT NOT NULL DEFAULT '[]',
        mood TEXT,
        tags TEXT NOT NULL DEFAULT '[]',
        latitude REAL,
        longitude REAL,
        address TEXT,
        ai_analyses TEXT NOT NULL DEFAULT '[]',
        is_favorite INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT
      )
    ''');
    await database.execute('''
      CREATE INDEX diary_entries_date_index
      ON diary_entries(entry_date DESC, created_at DESC)
    ''');
    await database.execute('''
      CREATE INDEX diary_entries_deleted_index
      ON diary_entries(deleted_at)
    ''');
    await _createCustomFestivalsTable(database);
    await _createLifeFragmentsTable(database);
    await _createLifeFragmentRevisionsTable(database);
    await _createLifeSpacesTable(database);
    await _createLifeDocumentsTable(database);
    await SelfEngineSchemaV2.createV11(database);
    await SelfEngineSchemaV2.createV12(database);
    await SelfEngineSchemaV2.createV13(database);
  }

  static Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await database.execute(
        'ALTER TABLE diary_entries '
        'ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 3) {
      await _createCustomFestivalsTable(database);
    }
    if (oldVersion < 4) {
      await _createLifeFragmentsTable(database);
    }
    if (oldVersion < 5) {
      await _createLifeFragmentRevisionsTable(database);
    }
    if (oldVersion < 6) {
      await _createLifeDocumentsTable(database);
    }
    if (oldVersion < 7) {
      await _createLifeSpacesTable(database);
      await _migrateLegacyLifeSpaces(database);
    }
    if (oldVersion >= 6 && oldVersion < 8) {
      await database.execute(
        "ALTER TABLE life_documents ADD COLUMN tags TEXT NOT NULL DEFAULT '[]'",
      );
    }
    if (oldVersion < 10) {
      await _ensureContentDeltaColumn(database);
    }
    if (oldVersion < 11) {
      await SelfEngineSchemaV2.createV11(database);
    }
    if (oldVersion < 12) {
      await SelfEngineSchemaV2.createV12(database);
    }
    if (oldVersion < 13) {
      await SelfEngineSchemaV2.createV13(database);
    }
  }

  static Future<void> _validateSchema(Database database) async {
    final diaryColumns = await database.rawQuery(
      'PRAGMA table_info(diary_entries)',
    );
    if (!diaryColumns.any((column) => column['name'] == 'content_delta')) {
      throw StateError('Schema drift: diary_entries.content_delta is missing.');
    }
    await SelfEngineSchemaV2.validateV13(database);
  }

  static Future<void> _ensureContentDeltaColumn(Database database) async {
    final columns = await database.rawQuery('PRAGMA table_info(diary_entries)');
    final hasContentDelta = columns.any(
      (column) => column['name'] == 'content_delta',
    );
    if (!hasContentDelta) {
      await database.execute(
        'ALTER TABLE diary_entries ADD COLUMN content_delta TEXT',
      );
    }
  }

  static Future<void> _createCustomFestivalsTable(Database database) async {
    await database.execute('''
      CREATE TABLE custom_festivals (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        month INTEGER NOT NULL,
        day INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createLifeFragmentsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS life_fragments (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        core_insight TEXT NOT NULL,
        context TEXT NOT NULL,
        evidence TEXT NOT NULL,
        future_use TEXT NOT NULL,
        message_to_future_self TEXT NOT NULL,
        theme TEXT NOT NULL,
        tags TEXT NOT NULL DEFAULT '[]',
        source_diary_ids TEXT NOT NULL DEFAULT '[]',
        is_rope INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'draft',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS life_fragments_updated_index
      ON life_fragments(is_rope DESC, updated_at DESC)
    ''');
  }

  static Future<void> _createLifeFragmentRevisionsTable(
    Database database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS life_fragment_revisions (
        id TEXT PRIMARY KEY NOT NULL,
        fragment_id TEXT NOT NULL,
        snapshot_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(fragment_id) REFERENCES life_fragments(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS life_fragment_revisions_fragment_index
      ON life_fragment_revisions(fragment_id, created_at DESC)
    ''');
  }

  static Future<void> _createLifeDocumentsTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS life_documents (
        id TEXT PRIMARY KEY NOT NULL,
        space TEXT NOT NULL,
        title TEXT NOT NULL,
        markdown TEXT NOT NULL,
        document_type TEXT NOT NULL DEFAULT 'note',
        document_date TEXT,
        template_id TEXT,
        tags TEXT NOT NULL DEFAULT '[]',
        is_pinned INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS life_documents_space_updated_index
      ON life_documents(space, is_pinned DESC, updated_at DESC)
    ''');
  }

  static Future<void> _createLifeSpacesTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS life_spaces (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL,
        icon_code_point INTEGER NOT NULL,
        color_value INTEGER NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_system INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    final now = DateTime.now().toUtc().toIso8601String();
    await database.insert('life_spaces', {
      'id': 'inbox',
      'name': '收件箱',
      'icon_code_point': 0xe156,
      'color_value': 0xff5c6bc0,
      'sort_order': -1,
      'is_system': 1,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> _migrateLegacyLifeSpaces(Database database) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final legacySpaces = await database.rawQuery('''
      SELECT DISTINCT space FROM life_documents
      WHERE space IS NOT NULL AND space <> '' AND space <> 'inbox'
    ''');
    for (final row in legacySpaces) {
      final id = row['space']! as String;
      await database.insert('life_spaces', {
        'id': id,
        'name': switch (id) {
          'cooking' => '厨艺',
          'habits' => '习惯与计划',
          _ => id,
        },
        'icon_code_point': 0xe2c8,
        'color_value': 0xff607d8b,
        'sort_order': 100,
        'is_system': 0,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }
}

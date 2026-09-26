import 'package:sqflite/sqflite.dart';

abstract final class SelfEngineSchemaV2 {
  static const pipelineVersion = 1;

  static Future<void> createV11(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE self_engine_state (
        id INTEGER PRIMARY KEY NOT NULL CHECK(id = 1),
        generation INTEGER NOT NULL CHECK(generation > 0)
      )
    ''');
    await database.insert('self_engine_state', {'id': 1, 'generation': 1});

    await database.execute('''
      CREATE TABLE diary_revisions (
        id TEXT PRIMARY KEY NOT NULL,
        diary_id TEXT NOT NULL,
        revision_no INTEGER NOT NULL CHECK(revision_no > 0),
        body TEXT NOT NULL,
        content_delta TEXT,
        source_hash TEXT NOT NULL,
        fingerprint_version INTEGER NOT NULL,
        entry_date TEXT NOT NULL,
        mood TEXT,
        tags TEXT NOT NULL DEFAULT '[]',
        latitude REAL,
        longitude REAL,
        address TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(diary_id) REFERENCES diary_entries(id) ON DELETE CASCADE,
        UNIQUE(diary_id, revision_no),
        UNIQUE(id, source_hash, fingerprint_version)
      )
    ''');
    await database.execute('''
      CREATE INDEX diary_revisions_diary_index
      ON diary_revisions(diary_id, revision_no DESC)
    ''');
    await database.execute('''
      CREATE INDEX diary_revisions_hash_index
      ON diary_revisions(source_hash, fingerprint_version)
    ''');

    await database.execute('''
      CREATE TABLE self_engine_computations (
        id TEXT PRIMARY KEY NOT NULL,
        source_hash TEXT NOT NULL,
        fingerprint_version INTEGER NOT NULL,
        pipeline_version INTEGER NOT NULL,
        job_type TEXT NOT NULL CHECK(job_type IN ('sourceChanged')),
        created_at TEXT NOT NULL,
        UNIQUE(source_hash, fingerprint_version, pipeline_version, job_type),
        UNIQUE(id, source_hash, fingerprint_version, pipeline_version, job_type)
      )
    ''');

    await database.execute('''
      CREATE TABLE self_engine_jobs (
        id TEXT PRIMARY KEY NOT NULL,
        revision_id TEXT NOT NULL,
        computation_id TEXT NOT NULL,
        source_hash TEXT NOT NULL,
        fingerprint_version INTEGER NOT NULL,
        job_type TEXT NOT NULL CHECK(job_type IN ('sourceChanged')),
        status TEXT NOT NULL CHECK(
          status IN ('pending', 'processing', 'completed', 'retryable', 'failed')
        ),
        attempt_count INTEGER NOT NULL DEFAULT 0 CHECK(attempt_count >= 0),
        pipeline_version INTEGER NOT NULL,
        generation INTEGER NOT NULL CHECK(generation > 0),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        next_retry_at TEXT,
        error TEXT,
        lease_id TEXT,
        lease_expires_at TEXT,
        CHECK(
          (status = 'processing' AND lease_id IS NOT NULL AND lease_expires_at IS NOT NULL)
          OR
          (status != 'processing' AND lease_id IS NULL AND lease_expires_at IS NULL)
        ),
        CHECK(status != 'retryable' OR next_retry_at IS NOT NULL),
        FOREIGN KEY(revision_id, source_hash, fingerprint_version)
          REFERENCES diary_revisions(id, source_hash, fingerprint_version)
          ON DELETE CASCADE,
        FOREIGN KEY(
          computation_id,
          source_hash,
          fingerprint_version,
          pipeline_version,
          job_type
        ) REFERENCES self_engine_computations(
          id,
          source_hash,
          fingerprint_version,
          pipeline_version,
          job_type
        ) ON DELETE RESTRICT,
        UNIQUE(revision_id, pipeline_version, job_type)
      )
    ''');
    await database.execute('''
      CREATE INDEX self_engine_jobs_ready_index
      ON self_engine_jobs(status, next_retry_at, lease_expires_at, created_at)
    ''');

    await database.execute('''
      CREATE TABLE memory_atoms (
        id TEXT PRIMARY KEY NOT NULL,
        revision_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        statement TEXT NOT NULL,
        source_quote TEXT NOT NULL,
        source_start INTEGER,
        source_end INTEGER,
        observed_at TEXT,
        scope TEXT NOT NULL DEFAULT 'unknown',
        pipeline_version INTEGER NOT NULL,
        generation INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        superseded_at TEXT,
        FOREIGN KEY(revision_id) REFERENCES diary_revisions(id) ON DELETE CASCADE,
        UNIQUE(id, generation)
      )
    ''');
    await database.execute('''
      CREATE INDEX memory_atoms_revision_index
      ON memory_atoms(revision_id, generation, created_at)
    ''');
    await database.execute('''
      CREATE TRIGGER memory_atoms_generation_insert_guard
      BEFORE INSERT ON memory_atoms
      WHEN NEW.generation != (
        SELECT generation FROM self_engine_state WHERE id = 1
      )
      BEGIN
        SELECT RAISE(ABORT, 'stale Self Engine generation');
      END
    ''');
    await database.execute('''
      CREATE TRIGGER memory_atoms_generation_update_guard
      BEFORE UPDATE ON memory_atoms
      WHEN OLD.generation != (
        SELECT generation FROM self_engine_state WHERE id = 1
      ) OR NEW.generation != (
        SELECT generation FROM self_engine_state WHERE id = 1
      )
      BEGIN
        SELECT RAISE(ABORT, 'stale Self Engine generation');
      END
    ''');

    await database.execute('''
      CREATE TABLE memory_threads (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'active',
        first_seen TEXT NOT NULL,
        last_seen TEXT NOT NULL,
        merged_into_id TEXT,
        pipeline_version INTEGER NOT NULL,
        generation INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(merged_into_id) REFERENCES memory_threads(id) ON DELETE SET NULL,
        UNIQUE(id, generation)
      )
    ''');
    await database.execute('''
      CREATE INDEX memory_threads_activity_index
      ON memory_threads(generation, status, last_seen DESC)
    ''');
    await database.execute('''
      CREATE TRIGGER memory_threads_generation_insert_guard
      BEFORE INSERT ON memory_threads
      WHEN NEW.generation != (
        SELECT generation FROM self_engine_state WHERE id = 1
      )
      BEGIN
        SELECT RAISE(ABORT, 'stale Self Engine generation');
      END
    ''');
    await database.execute('''
      CREATE TRIGGER memory_threads_generation_update_guard
      BEFORE UPDATE ON memory_threads
      WHEN OLD.generation != (
        SELECT generation FROM self_engine_state WHERE id = 1
      ) OR NEW.generation != (
        SELECT generation FROM self_engine_state WHERE id = 1
      )
      BEGIN
        SELECT RAISE(ABORT, 'stale Self Engine generation');
      END
    ''');

    await database.execute('''
      CREATE TABLE thread_memberships (
        thread_id TEXT NOT NULL,
        atom_id TEXT NOT NULL,
        relevance REAL NOT NULL DEFAULT 0,
        origin TEXT NOT NULL DEFAULT 'automatic',
        generation INTEGER NOT NULL CHECK(generation > 0),
        created_at TEXT NOT NULL,
        removed_at TEXT,
        PRIMARY KEY(thread_id, atom_id),
        FOREIGN KEY(thread_id, generation)
          REFERENCES memory_threads(id, generation) ON DELETE CASCADE,
        FOREIGN KEY(atom_id, generation)
          REFERENCES memory_atoms(id, generation) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE INDEX thread_memberships_atom_index
      ON thread_memberships(atom_id, removed_at)
    ''');
    await database.execute('''
      CREATE TRIGGER thread_memberships_generation_insert_guard
      BEFORE INSERT ON thread_memberships
      WHEN NEW.generation != (
        SELECT generation FROM self_engine_state WHERE id = 1
      )
      BEGIN
        SELECT RAISE(ABORT, 'stale Self Engine generation');
      END
    ''');
    await database.execute('''
      CREATE TRIGGER thread_memberships_generation_update_guard
      BEFORE UPDATE ON thread_memberships
      WHEN OLD.generation != (
        SELECT generation FROM self_engine_state WHERE id = 1
      ) OR NEW.generation != (
        SELECT generation FROM self_engine_state WHERE id = 1
      )
      BEGIN
        SELECT RAISE(ABORT, 'stale Self Engine generation');
      END
    ''');
  }

  static Future<void> validateV11(Database database) async {
    await _validateColumns(database, 'self_engine_state', const {
      'id',
      'generation',
    });
    await _validateColumns(database, 'diary_revisions', const {
      'id',
      'diary_id',
      'revision_no',
      'body',
      'content_delta',
      'source_hash',
      'fingerprint_version',
      'entry_date',
      'mood',
      'tags',
      'latitude',
      'longitude',
      'address',
      'created_at',
    });
    await _validateColumns(database, 'self_engine_computations', const {
      'id',
      'source_hash',
      'fingerprint_version',
      'pipeline_version',
      'job_type',
      'created_at',
    });
    await _validateColumns(database, 'self_engine_jobs', const {
      'id',
      'revision_id',
      'computation_id',
      'source_hash',
      'fingerprint_version',
      'job_type',
      'status',
      'attempt_count',
      'pipeline_version',
      'generation',
      'created_at',
      'updated_at',
      'next_retry_at',
      'error',
      'lease_id',
      'lease_expires_at',
    });
    await _validateColumns(database, 'memory_atoms', const {
      'id',
      'revision_id',
      'kind',
      'statement',
      'source_quote',
      'source_start',
      'source_end',
      'observed_at',
      'scope',
      'pipeline_version',
      'generation',
      'created_at',
      'superseded_at',
    });
    await _validateColumns(database, 'memory_threads', const {
      'id',
      'title',
      'description',
      'status',
      'first_seen',
      'last_seen',
      'merged_into_id',
      'pipeline_version',
      'generation',
      'created_at',
      'updated_at',
    });
    await _validateColumns(database, 'thread_memberships', const {
      'thread_id',
      'atom_id',
      'relevance',
      'origin',
      'generation',
      'created_at',
      'removed_at',
    });

    await _requireIndex(database, 'diary_revisions', const [
      'diary_id',
      'revision_no',
    ], unique: true);
    await _requireIndex(database, 'self_engine_computations', const [
      'source_hash',
      'fingerprint_version',
      'pipeline_version',
      'job_type',
    ], unique: true);
    await _requireIndex(database, 'self_engine_jobs', const [
      'revision_id',
      'pipeline_version',
      'job_type',
    ], unique: true);
    await _requireIndex(database, 'memory_atoms', const [
      'id',
      'generation',
    ], unique: true);
    await _requireIndex(database, 'memory_threads', const [
      'id',
      'generation',
    ], unique: true);
    await _requireForeignKey(
      database,
      'self_engine_jobs',
      parent: 'diary_revisions',
      from: const ['revision_id', 'source_hash', 'fingerprint_version'],
      to: const ['id', 'source_hash', 'fingerprint_version'],
      onDelete: 'CASCADE',
    );
    await _requireForeignKey(
      database,
      'self_engine_jobs',
      parent: 'self_engine_computations',
      from: const [
        'computation_id',
        'source_hash',
        'fingerprint_version',
        'pipeline_version',
        'job_type',
      ],
      to: const [
        'id',
        'source_hash',
        'fingerprint_version',
        'pipeline_version',
        'job_type',
      ],
      onDelete: 'RESTRICT',
    );
    await _requireForeignKey(
      database,
      'thread_memberships',
      parent: 'memory_atoms',
      from: const ['atom_id', 'generation'],
      to: const ['id', 'generation'],
      onDelete: 'CASCADE',
    );
    await _requireForeignKey(
      database,
      'thread_memberships',
      parent: 'memory_threads',
      from: const ['thread_id', 'generation'],
      to: const ['id', 'generation'],
      onDelete: 'CASCADE',
    );
    await _requireTriggers(database, const {
      'memory_atoms_generation_insert_guard',
      'memory_atoms_generation_update_guard',
      'memory_threads_generation_insert_guard',
      'memory_threads_generation_update_guard',
      'thread_memberships_generation_insert_guard',
      'thread_memberships_generation_update_guard',
    });
    final violations = await database.rawQuery('PRAGMA foreign_key_check');
    if (violations.isNotEmpty) {
      throw StateError('Database foreign-key validation failed: $violations');
    }
    final state = await database.query(
      'self_engine_state',
      where: 'id = 1',
      limit: 1,
    );
    if (state.length != 1 || (state.single['generation'] as int? ?? 0) < 1) {
      throw StateError('Self Engine generation state is missing or invalid.');
    }
  }

  static Future<void> _validateColumns(
    Database database,
    String table,
    Set<String> expected,
  ) async {
    final rows = await database.rawQuery('PRAGMA table_info($table)');
    final actual = rows.map((row) => row['name'] as String).toSet();
    if (actual.length != expected.length || !actual.containsAll(expected)) {
      throw StateError(
        'Schema drift in $table. Expected $expected, found $actual.',
      );
    }
  }

  static Future<void> _requireIndex(
    Database database,
    String table,
    List<String> columns, {
    required bool unique,
  }) async {
    final indexes = await database.rawQuery('PRAGMA index_list($table)');
    for (final index in indexes) {
      if ((index['unique'] == 1) != unique) continue;
      final name = index['name']! as String;
      final info = await database.rawQuery('PRAGMA index_info("$name")');
      final actual = info.map((row) => row['name'] as String).toList();
      if (_same(actual, columns)) return;
    }
    throw StateError(
      'Schema drift in $table: missing ${unique ? 'unique ' : ''}'
      'index on $columns.',
    );
  }

  static Future<void> _requireForeignKey(
    Database database,
    String table, {
    required String parent,
    required List<String> from,
    required List<String> to,
    required String onDelete,
  }) async {
    final rows = await database.rawQuery('PRAGMA foreign_key_list($table)');
    final ids = rows.map((row) => row['id'] as int).toSet();
    for (final id in ids) {
      final parts = rows.where((row) => row['id'] == id).toList()
        ..sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int));
      if (parts.isEmpty || parts.first['table'] != parent) continue;
      final actualFrom = parts.map((row) => row['from'] as String).toList();
      final actualTo = parts.map((row) => row['to'] as String).toList();
      if (_same(actualFrom, from) &&
          _same(actualTo, to) &&
          parts.every((row) => row['on_delete'] == onDelete)) {
        return;
      }
    }
    throw StateError('Schema drift in $table: missing foreign key $from.');
  }

  static Future<void> _requireTriggers(
    Database database,
    Set<String> expected,
  ) async {
    final rows = await database.query(
      'sqlite_master',
      columns: const ['name'],
      where: "type = 'trigger'",
    );
    final actual = rows.map((row) => row['name'] as String).toSet();
    if (!actual.containsAll(expected)) {
      throw StateError(
        'Schema drift: missing Self Engine generation triggers '
        '${expected.difference(actual)}.',
      );
    }
  }

  static bool _same(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

// 文件位置: lib/database_helper.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class DatabaseHelper {
  static const _databaseName = "MyDiary.db";
  // VVVV  1. 数据库版本号 +1 (从 4 变为 5) VVVV
  static const _databaseVersion = 6;
  static const table = 'diaries';

  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final dataPath = p.join(documentsDirectory.path, 'MyNewDiaryData');
    final dataDir = Directory(dataPath);
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    String path = p.join(dataPath, _databaseName);
    return await openDatabase(path,
        version: _databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade);
  }

  Future _onCreate(Database db, int version) async {
    // VVVV  2. 在 CREATE TABLE 语句中直接添加新字段 VVVV
    // 这对新安装的用户有效
    await db.execute('''
        CREATE TABLE $table (
          diaryId TEXT PRIMARY KEY,
          text TEXT NOT NULL,
          date TEXT NOT NULL,
          creationTime TEXT NOT NULL,
          lastModifiedTime TEXT,
          mood TEXT,
          address TEXT,
          latitude REAL,
          longitude REAL,
          imagePaths TEXT,
          tags TEXT,
          aiAnalyses TEXT,
          conversations TEXT,
          aiMetadata TEXT,
          isDeleted INTEGER NOT NULL DEFAULT 0,
          isPrivate INTEGER NOT NULL DEFAULT 0,
          isSelfHelp INTEGER NOT NULL DEFAULT 0
        )
        ''');

    await _createV2Tables(db);
    await _createV3Tables(db);
    await _createV4Tables(db);
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createV2Tables(db);
    }
    if (oldVersion < 3) {
      await _createV3Tables(db);
    }
    if (oldVersion < 4) {
      await _createV4Tables(db);
    }
    // VVVV  3. 添加版本 5 的升级逻辑 VVVV
    // 这对已安装旧版本的用户有效
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE $table ADD COLUMN isPrivate INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE $table ADD COLUMN isSelfHelp INTEGER NOT NULL DEFAULT 0');
    }
  }

  // --- 其他建表方法保持不变 ---
  Future<void> _createV2Tables(Database db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS daily_inspirations (
      date TEXT PRIMARY KEY,
      prompt TEXT NOT NULL,
      creationTime TEXT NOT NULL
    )
    ''');
    await db.execute('''
    CREATE TABLE IF NOT EXISTS weekly_letters (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      letterContent TEXT NOT NULL,
      generationDate TEXT NOT NULL
    )
    ''');
  }

  Future<void> _createV3Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_reflections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        reflectionType TEXT NOT NULL,
        reflectionContent TEXT NOT NULL,
        generationDate TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createV4Tables(Database db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS daily_check_ins (
      date TEXT PRIMARY KEY
    )
    ''');
  }
}
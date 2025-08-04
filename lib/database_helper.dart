// file: lib/database_helper.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static const _databaseName = "MyDiary.db";
  static const _databaseVersion = 1;

  static const table = 'diaries';

  static const columnId = 'diaryId';
  // ... 其他所有列名 ...

  // 单例模式
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  _initDatabase() async {
    String path = join(await getDatabasesPath(), _databaseName);
    return await openDatabase(path,
        version: _databaseVersion,
        onCreate: _onCreate);
  }

  // 创建数据库表的 SQL 语句
  Future _onCreate(Database db, int version) async {
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
            isDeleted INTEGER NOT NULL DEFAULT 0
          )
          ''');
  }
}
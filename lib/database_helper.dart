import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class DatabaseHelper {
  static const _databaseName = "MyDiary.db";
  // VVV 1. 数据库版本号 +1 VVV
  static const _databaseVersion = 4;

  static const table = 'diaries';
  // ... 其他列名 ...

  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  _initDatabase() async {
    // 1. 获取用户安全的“文档”目录
    final documentsDirectory = await getApplicationDocumentsDirectory();

    // 2. 在“文档”目录下创建一个专属的文件夹来存放数据
    final dataPath = p.join(documentsDirectory.path, 'MyNewDiaryData');
    final dataDir = Directory(dataPath);
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }

    // 3. 将数据库路径指向这个新位置
    String path = p.join(dataPath, _databaseName); // _databaseName is "MyDiary.db"

    print("--- 数据库路径 / Database Path ---");
    print(path); // 打印出实际路径方便您查找和确认
    print("---------------------------------");

    return await openDatabase(path,
        version: _databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade);
  }

  Future _onCreate(Database db, int version) async {
    // 1. 创建 diaries 表 (包含所有正确的列)
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
          isDeleted INTEGER NOT NULL DEFAULT 0
        )
        ''');

    // 2. 继续创建我们在版本2和版本3中新增的表
    await _createV2Tables(db);
    await _createV3Tables(db);
    await _createV4Tables(db);
  }

  Future<void> _createV4Tables(Database db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS daily_check_ins (
      date TEXT PRIMARY KEY -- 日期作为主键, 格式 'YYYY-MM-DD'
    )
  ''');
  }


  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createV2Tables(db);
    }
    // VVV 3. 添加版本3的升级逻辑 VVV
    if (oldVersion < 3) {
      await _createV3Tables(db);
    }
    if (oldVersion < 4) {
      await _createV4Tables(db);
    }
  }

  // VVV 4. 将版本2的建表逻辑单独存放 VVV
  Future<void> _createV2Tables(Database db) async {
    // 创建每日灵感表
    await db.execute('''
    CREATE TABLE IF NOT EXISTS daily_inspirations (
      date TEXT PRIMARY KEY, -- 日期作为主键, YYYY-MM-DD
      prompt TEXT NOT NULL,
      creationTime TEXT NOT NULL
    )
  ''');

    // 创建每周信件表
    await db.execute('''
    CREATE TABLE IF NOT EXISTS weekly_letters (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      letterContent TEXT NOT NULL,
      generationDate TEXT NOT NULL
    )
  ''');
  }

  // VVV 5. 新增版本3的建表逻辑 VVV
  Future<void> _createV3Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_reflections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        reflectionType TEXT NOT NULL, -- 'annual', 'monthly', 'hundred_day'
        reflectionContent TEXT NOT NULL,
        generationDate TEXT NOT NULL -- YYYY-MM-DD
      )
    ''');
  }
}
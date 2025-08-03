// file: lib/local_diary_repository.dart (Robust Final Version)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'diary_repository.dart';

class LocalDiaryRepository implements DiaryRepository {
  static Database? _database;
  final _streamController = StreamController<List<DiaryEntry>>.broadcast();
  final _trashStreamController = StreamController<List<DiaryEntry>>.broadcast();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'diary.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE diaries(
            diaryId TEXT PRIMARY KEY,
            authorId TEXT,
            text TEXT,
            date TEXT,
            creationTime TEXT,
            mood TEXT,
            latitude REAL,
            longitude REAL,
            address TEXT,
            isDeleted INTEGER DEFAULT 0,
            imagePaths TEXT,
            tags TEXT,
            aiAnalyses TEXT
          )
        ''');
      },
    );
  }

  Future<String> _getImagesDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final imagesPath = p.join(directory.path, 'diary_images');
    final imagesDir = Directory(imagesPath);
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesPath;
  }

  Future<void> _refreshEntries() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'diaries',
      where: 'isDeleted = ?',
      whereArgs: [0],
      orderBy: 'creationTime DESC',
    );
    // Use the now-safe fromMap constructor
    final entries = maps.map((map) => DiaryEntry.fromMap(map, map['diaryId'] as String)).toList();
    _streamController.add(entries);
  }

  Future<void> _refreshTrashEntries() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'diaries',
      where: 'isDeleted = ?',
      whereArgs: [1],
      orderBy: 'creationTime DESC',
    );
    final entries = maps.map((map) => DiaryEntry.fromMap(map, map['diaryId'] as String)).toList();
    _trashStreamController.add(entries);
  }

  @override
  Future<void> addEntry(DiaryEntry entry, List<File> localImageFiles) async {
    final db = await database;
    final imagesPath = await _getImagesDirectory();
    final List<String> savedImageFileNames = [];

    for (var file in localImageFiles) {
      final fileName = '${const Uuid().v4()}.jpg';
      final newPath = p.join(imagesPath, fileName);
      await file.copy(newPath);
      savedImageFileNames.add(fileName);
    }

    final newEntry = DiaryEntry(
      diaryId: const Uuid().v4(),
      authorId: 'local_user',
      text: entry.text,
      imagePaths: savedImageFileNames,
      date: entry.date,
      creationTime: entry.creationTime,
      mood: entry.mood,
      tags: entry.tags,
      latitude: entry.latitude,
      longitude: entry.longitude,
      address: entry.address,
    );

    final map = newEntry.toMap();
    // Convert bool to integer for SQLite
    map['isDeleted'] = newEntry.isDeleted ? 1 : 0;
    // JSON encode lists
    map['imagePaths'] = jsonEncode(newEntry.imagePaths);
    map['tags'] = jsonEncode(newEntry.tags);
    map['aiAnalyses'] = jsonEncode(newEntry.aiAnalyses);

    await db.insert('diaries', map, conflictAlgorithm: ConflictAlgorithm.replace);
    await _refreshEntries();
  }

  // --- Helper function to safely read and decode a JSON string from the database ---
  List<String> _decodeJsonString(dynamic jsonField) {
    if (jsonField is String && jsonField.isNotEmpty) {
      return List<String>.from(jsonDecode(jsonField));
    }
    return []; // Return an empty list if field is null or not a string
  }

  @override
  Future<void> deletePermanently(String diaryId) async {
    final db = await database;
    final imagesPath = await _getImagesDirectory();

    final List<Map<String, dynamic>> maps = await db.query('diaries', where: 'diaryId = ?', whereArgs: [diaryId], limit: 1);
    if (maps.isNotEmpty) {
      // Use the safe decoder
      final imageFileNames = _decodeJsonString(maps.first['imagePaths']);

      for (var fileName in imageFileNames) {
        final file = File(p.join(imagesPath, fileName));
        if (await file.exists()) {
          await file.delete();
        }
      }
    }

    await db.delete('diaries', where: 'diaryId = ?', whereArgs: [diaryId]);
    await _refreshTrashEntries();
  }

  @override
  Future<void> addAnalysisToEntry(DiaryEntry entry, String newAnalysis) async {
    final db = await database;

    final List<Map<String, dynamic>> maps = await db.query('diaries', where: 'diaryId = ?', whereArgs: [entry.diaryId], limit: 1);
    if (maps.isNotEmpty) {
      // Use the safe decoder
      final analysesList = _decodeJsonString(maps.first['aiAnalyses']);

      if (!analysesList.contains(newAnalysis)) {
        analysesList.add(newAnalysis);
      }

      await db.update('diaries', {'aiAnalyses': jsonEncode(analysesList)}, where: 'diaryId = ?', whereArgs: [entry.diaryId]);
      await _refreshEntries();
    }
  }

  // --- The rest of the methods are here for completeness ---

  @override
  Stream<List<DiaryEntry>> getAllEntriesSortedStream() {
    _refreshEntries();
    return _streamController.stream;
  }

  @override
  Future<void> updateEntry(DiaryEntry originalEntry, DiaryEntry updatedData, List<File> newImageFiles, List<String> remainingImagePaths) async {
    final db = await database;
    final imagesPath = await _getImagesDirectory();

    final deletedImageFiles = originalEntry.imagePaths.where((name) => !remainingImagePaths.contains(name));
    for (var fileName in deletedImageFiles) {
      final file = File(p.join(imagesPath, fileName));
      if (await file.exists()) {
        await file.delete();
      }
    }

    final List<String> newImageFileNames = [];
    for (var file in newImageFiles) {
      final fileName = '${const Uuid().v4()}.jpg';
      final newPath = p.join(imagesPath, fileName);
      await file.copy(newPath);
      newImageFileNames.add(fileName);
    }

    final finalImageNames = [...remainingImagePaths, ...newImageFileNames];

    final Map<String, dynamic> dataToUpdate = {
      'text': updatedData.text,
      'mood': updatedData.mood,
      'tags': jsonEncode(updatedData.tags),
      'imagePaths': jsonEncode(finalImageNames),
      'address': updatedData.address,
      'latitude': updatedData.latitude,
      'longitude': updatedData.longitude,
    };

    await db.update('diaries', dataToUpdate, where: 'diaryId = ?', whereArgs: [originalEntry.diaryId]);
    await _refreshEntries();
  }

  @override
  Future<void> moveEntryToTrash(String diaryId) async {
    final db = await database;
    await db.update('diaries', {'isDeleted': 1}, where: 'diaryId = ?', whereArgs: [diaryId]);
    await _refreshEntries();
    await _refreshTrashEntries();
  }

  @override
  Stream<List<DiaryEntry>> getTrashEntriesStream() {
    _refreshTrashEntries();
    return _trashStreamController.stream;
  }

  @override
  Future<void> restoreFromTrash(String diaryId) async {
    final db = await database;
    await db.update('diaries', {'isDeleted': 0}, where: 'diaryId = ?', whereArgs: [diaryId]);
    await _refreshEntries();
    await _refreshTrashEntries();
  }
}
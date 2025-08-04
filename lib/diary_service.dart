// file: lib/diary_service.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:my_new_diary/database_helper.dart';
import 'package:my_new_diary/diary_model.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:latlong2/latlong.dart' as latlong;
import 'package:intl/intl.dart';
import 'dart:convert';

class DiaryService extends ChangeNotifier {
  final dbHelper = DatabaseHelper.instance;

  // --- 核心 CRUD 操作 ---

  /// 添加一篇新日记到数据库
  Future<void> addEntry(DiaryEntry entry) async {
    final db = await dbHelper.database;
    // 确保每篇日记都有一个唯一的ID
    final entryWithId = entry.diaryId.isEmpty
        ? entry.copyWith(diaryId: const Uuid().v4())
        : entry;
    await db.insert(
      DatabaseHelper.table,
      entryWithId.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace, // 如果ID已存在，则替换
    );
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getRecentImagePathsWithEntries({int limit = 10}) async {
    final allEntries = await getAllEntriesSorted();
    final List<Map<String, dynamic>> imagePairs = [];

    for (final entry in allEntries) {
      for (final imagePath in entry.imagePaths) {
        imagePairs.add({
          'entry': entry,
          'imagePath': imagePath,
        });
        if (imagePairs.length >= limit) {
          return imagePairs;
        }
      }
    }
    return imagePairs;
  }

  Future<List<String>> getAllUniqueTags() async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      DatabaseHelper.table,
      columns: ['tags'],
      where: 'isDeleted = 0',
    );

    final Set<String> uniqueTags = {};
    for (var map in maps) {
      final tagsList = (jsonDecode(map['tags']) as List<dynamic>).cast<String>();
      uniqueTags.addAll(tagsList);
    }

    final sortedTags = uniqueTags.toList()..sort();
    return sortedTags;
  }


  Future<List<DiaryEntry>> searchEntries({
    String keyword = '',
    DateTimeRange? dateRange,
    String? mood,
    Set<String> selectedTags = const {},
  }) async {
    final db = await dbHelper.database;

    // 动态构建 SQL 查询语句
    List<String> whereClauses = ['isDeleted = ?'];
    List<dynamic> whereArgs = [0];

    if (keyword.isNotEmpty) {
      whereClauses.add('text LIKE ?');
      whereArgs.add('%$keyword%');
    }
    if (dateRange != null) {
      whereClauses.add('date BETWEEN ? AND ?');
      whereArgs.add(dateRange.start.toIso8601String());
      // 结束日期需要包含当天，所以我们取第二天的开始
      whereArgs.add(dateRange.end.add(const Duration(days: 1)).toIso8601String());
    }
    if (mood != null) {
      whereClauses.add('mood = ?');
      whereArgs.add(mood);
    }
    for (String tag in selectedTags) {
      whereClauses.add("tags LIKE ?");
      whereArgs.add('%"$tag"%'); // 在JSON字符串中模糊匹配标签
    }

    final String whereSql = whereClauses.join(' AND ');

    final maps = await db.query(
      DatabaseHelper.table,
      where: whereSql,
      whereArgs: whereArgs,
      orderBy: 'creationTime DESC',
    );

    return maps.map((map) => DiaryEntry.fromMap(map)).toList();
  }

  // file: lib/diary_service.dart -> inside DiaryService class

  Future<List<List<DiaryEntry>>> getGroupedEntriesByLocation({
    double distanceThreshold = 500,
  }) async {
    final db = await dbHelper.database;
    // 1. 先从数据库查出所有带位置的日记
    final maps = await db.query(
      DatabaseHelper.table,
      where: 'latitude IS NOT NULL AND longitude IS NOT NULL AND isDeleted = ?',
      whereArgs: [0],
    );
    final entriesWithLocation = maps.map((map) => DiaryEntry.fromMap(map)).toList();

    // 2. 在内存中进行地理位置聚类（这部分逻辑不变）
    if (entriesWithLocation.isEmpty) {
      return [];
    }
    final List<List<DiaryEntry>> clusteredEntries = [];
    final distance = const latlong.Distance(); // 需要确保 latlong2 的 import 存在

    for (var entry in entriesWithLocation) {
      bool foundCluster = false;
      final entryLocation = latlong.LatLng(entry.latitude!, entry.longitude!);
      for (var cluster in clusteredEntries) {
        final clusterCenter = latlong.LatLng(cluster.first.latitude!, cluster.first.longitude!);
        final double meters = distance(entryLocation, clusterCenter);
        if (meters <= distanceThreshold) {
          cluster.add(entry);
          foundCluster = true;
          break;
        }
      }
      if (!foundCluster) {
        clusteredEntries.add([entry]);
      }
    }
    clusteredEntries.sort((a, b) => b.length.compareTo(a.length));
    return clusteredEntries;
  }

  // file: lib/diary_service.dart -> inside DiaryService class
// 需要 'package:intl/intl.dart' for DateFormat

  Future<List<DiaryEntry>> getRecentEntriesWithImages({int limit = 5}) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      DatabaseHelper.table,
      where: "imagePaths != '[]' AND isDeleted = ?", // '[]' 是空列表的JSON字符串
      whereArgs: [0],
      orderBy: 'creationTime DESC',
      limit: limit,
    );
    return maps.map((map) => DiaryEntry.fromMap(map)).toList();
  }

  // file: lib/diary_service.dart -> inside DiaryService class

  Future<List<DiaryEntry>> getOnThisDayEntries() async {
    final db = await dbHelper.database;
    final now = DateTime.now();
    // 格式化日期为 'MM-DD'
    final monthDay = DateFormat('MM-dd').format(now);
    final currentYear = now.year.toString();

    // 使用 SQLite 的 strftime 函数来匹配月和日
    final maps = await db.query(
      DatabaseHelper.table,
      where: "strftime('%m-%d', date) = ? AND strftime('%Y', date) != ? AND isDeleted = ?",
      whereArgs: [monthDay, currentYear, 0],
      orderBy: 'date ASC',
    );
    return maps.map((map) => DiaryEntry.fromMap(map)).toList();
  }

  // file: lib/diary_service.dart -> inside DiaryService class

  Future<String> getDebugInfo() async {
    final buffer = StringBuffer();
    final now = DateTime.now();
    buffer.writeln('--- 调试信息 (数据库模式) ---');
    buffer.writeln('当前时间: $now');

    // 直接复用已有的数据库查询方法
    final allEntries = await getAllEntriesSorted();
    buffer.writeln('共找到 ${allEntries.length} 篇日记:');
    buffer.writeln('--------------------');

    for (var entry in allEntries) {
      buffer.writeln('ID: ${entry.diaryId}');
      buffer.writeln('所属日期 (date): ${entry.date.toIso8601String()}');
      buffer.writeln('创建时间 (creationTime): ${entry.creationTime.toIso8601String()}');
      buffer.writeln('---');
    }
    return buffer.toString();
  }

  /// 更新一篇现有日记
  Future<void> updateEntry(DiaryEntry entry) async {
    final db = await dbHelper.database;
    // 自动更新“最后修改时间”
    final entryWithTimestamp = entry.copyWith(lastModifiedTime: DateTime.now());
    await db.update(
      DatabaseHelper.table,
      entryWithTimestamp.toMap(),
      where: 'diaryId = ?',
      whereArgs: [entry.diaryId],
    );
    notifyListeners();
  }

  /// 根据ID获取一篇日记
  Future<DiaryEntry?> getEntryById(String id) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      DatabaseHelper.table,
      where: 'diaryId = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return DiaryEntry.fromMap(maps.first);
    }
    return null;
  }

  // --- 列表查询 ---

  /// 获取所有未删除的日记，按时间倒序排列
  Future<List<DiaryEntry>> getAllEntriesSorted() async {
    final db = await dbHelper.database;
    final maps = await db.query(
      DatabaseHelper.table,
      where: 'isDeleted = ?',
      whereArgs: [0],
      orderBy: 'creationTime DESC',
    );
    return maps.map((map) => DiaryEntry.fromMap(map)).toList();
  }

  /// 获取指定某一天的所有日记
  Future<List<DiaryEntry>> getEntriesForDay(DateTime day) async {
    final db = await dbHelper.database;
    // 格式化日期为 YYYY-MM-DD 格式，用于模糊查询
    final dayString = day.toIso8601String().substring(0, 10);
    final maps = await db.query(
      DatabaseHelper.table,
      where: 'date LIKE ? AND isDeleted = ?',
      whereArgs: ['$dayString%', 0],
      orderBy: 'creationTime DESC',
    );
    return maps.map((map) => DiaryEntry.fromMap(map)).toList();
  }

  // --- 回收站功能 ---

  Future<void> moveEntryToTrash(String diaryId) async {
    final db = await dbHelper.database;
    await db.update(
      DatabaseHelper.table,
      {'isDeleted': 1}, // 标记为已删除
      where: 'diaryId = ?',
      whereArgs: [diaryId],
    );
    notifyListeners();
  }

  Future<void> restoreFromTrash(String diaryId) async {
    final db = await dbHelper.database;
    await db.update(
      DatabaseHelper.table,
      {'isDeleted': 0}, // 标记为未删除
      where: 'diaryId = ?',
      whereArgs: [diaryId],
    );
    notifyListeners();
  }

  Future<List<DiaryEntry>> getTrashEntries() async {
    final db = await dbHelper.database;
    final maps = await db.query(
      DatabaseHelper.table,
      where: 'isDeleted = ?',
      whereArgs: [1],
      orderBy: 'creationTime DESC',
    );
    return maps.map((map) => DiaryEntry.fromMap(map)).toList();
  }

  Future<void> deletePermanently(String diaryId) async {
    final db = await dbHelper.database;
    await db.delete(
      DatabaseHelper.table,
      where: 'diaryId = ?',
      whereArgs: [diaryId],
    );
    notifyListeners();
  }

  // --- AI 相关功能 ---

  Future<void> saveConversationAsAnalysis(String diaryId, String conversationText) async {
    final entry = await getEntryById(diaryId);
    if (entry != null) {
      final newAnalyses = List<String>.from(entry.aiAnalyses)..insert(0, conversationText);
      final updatedEntry = entry.copyWith(aiAnalyses: newAnalyses);
      await updateEntry(updatedEntry); // 复用 updateEntry 逻辑
    }
  }

  // --- 图片文件操作 (这部分逻辑与数据库无关，保持不变) ---

  Future<Directory> get _imagesDir async {
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'images'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> saveImageFromBytes(Uint8List bytes) async {
    final imagesDir = await _imagesDir;
    final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = File(p.join(imagesDir.path, fileName));
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
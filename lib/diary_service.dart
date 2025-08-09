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
import 'gemini_service_local.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class DiaryService extends ChangeNotifier {
  final dbHelper = DatabaseHelper.instance;

  // --- 核心 CRUD 操作 ---

  Future<List<DiaryEntry>> getMonthlyAnniversaryEntries() async {
    final db = await dbHelper.database;
    final now = DateTime.now();
    // 格式化日期为 'DD'，只匹配“日”
    final dayOfMonth = DateFormat('dd').format(now);

    // 使用 SQLite 的 strftime 函数来匹配“日”，但不匹配当前年月
    final maps = await db.query(
      DatabaseHelper.table,
      // 查询条件：日匹配，但年月不完全匹配，且未被删除
      where: "strftime('%d', date) = ? AND strftime('%Y-%m', date) != ? AND isDeleted = ?",
      whereArgs: [dayOfMonth, DateFormat('yyyy-MM').format(now), 0],
      orderBy: 'date DESC', // 按日期倒序，让最近的月份排在前面
    );
    return maps.map((map) => DiaryEntry.fromMap(map)).toList();
  }

  Future<List<DiaryEntry>> getHundredDayAnniversaries() async {
    final db = await dbHelper.database;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day); // 确保只比较日期，忽略时间

    final List<DiaryEntry> foundEntries = [];

    // 我们可以查找过去多个百日纪念，例如100天, 200天, 300天...
    // 这里我们先查找到1000天前，您可以根据需要调整
    for (int i = 1; i <= 10; i++) {
      final daysAgo = i * 100;
      final targetDate = today.subtract(Duration(days: daysAgo));
      final targetDateString = targetDate.toIso8601String().substring(0, 10);

      // 查询数据库中是否有正好在那一天写的日记
      final maps = await db.query(
        DatabaseHelper.table,
        where: "date LIKE ? AND isDeleted = ?",
        whereArgs: ['$targetDateString%', 0],
      );

      if (maps.isNotEmpty) {
        // 如果找到了，将那天的所有日记都添加进来
        foundEntries.addAll(maps.map((map) => DiaryEntry.fromMap(map)));
      }
    }

    return foundEntries;
  }

  Future<List<DiaryEntry>> getEntriesForDateRange(DateTimeRange dateRange) async {
    // This method simply uses your existing search functionality
    return await searchEntries(dateRange: dateRange);
  }

  Future<void> addCheckIn(DateTime date) async {
    final db = await dbHelper.database;
    final dateString = DateFormat('yyyy-MM-dd').format(date);
    // Insert the date into the 'daily_check_ins' table.
    // If a record for that date already exists, it will be ignored.
    await db.insert(
      'daily_check_ins',
      {'date': dateString},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    // Notify listeners (like the calendar) that data has changed.
    notifyListeners();
  }

  Future<void> saveDailyInspiration(DateTime date, String prompt) async {
    final db = await dbHelper.database;
    final dateString = DateFormat('yyyy-MM-dd').format(date);
    await db.insert(
      'daily_inspirations',
      {
        'date': dateString,
        'prompt': prompt,
        'creationTime': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace, // 如果当天已有，则覆盖
    );
    notifyListeners(); // 通知UI刷新
  }

  Future<String?> getInspirationForDay(DateTime day) async {
    final db = await dbHelper.database;
    final dateString = DateFormat('yyyy-MM-dd').format(day);
    final maps = await db.query(
      'daily_inspirations',
      where: 'date = ?',
      whereArgs: [dateString],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return maps.first['prompt'] as String?;
    }
    return null;
  }

  // In lib/diary_service.dart -> inside DiaryService class

// VVV 用这个全新的、完全由AI驱动的版本替换旧方法 VVV
  Future<Map<String, dynamic>> generatePersonalizedPrompt({required String modelName}) async {
    final geminiService = GeminiServiceLocal();
    final daysSinceLast = await getDaysSinceLastEntry();

    String prompt;
    String promptType;
    bool requiresJsonResponse = false;

    if (daysSinceLast >= 999) {
      promptType = 'welcome'; // 改为 welcome 类型
      prompt = """
    你是一个非常友善和热情的“日记小精灵”。我是你的新朋友，第一次打开这个日记本。
    请为我生成一句充满欢迎意味、能鼓励我开始写第一篇日记的、简短而独特的话。
    让它听起来像一个真诚的邀请。只返回邀请内容本身，不要有额外文字。
    """;
    } else if (daysSinceLast > 2) {
      promptType = 'check_in';
      prompt = """
    你是一个温暖、充满同理心的“日记小精灵”，也是我的朋友。
    我已经 $daysSinceLast 天没有写日记了。请为我生成一句简短、温柔的关心问候。
    严格规则：
    1. 直接以朋友的口吻对我说话。
    2. 不要催促我写日记，只需表达关心和想念。
    3. 保持在1-2句话之内。
    4. 只返回关心的内容本身，不要有任何额外文字。
    """;
    } else {
      // VVVV 核心修改在这里 VVVV
      promptType = 'inspiration';
      requiresJsonResponse = true; // 标记这个请求需要解析JSON
      final recentEntries = await getRecentEntriesWithImages(limit: 5);
      final buffer = StringBuffer();
      buffer.writeln("这是我最近几天的日记摘要：\n");
      for (final entry in recentEntries) {
        buffer.writeln("- 日期: ${DateFormat('yyyy-MM-dd').format(entry.date)}, 内容: ${entry.text.substring(0, (entry.text.length > 100) ? 100 : entry.text.length)}...");
      }

      prompt = """
    你是一位富有创意的写作伙伴。根据我最近的日记，为我生成一个写作灵感。
    请严格按照以下JSON格式返回，不要有任何额外的解释或修饰:
    {
      "question": "<这里是一个与我日记相关、能激发深度思考的开放式问题>",
      "sampleAnswer": "<这里是你模仿我的口吻，对上面这个问题写的一段简短、充满创意和情感的示例回答，大约50-80字>"
    }

    我的近期日记摘要如下：
    ${buffer.toString()}
    """;
    }

    try {
      final (responseText, _) = await geminiService.generateResponse(
        [Content.text(prompt)],
        modelName: modelName,
      );

      if (responseText == null || responseText.isEmpty) {
        throw Exception('AI did not return a response.');
      }

      if (requiresJsonResponse) {
        // 如果需要JSON，就解析它
        final jsonResponse = jsonDecode(responseText);
        return {
          'type': promptType,
          'question': jsonResponse['question'],
          'sampleAnswer': jsonResponse['sampleAnswer'],
        };
      } else {
        // 否则，按旧方式返回
        return {'type': promptType, 'text': responseText.replaceAll('"', '').trim()};
      }
    } catch (e) {
      print("生成AI提示失败: $e");
      // 返回一个安全的、用户友好的错误信息
      if (requiresJsonResponse) {
        return {
          'type': promptType,
          'question': '哎呀，连接时出了点小问题，稍后再试试吧！',
          'sampleAnswer': '我的思绪也暂时卡住了...',
        };
      } else {
        return {'type': 'error', 'text': '哎呀，连接时出了点小问题，稍后再试试吧！'};
      }
    }
  }

  /// 2. 获取指定月份的所有签到日期 (用于日历标记)
  Future<Set<String>> getCheckInsForMonth(DateTime month) async {
    final db = await dbHelper.database;
    final monthString = DateFormat('yyyy-MM').format(month);
    final maps = await db.query(
      'daily_check_ins',
      where: "strftime('%Y-%m', date) = ?",
      whereArgs: [monthString],
    );
    return maps.map((map) => map['date'] as String).toSet();
  }

  /// 3. 计算当前连续签到天数 (用于激励)
  Future<int> getConsecutiveCheckInDays() async {
    final db = await dbHelper.database;
    var consecutiveDays = 0;
    var currentDate = DateTime.now();

    // 检查今天是否签到
    var dateString = DateFormat('yyyy-MM-dd').format(currentDate);
    var maps = await db.query('daily_check_ins', where: 'date = ?', whereArgs: [dateString]);

    if (maps.isNotEmpty) {
      consecutiveDays++;
      currentDate = currentDate.subtract(const Duration(days: 1));
    }

    // 从昨天开始循环检查
    while (true) {
      dateString = DateFormat('yyyy-MM-dd').format(currentDate);
      maps = await db.query('daily_check_ins', where: 'date = ?', whereArgs: [dateString]);

      if (maps.isNotEmpty) {
        consecutiveDays++;
        currentDate = currentDate.subtract(const Duration(days: 1));
      } else {
        break; // 一旦中断就停止计数
      }
    }

    return consecutiveDays;
  }

  /// 添加一篇新日记到数据库
  Future<DiaryEntry> addEntry(DiaryEntry entry) async { // VVV 1. 修改返回类型 VVV
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
    return entryWithId; // VVV 2. 返回带有ID的日记对象 VVV
  }


  Future<void> saveAiReflection(String type, String content) async {
    final db = await dbHelper.database;
    final todayString = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await db.insert(
      'ai_reflections',
      {
        'reflectionType': type,
        'reflectionContent': content,
        'generationDate': todayString,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getTodaysReflection(String type) async {
    final db = await dbHelper.database;
    final todayString = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final maps = await db.query(
      'ai_reflections',
      where: 'reflectionType = ? AND generationDate = ?',
      whereArgs: [type, todayString],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return maps.first['reflectionContent'] as String?;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getAllAiReflections() async {
    final db = await dbHelper.database;
    return await db.query('ai_reflections', orderBy: 'generationDate DESC');
  }

  Future<void> saveWeeklyLetter(String letterContent) async {
    print("--- DEBUG: Attempting to save weekly letter... ---");
    try {
      final db = await dbHelper.database;
      final id = await db.insert('weekly_letters', {
        'letterContent': letterContent,
        'generationDate': DateTime.now().toIso8601String(),
      });
      print("--- DEBUG: Weekly letter saved successfully to database with ID: $id. ---");
      notifyListeners();
    } catch (e) {
      // 如果这里有任何错误，我们就能在控制台看到
      print("--- DEBUG: FAILED to save weekly letter. Error: $e ---");
    }
  }

  Future<List<Map<String, dynamic>>> getAllWeeklyLetters() async {
    final db = await dbHelper.database;
    return await db.query('weekly_letters', orderBy: 'generationDate DESC');
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
      orderBy: 'date DESC, creationTime DESC',
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
    print("--- DEBUG: Attempting to get recent entries for AI prompt... ---");
    try {
      final db = await dbHelper.database;
      final maps = await db.query(
        DatabaseHelper.table,
        where: "imagePaths != '[]' AND isDeleted = ?",
        whereArgs: [0],
        orderBy: 'date DESC, creationTime DESC',
        limit: limit,
      );
      print("--- DEBUG: Successfully queried recent entries. Found ${maps.length} items. ---");
      return maps.map((map) => DiaryEntry.fromMap(map)).toList();
    } catch (e) {
      print("--- DEBUG: FAILED to get recent entries. Error: $e ---");
      // 发生错误时返回一个空列表，避免整个流程卡死
      return [];
    }
  }

  Future<int> getDaysSinceLastEntry() async {
    final db = await dbHelper.database;
    final maps = await db.query(
      DatabaseHelper.table,
      where: 'isDeleted = ?',
      whereArgs: [0],
      orderBy: 'date DESC', // 按日记日期排序
      limit: 1, // 只取最新的一篇
    );

    if (maps.isEmpty) {
      return 999; // 如果一篇日记都没有，返回一个很大的数
    }

    final lastEntryDate = DateTime.parse(maps.first['date'] as String);
    final today = DateTime.now();
    // 只比较日期，忽略时间
    final lastDateOnly = DateTime(lastEntryDate.year, lastEntryDate.month, lastEntryDate.day);
    final todayOnly = DateTime(today.year, today.month, today.day);

    return todayOnly.difference(lastDateOnly).inDays;
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
      orderBy: 'date DESC, creationTime DESC',
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
      orderBy: 'date DESC, creationTime DESC',
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
      orderBy: 'date DESC, creationTime DESC',
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

  Future<void> deleteWeeklyLetter(int id) async {
    final db = await dbHelper.database;
    await db.delete(
      'weekly_letters',
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyListeners(); // 通知UI刷新
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
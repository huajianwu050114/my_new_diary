// file: libs/diary_service.dart

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
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      where: "strftime('%d', date) = ? AND strftime('%Y-%m', date) != ? AND isDeleted = 0 AND isPrivate = 0",
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
        where: "date LIKE ? AND isDeleted = 0 AND isPrivate = 0",
        whereArgs: ['$targetDateString%', 0],
      );

      if (maps.isNotEmpty) {
        // 如果找到了，将那天的所有日记都添加进来
        foundEntries.addAll(maps.map((map) => DiaryEntry.fromMap(map)));
      }
    }

    return foundEntries;
  }

  // 文件位置: libs/diary_service.dart -> DiaryService class

  /// 检查用户最近是否情绪低落
  /// @param days: 检查最近几天的日记，默认为7天
  /// @param threshold: 至少需要几篇日记才进行判断，默认为2篇
  /// @return: 如果负面情绪日记超过一半，返回 true
  Future<bool> isFeelingDownRecently({int days = 7, int threshold = 2}) async {
    final db = await dbHelper.database;
    final recentDays = DateTime.now().subtract(Duration(days: days));

    final maps = await db.query(
      DatabaseHelper.table,
      where: 'date >= ? AND isDeleted = 0 AND isPrivate = 0',
      whereArgs: [recentDays.toIso8601String()],
    );

    final recentEntries = maps.map((map) => DiaryEntry.fromMap(map)).toList();

    if (recentEntries.length < threshold) {
      return false; // 日记太少，不作判断
    }

    // 定义负面情绪代码
    const negativeMoods = {'5', '6', '7', '8', '0'}; // 伤心, 很伤心, 崩溃, 生病
    int negativeCount = 0;

    for (final entry in recentEntries) {
      if (entry.mood != null && negativeMoods.contains(entry.mood)) {
        negativeCount++;
      }
    }

    // 如果负面情绪日记数量超过总数的一半
    return negativeCount > (recentEntries.length / 2);
  }

  /// 随机获取指定数量的开心日记
  Future<List<DiaryEntry>> getHappyEntries({int limit = 10}) async {
    final db = await dbHelper.database;
    const happyMoods = ['1', '2', '3']; // 特别开心, 很开心, 有点开心

    final maps = await db.query(
      DatabaseHelper.table,
      where: 'mood IN (?, ?, ?) AND isDeleted = 0 AND isPrivate = 0',
      whereArgs: happyMoods,
      orderBy: 'RANDOM()', // 随机排序
      limit: limit,
    );

    return maps.map((map) => DiaryEntry.fromMap(map)).toList();
  }

  // 文件位置: lib/diary_service.dart -> DiaryService class

  /// 将用户选择的图片文件复制到应用的安全目录，并返回新的路径。
  Future<String> copyImageToAppDirectory(File originalFile) async {
    // 1. 获取应用专属的、用于存放图片的文件夹
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(documentsDirectory.path, 'MyNewDiaryData', 'images'));

    // 2. 如果这个文件夹不存在，就创建它
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    // 3. 为复制过来的文件创建一个新的、唯一的文件名
    final String fileName = 'diary_img_${DateTime.now().millisecondsSinceEpoch}${p.extension(originalFile.path)}';
    final String newPath = p.join(imagesDir.path, fileName);

    // 4. 执行复制操作
    await originalFile.copy(newPath);

    // 5. 返回这个新的、安全的文件路径
    return newPath;
  }

  Future<List<DiaryEntry>> getEntriesForDateRange(DateTimeRange dateRange) async {
    final db = await dbHelper.database;
    final maps = await db.query(
      DatabaseHelper.table,
      // 这个查询永远不会包含私密日记
      where: 'date BETWEEN ? AND ? AND isDeleted = 0 AND isPrivate = 0',
      whereArgs: [
        dateRange.start.toIso8601String(),
        dateRange.end.add(const Duration(days: 1)).toIso8601String()
      ],
      orderBy: 'date DESC, creationTime DESC',
    );
    return maps.map((map) => DiaryEntry.fromMap(map)).toList();
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

  // 文件位置: libs/diary_service.dart -> DiaryService class

// VVVV  用这个新版本替换旧的 saveDailyInspiration VVVV
// 它现在接收一个 Map<String, dynamic> 并将其编码为 JSON 字符串进行存储
  Future<void> saveDailyInspiration(DateTime date, Map<String, dynamic> promptData) async {
    final db = await dbHelper.database;
    final dateString = DateFormat('yyyy-MM-dd').format(date);
    final promptJson = jsonEncode(promptData); // 将整个 Map 编码为 JSON 字符串

    await db.insert(
      'daily_inspirations',
      {
        'date': dateString,
        'prompt': promptJson, // 存储 JSON 字符串
        'creationTime': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

// VVVV  用这个新版本替换旧的 getInspirationForDay VVVV
// 它现在返回 Future<Map<String, dynamic>?> 并会自动解码 JSON
  Future<Map<String, dynamic>?> getInspirationForDay(DateTime day) async {
    final db = await dbHelper.database;
    final dateString = DateFormat('yyyy-MM-dd').format(day);
    final maps = await db.query(
      'daily_inspirations',
      where: 'date = ?',
      whereArgs: [dateString],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      try {
        // 从数据库取出 JSON 字符串并解码回 Map
        return jsonDecode(maps.first['prompt'] as String) as Map<String, dynamic>;
      } catch (e) {
        print("解码每日灵感缓存失败: $e");
        return null; // 如果解码失败，返回null，让程序重新获取
      }
    }
    return null;
  }

  // In libs/diary_service.dart -> inside DiaryService class

// VVV 用这个全新的、完全由AI驱动的版本替换旧方法 VVV
  // 文件位置: libs/diary_service.dart -> DiaryService class

  // +++ 这是修正后的 generatePersonalizedPrompt 方法 +++
  Future<Map<String, dynamic>> generatePersonalizedPrompt({required String modelName}) async {
    final geminiService = GeminiServiceLocal();
    final daysSinceLast = await getDaysSinceLastEntry();

    String prompt;
    String promptType;
    bool requiresJsonResponse = false;

    if (daysSinceLast >= 999) {
      promptType = 'welcome';
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
      promptType = 'inspiration';
      requiresJsonResponse = true;
      final recentEntries = await getRecentEntriesWithImages(limit: 5);
      final buffer = StringBuffer();
      if (recentEntries.isNotEmpty) {
        buffer.writeln("这是我最近几天的日记摘要：\n");
        for (final entry in recentEntries) {
          buffer.writeln("- 日期: ${DateFormat('yyyy-MM-dd').format(entry.date)}, 内容: ${entry.text.substring(0, (entry.text.length > 100) ? 100 : entry.text.length)}...");
        }
      }
      prompt = """
    你是一位富有创意的写作伙伴。根据我最近的日记(如果为空则随机生成)，为我生成一个写作灵感。
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
        // 智能查找并提取JSON字符串
        String extractedJson;
        final startIndex = responseText.indexOf('{');
        final endIndex = responseText.lastIndexOf('}');

        if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
          extractedJson = responseText.substring(startIndex, endIndex + 1);
        } else {
          throw FormatException("AI返回的内容中未找到有效的JSON对象。");
        }

        // 修正了变量名：使用 decodedJson
        final decodedJson = jsonDecode(extractedJson);

        return {
          'type': promptType,
          'question': decodedJson['question'],
          'sampleAnswer': decodedJson['sampleAnswer'],
        };
      } else {
        return {'type': promptType, 'text': responseText.replaceAll('"', '').trim()};
      }
    } catch (e) {
      print("生成AI提示失败: $e");
      // 完整的 catch 块，处理错误并提供回退
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

  Future<void> saveDraft(DiaryEntry draft) async {
    final prefs = await SharedPreferences.getInstance();
    // 将草稿对象转换为Map，再编码为JSON字符串进行存储
    final draftJson = jsonEncode(draft.toMap());
    await prefs.setString('unsaved_diary_draft', draftJson);
  }

  /// 从本地加载日记草稿
  Future<DiaryEntry?> loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draftJson = prefs.getString('unsaved_diary_draft');
    if (draftJson != null) {
      // 如果存在草稿，解码JSON字符串并转换为日记对象
      return DiaryEntry.fromMap(jsonDecode(draftJson));
    }
    return null;
  }

  /// 删除已保存的草稿
  Future<void> deleteDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('unsaved_diary_draft');
  }

  // 文件位置: libs/diary_service.dart -> DiaryService class

  /// 获取或创建疗伤角专属的对话日记。
  /// 这个方法会查找一个固定ID的日记条目，如果不存在则会创建一个新的。
  Future<DiaryEntry> getOrCreateComfortChatEntry() async {
    const comfortChatId = 'comfort-chat-session'; // 这是疗伤角对话的专属固定ID
    final existingEntry = await getEntryById(comfortChatId);

    if (existingEntry != null) {
      // 如果找到了，直接返回已存在的日记（包含所有历史对话）
      return existingEntry;
    } else {
      // 如果没找到，说明是第一次使用，需要创建一个新的
      final newComfortEntry = DiaryEntry(
        diaryId: comfortChatId,
        text: "你是一位非常温暖、有同理心的倾听者。我的朋友现在心情不太好，正需要一些慰藉。请你用最温柔、最包容的语气和他开始对话，不要提任何建议，只是纯粹的陪伴和倾听。请以'嘿，朋友，我在呢。'作为开场白。",
        date: DateTime.now(),
        creationTime: DateTime.now(),
        conversations: [], // 初始对话历史为空
        // 将这篇特殊日记设为私密，这样它就不会出现在你的主列表或日历里
        isPrivate: true,
      );
      // 立即将其存入数据库，以便下次可以找到它
      await addEntry(newComfortEntry);
      return newComfortEntry;
    }
  }

  // 文件位置: libs/diary_service.dart -> DiaryService class

  /// 从所有包含图片的日记中，随机挑选一篇返回
  Future<DiaryEntry?> getRandomEntryWithImage() async {
    final db = await dbHelper.database;

    // 查询条件: imagePaths 字段不为空 ('[]'), 未被删除, 并且非私密
    final maps = await db.query(
      DatabaseHelper.table,
      where: "imagePaths IS NOT NULL AND imagePaths != '[]' AND isDeleted = 0 AND isPrivate = 0",
      orderBy: 'RANDOM()', // 关键：使用 RANDOM() 来实现随机排序
      limit: 1,           // 关键：只取符合条件的第一条记录
    );

    if (maps.isNotEmpty) {
      // 如果找到了，就将它从数据库格式转换为我们的日记对象并返回
      return DiaryEntry.fromMap(maps.first);
    }

    // 如果没有任何带图片的日记，则返回 null
    return null;
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
  // +++ 这是修正后的新代码 +++
  Future<int> getConsecutiveCheckInDays() async {
    final db = await dbHelper.database;
    var consecutiveDays = 0;
    var now = DateTime.now();
    var today = DateTime(now.year, now.month, now.day);

    // 1. 先检查今天是否已经签到
    final todayString = DateFormat('yyyy-MM-dd').format(today);
    final todayMaps = await db.query(
      'daily_check_ins',
      where: 'date = ?',
      whereArgs: [todayString],
      limit: 1,
    );

    // 2. 根据今天是否已签到，决定从哪天开始检查
    var dateToCheck = (todayMaps.isNotEmpty) ? today : today.subtract(const Duration(days: 1));

    // 3. 循环向前检查
    while (true) {
      final dateString = DateFormat('yyyy-MM-dd').format(dateToCheck);
      final maps = await db.query(
        'daily_check_ins',
        where: 'date = ?',
        whereArgs: [dateString],
        limit: 1,
      );
      if (maps.isNotEmpty) {
        consecutiveDays++;
        dateToCheck = dateToCheck.subtract(const Duration(days: 1));
      } else {
        // 遇到没有签到的日期，中断循环
        break;
      }
    }
    return consecutiveDays;
  }

  Future<Map<String, dynamic>> getStatistics() async {
    final db = await dbHelper.database;
    final allEntries = await getAllEntriesSorted(); // 获取所有非私密、未删除的日记

    // 1. 总日记篇数
    final totalEntries = allEntries.length;

    // 2. 总字数
    int totalWordCount = 0;
    for (var entry in allEntries) {
      totalWordCount += entry.text.length;
    }

    // 3. 总签到天数
    final totalCheckIns = (await db.query('daily_check_ins')).length;

    // 4. 最长连续写作天数
    int longestStreak = 0;
    int currentStreak = 0;
    if (allEntries.isNotEmpty) {
      // 提取所有唯一的写作日期并排序
      final uniqueDates = allEntries.map((e) => DateTime(e.date.year, e.date.month, e.date.day)).toSet().toList();
      uniqueDates.sort((a, b) => b.compareTo(a)); // 按日期从近到远排序

      for (int i = 0; i < uniqueDates.length; i++) {
        if (i == 0) {
          currentStreak = 1;
        } else {
          // 检查当前日期是否比前一个日期刚好早一天
          if (uniqueDates[i-1].difference(uniqueDates[i]).inDays == 1) {
            currentStreak++;
          } else {
            // 如果中断，则重置计数
            currentStreak = 1;
          }
        }
        if (currentStreak > longestStreak) {
          longestStreak = currentStreak;
        }
      }
    }

    // 5. 心情分布
    final Map<String, int> moodCounts = {};
    for (var entry in allEntries) {
      if (entry.mood != null) {
        moodCounts.update(entry.mood!, (value) => value + 1, ifAbsent: () => 1);
      }
    }

    // 6. 写作时段分布
    final Map<String, int> timeOfDayCounts = {
      '清晨 (5-8点)': 0,
      '上午 (8-12点)': 0,
      '下午 (12-18点)': 0,
      '晚上 (18-22点)': 0,
      '深夜 (22-5点)': 0,
    };
    for (var entry in allEntries) {
      final hour = entry.creationTime.hour;
      if (hour >= 5 && hour < 8) timeOfDayCounts['清晨 (5-8点)'] = timeOfDayCounts['清晨 (5-8点)']! + 1;
      else if (hour >= 8 && hour < 12) timeOfDayCounts['上午 (8-12点)'] = timeOfDayCounts['上午 (8-12点)']! + 1;
      else if (hour >= 12 && hour < 18) timeOfDayCounts['下午 (12-18点)'] = timeOfDayCounts['下午 (12-18点)']! + 1;
      else if (hour >= 18 && hour < 22) timeOfDayCounts['晚上 (18-22点)'] = timeOfDayCounts['晚上 (18-22点)']! + 1;
      else timeOfDayCounts['深夜 (22-5点)'] = timeOfDayCounts['深夜 (22-5点)']! + 1;
    }

    // 将所有结果打包到一个 Map 中返回
    return {
      'totalEntries': totalEntries,
      'totalWordCount': totalWordCount,
      'totalCheckIns': totalCheckIns,
      'longestStreak': longestStreak,
      'moodCounts': moodCounts,
      'timeOfDayCounts': timeOfDayCounts,
    };
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

  // 文件位置: libs/diary_service.dart -> DiaryService class

  /// 获取所有被标记为“自救锦囊”的日记
  Future<List<DiaryEntry>> getSelfHelpEntries() async {
    final db = await dbHelper.database;
    final maps = await db.query(
      DatabaseHelper.table,
      where: 'isSelfHelp = ? AND isDeleted = 0',
      whereArgs: [1],
      orderBy: 'date DESC', // 按时间倒序排列
    );
    return maps.map((map) => DiaryEntry.fromMap(map)).toList();
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

  // file: lib/diary_service.dart -> DiaryService class

  /// 获取所有未删除日记中出现过的、不重复的标签列表
  Future<List<String>> getAllUniqueTags() async {
    final db = await dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      DatabaseHelper.table,
      columns: ['tags'],
      where: 'isDeleted = 0',
    );

    final Set<String> uniqueTags = {};
    for (var map in maps) {
      // 标签在数据库中以JSON字符串形式存储，如 '["标签1","标签2"]'
      final tagsList = (jsonDecode(map['tags']) as List<dynamic>).cast<String>();
      uniqueTags.addAll(tagsList);
    }

    // 返回一个排序后的列表
    final sortedTags = uniqueTags.toList()..sort();
    return sortedTags;
  }


  Future<List<DiaryEntry>> searchEntries({
    String keyword = '',
    DateTimeRange? dateRange,
    String? mood,
    Set<String> selectedTags = const {},
    // 新增一个参数，决定是否包含私密日记，默认为 false (不包含)
    bool includePrivateEntries = false,
  }) async {
    final db = await dbHelper.database;
    List<String> whereClauses = ['isDeleted = ?'];
    List<dynamic> whereArgs = [0];

    // VVVV 核心修改：除非明确要求，否则过滤掉私密日记 VVVV
    if (!includePrivateEntries) {
      whereClauses.add('isPrivate = ?');
      whereArgs.add(0); // 0 代表 false
    }

    if (keyword.isNotEmpty) {
      whereClauses.add('text LIKE ?');
      whereArgs.add('%$keyword%');
    }
    if (dateRange != null) {
      whereClauses.add('date BETWEEN ? AND ?');
      whereArgs.add(dateRange.start.toIso8601String());
      whereArgs.add(dateRange.end.add(const Duration(days: 1)).toIso8601String());
    }
    if (mood != null) {
      whereClauses.add('mood = ?');
      whereArgs.add(mood);
    }
    for (String tag in selectedTags) {
      whereClauses.add("tags LIKE ?");
      whereArgs.add('%"$tag"%');
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

  // file: libs/diary_service.dart -> inside DiaryService class

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

  // file: libs/diary_service.dart -> inside DiaryService class
// 需要 'package:intl/intl.dart' for DateFormat

  Future<List<DiaryEntry>> getRecentEntriesWithImages({int limit = 5}) async {
    print("--- DEBUG: Attempting to get recent entries for AI prompt... ---");
    try {
      final db = await dbHelper.database;
      final maps = await db.query(
        DatabaseHelper.table,
        where: "imagePaths != '[]' AND isDeleted = 0 AND isPrivate = 0",
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

  // file: libs/diary_service.dart -> inside DiaryService class

  Future<List<DiaryEntry>> getOnThisDayEntries() async {
    final db = await dbHelper.database;
    final now = DateTime.now();
    // 格式化日期为 'MM-DD'
    final monthDay = DateFormat('MM-dd').format(now);
    final currentYear = now.year.toString();

    // 使用 SQLite 的 strftime 函数来匹配月和日
    final maps = await db.query(
      DatabaseHelper.table,
      where: "strftime('%m-%d', date) = ? AND strftime('%Y', date) != ? AND isDeleted = 0 AND isPrivate = 0",
      whereArgs: [monthDay, currentYear, 0],
      orderBy: 'date ASC',
    );
    return maps.map((map) => DiaryEntry.fromMap(map)).toList();
  }

  // file: libs/diary_service.dart -> inside DiaryService class

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
  // 文件位置: libs/diary_service.dart -> DiaryService class

  /// 获取所有未删除的日记，按时间倒序排列
  Future<List<DiaryEntry>> getAllEntriesSorted() async {
    final db = await dbHelper.database;
    final maps = await db.query(
      DatabaseHelper.table,
      // VVVV 核心修改：不再用 isPrivate 过滤，而是用 diaryId 精确排除疗伤角 VVVV
      where: "isDeleted = ? AND diaryId != ?",
      whereArgs: [0, 'comfort-chat-session'],
      orderBy: 'date DESC, creationTime DESC',
    );
    return maps.map((map) => DiaryEntry.fromMap(map)).toList();
  }

  /// 获取指定某一天的所有日记
  // 文件位置: libs/diary_service.dart -> DiaryService class

  /// 获取指定某一天的所有日记
  Future<List<DiaryEntry>> getEntriesForDay(DateTime day) async {
    final db = await dbHelper.database;
    final dayString = day.toIso8601String().substring(0, 10);
    final maps = await db.query(
      DatabaseHelper.table,
      // VVVV 核心修改：同样，用 diaryId 精确排除 VVVV
      where: 'date LIKE ? AND isDeleted = ? AND diaryId != ?',
      whereArgs: ['$dayString%', 0, 'comfort-chat-session'],
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
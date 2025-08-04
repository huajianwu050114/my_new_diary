// file: lib/migration_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:my_new_diary/diary_model.dart'; // 导入新的模型，用于转换

// 这是一个临时的、只用于读取旧JSON文件的数据模型
class OldDiaryEntry {
  final String filePath;
  final List<String> imagePaths;
  final String text;
  final DateTime date;
  final DateTime creationTime;
  final DateTime? lastModifiedTime;
  final String? mood;
  final List<String> tags;
  final double? latitude;
  final double? longitude;
  final String? address;
  final List<String> aiAnalyses;
  final List<dynamic> conversations; // 以 dynamic 形式读取

  OldDiaryEntry({
    required this.filePath,
    required this.imagePaths,
    required this.text,
    required this.date,
    required this.creationTime,
    this.lastModifiedTime,
    this.mood,
    this.tags = const [],
    this.latitude,
    this.longitude,
    this.address,
    this.aiAnalyses = const [],
    this.conversations = const [],
  });

  factory OldDiaryEntry.fromMap(Map<String, dynamic> map, String filePath) {
    return OldDiaryEntry(
      filePath: filePath,
      imagePaths: List<String>.from(map['imagePaths'] ?? []),
      text: map['text'] ?? '',
      date: DateTime.parse(map['date']),
      creationTime: map['creationTime'] != null
          ? DateTime.parse(map['creationTime'])
          : DateTime.parse(map['date']),
      lastModifiedTime: map['lastModifiedTime'] != null
          ? DateTime.parse(map['lastModifiedTime'])
          : null,
      mood: map['mood'],
      tags: map['tags'] != null ? List<String>.from(map['tags']) : [],
      latitude: map['latitude'],
      longitude: map['longitude'],
      address: map['address'],
      aiAnalyses: map['aiAnalyses'] != null ? List<String>.from(map['aiAnalyses']) : [],
      conversations: map['conversations'] ?? [],
    );
  }

  // 转换到新的数据库模型
  DiaryEntry toNewDiaryEntry() {
    return DiaryEntry(
      diaryId: '', // 新的ID将由数据库服务生成
      text: text,
      date: date,
      creationTime: creationTime,
      lastModifiedTime: lastModifiedTime,
      mood: mood,
      address: address,
      latitude: latitude,
      longitude: longitude,
      imagePaths: imagePaths,
      tags: tags,
      aiAnalyses: aiAnalyses,
      // 注意：这里我们尝试转换对话记录
      conversations: conversations.map((c) => Conversation.fromJson(c as Map<String, dynamic>)).toList(),
    );
  }
}

// 临时的文件读取服务
class MigrationService {
  Future<Directory> get _appDir async =>
      await getApplicationDocumentsDirectory();

  Future<Directory> get _diariesDir async {
    final dir = Directory(p.join((await _appDir).path, 'diaries'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<OldDiaryEntry>> getAllFileEntries() async {
    final List<OldDiaryEntry> allEntries = [];
    final dir = await _diariesDir;

    if (!await dir.exists()) return [];

    await for (var yearEntity in dir.list(recursive: true)) {
      if (yearEntity is File && p.basename(yearEntity.path).endsWith('.json')) {
        try {
          final jsonString = await yearEntity.readAsString();
          final map = jsonDecode(jsonString);
          allEntries.add(OldDiaryEntry.fromMap(map, yearEntity.path));
        } catch (e) {
          print("解析旧文件失败: ${yearEntity.path}, 错误: $e");
        }
      }
    }
    return allEntries;
  }
}
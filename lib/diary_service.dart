// file: lib/diary_service.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:latlong2/latlong.dart' as latlong;
// 导入 google_generative_ai 包以使用 Content 类型
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:uuid/uuid.dart';

class Conversation {
  final String id;
  String title;
  final List<Content> history;

  Conversation({required this.id, required this.title, required this.history});

  // 从 Map 创建 Conversation
  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String? ?? const Uuid().v4(),
      title: json['title'] as String? ?? '新对话',
      history: (json['history'] as List<dynamic>? ?? [])
          .map((item) => _contentFromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  // 将 Conversation 转换为 Map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'history': history.map((c) => _contentToJson(c)).toList(),
    };
  }
}
// VVV 1. 手动添加的辅助函数，用于序列化 Content VVV
Map<String, dynamic> _contentToJson(Content content) {
  return {
    'role': content.role,
    'parts': content.parts.map((part) {
      if (part is TextPart) {
        return {'type': 'text', 'text': part.text};
      }
      // 可以根据需要在这里添加对其他 Part 类型的处理
      return {};
    }).toList(),
  };
}

// VVV 2. 手动添加的辅助函数，用于反序列化 Content VVV
Content _contentFromJson(Map<String, dynamic> json) {
  final role = json['role'] as String?;

  // --- 关键修正 ---
  // 1. 安全地获取 parts 列表，如果不存在则默认为一个空列表
  final partsList = json['parts'] as List<dynamic>? ?? [];

  // 2. 在安全的列表上进行 map 操作
  final parts = partsList.map((partJson) {
    final partMap = partJson as Map<String, dynamic>;
    if (partMap['type'] == 'text') {
      // 确保 text 字段也安全地处理
      return TextPart(partMap['text'] as String? ?? '');
    }
    return TextPart('');
  }).toList();

  return Content(role ?? 'model', parts);
}


class DiaryEntry {
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
  List<String> aiAnalyses;
  final List<Content> chatHistory;
  final List<Conversation> conversations;

  DiaryEntry({
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
    this.chatHistory = const [],
    this.conversations = const [],
  });

  DiaryEntry copyWith({
    String? filePath,
    List<String>? imagePaths,
    String? text,
    DateTime? date,
    DateTime? creationTime,
    DateTime? lastModifiedTime,
    String? mood,
    List<String>? tags,
    double? latitude,
    double? longitude,
    String? address,
    List<String>? aiAnalyses,
    List<Content>? chatHistory,
    List<Conversation>? conversations,
  }) {
    return DiaryEntry(
      filePath: filePath ?? this.filePath,
      imagePaths: imagePaths ?? this.imagePaths,
      text: text ?? this.text,
      date: date ?? this.date,
      creationTime: creationTime ?? this.creationTime,
      lastModifiedTime: lastModifiedTime ?? this.lastModifiedTime,
      mood: mood ?? this.mood,
      tags: tags ?? this.tags,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      aiAnalyses: aiAnalyses ?? this.aiAnalyses,
      chatHistory: chatHistory ?? this.chatHistory,
      conversations: conversations ?? this.conversations,
    );
  }

  factory DiaryEntry.fromMap(Map<String, dynamic> map, String filePath) {
    List<String> paths = [];
    if (map['imagePaths'] != null && map['imagePaths'] is List) {
      paths = List<String>.from(map['imagePaths']);
    } else if (map['imagePath'] != null && map['imagePath'] is String) {
      paths = [map['imagePath']];
    }

    // Helper to parse chat history safely
    List<Conversation> _parseConversations(dynamic convValue) {
      if (convValue is List) {
        return convValue.map((item) => Conversation.fromJson(item as Map<String, dynamic>)).toList();
      }
      return [];
    }

    return DiaryEntry(
      filePath: filePath,
      imagePaths: paths,
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
      conversations: _parseConversations(map['conversations']),
    );
  }

  Future<Map<String, dynamic>> toMap({bool forExport = false}) async {
    List<String> imagePayload = [];
    if (forExport) {
      for (final path in imagePaths) {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          imagePayload.add(base64Encode(bytes));
        }
      }
    } else {
      imagePayload = imagePaths;
    }

    return {
      'imagePaths': imagePayload,
      'text': text,
      'date': date.toIso8601String(),
      'creationTime': creationTime.toIso8601String(),
      'lastModifiedTime': lastModifiedTime?.toIso8601String(),
      'mood': mood,
      'tags': tags,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'aiAnalyses': aiAnalyses,
      // VVV 4. 调用我们手动创建的辅助函数 VVV
      'chatHistory': chatHistory.map((c) => _contentToJson(c)).toList(),
      'conversations': conversations.map((c) => c.toJson()).toList(),
    };
  }
}

class DiaryService extends ChangeNotifier {
  // ... (all existing properties and methods like _appDir, addEntry, getEntriesForDay, etc. remain here)

  // 更新指定日记的聊天记录
  Future<void> saveConversationAsAnalysis(String filePath, String conversationText) async {
    final file = File(filePath);
    if (!await file.exists()) return;

    final entry = await DiaryService.fromFile(file);

    // 创建一个新的分析列表，并将新的对话内容插入到最前面
    final newAnalyses = List<String>.from(entry.aiAnalyses)..insert(0, conversationText);

    // 使用 copyWith 创建更新后的日记对象
    final updatedEntry = entry.copyWith(aiAnalyses: newAnalyses);

    // 调用我们之前重构好的 updateEntry 方法来保存
    await updateEntry(updatedEntry);
  }

  Future<void> updateChatHistory(String filePath, List<Content> history) async {
    final file = File(filePath);
    if (!await file.exists()) return;

    final entry = await DiaryService.fromFile(file);
    final updatedEntry = entry.copyWith(chatHistory: history);

    await file.writeAsString(jsonEncode(await updatedEntry.toMap()));
    notifyListeners();
  }

  Future<void> updateEntry(DiaryEntry entry) async {
    // VVV 关键修改：在保存前，使用 copyWith 更新 lastModifiedTime 为当前时间 VVV
    final entryWithTimestamp = entry.copyWith(lastModifiedTime: DateTime.now());

    final file = File(entryWithTimestamp.filePath);
    if (!await file.exists()) {
      print("文件不存在，无法更新: ${entry.filePath}");
      return;
    }
    await file.writeAsString(jsonEncode(await entryWithTimestamp.toMap()));
    notifyListeners();
  }


  // 将对话追加到日记正文
  Future<void> appendConversationToEntry(String filePath, String conversationText) async {
    final file = File(filePath);
    if (!await file.exists()) return;

    final entry = await DiaryService.fromFile(file);
    final newText = '${entry.text}\n\n--- AI 对话记录 ---\n$conversationText';
    final updatedEntry = entry.copyWith(text: newText);

    await file.writeAsString(jsonEncode(await updatedEntry.toMap()));
    notifyListeners();
  }

  // Keep all other methods of DiaryService...
  // ... fromFile, addAnalysisToEntry, _trashDir, etc. ...

  Future<Directory> get _appDir async => await getApplicationDocumentsDirectory();
  Future<Directory> get _diariesDir async {
    final dir = Directory(p.join((await _appDir).path, 'diaries'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> get _imagesDir async {
    final dir = Directory(p.join((await _appDir).path, 'images'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<DiaryEntry> fromFile(File file) async {
    final jsonString = await file.readAsString();
    final map = jsonDecode(jsonString);
    return DiaryEntry.fromMap(map, file.path);
  }

  Future<void> addAnalysisToEntry(DiaryEntry entry, String newAnalysis) async {
    final file = File(entry.filePath);
    if (!await file.exists()) {
      print('Error: File does not exist: ${entry.filePath}');
      return;
    }
    entry.aiAnalyses.add(newAnalysis);
    await file.writeAsString(jsonEncode(await entry.toMap()));
    notifyListeners();
  }

  Future<Directory> get _trashDir async {
    final dir = Directory(p.join((await _appDir).path, 'diaries_trash'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> saveImageFromBytes(Uint8List bytes) async {
    final imagesDir = await _imagesDir;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'imported_image_$timestamp.jpg';
    final file = File(p.join(imagesDir.path, fileName));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<List<DiaryEntry>> getEntriesForDay(DateTime day) async {
    final year = day.year.toString();
    final month = day.month.toString().padLeft(2, '0');
    final dayDir = Directory(p.join((await _diariesDir).path, year, month));

    if (!await dayDir.exists()) {
      return [];
    }

    final List<DiaryEntry> entries = [];
    final dayString =
        "${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}";
    await for (var entity in dayDir.list()) {
      if (entity is File &&
          p.basename(entity.path).startsWith(dayString) &&
          p.basename(entity.path).endsWith('.json')) {
        try {
          final jsonString = await entity.readAsString();
          final map = jsonDecode(jsonString);
          entries.add(DiaryEntry.fromMap(map, entity.path));
        } catch (e) {
          print("解析文件失败: ${entity.path}, 错误: $e");
        }
      }
    }

    entries.sort((a, b) => b.creationTime.compareTo(a.creationTime));
    return entries;
  }

  Future<void> addEntry(DiaryEntry entry) async {
    final year = entry.date.year.toString();
    final month = entry.date.month.toString().padLeft(2, '0');
    final day = entry.date.day.toString().padLeft(2, '0');

    final monthDir = Directory(p.join((await _diariesDir).path, year, month));
    if (!await monthDir.exists()) {
      await monthDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = "$year-$month-${day}_$timestamp.json";
    final file = File(p.join(monthDir.path, fileName));

    await file.writeAsString(jsonEncode(await entry.toMap()));
    notifyListeners();
  }

  Future<void> moveEntryToTrash(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return;
      }
      final trashDir = await _trashDir;
      final fileName = p.basename(filePath);
      final newPath = p.join(trashDir.path, fileName);
      await file.rename(newPath);
      notifyListeners();
    } catch (e) {
      print('移动文件到回收站时出错: $e');
    }
  }

  Future<List<DiaryEntry>> getAllEntriesSorted() async {
    final List<DiaryEntry> allEntries = [];
    final dir = await _diariesDir;

    if (!await dir.exists()) return [];
    await for (var yearEntity in dir.list()) {
      if (yearEntity is Directory) {
        await for (var monthEntity in yearEntity.list()) {
          if (monthEntity is Directory) {
            await for (var fileEntity in monthEntity.list()) {
              if (fileEntity is File &&
                  p.basename(fileEntity.path).endsWith('.json')) {
                try {
                  final jsonString = await fileEntity.readAsString();
                  final map = jsonDecode(jsonString);
                  allEntries.add(DiaryEntry.fromMap(map, fileEntity.path));
                } catch (e) {
                  print("解析文件失败: ${fileEntity.path}, 错误: $e");
                }
              }
            }
          }
        }
      }
    }

    allEntries.sort((a, b) {
      int dateComparison = b.date.compareTo(a.date);
      if (dateComparison == 0) {
        return b.creationTime.compareTo(a.creationTime);
      }
      return dateComparison;
    });

    return allEntries;
  }

  Future<List<DiaryEntry>> getRecentEntriesWithImages({int limit = 5}) async {
    final allEntries = await getAllEntriesSorted();
    final entriesWithImages = allEntries.where((entry) {
      return entry.imagePaths.isNotEmpty;
    }).toList();
    return entriesWithImages.take(limit).toList();
  }

  Future<List<DiaryEntry>> getTrashEntries() async {
    final trashDir = await _trashDir;
    final List<DiaryEntry> entries = [];
    if (!await trashDir.exists()) {
      return [];
    }

    await for (var entity in trashDir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          final jsonString = await entity.readAsString();
          final map = jsonDecode(jsonString);
          entries.add(DiaryEntry.fromMap(map, entity.path));
        } catch (e) {
          print("解析回收站文件失败: ${entity.path}, 错误: $e");
        }
      }
    }
    entries.sort((a, b) => b.creationTime.compareTo(a.creationTime));
    return entries;
  }

  Future<void> restoreFromTrash(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return;
    final entry = DiaryEntry.fromMap(jsonDecode(await file.readAsString()), filePath);
    final diariesDir = await _diariesDir;

    final year = entry.date.year.toString();
    final month = entry.date.month.toString().padLeft(2, '0');
    final monthDir = Directory(p.join(diariesDir.path, year, month));

    if (!await monthDir.exists()) {
      await monthDir.create(recursive: true);
    }

    final newPath = p.join(monthDir.path, p.basename(filePath));
    await file.rename(newPath);
    notifyListeners();
  }

  Future<void> deletePermanently(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
    notifyListeners();
  }

  Future<List<DiaryEntry>> searchEntries(String keyword) async {
    if (keyword.isEmpty) {
      return [];
    }

    final allEntries = await getAllEntriesSorted();
    final List<DiaryEntry> results = [];
    final lowerCaseKeyword = keyword.toLowerCase();
    for (var entry in allEntries) {
      if (entry.text.toLowerCase().contains(lowerCaseKeyword)) {
        results.add(entry);
      }
    }

    return results;
  }

  Future<List<DiaryEntry>> getOnThisDayEntries() async {
    final now = DateTime.now();
    final todayDateOnly = DateTime(now.year, now.month, now.day);

    final allEntries = await getAllEntriesSorted();
    final List<DiaryEntry> resultEntries = allEntries.where((entry) {
      final entryDateOnly = DateTime(entry.date.year, entry.date.month, entry.date.day);

      return entryDateOnly.month == todayDateOnly.month &&
          entryDateOnly.day == todayDateOnly.day &&
          entryDateOnly.year != todayDateOnly.year;
    }).toList();
    resultEntries.sort((a, b) => a.date.compareTo(b.date));

    return resultEntries;
  }

  Future<String> getDebugInfo() async {
    final buffer = StringBuffer();
    final now = DateTime.now();
    buffer.writeln('--- 调试信息 ---');
    buffer.writeln('当前时间: $now');
    buffer.writeln('当前时区: ${now.timeZoneName} (偏移量: ${now.timeZoneOffset})');
    buffer.writeln('');

    final allEntries = await getAllEntriesSorted();
    buffer.writeln('共找到 ${allEntries.length} 篇日记:');
    buffer.writeln('--------------------');

    for (var entry in allEntries) {
      buffer.writeln(
          '日记所属日期 (date): ${entry.date.toIso8601String()}');
      buffer.writeln(
          '日记创建时间 (creationTime): ${entry.creationTime.toIso8601String()}');
      buffer.writeln('日记文本 (text): "${entry.text.substring(0, (entry.text.length > 20 ? 20 : entry.text.length))
      }..."');
      buffer.writeln('---');
    }

    return buffer.toString();
  }

  Future<List<List<DiaryEntry>>> getGroupedEntriesByLocation({
    double distanceThreshold = 200,
  }) async {
    final allEntries = await getAllEntriesSorted();
    final entriesWithLocation = allEntries.where((e) => e.latitude != null && e.longitude != null).toList();
    if (entriesWithLocation.isEmpty) {
      return [];
    }

    final List<List<DiaryEntry>> clusteredEntries = [];
    final distance = const latlong.Distance();

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
}
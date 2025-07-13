// file: lib/diary_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class DiaryEntry {
  final String filePath;
  final List<String> imagePaths;
  final String text;
  final DateTime date;
  final DateTime creationTime;
  final String? mood;
  final List<String> tags;
  // VVV 1. Add new fields for location data VVV
  final double? latitude;
  final double? longitude;
  final String? address;

  DiaryEntry({
    required this.filePath,
    required this.imagePaths,
    required this.text,
    required this.date,
    required this.creationTime,
    this.mood,
    this.tags = const [],
    // VVV 2. Update the constructor VVV
    this.latitude,
    this.longitude,
    this.address,
  });

  factory DiaryEntry.fromMap(Map<String, dynamic> map, String filePath) {
    List<String> paths = [];
    if (map['imagePaths'] != null && map['imagePaths'] is List) {
      paths = List<String>.from(map['imagePaths']);
    } else if (map['imagePath'] != null && map['imagePath'] is String) {
      paths = [map['imagePath']];
    }

    return DiaryEntry(
      filePath: filePath,
      imagePaths: paths,
      text: map['text'],
      date: DateTime.parse(map['date']),
      creationTime: map['creationTime'] != null
          ? DateTime.parse(map['creationTime'])
          : DateTime.parse(map['date']),
      mood: map['mood'],
      tags: map['tags'] != null ? List<String>.from(map['tags']) : [],
      // VVV 3. Read location data from the map VVV
      latitude: map['latitude'],
      longitude: map['longitude'],
      address: map['address'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'imagePaths': imagePaths,
      'text': text,
      'date': date.toIso8601String(),
      'creationTime': creationTime.toIso8601String(),
      'mood': mood,
      'tags': tags,
      // VVV 4. Write location data to the map VVV
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
    };
  }
}

class DiaryService extends ChangeNotifier {
  Future<Directory> get _diariesDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final diariesDir = Directory(p.join(appDir.path, 'diaries'));
    if (!await diariesDir.exists()) {
      await diariesDir.create(recursive: true);
    }
    return diariesDir;
  }

  Future<Directory> get _trashDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final trashDir = Directory(p.join(appDir.path, 'diaries_trash'));
    if (!await trashDir.exists()) {
      await trashDir.create(recursive: true);
    }
    return trashDir;
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

    await file.writeAsString(jsonEncode(entry.toMap()));
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

  // VVV 用这个新的、更健壮的版本，完整替换旧的 getOnThisDayEntries 方法 VVV
  Future<List<DiaryEntry>> getOnThisDayEntries() async {
    final now = DateTime.now();
    // 创建一个只包含今天“年月日”的日期对象，忽略所有时间信息
    final todayDateOnly = DateTime(now.year, now.month, now.day);

    final allEntries = await getAllEntriesSorted();

    final List<DiaryEntry> resultEntries = allEntries.where((entry) {
      // 同样，为每篇日记创建一个只包含“年月日”的日期对象
      final entryDateOnly = DateTime(entry.date.year, entry.date.month, entry.date.day);

      // 条件：月份相同、日期相同、但年份不同
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
}
// file: diary_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart'; // <-- 1. 导入 material
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// --- 数据模型 (保持不变) ---
class DiaryEntry {
  final String filePath;
  final String? imagePath;
  final String text;
  final DateTime date;
  final DateTime creationTime;

  DiaryEntry({
    required this.filePath,
    this.imagePath,
    required this.text,
    required this.date,
    required this.creationTime,
  });

  factory DiaryEntry.fromMap(Map<String, dynamic> map, String filePath) {
    return DiaryEntry(
      filePath: filePath,
      imagePath: map['imagePath'],
      text: map['text'],
      date: DateTime.parse(map['date']),
      creationTime: map['creationTime'] != null ? DateTime.parse(map['creationTime']) : DateTime.parse(map['date']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'imagePath': imagePath,
      'text': text,
      'date': date.toIso8601String(),
      'creationTime': creationTime.toIso8601String(),
    };
  }
}

// --- 日记数据服务 ---
class DiaryService extends ChangeNotifier { // <-- 2. 继承自 ChangeNotifier

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
    final dayString = "${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}";

    await for (var entity in dayDir.list()) {
      if (entity is File && p.basename(entity.path).startsWith(dayString) && p.basename(entity.path).endsWith('.json')) {
        // <-- 3. 添加了错误处理
        try {
          final jsonString = await entity.readAsString();
          final map = jsonDecode(jsonString);
          entries.add(DiaryEntry.fromMap(map, entity.path));
        } catch (e) {
          print("解析文件失败: ${entity.path}, 错误: $e");
        }
      }
    }
    // 按创建时间排序，让最新的显示在最前面
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
    notifyListeners(); // <-- 4. 数据变化后，通知监听者
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
      notifyListeners(); // <-- 4. 数据变化后，通知监听者
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
              if (fileEntity is File && p.basename(fileEntity.path).endsWith('.json')) {
                // <-- 3. 添加了错误处理
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

    allEntries.sort((a, b) => b.creationTime.compareTo(a.creationTime));
    return allEntries;
  }

  Future<List<DiaryEntry>> getRecentEntriesWithImages({int limit = 5}) async {
    final allEntries = await getAllEntriesSorted();
    final entriesWithImages = allEntries.where((entry) {
      return entry.imagePath != null && entry.imagePath!.isNotEmpty;
    }).toList();
    return entriesWithImages.take(limit).toList();
  }
}
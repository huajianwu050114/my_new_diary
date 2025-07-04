import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// --- 复用我们之前的数据模型 ---
class DiaryEntry {
  final String filePath;
  final String? imagePath; // 注意：这里从 imageUrl 变成了 imagePath，存储本地路径
  final String text;
  final DateTime date;
  final DateTime creationTime;

  DiaryEntry({
    required this.filePath, // 2. 在构造函数里添加
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
      // 3. 读取 creationTime，如果不存在则使用date作为备用
      creationTime: map['creationTime'] != null ? DateTime.parse(map['creationTime']) : DateTime.parse(map['date']),
    );
  }

  // 把对象转换成Map时，也要写入新字段
  Map<String, dynamic> toMap() {
    return {
      'imagePath': imagePath,
      'text': text,
      'date': date.toIso8601String(),
      'creationTime': creationTime.toIso8601String(), // 4. 添加新字段到 toMap
    };
  }
}

// --- 日记数据服务（管家） ---
class DiaryService {
  // 获取日记存储的总目录
  Future<Directory> get _diariesDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final diariesDir = Directory(p.join(appDir.path, 'diaries'));
    // 如果文件夹不存在，就创建它
    if (!await diariesDir.exists()) {
      await diariesDir.create(recursive: true);
    }
    return diariesDir;
  }

  // 获取某一天所有的日记
  Future<List<DiaryEntry>> getEntriesForDay(DateTime day) async {
    final year = day.year.toString();
    final month = day.month.toString().padLeft(2, '0'); // 确保月份是两位数，如 07
    final dayDir = Directory(p.join((await _diariesDir).path, year, month));

    if (!await dayDir.exists()) {
      return []; // 如果当月的文件夹都不存在，直接返回空列表
    }

    final List<DiaryEntry> entries = [];
    final dayString = "${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}";

    // 遍历文件夹里的所有文件
    await for (var entity in dayDir.list()) {
      if (entity is File && p.basename(entity.path).startsWith(dayString) && p.basename(entity.path).endsWith('.json')) {
        final jsonString = await entity.readAsString();
        final map = jsonDecode(jsonString);
        entries.add(DiaryEntry.fromMap(map, entity.path));
      }
    }
    return entries;
  }

  // 添加一篇新日记
  Future<void> addEntry(DiaryEntry entry) async {
    final year = entry.date.year.toString();
    final month = entry.date.month.toString().padLeft(2, '0');
    final day = entry.date.day.toString().padLeft(2, '0');

    final monthDir = Directory(p.join((await _diariesDir).path, year, month));
    if (!await monthDir.exists()) {
      await monthDir.create(recursive: true);
    }

    // 为了防止文件名重复，我们用时间戳作为序号
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = "$year-$month-${day}_$timestamp.json";
    final file = File(p.join(monthDir.path, fileName));

    await file.writeAsString(jsonEncode(entry.toMap()));
  }

  // 新方法
  Future<void> moveEntryToTrash(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return; // 如果文件不存在，直接返回
      }

      final trashDir = await _trashDir;
      final fileName = p.basename(filePath);
      final newPath = p.join(trashDir.path, fileName);

      // 移动文件到回收站目录
      await file.rename(newPath);
    } catch (e) {
      print('移动文件到回收站时出错: $e');
    }
  }
  // 在 DiaryService 类里

// 获取日记回收站的目录
  Future<Directory> get _trashDir async {
    final appDir = await getApplicationDocumentsDirectory();
    final trashDir = Directory(p.join(appDir.path, 'diaries_trash'));
    if (!await trashDir.exists()) {
      await trashDir.create(recursive: true);
    }
    return trashDir;
  }

  // 在 DiaryService 类的内部

// 获取所有日记，并按创建时间从新到旧排序
  Future<List<DiaryEntry>> getAllEntriesSorted() async {
    final List<DiaryEntry> allEntries = [];
    final dir = await _diariesDir;

    // 遍历所有年份文件夹
    await for (var yearEntity in dir.list()) {
      if (yearEntity is Directory) {
        // 遍历所有月份文件夹
        await for (var monthEntity in yearEntity.list()) {
          if (monthEntity is Directory) {
            // 遍历所有.json日记文件
            await for (var fileEntity in monthEntity.list()) {
              if (fileEntity is File && p.basename(fileEntity.path).endsWith('.json')) {
                final jsonString = await fileEntity.readAsString();
                final map = jsonDecode(jsonString);
                allEntries.add(DiaryEntry.fromMap(map, fileEntity.path));
              }
            }
          }
        }
      }
    }

    // 按 creationTime 降序排序（最新的在最前面）
    allEntries.sort((a, b) => b.creationTime.compareTo(a.creationTime));

    return allEntries;
  }

  // 在 DiaryService 类的内部

// 获取最近的、带图片的日记，可以指定获取几条
  Future<List<DiaryEntry>> getRecentEntriesWithImages({int limit = 5}) async {
    // 先获取所有排好序的日记
    final allEntries = await getAllEntriesSorted();

    // 筛选出其中有图片路径的日记
    final entriesWithImages = allEntries.where((entry) {
      return entry.imagePath != null && entry.imagePath!.isNotEmpty;
    }).toList();

    // 只返回前面几条（最新的），如果不够就返回所有
    return entriesWithImages.take(limit).toList();
  }
}
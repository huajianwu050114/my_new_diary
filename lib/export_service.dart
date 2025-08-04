// file: lib/export_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_picker/file_picker.dart';
import 'diary_service.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:archive/archive_io.dart'; // VVV 1. 导入 archive 包// VVV 2. 导入 path_provider 包';
import 'package:path/path.dart' as p;
import 'package:my_new_diary/diary_model.dart';

typedef ExportProgressCallback = void Function(int current, int total);

class ExportService {
  final List<DiaryEntry> entries;

  ExportService(this.entries);

  // VVV 2. 全新的导出为 ZIP 的方法
  Future<String?> exportToZip({ExportProgressCallback? onProgress}) async {
    final archive = Archive();
    final List<Map<String, dynamic>> jsonEntries = [];

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final newImagePaths = <String>[];

      // 处理图片：将图片文件添加到 archive 中，并记录相对路径
      for (final imagePath in entry.imagePaths) {
        final file = File(imagePath);
        if (await file.exists()) {
          final fileName = p.basename(imagePath);
          final imageBytes = await file.readAsBytes();
          // 将图片添加到 zip 包的 'images' 文件夹下
          final archiveFile = ArchiveFile('images/$fileName', imageBytes.length, imageBytes);
          archive.addFile(archiveFile);
          // 在 json 中记录这个相对路径
          newImagePaths.add('images/$fileName');
        }
      }

      // 使用相对图片路径创建用于JSON的map
      final entryMap = (await entry.toMap())..['imagePaths'] = newImagePaths;
      jsonEntries.add(entryMap);

      onProgress?.call(i + 1, entries.length);
      await Future.delayed(const Duration(milliseconds: 5));
    }

    // 将日记的文本数据添加到 zip 包的根目录
    final jsonData = jsonEncode(jsonEntries);
    final jsonFile = ArchiveFile('backup.json', jsonData.length, utf8.encode(jsonData));
    archive.addFile(jsonFile);

    // 将 archive 对象编码为 zip 格式的字节
    final zipEncoder = ZipEncoder();
    final zipBytes = zipEncoder.encode(archive);

    if (zipBytes == null) {
      print("ZIP 编码失败");
      return null;
    }

    return await _saveFileWithPicker(zipBytes, 'my_diary_backup.zip');
  }

  // _saveFileWithPicker 方法保持不变
  Future<String?> _saveFileWithPicker(dynamic content, String fileName) async {
    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/$fileName';
    final file = File(filePath);

    if (content is List<int>) {
      await file.writeAsBytes(content);
    } else {
      return null;
    }

    final xfile = XFile(filePath);
    final result = await Share.shareXFiles([xfile], text: '我的日记备份');

    if (result.status == ShareResultStatus.success) {
      return "分享成功";
    }

    return null;
  }

// (你可以暂时移除 exportToPdf 和 exportToJson 方法，或保留它们)
}
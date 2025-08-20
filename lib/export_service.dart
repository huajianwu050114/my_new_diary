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
import 'dart:typed_data';

typedef ExportProgressCallback = void Function(int current, int total);

class ExportService {
  final List<DiaryEntry> entries;

  ExportService(this.entries);

  // VVV 2. 全新的导出为 ZIP 的方法
  // 文件位置: lib/export_service.dart -> ExportService class

  // 文件位置: lib/export_service.dart -> ExportService class

  Future<String?> exportToZip({ExportProgressCallback? onProgress}) async {
    final archive = Archive();
    final List<Map<String, dynamic>> jsonEntries = [];

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final newRelativeImagePaths = <String>[];

      for (final imagePath in entry.imagePaths) {
        final file = File(imagePath);
        if (await file.exists()) {
          final fileName = p.basename(imagePath);
          final imageBytes = await file.readAsBytes();
          final archiveFile = ArchiveFile('images/$fileName', imageBytes.length, imageBytes);
          archive.addFile(archiveFile);
          newRelativeImagePaths.add('images/$fileName');
        }
      }

      final entryForJson = entry.copyWith(imagePaths: newRelativeImagePaths);
      jsonEntries.add(entryForJson.toMap());

      onProgress?.call(i + 1, entries.length);
      await Future.delayed(const Duration(milliseconds: 5));
    }

    final jsonData = jsonEncode(jsonEntries);
    final jsonBytes = utf8.encode(jsonData);
    final jsonFile = ArchiveFile('backup.json', jsonBytes.length, jsonBytes);
    archive.addFile(jsonFile);

    final zipEncoder = ZipEncoder();
    final zipBytes = zipEncoder.encode(archive);

    if (zipBytes == null) {
      print("ZIP 编码失败");
      return "错误：ZIP 文件编码失败";
    }

    // VVVV  主要修改区域 VVVV

    // 1. 获取当前时间
    final now = DateTime.now();
    // 2. 创建一个适合文件名的日期格式化工具 (例如: 20250818_120000)
    final formatter = DateFormat('yyyyMMdd_HHmmss');
    // 3. 格式化当前时间
    final timestamp = formatter.format(now);
    // 4. 创建带有时间戳的新文件名
    final fileName = '我的日记_$timestamp.zip';

    // 5. 将新的动态文件名传递给保存方法
    return await _saveFileToDevice(Uint8List.fromList(zipBytes), fileName);

    // ^^^^ 修改结束 ^^^^
  }

  // _saveFileWithPicker 方法保持不变
  // 在 ExportService 类内部，用下面的方法替换掉旧的 _saveFileWithPicker

  Future<String?> _saveFileToDevice(Uint8List content, String fileName) async {
    try {
      // 调用 file_picker 的保存文件功能
      // 这会打开一个原生文件浏览器，让用户选择保存位置
      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '请选择备份文件的保存位置',
        fileName: fileName,
        bytes: content,
      );

      // 如果 outputPath 不是 null，说明用户选择了位置并成功保存
      if (outputPath != null) {
        return '备份已成功保存。';
      } else {
        // 如果是 null，说明用户取消了操作
        return '已取消保存操作。';
      }
    } catch (e) {
      // 捕获可能发生的错误
      print("保存文件时出错: $e");
      return '保存文件失败: $e';
    }
  }

// (你可以暂时移除 exportToPdf 和 exportToJson 方法，或保留它们)
}
// file: lib/export_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_picker/file_picker.dart'; // VVV 1. 导入新的插件
import 'diary_service.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart'; // 导入 path_provider
import 'package:share_plus/share_plus.dart';

typedef ExportProgressCallback = void Function(int current, int total);

class ExportService {
  final List<DiaryEntry> entries;

  ExportService(this.entries);

  // VVV 2. 修改方法，让它返回保存的路径，方便UI提示
  Future<String?> exportToJson({ExportProgressCallback? onProgress}) async {
    final List<Map<String, dynamic>> entryList = [];
    for (int i = 0; i < entries.length; i++) {
      // Call toMap with forExport: true to get Base64 image data
      entryList.add(await entries[i].toMap(forExport: true));
      onProgress?.call(i + 1, entries.length);
      // Optional delay to keep the UI responsive on large exports
      await Future.delayed(const Duration(milliseconds: 5));
    }

    final jsonString = jsonEncode(entryList);
    return await _saveFileWithPicker(jsonString, 'my_diary_backup.json');
  }

  Future<String?> exportToPdf({ExportProgressCallback? onProgress}) async {
    final doc = pw.Document();
    final fontData = await rootBundle.load("assets/fonts/MiSans-Regular.ttf");
    final ttf = pw.Font.ttf(fontData);

    // VVV 1. 添加一个心情的映射表，用于显示中文心情 VVV
    const moodMap = {
      '1': '特别开心', '2': '很开心', '3': '有点开心', '4': '一般',
      '5': '有点伤心', '6': '伤心', '7': '很伤心', '8': '崩溃', '0': '生病',
    };

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final List<pw.MemoryImage> imageWidgets = [];
      if (entry.imagePaths.isNotEmpty) {
        for (var path in entry.imagePaths) {
          final file = File(path);
          if (await file.exists()) {
            final imageBytes = await file.readAsBytes();
            imageWidgets.add(pw.MemoryImage(imageBytes));
          }
        }
      }

      doc.addPage(
        pw.Page(
          theme: pw.ThemeData.withFont(fontFallback: [ttf]),
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            // VVV 2. 全新的、内容更丰富的页面布局 VVV
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // 页面顶部：日期和创建时间
                pw.Header(
                  level: 0,
                  text: '${entry.date.year}年${entry.date.month}月${entry.date.day}日',
                ),
                pw.Text(
                  '创建于: ${DateFormat('yyyy-MM-dd HH:mm').format(entry.creationTime)}',
                  style: pw.TextStyle(color: PdfColors.grey600, font: ttf),
                ),
                pw.SizedBox(height: 10),

                // 元数据区域：心情和位置
                if (entry.mood != null || (entry.address != null && entry.address!.isNotEmpty)) ...[
                  pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey100,
                      borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (entry.mood != null && moodMap.containsKey(entry.mood))
                          pw.Text('心情: ${moodMap[entry.mood]!}', style: pw.TextStyle(font: ttf)),
                        if (entry.address != null && entry.address!.isNotEmpty)
                          pw.Text('位置: ${entry.address!}', style: pw.TextStyle(font: ttf)),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 10),
                ],

                pw.Divider(height: 20),

                // 日记正文
                pw.Text(
                  entry.text.isNotEmpty ? entry.text : '(这篇日记没有写内容)',
                  style: pw.TextStyle(font: ttf, fontSize: 14, height: 1.5),
                ),
                pw.SizedBox(height: 20),

                // 标签区域
                if (entry.tags.isNotEmpty) ...[
                  pw.Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: entry.tags.map((tag) {
                      return pw.Container(
                        decoration: pw.BoxDecoration(
                          color: PdfColors.blueGrey50,
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                        ),
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: pw.Text(tag, style: pw.TextStyle(font: ttf, fontSize: 10, color: PdfColors.blueGrey800)),
                      );
                    }).toList(),
                  ),
                  pw.SizedBox(height: 20),
                ],

                // 图片区域
                if (imageWidgets.isNotEmpty)
                  pw.Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: imageWidgets.map((image) {
                      return pw.Container(
                          width: 150,
                          height: 150,
                          child: pw.Image(image, fit: pw.BoxFit.cover)
                      );
                    }).toList(),
                  )
              ],
            );
          },
        ),
      );
      onProgress?.call(i + 1, entries.length);
    }

    final pdfBytes = await doc.save();
    return await _saveFileWithPicker(pdfBytes, 'my_diary.pdf');
  }

  // VVV 3. 全新的文件保存方法，使用 file_picker VVV
  Future<String?> _saveFileWithPicker(dynamic content, String fileName) async {
    // 1. 获取应用的临时目录
    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/$fileName';
    final file = File(filePath);

    // 2. 将内容写入临时文件
    try {
      if (content is String) {
        await file.writeAsString(content);
      } else if (content is List<int>) {
        await file.writeAsBytes(content);
      }
    } catch (e) {
      print('写入临时文件时出错: $e');
      return null;
    }

    // 3. 调用分享功能
    final xfile = XFile(filePath);
    final result = await Share.shareXFiles([xfile], text: '我的日记备份');

    // 可以在分享成功后返回一个成功的提示
    if (result.status == ShareResultStatus.success) {
      return "分享成功"; // 或者返回文件路径 filePath
    }

    return null;
  }
}
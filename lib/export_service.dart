// 文件: lib/export_service.dart (已适配云端数据模式)

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:http/http.dart' as http; // <--- 新增 http 包导入，用于下载网络图片
import 'diary_service.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

typedef ExportProgressCallback = void Function(int current, int total);

class ExportService {
  final List<DiaryEntry> entries;

  ExportService(this.entries);

  /// 导出为JSON。现在导出的JSON文件将包含图片的URL。
  Future<String?> exportToJson() async {
    final List<Map<String, dynamic>> entryList = [];
    for (int i = 0; i < entries.length; i++) {
      entryList.add(entries[i].toMap());
      // onProgress?.call(i + 1, entries.length); // <--- 移除调用
      await Future.delayed(const Duration(milliseconds: 5));
    }

    final jsonString = jsonEncode(entryList);
    return await _saveFileWithPicker(jsonString, 'my_diary_backup.json');
  }

  /// 导出为PDF。现在会通过网络下载图片来生成PDF。
  Future<String?> exportToPdf() async {
    final doc = pw.Document();
    final fontData = await rootBundle.load("assets/fonts/MiSans-Regular.ttf");
    final ttf = pw.Font.ttf(fontData);
    const moodMap = {
      '1': '特别开心', '2': '很开心', '3': '有点开心', '4': '一般',
      '5': '有点伤心', '6': '伤心', '7': '很伤心', '8': '崩溃', '0': '生病',
    };

    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final List<pw.MemoryImage> imageWidgets = [];

      if (entry.imagePaths.isNotEmpty) {
        for (var imageUrl in entry.imagePaths) {
          try {
            final response = await http.get(Uri.parse(imageUrl));
            if (response.statusCode == 200) {
              imageWidgets.add(pw.MemoryImage(response.bodyBytes));
            }
          } catch (e) {
            print("下载PDF用图片失败: $e");
          }
        }
      }
      // --- 修正结束 ---

      // PDF页面布局的其余部分保持不变
      doc.addPage(
        pw.Page(
          theme: pw.ThemeData.withFont(fontFallback: [ttf]),
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // ... (日期、心情、文本、标签等PDF布局代码保持不变)
                pw.Header(
                  level: 0,
                  text: '${entry.date.year}年${entry.date.month}月${entry.date.day}日',
                ),
                pw.Text(
                  '创建于: ${DateFormat('yyyy-MM-dd HH:mm').format(entry.creationTime)}',
                  style: pw.TextStyle(color: PdfColors.grey600, font: ttf),
                ),
                pw.Divider(height: 20),
                pw.Text(
                  entry.text.isNotEmpty ? entry.text : '(这篇日记没有写内容)',
                  style: pw.TextStyle(font: ttf, fontSize: 14, height: 1.5),
                ),
                pw.SizedBox(height: 20),
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
    }

    final pdfBytes = await doc.save();
    return await _saveFileWithPicker(pdfBytes, 'my_diary.pdf');
  }

  /// 文件保存/分享功能，无需修改。
  Future<String?> _saveFileWithPicker(dynamic content, String fileName) async {
    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/$fileName';
    final file = File(filePath);

    if (content is String) {
      await file.writeAsString(content);
    } else if (content is List<int>) {
      await file.writeAsBytes(content);
    }

    final xfile = XFile(filePath);
    final result = await Share.shareXFiles([xfile], text: '我的日记备份');

    if (result.status == ShareResultStatus.success) {
      return "分享成功";
    }

    return null;
  }
}
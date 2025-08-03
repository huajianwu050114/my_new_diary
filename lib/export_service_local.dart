// file: lib/export_service_local.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

class ExportServiceLocal {

  Future<String> get _imagesPath async {
    final directory = await getApplicationDocumentsDirectory();
    return p.join(directory.path, 'diary_images');
  }

  Future<String> get _dbPath async {
    final dbFolder = await getDatabasesPath();
    return p.join(dbFolder, 'diary.db');
  }

  Future<void> exportToZip(BuildContext context) async {
    final tempDir = await getTemporaryDirectory();
    final archivePath = p.join(tempDir.path, 'MyDiary_Backup_${DateTime.now().millisecondsSinceEpoch}.zip');
    final encoder = ZipFileEncoder();
    encoder.create(archivePath);

    // 1. 添加資料庫文件
    final dbFile = File(await _dbPath);
    if (await dbFile.exists()) {
      encoder.addFile(dbFile);
    }

    // 2. 添加所有圖片文件
    final imagesDir = Directory(await _imagesPath);
    if (await imagesDir.exists()) {
      final files = await imagesDir.list().toList();
      for (var file in files) {
        if (file is File) {
          encoder.addFile(file);
        }
      }
    }

    encoder.close();

    // 3. 分享 .zip 文件
    final xfile = XFile(archivePath);
    await Share.shareXFiles([xfile], text: '我的日記本地備份');
  }

  Future<void> importFromZip(BuildContext context, String zipPath) async {
    final dbFile = File(await _dbPath);
    final imagesDirPath = await _imagesPath;
    final imagesDir = Directory(imagesDirPath);

    // Delete the old images folder to prevent data mixing
    if (await imagesDir.exists()) {
      await imagesDir.delete(recursive: true);
    }
    await imagesDir.create(recursive: true);

    // --- VVV THIS IS THE CORRECTED PART VVV ---
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    // --- ^^^ END OF CORRECTION ^^^ ---

    for (final file in archive) {
      final filename = file.name;
      final data = file.content as List<int>;

      if (filename == 'diary.db') {
        // Restore the database file
        await dbFile.writeAsBytes(data);
      } else {
        // Restore image files, ensuring the path is correct
        final fullPath = p.join(imagesDirPath, p.basename(filename));
        final imageFile = File(fullPath);
        // Make sure the directory exists before writing the file
        await imageFile.parent.create(recursive: true);
        await imageFile.writeAsBytes(data);
      }
    }
  }
}
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../analysis/data/stop_words_store_v2.dart';
import '../../diary/application/ports/diary_image_store_v2.dart';
import '../../diary/domain/repositories/diary_repository_v2.dart';
import '../../festival/domain/festival_repository_v2.dart';
import '../../life_library/domain/life_document_repository_v2.dart';
import '../application/diary_backup_service_v2.dart';
import '../application/diary_pdf_service_v2.dart';

class DataToolsPageV2 extends StatefulWidget {
  const DataToolsPageV2({
    required this.diaryRepository,
    required this.imageStore,
    required this.festivalRepository,
    this.lifeDocumentRepository,
    super.key,
  });

  final DiaryRepositoryV2 diaryRepository;
  final DiaryImageStoreV2 imageStore;
  final FestivalRepositoryV2 festivalRepository;
  final LifeDocumentRepositoryV2? lifeDocumentRepository;

  @override
  State<DataToolsPageV2> createState() => _DataToolsPageV2State();
}

class _DataToolsPageV2State extends State<DataToolsPageV2> {
  bool _busy = false;

  DiaryBackupServiceV2 get _backup => DiaryBackupServiceV2(
    diaryRepository: widget.diaryRepository,
    imageStore: widget.imageStore,
    festivalRepository: widget.festivalRepository,
    stopWordsStore: StopWordsStoreV2(),
    lifeDocumentRepository: widget.lifeDocumentRepository,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导出与备份')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('导出全部日记为 PDF'),
            subtitle: const Text('包含正文、标签、地点和照片'),
            enabled: !_busy,
            onTap: _exportPdf,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: const Text('导出完整 ZIP 备份'),
            subtitle: const Text('包含日记、照片、生活文档、回收站、纪念日和停用词'),
            enabled: !_busy,
            onTap: _exportBackup,
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('从 ZIP 备份导入'),
            subtitle: const Text('相同日记 ID 会更新，不会生成重复日记'),
            enabled: !_busy,
            onTap: _importBackup,
          ),
        ],
      ),
    );
  }

  Future<void> _exportPdf() async {
    await _run(() async {
      final entries = await widget.diaryRepository.watchEntries().first;
      if (entries.isEmpty) throw StateError('没有可导出的日记');
      final bytes = await DiaryPdfServiceV2(
        imageStore: widget.imageStore,
      ).create(entries);
      await _save(
        bytes,
        'MyDiary_${DateTime.now().millisecondsSinceEpoch}.pdf',
        'pdf',
      );
    });
  }

  Future<void> _exportBackup() async {
    await _run(() async {
      final bytes = await _backup.exportZip();
      await _save(
        bytes,
        'MyDiary_Backup_${DateTime.now().millisecondsSinceEpoch}.zip',
        'zip',
      );
    });
  }

  Future<void> _importBackup() async {
    await _run(() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        withData: true,
      );
      if (result == null) return;
      final selected = result.files.single;
      final bytes = selected.bytes ?? await File(selected.path!).readAsBytes();
      final report = await _backup.importZip(bytes);
      _message(
        '已导入 ${report.importedEntries} 篇日记、${report.importedFestivals} 个纪念日',
      );
    });
  }

  Future<void> _save(List<int> bytes, String name, String extension) async {
    final target = await FilePicker.platform.saveFile(
      dialogTitle: '选择保存位置',
      fileName: name,
      type: FileType.custom,
      allowedExtensions: [extension],
    );
    if (target != null) {
      await File(target).writeAsBytes(bytes, flush: true);
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    setState(() => _busy = true);
    try {
      await operation();
    } catch (error) {
      _message('操作失败：$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }
}

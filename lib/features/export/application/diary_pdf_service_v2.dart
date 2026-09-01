import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../diary/application/ports/diary_image_store_v2.dart';
import '../../diary/domain/entities/diary_entry.dart';

class DiaryPdfServiceV2 {
  const DiaryPdfServiceV2({required this.imageStore});

  final DiaryImageStoreV2 imageStore;

  Future<Uint8List> create(List<DiaryEntryV2> entries) async {
    final document = pw.Document();
    final fontData = await rootBundle.load('assets/fonts/MiSans-Regular.ttf');
    final font = pw.Font.ttf(fontData);
    for (final entry in entries) {
      final images = <pw.Widget>[];
      for (final imageId in entry.imageIds) {
        final bytes = await imageStore.read(imageId);
        if (bytes != null) {
          images.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 10),
              child: pw.Image(pw.MemoryImage(bytes), height: 220),
            ),
          );
        }
      }
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(base: font, bold: font),
          build: (_) {
            final date = entry.entryDate.toLocal();
            return [
              pw.Text(
                '${date.year}年${date.month}月${date.day}日 '
                '${entry.mood ?? ''}',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (entry.tags.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 8),
                  child: pw.Text(entry.tags.map((tag) => '#$tag').join('  ')),
                ),
              if (entry.location != null)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 8),
                  child: pw.Text(entry.location!.address ?? '位置记录'),
                ),
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 18),
                child: pw.Text(
                  entry.body,
                  style: const pw.TextStyle(fontSize: 13),
                ),
              ),
              ...images,
            ];
          },
        ),
      );
    }
    return document.save();
  }
}

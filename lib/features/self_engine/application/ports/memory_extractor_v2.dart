import '../../domain/entities/diary_revision_v2.dart';
import '../../domain/entities/memory_extraction_v2.dart';

abstract interface class MemoryExtractorV2 {
  Future<MemoryExtractionBatchV2> extract(DiaryRevisionV2 revision);
}

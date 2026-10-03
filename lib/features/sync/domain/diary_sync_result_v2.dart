class DiarySyncIssueV2 {
  const DiarySyncIssueV2({required this.subject, required this.message});

  final String subject;
  final String message;
}

class DiarySyncResultV2 {
  const DiarySyncResultV2({
    this.imported = 0,
    this.exported = 0,
    this.updated = 0,
    this.skipped = 0,
    this.imagesImported = 0,
    this.imagesExported = 0,
    this.warnings = const [],
    this.errors = const [],
  });

  final int imported;
  final int exported;
  final int updated;
  final int skipped;
  final int imagesImported;
  final int imagesExported;
  final List<DiarySyncIssueV2> warnings;
  final List<DiarySyncIssueV2> errors;

  int get imageCount => imagesImported + imagesExported;
}

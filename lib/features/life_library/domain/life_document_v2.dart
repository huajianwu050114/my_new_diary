enum LifeDocumentTypeV2 { note, recipe, checklist, plan, dailyLog, template }

class LifeDocumentV2 {
  const LifeDocumentV2({
    required this.id,
    required this.space,
    required this.title,
    required this.markdown,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
    this.documentDate,
    this.templateId,
    this.isPinned = false,
    this.deletedAt,
  });

  final String id;
  final String space;
  final String title;
  final String markdown;
  final LifeDocumentTypeV2 type;
  final DateTime? documentDate;
  final String? templateId;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  LifeDocumentV2 copyWith({
    String? space,
    String? title,
    String? markdown,
    LifeDocumentTypeV2? type,
    DateTime? documentDate,
    String? templateId,
    bool? isPinned,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => LifeDocumentV2(
    id: id,
    space: space ?? this.space,
    title: title ?? this.title,
    markdown: markdown ?? this.markdown,
    type: type ?? this.type,
    documentDate: documentDate ?? this.documentDate,
    templateId: templateId ?? this.templateId,
    isPinned: isPinned ?? this.isPinned,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );

  int get checklistTotal => RegExp(
    r'^\s*[-*+]\s+\[[ xX]\]\s+',
    multiLine: true,
  ).allMatches(markdown).length;

  int get checklistCompleted => RegExp(
    r'^\s*[-*+]\s+\[[xX]\]\s+',
    multiLine: true,
  ).allMatches(markdown).length;
}

abstract final class LifeSpacesV2 {
  static const cooking = 'cooking';
  static const habits = 'habits';
  static const values = [cooking, habits];

  static String label(String value) => switch (value) {
    cooking => '厨艺',
    habits => '习惯与计划',
    _ => value,
  };
}

extension LifeDocumentTypeLabelV2 on LifeDocumentTypeV2 {
  String get label => switch (this) {
    LifeDocumentTypeV2.note => '普通笔记',
    LifeDocumentTypeV2.recipe => '菜谱',
    LifeDocumentTypeV2.checklist => '清单',
    LifeDocumentTypeV2.plan => '计划',
    LifeDocumentTypeV2.dailyLog => '每日记录',
    LifeDocumentTypeV2.template => '模板',
  };
}

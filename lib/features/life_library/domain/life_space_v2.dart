class LifeSpaceV2 {
  const LifeSpaceV2({
    required this.id,
    required this.name,
    required this.iconCodePoint,
    required this.colorValue,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.isSystem = false,
  });

  final String id;
  final String name;
  final int iconCodePoint;
  final int colorValue;
  final int sortOrder;
  final bool isSystem;
  final DateTime createdAt;
  final DateTime updatedAt;

  LifeSpaceV2 copyWith({
    String? name,
    int? iconCodePoint,
    int? colorValue,
    int? sortOrder,
    DateTime? updatedAt,
  }) => LifeSpaceV2(
    id: id,
    name: name ?? this.name,
    iconCodePoint: iconCodePoint ?? this.iconCodePoint,
    colorValue: colorValue ?? this.colorValue,
    sortOrder: sortOrder ?? this.sortOrder,
    isSystem: isSystem,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

abstract final class LifeSpaceDefaultsV2 {
  static const inboxId = 'inbox';
  static const inboxName = '收件箱';

  static String legacyName(String id) => switch (id) {
    'cooking' => '厨艺',
    'habits' => '习惯与计划',
    inboxId => inboxName,
    _ => id,
  };
}

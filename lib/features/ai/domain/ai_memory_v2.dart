class AiMemoryV2 {
  const AiMemoryV2({
    required this.id,
    required this.text,
    required this.createdAt,
    this.enabled = true,
  });

  final String id;
  final String text;
  final DateTime createdAt;
  final bool enabled;

  AiMemoryV2 copyWith({String? text, bool? enabled}) => AiMemoryV2(
    id: id,
    text: text ?? this.text,
    createdAt: createdAt,
    enabled: enabled ?? this.enabled,
  );
}

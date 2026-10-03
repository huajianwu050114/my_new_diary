enum SyncLocationKindV2 { filesystem, androidSafTree }

class SyncLocationV2 {
  const SyncLocationV2({
    required this.kind,
    required this.value,
    required this.displayName,
  });

  final SyncLocationKindV2 kind;
  final String value;
  final String displayName;
}

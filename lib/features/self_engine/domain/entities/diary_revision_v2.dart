class DiaryRevisionV2 {
  const DiaryRevisionV2({
    required this.id,
    required this.diaryId,
    required this.revisionNo,
    required this.body,
    required this.sourceHash,
    this.fingerprintVersion = 1,
    required this.entryDate,
    required this.createdAt,
    this.contentDelta,
    this.mood,
    this.tags = const [],
    this.latitude,
    this.longitude,
    this.address,
  });

  final String id;
  final String diaryId;
  final int revisionNo;
  final String body;
  final String? contentDelta;
  final String sourceHash;
  final int fingerprintVersion;
  final DateTime entryDate;
  final String? mood;
  final List<String> tags;
  final double? latitude;
  final double? longitude;
  final String? address;
  final DateTime createdAt;
}

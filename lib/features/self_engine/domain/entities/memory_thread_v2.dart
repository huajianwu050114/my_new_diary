enum MemoryThreadStatusV2 { active, dormant, merged, archived }

class MemoryThreadV2 {
  const MemoryThreadV2({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.firstSeen,
    required this.lastSeen,
    required this.pipelineVersion,
    required this.generation,
    required this.createdAt,
    required this.updatedAt,
    this.mergedIntoId,
  });

  final String id;
  final String title;
  final String description;
  final MemoryThreadStatusV2 status;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final String? mergedIntoId;
  final int pipelineVersion;
  final int generation;
  final DateTime createdAt;
  final DateTime updatedAt;
}

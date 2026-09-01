import 'life_fragment_v2.dart';

class LifeFragmentRevisionV2 {
  const LifeFragmentRevisionV2({
    required this.id,
    required this.fragmentId,
    required this.snapshot,
    required this.createdAt,
  });

  final String id;
  final String fragmentId;
  final LifeFragmentV2 snapshot;
  final DateTime createdAt;
}

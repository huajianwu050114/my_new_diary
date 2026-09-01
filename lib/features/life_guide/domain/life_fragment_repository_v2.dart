import 'life_fragment_v2.dart';
import 'life_fragment_revision_v2.dart';

abstract interface class LifeFragmentRepositoryV2 {
  Stream<List<LifeFragmentV2>> watchFragments({
    LifeFragmentStatusV2? status,
    bool onlyRopes = false,
  });

  Future<LifeFragmentV2?> getById(String id);

  Future<void> save(LifeFragmentV2 fragment);

  Future<void> updateWithRevision(
    LifeFragmentV2 fragment, {
    required LifeFragmentV2 previous,
  });

  Future<List<LifeFragmentRevisionV2>> getRevisions(String fragmentId);

  Future<void> delete(String id);
}

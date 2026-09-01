import 'festival_v2.dart';

abstract interface class FestivalRepositoryV2 {
  Stream<List<CustomFestivalV2>> watchCustomFestivals();

  Future<void> save(CustomFestivalV2 festival);

  Future<void> delete(String id);
}

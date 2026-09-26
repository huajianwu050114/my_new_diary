import 'life_document_v2.dart';
import 'life_space_v2.dart';

abstract interface class LifeDocumentRepositoryV2 {
  Stream<List<LifeDocumentV2>> watchDocuments({String? space});

  Future<List<LifeDocumentV2>> getAllDocuments({bool includeDeleted = false});

  Stream<List<LifeSpaceV2>> watchSpaces();

  Future<LifeDocumentV2?> getById(String id);

  Future<LifeSpaceV2?> getSpaceById(String id);

  Future<void> save(LifeDocumentV2 document);

  Future<void> saveSpace(LifeSpaceV2 space);

  Future<void> delete(String id);

  Future<void> deleteSpace(String id);
}

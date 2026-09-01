import 'life_document_v2.dart';

abstract interface class LifeDocumentRepositoryV2 {
  Stream<List<LifeDocumentV2>> watchDocuments({String? space});

  Future<LifeDocumentV2?> getById(String id);

  Future<void> save(LifeDocumentV2 document);

  Future<void> delete(String id);
}

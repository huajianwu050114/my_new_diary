import 'dart:typed_data';

abstract interface class DiaryImageStoreV2 {
  Future<String> save({required Uint8List bytes, required String extension});

  Future<Uint8List?> read(String imageId);

  Future<void> delete(String imageId);
}

/// Optional capability used by cross-device sync to preserve image IDs.
abstract interface class DiaryImageImportStoreV2 {
  Future<void> import({required String imageId, required Uint8List bytes});
}

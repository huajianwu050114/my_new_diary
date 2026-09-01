import 'dart:typed_data';

abstract interface class DiaryImageStoreV2 {
  Future<String> save({required Uint8List bytes, required String extension});

  Future<Uint8List?> read(String imageId);

  Future<void> delete(String imageId);
}

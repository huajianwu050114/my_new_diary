import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../application/ports/diary_image_store_v2.dart';

class LocalDiaryImageStoreV2 implements DiaryImageStoreV2 {
  LocalDiaryImageStoreV2({Future<Directory> Function()? rootDirectory})
    : _rootDirectory = rootDirectory ?? _defaultRootDirectory;

  final Future<Directory> Function() _rootDirectory;

  @override
  Future<String> save({
    required Uint8List bytes,
    required String extension,
  }) async {
    final directory = await _ensureDirectory();
    final safeExtension = _safeExtension(extension);
    final imageId = '${const Uuid().v4()}.$safeExtension';
    final destination = File(path.join(directory.path, imageId));
    final temporary = File('${destination.path}.tmp');

    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(destination.path);
    return imageId;
  }

  @override
  Future<Uint8List?> read(String imageId) async {
    final file = await _safeFile(imageId);
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<void> delete(String imageId) async {
    final file = await _safeFile(imageId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> _safeFile(String imageId) async {
    if (path.basename(imageId) != imageId) {
      throw ArgumentError.value(imageId, 'imageId', 'Invalid image ID');
    }
    final directory = await _ensureDirectory();
    return File(path.join(directory.path, imageId));
  }

  Future<Directory> _ensureDirectory() async {
    final directory = await _rootDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  String _safeExtension(String extension) {
    final value = extension.toLowerCase().replaceFirst('.', '');
    const supported = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'};
    return supported.contains(value) ? value : 'jpg';
  }

  static Future<Directory> _defaultRootDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(path.join(documents.path, 'diary_v2', 'images'));
  }
}

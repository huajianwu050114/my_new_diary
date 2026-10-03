import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import '../domain/sync_storage_v2.dart';

class FileDiarySyncStoreV2 implements SyncStorageV2 {
  FileDiarySyncStoreV2(Directory selectedRoot)
    : root = Directory(path.join(selectedRoot.path, 'diary-sync'));

  final Directory root;

  Directory get entriesDirectory => Directory(path.join(root.path, 'entries'));
  Directory get imagesDirectory => Directory(path.join(root.path, 'images'));

  Future<void> ensureReady() async {
    await entriesDirectory.create(recursive: true);
    await imagesDirectory.create(recursive: true);
  }

  @override
  Future<bool> isAvailable() async {
    try {
      await ensureReady();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<List<String>> listEntryFiles() async {
    await ensureReady();
    final files = <String>[];
    await for (final entity in entriesDirectory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = path.basename(entity.path);
      if (name.endsWith('.tmp')) continue;
      if (name.contains('.sync-conflict-')) {
        files.add(name);
        continue;
      }
      if (!name.endsWith('.json')) continue;
      files.add(name);
    }
    files.sort();
    return files;
  }

  @override
  Future<Uint8List?> readEntry(String fileName) async {
    _validateLeaf(fileName);
    final file = File(path.join(entriesDirectory.path, fileName));
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<bool> writeEntryAtomic(String fileName, Uint8List bytes) async {
    _validateLeaf(fileName);
    await ensureReady();
    final destination = File(path.join(entriesDirectory.path, fileName));
    return _writeIfChanged(destination, bytes);
  }

  @override
  Future<Uint8List?> readImage(String imageId) async {
    _validateLeaf(imageId);
    final file = File(path.join(imagesDirectory.path, imageId));
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<bool> writeImageAtomic(String imageId, Uint8List bytes) async {
    _validateLeaf(imageId);
    await ensureReady();
    return _writeIfChanged(
      File(path.join(imagesDirectory.path, imageId)),
      bytes,
    );
  }

  Future<bool> _writeIfChanged(File destination, Uint8List bytes) async {
    if (await destination.exists()) {
      final existing = await destination.readAsBytes();
      if (_sameBytes(existing, bytes)) return false;
    }
    final temporary = File('${destination.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
    await temporary.writeAsBytes(bytes, flush: true);
    try {
      await temporary.rename(destination.path);
    } on FileSystemException {
      // Dart's rename cannot replace an existing file on every Windows setup.
      // The old complete file remains authoritative until the new temp file is
      // fully flushed; replacement is therefore never a partial write.
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
    }
    return true;
  }

  bool _sameBytes(Uint8List left, Uint8List right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  void _validateLeaf(String value) {
    if (value.isEmpty || path.basename(value) != value) {
      throw ArgumentError.value(value, 'filename', 'Invalid sync filename');
    }
  }
}

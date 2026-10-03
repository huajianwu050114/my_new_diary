import 'dart:typed_data';

class SyncStorageUnavailableException implements Exception {
  const SyncStorageUnavailableException([
    this.message = 'Sync storage unavailable.',
  ]);

  final String message;

  @override
  String toString() => 'SyncStorageUnavailableException: $message';
}

/// Storage boundary for the versioned diary sync protocol.
///
/// Implementations may use a normal filesystem directory or an Android SAF
/// tree. Reconciliation deliberately knows nothing about paths or content URIs.
abstract interface class SyncStorageV2 {
  Future<bool> isAvailable();

  Future<List<String>> listEntryFiles();

  Future<Uint8List?> readEntry(String fileName);

  /// Writes a complete payload, returning false when identical bytes exist.
  Future<bool> writeEntryAtomic(String fileName, Uint8List bytes);

  Future<Uint8List?> readImage(String imageId);

  /// Writes a complete payload, returning false when identical bytes exist.
  Future<bool> writeImageAtomic(String imageId, Uint8List bytes);
}

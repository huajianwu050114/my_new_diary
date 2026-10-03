import 'package:flutter/services.dart';

import '../domain/sync_storage_v2.dart';

class AndroidSafTreeSelectionV2 {
  const AndroidSafTreeSelectionV2({
    required this.treeUri,
    required this.displayName,
  });

  final String treeUri;
  final String displayName;
}

class AndroidSafBridgeV2 {
  const AndroidSafBridgeV2({
    MethodChannel channel = const MethodChannel(
      'com.huajianwu.shiguangdiary.v2/diary_sync_saf',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<AndroidSafTreeSelectionV2?> pickTree() async {
    final result = await _channel.invokeMapMethod<String, Object?>('pickTree');
    if (result == null) return null;
    return AndroidSafTreeSelectionV2(
      treeUri: result['treeUri']! as String,
      displayName: result['displayName']! as String,
    );
  }

  Future<bool> isAvailable(String treeUri) async {
    return await _channel.invokeMethod<bool>('isAvailable', <String, Object?>{
          'treeUri': treeUri,
        }) ??
        false;
  }

  Future<List<String>> listEntryFiles(String treeUri) async {
    final values = await _channel.invokeListMethod<String>(
      'listEntryFiles',
      <String, Object?>{'treeUri': treeUri},
    );
    return values ?? const [];
  }

  Future<Uint8List?> read(String method, String treeUri, String name) {
    return _channel.invokeMethod<Uint8List>(method, <String, Object?>{
      'treeUri': treeUri,
      'name': name,
    });
  }

  Future<bool> write(
    String method,
    String treeUri,
    String name,
    Uint8List bytes,
  ) async {
    return await _channel.invokeMethod<bool>(method, <String, Object?>{
          'treeUri': treeUri,
          'name': name,
          'bytes': bytes,
        }) ??
        false;
  }
}

class AndroidSafSyncStorageV2 implements SyncStorageV2 {
  AndroidSafSyncStorageV2({
    required this.treeUri,
    AndroidSafBridgeV2 bridge = const AndroidSafBridgeV2(),
  }) : _bridge = bridge {
    if (!treeUri.startsWith('content://')) {
      throw ArgumentError.value(treeUri, 'treeUri', 'Expected a content URI');
    }
  }

  final String treeUri;
  final AndroidSafBridgeV2 _bridge;

  @override
  Future<bool> isAvailable() => _bridge.isAvailable(treeUri);

  @override
  Future<List<String>> listEntryFiles() => _bridge.listEntryFiles(treeUri);

  @override
  Future<Uint8List?> readEntry(String fileName) {
    _validateName(fileName, requireJson: true);
    return _bridge.read('readEntry', treeUri, fileName);
  }

  @override
  Future<bool> writeEntryAtomic(String fileName, Uint8List bytes) {
    _validateName(fileName, requireJson: true);
    return _bridge.write('writeEntry', treeUri, fileName, bytes);
  }

  @override
  Future<Uint8List?> readImage(String imageId) {
    _validateName(imageId);
    return _bridge.read('readImage', treeUri, imageId);
  }

  @override
  Future<bool> writeImageAtomic(String imageId, Uint8List bytes) {
    _validateName(imageId);
    return _bridge.write('writeImage', treeUri, imageId, bytes);
  }

  void _validateName(String value, {bool requireJson = false}) {
    if (value.isEmpty ||
        value == '.' ||
        value == '..' ||
        value.contains('/') ||
        value.contains('\\') ||
        value.contains('://') ||
        (requireJson && !value.endsWith('.json'))) {
      throw ArgumentError.value(value, 'name', 'Unsafe sync file name');
    }
  }
}

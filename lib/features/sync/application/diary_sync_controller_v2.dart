import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/sync_directory_provider_v2.dart';
import '../domain/diary_sync_result_v2.dart';
import '../domain/sync_storage_v2.dart';
import 'diary_sync_service_v2.dart';

class DiarySyncControllerV2 extends ChangeNotifier {
  DiarySyncControllerV2({
    required DiarySyncServiceV2 service,
    required SyncDirectoryProviderV2 directoryProvider,
  }) : _service = service,
       _directoryProvider = directoryProvider;

  final DiarySyncServiceV2 _service;
  final SyncDirectoryProviderV2 _directoryProvider;
  DiarySyncSettingsV2 _settings = const DiarySyncSettingsV2();
  DiarySyncResultV2? _lastResult;
  Object? _lastError;
  bool _loaded = false;
  bool _running = false;
  Future<DiarySyncResultV2?>? _activeSync;

  DiarySyncSettingsV2 get settings => _settings;
  DiarySyncResultV2? get lastResult => _lastResult;
  Object? get lastError => _lastError;
  bool get loaded => _loaded;
  bool get running => _running;
  bool get requiresReauthorization =>
      _lastError is SyncStorageUnavailableException;

  Future<void> load() async {
    _settings = await _directoryProvider.load();
    _loaded = true;
    notifyListeners();
  }

  Future<bool> selectFolder() async {
    final selected = await _directoryProvider.pickLocation();
    if (selected == null) return false;
    final storage = _directoryProvider.storageFor(selected);
    if (!await storage.isAvailable()) {
      throw const SyncStorageUnavailableException(
        'The selected folder is not readable and writable.',
      );
    }
    await _directoryProvider.select(selected);
    _settings = await _directoryProvider.load();
    notifyListeners();
    await synchronize();
    return true;
  }

  Future<DiarySyncResultV2?> synchronize() {
    final active = _activeSync;
    if (active != null) return active;
    final operation = _runSync();
    _activeSync = operation;
    return operation.whenComplete(() => _activeSync = null);
  }

  Future<DiarySyncResultV2?> _runSync() async {
    if (!_loaded) await load();
    final location = _settings.location;
    if (location == null) return null;
    _running = true;
    _lastError = null;
    notifyListeners();
    try {
      final result = await _service.synchronize(
        _directoryProvider.storageFor(location),
      );
      _lastResult = result;
      await _directoryProvider.recordSuccess(DateTime.now());
      _settings = await _directoryProvider.load();
      return result;
    } catch (error) {
      _lastError = error;
      rethrow;
    } finally {
      _running = false;
      notifyListeners();
    }
  }
}

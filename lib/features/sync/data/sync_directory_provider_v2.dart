import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/sync_location_v2.dart';
import '../domain/sync_storage_v2.dart';
import 'android_saf_sync_storage_v2.dart';
import 'file_diary_sync_store_v2.dart';

class DiarySyncSettingsV2 {
  const DiarySyncSettingsV2({this.location, this.lastSuccessfulSync});

  final SyncLocationV2? location;
  final DateTime? lastSuccessfulSync;

  bool get enabled => location != null;
  String? get displayName => location?.displayName;
}

class SyncDirectoryProviderV2 {
  SyncDirectoryProviderV2({
    Future<SharedPreferences> Function()? preferences,
    Future<String?> Function()? pickFilesystemDirectory,
    AndroidSafBridgeV2 androidBridge = const AndroidSafBridgeV2(),
    TargetPlatform Function()? platform,
  }) : _preferences = preferences ?? SharedPreferences.getInstance,
       _pickFilesystemDirectory =
           pickFilesystemDirectory ??
           (() => FilePicker.platform.getDirectoryPath()),
       _androidBridge = androidBridge,
       _platform = platform ?? (() => defaultTargetPlatform);

  static const _kindKey = 'diary_sync_location_kind_v2';
  static const _valueKey = 'diary_sync_location_value_v2';
  static const _displayNameKey = 'diary_sync_location_display_name_v2';
  static const _legacyPathKey = 'diary_sync_selected_path_v2';
  static const _lastSuccessKey = 'diary_sync_last_success_v2';

  final Future<SharedPreferences> Function() _preferences;
  final Future<String?> Function() _pickFilesystemDirectory;
  final AndroidSafBridgeV2 _androidBridge;
  final TargetPlatform Function() _platform;

  Future<DiarySyncSettingsV2> load() async {
    final preferences = await _preferences();
    final last = preferences.getString(_lastSuccessKey);
    final kindName = preferences.getString(_kindKey);
    final value = preferences.getString(_valueKey);
    SyncLocationV2? location;
    if (kindName != null && value != null) {
      SyncLocationKindV2? kind;
      for (final candidate in SyncLocationKindV2.values) {
        if (candidate.name == kindName) kind = candidate;
      }
      if (kind != null) {
        location = SyncLocationV2(
          kind: kind,
          value: value,
          displayName: preferences.getString(_displayNameKey) ?? value,
        );
      }
    } else {
      final legacyPath = preferences.getString(_legacyPathKey);
      if (legacyPath != null && legacyPath.isNotEmpty) {
        location = SyncLocationV2(
          kind: SyncLocationKindV2.filesystem,
          value: legacyPath,
          displayName: legacyPath,
        );
      }
    }
    return DiarySyncSettingsV2(
      location: location,
      lastSuccessfulSync: last == null
          ? null
          : DateTime.tryParse(last)?.toLocal(),
    );
  }

  Future<SyncLocationV2?> pickLocation() async {
    if (_platform() == TargetPlatform.android) {
      final selection = await _androidBridge.pickTree();
      if (selection == null) return null;
      return SyncLocationV2(
        kind: SyncLocationKindV2.androidSafTree,
        value: selection.treeUri,
        displayName: selection.displayName,
      );
    }
    final selected = await _pickFilesystemDirectory();
    if (selected == null || selected.trim().isEmpty) return null;
    return SyncLocationV2(
      kind: SyncLocationKindV2.filesystem,
      value: selected,
      displayName: selected,
    );
  }

  Future<void> select(SyncLocationV2 location) async {
    final preferences = await _preferences();
    await preferences.setString(_kindKey, location.kind.name);
    await preferences.setString(_valueKey, location.value);
    await preferences.setString(_displayNameKey, location.displayName);
    await preferences.remove(_legacyPathKey);
  }

  SyncStorageV2 storageFor(SyncLocationV2 location) {
    return switch (location.kind) {
      SyncLocationKindV2.filesystem => FileDiarySyncStoreV2(
        Directory(location.value),
      ),
      SyncLocationKindV2.androidSafTree => AndroidSafSyncStorageV2(
        treeUri: location.value,
        bridge: _androidBridge,
      ),
    };
  }

  Future<void> recordSuccess(DateTime value) async {
    final preferences = await _preferences();
    await preferences.setString(
      _lastSuccessKey,
      value.toUtc().toIso8601String(),
    );
  }
}

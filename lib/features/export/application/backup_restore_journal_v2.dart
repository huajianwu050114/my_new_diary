import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class BackupRestoreJournalV2 {
  static const _key = 'v2_active_backup_restore';

  Future<BackupRestoreJournalStateV2?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null) return null;
    final value = jsonDecode(raw);
    if (value is! Map) throw const FormatException('Invalid restore journal.');
    return BackupRestoreJournalStateV2.fromJson(
      Map<String, dynamic>.from(value),
    );
  }

  Future<BackupRestoreJournalStateV2> begin(String backupDigest) async {
    final existing = await load();
    if (existing != null) {
      if (existing.backupDigest != backupDigest) {
        throw BackupRestoreConflictV2(
          'Another backup restore is incomplete. Resume that backup first.',
        );
      }
      return existing;
    }
    final state = BackupRestoreJournalStateV2(
      backupDigest: backupDigest,
      imageIds: const {},
    );
    await _write(state);
    return state;
  }

  Future<BackupRestoreJournalStateV2> recordImage(
    BackupRestoreJournalStateV2 state, {
    required String sourceId,
    required String restoredId,
  }) async {
    final updated = BackupRestoreJournalStateV2(
      backupDigest: state.backupDigest,
      imageIds: {...state.imageIds, sourceId: restoredId},
    );
    await _write(updated);
    return updated;
  }

  Future<void> complete(String backupDigest) async {
    final existing = await load();
    if (existing == null) return;
    if (existing.backupDigest != backupDigest) {
      throw BackupRestoreConflictV2('Restore journal digest changed.');
    }
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.remove(_key)) {
      throw StateError('Could not complete the restore journal.');
    }
  }

  Future<void> _write(BackupRestoreJournalStateV2 state) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(_key, jsonEncode(state.toJson()))) {
      throw StateError('Could not persist the restore journal.');
    }
  }
}

class BackupRestoreJournalStateV2 {
  const BackupRestoreJournalStateV2({
    required this.backupDigest,
    required this.imageIds,
  });

  factory BackupRestoreJournalStateV2.fromJson(Map<String, dynamic> value) {
    final imageIds = value['imageIds'];
    if (value['backupDigest'] is! String || imageIds is! Map) {
      throw const FormatException('Invalid restore journal fields.');
    }
    return BackupRestoreJournalStateV2(
      backupDigest: value['backupDigest'] as String,
      imageIds: Map<String, String>.from(imageIds),
    );
  }

  final String backupDigest;
  final Map<String, String> imageIds;

  Map<String, Object?> toJson() => {
    'backupDigest': backupDigest,
    'imageIds': imageIds,
  };
}

class BackupRestoreConflictV2 implements Exception {
  const BackupRestoreConflictV2(this.message);

  final String message;

  @override
  String toString() => 'BackupRestoreConflictV2: $message';
}

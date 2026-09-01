import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalProfileStoreV2 {
  LocalProfileStoreV2({Future<Directory> Function()? profileDirectory})
    : _profileDirectory = profileDirectory ?? _defaultProfileDirectory;

  static const _nicknameKey = 'v2_profile_nickname';

  final Future<Directory> Function() _profileDirectory;

  Future<LocalProfileV2> load() async {
    final preferences = await SharedPreferences.getInstance();
    final avatar = await _avatarFile();
    return LocalProfileV2(
      nickname: preferences.getString(_nicknameKey) ?? '日记主人',
      avatarBytes: await avatar.exists() ? await avatar.readAsBytes() : null,
    );
  }

  Future<void> saveNickname(String nickname) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_nicknameKey, nickname.trim());
  }

  Future<void> saveAvatar(Uint8List bytes) async {
    final avatar = await _avatarFile();
    await avatar.parent.create(recursive: true);
    final temporary = File('${avatar.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(avatar.path);
  }

  Future<void> removeAvatar() async {
    final avatar = await _avatarFile();
    if (await avatar.exists()) {
      await avatar.delete();
    }
  }

  Future<File> _avatarFile() async {
    final directory = await _profileDirectory();
    return File(path.join(directory.path, 'avatar'));
  }

  static Future<Directory> _defaultProfileDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(path.join(documents.path, 'diary_v2', 'profile'));
  }
}

class LocalProfileV2 {
  const LocalProfileV2({required this.nickname, this.avatarBytes});

  final String nickname;
  final Uint8List? avatarBytes;
}

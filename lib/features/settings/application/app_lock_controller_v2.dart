import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import '../data/privacy_settings_store_v2.dart';

class AppLockControllerV2 extends ChangeNotifier {
  AppLockControllerV2({
    LocalAuthentication? authentication,
    PrivacySettingsStoreV2? settingsStore,
  }) : _authentication = authentication ?? LocalAuthentication(),
       _settingsStore = settingsStore ?? PrivacySettingsStoreV2();

  final LocalAuthentication _authentication;
  final PrivacySettingsStoreV2 _settingsStore;

  bool _enabled = false;
  bool _unlocked = true;
  bool _authenticating = false;

  bool get enabled => _enabled;
  bool get unlocked => !_enabled || _unlocked;
  bool get authenticating => _authenticating;

  Future<void> load() async {
    _enabled = (await _settingsStore.load()).appLockEnabled;
    _unlocked = !_enabled;
    notifyListeners();
  }

  Future<bool> canEnable() async {
    try {
      return await _authentication.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> setEnabled(bool enabled) async {
    if (enabled && !await canEnable()) {
      return false;
    }
    _enabled = enabled;
    _unlocked = !enabled;
    await _settingsStore.saveAppLock(enabled);
    notifyListeners();
    if (enabled) {
      return unlock();
    }
    return true;
  }

  void lock() {
    if (_enabled) {
      _unlocked = false;
      notifyListeners();
    }
  }

  Future<bool> unlock() async {
    if (!_enabled || _authenticating) {
      return unlocked;
    }
    _authenticating = true;
    notifyListeners();
    try {
      _unlocked = await _authentication.authenticate(
        localizedReason: '解锁你的日记',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      return _unlocked;
    } catch (_) {
      return false;
    } finally {
      _authenticating = false;
      notifyListeners();
    }
  }
}

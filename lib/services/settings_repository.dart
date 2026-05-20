import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/root_mode.dart';
import '../models/server_config.dart';

/// Keys used for SharedPreferences (non-sensitive settings).
abstract final class _PrefKeys {
  static const String port = 'server_port';
  static const String rootMode = 'server_root_mode';
  static const String username = 'server_username';
}

/// Secure storage key for the FTP password.
const _passwordKey = 'server_password';

/// Thin abstraction over secure key-value storage so the repository can be
/// tested without the Android Keystore (which is unavailable in unit tests).
abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
  Future<void> delete(String key);
}

/// Production implementation backed by [FlutterSecureStorage].
class _FlutterSecureStorageAdapter implements SecureKeyValueStore {
  _FlutterSecureStorageAdapter(this._storage);
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Persists and retrieves [ServerConfig] across app launches.
///
/// - Sensitive data (password) is stored in the Android Keystore via
///   [FlutterSecureStorage]. Never stored in SharedPreferences.
/// - Non-sensitive data (port, rootMode) is stored in [SharedPreferences].
class SettingsRepository {
  SettingsRepository({
    SecureKeyValueStore? secureStore,
    SharedPreferences? prefs,
  })  : _secure = secureStore ??
            _FlutterSecureStorageAdapter(const FlutterSecureStorage()),
        _prefs = prefs;

  final SecureKeyValueStore _secure;
  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Loads the saved [ServerConfig]. Returns [ServerConfig.defaults] if nothing
  /// has been saved yet.
  Future<ServerConfig> loadSettings() async {
    final prefs = await _getPrefs();

    final port = prefs.getInt(_PrefKeys.port) ?? ServerConfig.defaults.port;
    final username =
        prefs.getString(_PrefKeys.username) ?? ServerConfig.defaults.username;
    final rootModeName = prefs.getString(_PrefKeys.rootMode);
    final rootMode = rootModeName != null
        ? RootMode.values.firstWhere(
            (e) => e.name == rootModeName,
            orElse: () => ServerConfig.defaults.rootMode,
          )
        : ServerConfig.defaults.rootMode;

    // Password is loaded from secure storage; null means not yet set.
    final password = await _secure.read(_passwordKey) ?? '';

    return ServerConfig(
      port: port,
      password: password,
      username: username,
      rootMode: rootMode,
    );
  }

  /// Saves [config] to persistent storage.
  ///
  /// Password goes to the secure store; everything else to [SharedPreferences].
  Future<void> saveSettings(ServerConfig config) async {
    final prefs = await _getPrefs();

    await Future.wait([
      prefs.setInt(_PrefKeys.port, config.port),
      prefs.setString(_PrefKeys.username, config.username),
      prefs.setString(_PrefKeys.rootMode, config.rootMode.name),
      _secure.write(_passwordKey, config.password),
    ]);
  }

  /// Clears all persisted settings (useful for testing / factory reset).
  Future<void> clearSettings() async {
    final prefs = await _getPrefs();
    await Future.wait([
      prefs.remove(_PrefKeys.port),
      prefs.remove(_PrefKeys.username),
      prefs.remove(_PrefKeys.rootMode),
      _secure.delete(_passwordKey),
    ]);
  }
}

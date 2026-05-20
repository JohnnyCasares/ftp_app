import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ftp_app/models/root_mode.dart';
import 'package:ftp_app/models/server_config.dart';
import 'package:ftp_app/services/settings_repository.dart';

// ---------------------------------------------------------------------------
// In-memory fake for SecureKeyValueStore — no Android Keystore required.
// ---------------------------------------------------------------------------
class _FakeSecureStore implements SecureKeyValueStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<void> delete(String key) async => _data.remove(key);
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------
SettingsRepository _makeRepo(SharedPreferences prefs) {
  return SettingsRepository(
    secureStore: _FakeSecureStore(),
    prefs: prefs,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsRepository', () {
    late SharedPreferences prefs;
    late SettingsRepository repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      repo = _makeRepo(prefs);
    });

    test('loadSettings returns defaults when nothing is saved', () async {
      final config = await repo.loadSettings();

      expect(config.port, equals(ServerConfig.defaults.port));
      expect(config.username, equals(ServerConfig.defaults.username));
      expect(config.password, equals(''));
      expect(config.rootMode, equals(ServerConfig.defaults.rootMode));
    });

    test('saveSettings then loadSettings round-trips port correctly', () async {
      const config = ServerConfig(port: 5555, password: 'test123');
      await repo.saveSettings(config);

      final loaded = await repo.loadSettings();
      expect(loaded.port, equals(5555));
    });

    test('saveSettings round-trips password via secure store', () async {
      const config = ServerConfig(port: 2121, password: 'super_secret!');
      await repo.saveSettings(config);

      final loaded = await repo.loadSettings();
      expect(loaded.password, equals('super_secret!'));
    });

    test('saveSettings round-trips rootMode', () async {
      const config = ServerConfig(
        port: 2121,
        password: 'pw',
        rootMode: RootMode.virtualRoot,
      );
      await repo.saveSettings(config);

      final loaded = await repo.loadSettings();
      expect(loaded.rootMode, equals(RootMode.virtualRoot));
    });

    test('saveSettings round-trips username (default "ftp")', () async {
      const config = ServerConfig(port: 2121, password: 'pw', username: 'ftp');
      await repo.saveSettings(config);

      final loaded = await repo.loadSettings();
      expect(loaded.username, equals('ftp'));
    });

    test('saveSettings round-trips a custom username', () async {
      const config = ServerConfig(
        port: 2121,
        password: 'hunter2',
        username: 'johnny',
      );
      await repo.saveSettings(config);

      final loaded = await repo.loadSettings();
      expect(loaded.username, equals('johnny'));
    });

    test('username defaults to "ftp" when nothing is saved', () async {
      // No saveSettings call — loadSettings should return the default.
      final config = await repo.loadSettings();
      expect(config.username, equals('ftp'));
    });

    test('saveSettings round-trips empty username string', () async {
      const config = ServerConfig(port: 2121, password: 'pw', username: '');
      await repo.saveSettings(config);

      final loaded = await repo.loadSettings();
      expect(loaded.username, equals(''));
    });

    test('saving empty password is stored and loaded back as empty string',
        () async {
      const config = ServerConfig(port: 2121, password: '');
      await repo.saveSettings(config);

      final loaded = await repo.loadSettings();
      expect(loaded.password, equals(''));
    });

    test('clearSettings resets everything to defaults', () async {
      const config = ServerConfig(
        port: 9999,
        password: 'topsecret',
        rootMode: RootMode.virtualRoot,
      );
      await repo.saveSettings(config);
      await repo.clearSettings();

      final loaded = await repo.loadSettings();
      expect(loaded.port, equals(ServerConfig.defaults.port));
      expect(loaded.password, equals(''));
      expect(loaded.rootMode, equals(ServerConfig.defaults.rootMode));
    });
  });
}

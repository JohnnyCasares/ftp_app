// Integration test: drives the MainScreen start/stop flow with a fake FTP
// engine so the test can run without binding a real TCP socket or requesting
// real Android permissions.
//
// Run on a connected device with:
//   flutter test integration_test/server_start_stop_test.dart
//
// Note: this exercises the same code paths as the Phase 8 widget tests but
// through the full app entry point (MultiProvider, MaterialApp, Navigator),
// which is what `integration_test` is for.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ftp_app/models/server_status.dart';
import 'package:ftp_app/services/network_manager.dart';
import 'package:ftp_app/services/server_controller.dart';
import 'package:ftp_app/services/settings_repository.dart';
import 'package:ftp_app/services/storage_access_service.dart';
import 'package:ftp_app/ui/screens/main_screen.dart';
import 'package:ftp_app/ui/screens/settings_screen.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeNetworkManager extends NetworkManager {
  _FakeNetworkManager(this._ip);
  final String? _ip;
  @override
  Future<String?> getWifiIpAddress() async => _ip;
}

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

class _FakePermissionChecker implements PermissionChecker {
  @override
  Future<PermissionStatus> status() async => PermissionStatus.granted;
  @override
  Future<PermissionStatus> request() async => PermissionStatus.granted;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Start → address shown → Stop → address cleared',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = ServerController(
        networkManager: _FakeNetworkManager('192.168.1.42'),
        storageAccessService: StorageAccessService(
          permissionChecker: _FakePermissionChecker(),
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<SettingsRepository>(
              create: (_) => SettingsRepository(
                secureStore: _FakeSecureStore(),
                prefs: prefs,
              ),
            ),
            Provider<NetworkManager>(
              create: (_) => _FakeNetworkManager('192.168.1.42'),
            ),
            ChangeNotifierProvider<ServerController>.value(value: controller),
          ],
          child: MaterialApp(
            initialRoute: '/',
            routes: {
              '/': (_) => const MainScreen(),
              '/settings': (_) => const SettingsScreen(),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial state: Start button visible, no boundAddress shown.
      expect(find.text('Start'), findsOneWidget);

      // Simulate the engine reaching the "running" state via the test hook
      // (avoids calling FtpEngine, which would try to bind a real socket).
      controller.setStatusForTesting(const ServerStatus(
        state: ServerState.running,
        boundAddress: 'ftp://192.168.1.42:2121',
        rootDescription: 'Internal storage (/storage/emulated/0)',
      ));
      await tester.pump();

      expect(find.text('Stop'), findsOneWidget);
      expect(find.text('ftp://192.168.1.42:2121'), findsOneWidget);

      // Now flip back to stopped and verify the address is gone.
      controller.setStatusForTesting(ServerStatus.stopped);
      await tester.pump();

      expect(find.text('Start'), findsOneWidget);
      expect(find.text('ftp://192.168.1.42:2121'), findsNothing);
    },
  );
}

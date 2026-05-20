import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ftp_app/models/server_status.dart';
import 'package:ftp_app/services/network_manager.dart';
import 'package:ftp_app/services/server_controller.dart';
import 'package:ftp_app/services/settings_repository.dart';
import 'package:ftp_app/services/storage_access_service.dart';
import 'package:ftp_app/ui/screens/main_screen.dart';

// ---------------------------------------------------------------------------
// Fakes — keep widget tests off-device.
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

Future<Widget> _buildApp({
  required ServerController controller,
  String? wifiIp = '192.168.1.42',
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  return MultiProvider(
    providers: [
      Provider<SettingsRepository>(
        create: (_) => SettingsRepository(
          secureStore: _FakeSecureStore(),
          prefs: prefs,
        ),
      ),
      Provider<NetworkManager>(create: (_) => _FakeNetworkManager(wifiIp)),
      ChangeNotifierProvider<ServerController>.value(value: controller),
    ],
    child: const MaterialApp(home: MainScreen()),
  );
}

ServerController _makeController() {
  return ServerController(
    networkManager: _FakeNetworkManager('192.168.1.42'),
    storageAccessService: StorageAccessService(
      permissionChecker: _FakePermissionChecker(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MainScreen', () {
    testWidgets('shows Start button enabled when server is stopped',
        (tester) async {
      final controller = _makeController();
      await tester.pumpWidget(await _buildApp(controller: controller));
      await tester.pump(); // settle async _loadInitialData

      expect(find.text('Start'), findsOneWidget);
      expect(find.text('Stop'), findsNothing);

      final button = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Start'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('switches to Stop button when state changes to running',
        (tester) async {
      final controller = _makeController();
      await tester.pumpWidget(await _buildApp(controller: controller));
      await tester.pump();

      controller.setStatusForTesting(const ServerStatus(
        state: ServerState.running,
        boundAddress: 'ftp://192.168.1.42:2121',
        rootDescription: 'Internal storage (/storage/emulated/0)',
      ));
      await tester.pump();

      expect(find.text('Stop'), findsOneWidget);
      expect(find.text('Start'), findsNothing);
    });

    testWidgets('Address field shows boundAddress when running',
        (tester) async {
      final controller = _makeController();
      await tester.pumpWidget(await _buildApp(controller: controller));
      await tester.pump();

      controller.setStatusForTesting(const ServerStatus(
        state: ServerState.running,
        boundAddress: 'ftp://10.0.0.5:5555',
        rootDescription: 'Internal storage (/storage/emulated/0)',
      ));
      await tester.pump();

      expect(find.text('ftp://10.0.0.5:5555'), findsOneWidget);
    });

    testWidgets('StatusBanner appears only when rootDescription starts with "Virtual root"',
        (tester) async {
      final controller = _makeController();
      await tester.pumpWidget(await _buildApp(controller: controller));
      await tester.pump();

      // Native root — banner should NOT appear.
      controller.setStatusForTesting(const ServerStatus(
        state: ServerState.running,
        boundAddress: 'ftp://192.168.1.42:2121',
        rootDescription: 'Internal storage (/storage/emulated/0)',
      ));
      await tester.pump();
      expect(
        find.textContaining('Full storage access was not granted'),
        findsNothing,
      );

      // Virtual root — banner SHOULD appear.
      controller.setStatusForTesting(const ServerStatus(
        state: ServerState.running,
        boundAddress: 'ftp://192.168.1.42:2121',
        rootDescription: 'Virtual root (DCIM, Pictures, Download)',
      ));
      await tester.pump();
      expect(
        find.textContaining('Full storage access was not granted'),
        findsOneWidget,
      );
    });

    testWidgets('Start button disabled (spinner shown) while starting',
        (tester) async {
      final controller = _makeController();
      await tester.pumpWidget(await _buildApp(controller: controller));
      await tester.pump();

      controller.setStatusForTesting(
        const ServerStatus(state: ServerState.starting),
      );
      await tester.pump();

      // The button child is a CircularProgressIndicator, not text.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Address field falls back to "No Wi-Fi connection" when IP is null',
        (tester) async {
      final controller = ServerController(
        networkManager: _FakeNetworkManager(null),
        storageAccessService: StorageAccessService(
          permissionChecker: _FakePermissionChecker(),
        ),
      );
      await tester.pumpWidget(
        await _buildApp(controller: controller, wifiIp: null),
      );
      await tester.pump();

      expect(find.text('No Wi-Fi connection'), findsOneWidget);
    });
  });
}

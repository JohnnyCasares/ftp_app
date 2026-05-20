import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ftp_app/services/settings_repository.dart';
import 'package:ftp_app/ui/screens/settings_screen.dart';

// ---------------------------------------------------------------------------
// Fakes
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

Future<Widget> _buildApp({SettingsRepository? repo}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final actualRepo =
      repo ?? SettingsRepository(secureStore: _FakeSecureStore(), prefs: prefs);

  return MaterialApp(
    home: Provider<SettingsRepository>(
      create: (_) => actualRepo,
      child: const SettingsScreen(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsScreen', () {
    testWidgets(
      'empty password is valid and does NOT block save (A6 user override)',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final repo = SettingsRepository(
          secureStore: _FakeSecureStore(),
          prefs: prefs,
        );

        await tester.pumpWidget(await _buildApp(repo: repo));
        await tester.pumpAndSettle();

        // Clear the password field (it loads with "" by default — confirm).
        final passwordField = find.widgetWithText(TextFormField, 'Password');
        expect(passwordField, findsOneWidget);
        await tester.enterText(passwordField, '');
        await tester.pump();

        // Press Save — should succeed (no validator error, no SnackBar error).
        await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
        await tester.pump();
        // Wait for the save SnackBar to appear.
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Settings saved'), findsOneWidget);

        // Verify it actually persisted as empty.
        final loaded = await repo.loadSettings();
        expect(loaded.password, equals(''));
      },
    );

    testWidgets('out-of-range port (below 1024) shows an error', (
      tester,
    ) async {
      await tester.pumpWidget(await _buildApp());
      await tester.pumpAndSettle();

      final portField = find.widgetWithText(TextFormField, 'Port');
      await tester.enterText(portField, '80');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pump();

      expect(
        find.text('Port must be 0 (random) or between 1024 and 65535'),
        findsOneWidget,
      );
    });

    testWidgets('out-of-range port (above 65535) shows an error', (
      tester,
    ) async {
      await tester.pumpWidget(await _buildApp());
      await tester.pumpAndSettle();

      final portField = find.widgetWithText(TextFormField, 'Port');
      await tester.enterText(portField, '70000');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pump();

      expect(
        find.text('Port must be 0 (random) or between 1024 and 65535'),
        findsOneWidget,
      );
    });

    testWidgets('valid input (port 2121 + password "hunter2") saves cleanly', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = SettingsRepository(
        secureStore: _FakeSecureStore(),
        prefs: prefs,
      );

      await tester.pumpWidget(await _buildApp(repo: repo));
      await tester.pumpAndSettle();

      // Use index-based lookup: 0=Username, 1=Password, 2=Port.
      // `find.widgetWithText(TextFormField, 'Password')` is flaky when entering
      // text in multiple fields back-to-back because the password field's
      // onChanged triggers a setState that can confuse the next finder.
      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(3));

      await tester.enterText(fields.at(1), 'hunter2');
      await tester.pump();
      await tester.enterText(fields.at(2), '2121');
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Settings saved'), findsOneWidget);

      final loaded = await repo.loadSettings();
      expect(loaded.port, equals(2121));
      expect(loaded.password, equals('hunter2'));
    });

    testWidgets('port "0" (random) is accepted', (tester) async {
      await tester.pumpWidget(await _buildApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Port'), '0');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Port must be 0 (random) or between 1024 and 65535'),
        findsNothing,
      );
    });

    testWidgets('password strength indicator shows "Weak" for < 8 chars', (
      tester,
    ) async {
      await tester.pumpWidget(await _buildApp());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'short',
      );
      await tester.pump();

      expect(find.text('Strength: Weak'), findsOneWidget);
    });

    testWidgets('password strength indicator shows "OK" for >= 8 chars', (
      tester,
    ) async {
      await tester.pumpWidget(await _buildApp());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'longenough',
      );
      await tester.pump();

      expect(find.text('Strength: OK'), findsOneWidget);
    });
  });
}

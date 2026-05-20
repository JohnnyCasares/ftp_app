import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:ftp_app/models/root_mode.dart';
import 'package:ftp_app/services/storage_access_service.dart';

// ---------------------------------------------------------------------------
// Fake [PermissionChecker] so tests run without a real device or Keystore.
// ---------------------------------------------------------------------------
class _FakePermissionChecker implements PermissionChecker {
  _FakePermissionChecker({
    required PermissionStatus statusResult,
    required PermissionStatus requestResult,
  })  : _status = statusResult,
        _requestResult = requestResult;

  final PermissionStatus _status;
  final PermissionStatus _requestResult;

  @override
  Future<PermissionStatus> status() async => _status;

  @override
  Future<PermissionStatus> request() async => _requestResult;
}

StorageAccessService _makeService(PermissionStatus status,
    [PermissionStatus? requestResult]) {
  return StorageAccessService(
    permissionChecker: _FakePermissionChecker(
      statusResult: status,
      requestResult: requestResult ?? status,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageAccessService', () {
    group('requestNativeRootAccess', () {
      test('returns /storage/emulated/0 when permission is granted', () async {
        final service = _makeService(PermissionStatus.granted);
        final result = await service.requestNativeRootAccess();
        expect(result, equals('/storage/emulated/0'));
      });

      test('returns null when permission is denied', () async {
        final service = _makeService(PermissionStatus.denied);
        final result = await service.requestNativeRootAccess();
        expect(result, isNull);
      });

      test('returns null when permission is permanently denied', () async {
        final service = _makeService(PermissionStatus.permanentlyDenied);
        final result = await service.requestNativeRootAccess();
        expect(result, isNull);
      });
    });

    group('determineRootMode — permission granted', () {
      test('returns NATIVE_ROOT mode when permission is granted', () async {
        final service = _makeService(PermissionStatus.granted);
        final result = await service.determineRootMode();
        expect(result.mode, equals(RootMode.nativeRoot));
      });

      test('returns /storage/emulated/0 as nativePath when granted', () async {
        final service = _makeService(PermissionStatus.granted);
        final result = await service.determineRootMode();
        expect(result.nativePath, equals('/storage/emulated/0'));
      });

      test('returns empty virtualPaths when in native-root mode', () async {
        final service = _makeService(PermissionStatus.granted);
        final result = await service.determineRootMode();
        expect(result.virtualPaths, isEmpty);
      });

      test('description includes /storage/emulated/0 when granted', () async {
        final service = _makeService(PermissionStatus.granted);
        final result = await service.determineRootMode();
        expect(result.description, contains('/storage/emulated/0'));
      });
    });

    group('determineRootMode — permission denied', () {
      test('returns VIRTUAL_ROOT mode when permission is denied', () async {
        final service = _makeService(PermissionStatus.denied);
        final result = await service.determineRootMode();
        expect(result.mode, equals(RootMode.virtualRoot));
      });

      test('nativePath is null in virtual-root mode', () async {
        final service = _makeService(PermissionStatus.denied);
        final result = await service.determineRootMode();
        expect(result.nativePath, isNull);
      });

      test('description starts with "Virtual root" when denied', () async {
        final service = _makeService(PermissionStatus.denied);
        final result = await service.determineRootMode();
        expect(result.description, startsWith('Virtual root'));
      });

      // On a real device the directories would exist; in unit tests (host
      // machine) the /storage/emulated/0 paths do not exist, so virtualPaths
      // will be empty.  We verify there is NO crash when no dirs are found.
      test('handles empty virtual root gracefully (no crash)', () async {
        final service = _makeService(PermissionStatus.denied);
        // Should not throw even when no directories are found.
        final result = await service.determineRootMode();
        expect(result.mode, equals(RootMode.virtualRoot));
        // virtualPaths may be empty on the test host — that is acceptable.
        expect(result.virtualPaths, isA<List>());
      });
    });

    group('checkNativeRootPermissionStatus', () {
      test('returns the current status without requesting', () async {
        final service = _makeService(
          PermissionStatus.denied,
          PermissionStatus.granted, // request would return granted, but we should not call it
        );
        final status = await service.checkNativeRootPermissionStatus();
        // Should report denied (the check status), not granted (the request result).
        expect(status, equals(PermissionStatus.denied));
      });
    });
  });
}

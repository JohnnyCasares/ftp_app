import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/root_mode.dart';
import '../models/virtual_path.dart';

/// The concrete native root that Android exposes as "Internal storage" in the
/// Files / My Files app.  DCIM/, Pictures/, Download/, Documents/, etc. all
/// live directly under this path.
const _nativeRoot = '/storage/emulated/0';

/// Well-known public directories to include in the virtual root when
/// MANAGE_EXTERNAL_STORAGE is not granted.
const _virtualDirs = [
  'DCIM',
  'Pictures',
  'Download',
  'Documents',
  'Music',
  'Movies',
];

/// Result of [StorageAccessService.determineRootMode].
///
/// Carries everything [ServerController] needs to call the right
/// [FtpEngine] method without knowing about permission internals.
class StorageRootResult {
  const StorageRootResult.native()
      : mode = RootMode.nativeRoot,
        nativePath = _nativeRoot,
        virtualPaths = const [],
        description = 'Internal storage ($_nativeRoot)';

  const StorageRootResult.virtual(this.virtualPaths, this.description)
      : mode = RootMode.virtualRoot,
        nativePath = null;

  final RootMode mode;

  /// Absolute path to serve in native-root mode (non-null iff [mode] is
  /// [RootMode.nativeRoot]).
  final String? nativePath;

  /// List of virtual paths for virtual-root mode (empty in native-root mode).
  final List<VirtualPath> virtualPaths;

  /// Human-readable description shown in the Directory(ies) card.
  final String description;
}

/// Determines what storage the FTP server can actually access and builds the
/// appropriate root configuration.
///
/// Two modes:
///   1. **NATIVE_ROOT** — MANAGE_EXTERNAL_STORAGE is granted → serve
///      `/storage/emulated/0/` directly (the full "Internal storage" tree the
///      user sees in the phone's file manager).
///   2. **VIRTUAL_ROOT** — permission denied → build a [VirtualFileOperations]
///      mapping from the public directories we CAN read without the special
///      permission (DCIM, Pictures, Downloads, etc.).
class StorageAccessService {
  // Allow injection in tests.
  StorageAccessService({PermissionChecker? permissionChecker})
      : _permissionChecker = permissionChecker ?? const _RealPermissionChecker();

  final PermissionChecker _permissionChecker;

  /// Checks whether MANAGE_EXTERNAL_STORAGE is currently granted WITHOUT
  /// prompting the user.  Returns the status so callers can decide whether
  /// to show an explanation dialog before calling [requestNativeRootAccess].
  Future<PermissionStatus> checkNativeRootPermissionStatus() {
    return _permissionChecker.status();
  }

  /// Requests MANAGE_EXTERNAL_STORAGE.  On Android 11+ this opens the system
  /// Settings screen; the user must toggle the switch and return to the app.
  ///
  /// Returns the granted root path `/storage/emulated/0` if permission was
  /// granted, or `null` if denied.
  Future<String?> requestNativeRootAccess() async {
    final status = await _permissionChecker.request();
    if (status.isGranted) {
      return _nativeRoot;
    }
    return null;
  }

  /// Requests POST_NOTIFICATIONS (Android 13+).  No-op on older versions —
  /// permission_handler returns granted automatically.  The foreground-service
  /// notification will be silently suppressed without this permission.
  Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Requests REQUEST_IGNORE_BATTERY_OPTIMIZATIONS.  Fires the system intent
  /// (handled inside permission_handler) and returns whether the user accepted.
  /// Without this, Android's battery optimizer may kill the foreground service.
  Future<bool> requestBatteryOptimizationExemption() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    return status.isGranted;
  }

  /// True if REQUEST_IGNORE_BATTERY_OPTIMIZATIONS has already been granted, so
  /// callers can skip showing the explanatory dialog on every Start press.
  Future<bool> isBatteryOptimizationIgnored() async {
    return (await Permission.ignoreBatteryOptimizations.status).isGranted;
  }

  /// Builds a virtual root from the public directories that are readable
  /// without MANAGE_EXTERNAL_STORAGE.
  ///
  /// Each directory under `/storage/emulated/0/<name>` is included if it
  /// exists and is a directory.  Inaccessible directories are silently skipped
  /// (the user's device simply may not have a Movies/ folder, for example).
  Future<List<VirtualPath>> buildVirtualRoot() async {
    final result = <VirtualPath>[];

    for (final dirName in _virtualDirs) {
      final realPath = '$_nativeRoot/$dirName';
      final dir = Directory(realPath);

      bool exists = false;
      try {
        exists = dir.existsSync();
      } catch (_) {
        // existsSync can throw on permission denied — treat as non-existent.
      }

      if (exists) {
        result.add(VirtualPath(
          virtualPath: '/$dirName',
          realPath: realPath,
          readable: true,
          writable: true,
        ));
      }
    }

    debugPrint(
        '[StorageAccessService] Virtual root dirs: '
        '${result.map((p) => p.virtualPath).join(', ')}');
    return result;
  }

  /// Top-level entry point called by [ServerController] before starting.
  ///
  /// This method does NOT request permission — callers should have already
  /// shown a dialog and called [requestNativeRootAccess()] if appropriate.
  /// It simply checks the current status and returns the correct root config.
  Future<StorageRootResult> determineRootMode() async {
    final status = await _permissionChecker.status();

    if (status.isGranted) {
      debugPrint('[StorageAccessService] MANAGE_EXTERNAL_STORAGE granted → NATIVE_ROOT');
      return const StorageRootResult.native();
    }

    // Denied — fall back to virtual root.
    debugPrint('[StorageAccessService] MANAGE_EXTERNAL_STORAGE denied → VIRTUAL_ROOT');
    final paths = await buildVirtualRoot();

    if (paths.isEmpty) {
      // Absolute last resort: nothing is readable.  Serve from the app's
      // own external directory so at least the server starts (the user
      // will see an empty tree but can still upload files into it).
      debugPrint(
          '[StorageAccessService] No readable public dirs found — '
          'virtual root will be empty; server will still start.');
    }

    final names = paths.map((p) => p.virtualPath.replaceFirst('/', '')).join(', ');
    final description = paths.isEmpty
        ? 'Virtual root (no readable directories found)'
        : 'Virtual root ($names)';

    return StorageRootResult.virtual(paths, description);
  }
}

// ---------------------------------------------------------------------------
// Abstraction over permission_handler to enable unit testing without Android.
// ---------------------------------------------------------------------------

/// Thin interface over [Permission.manageExternalStorage] so tests can inject
/// a fake without needing a real device.
abstract interface class PermissionChecker {
  Future<PermissionStatus> status();
  Future<PermissionStatus> request();
}

class _RealPermissionChecker implements PermissionChecker {
  const _RealPermissionChecker();

  @override
  Future<PermissionStatus> status() =>
      Permission.manageExternalStorage.status;

  @override
  Future<PermissionStatus> request() =>
      Permission.manageExternalStorage.request();
}

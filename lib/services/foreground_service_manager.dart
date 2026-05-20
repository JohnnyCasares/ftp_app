import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Notification button identifier for the "Stop" action.
const _kStopButtonId = 'btn_stop';

/// Manages starting and stopping the Android foreground service that keeps
/// the FTP server alive when the app is backgrounded.
///
/// The [FlutterForegroundTask] plugin handles the persistent notification and
/// the service lifecycle.  This class is a thin wrapper that:
///   1. Calls [FlutterForegroundTask.init] once (idempotent — safe to call
///      again if notification text needs updating).
///   2. Calls [startService] / [stopService] with the correct parameters.
///
/// ISOLATE CHOICE — Option (b):
///   The FTP engine ([FtpEngine]) runs in the main isolate. The foreground
///   service keeps the Android process alive so the main isolate — and the
///   FTP socket it owns — is not killed by the OS when the app is backgrounded.
///   Option (a) (running FtpEngine inside the TaskHandler isolate) would
///   require all state (ServerConfig, FtpServer socket, VirtualPath list) to
///   be isolate-safe.  FtpServer's ServerSocket is not transferable across
///   isolate boundaries, making option (a) impractical without a full rewrite.
class ForegroundServiceManager {
  /// Initialises the [FlutterForegroundTask] plugin options.
  ///
  /// This must be called once before [startForegroundTask].  Calling it
  /// multiple times is safe — [FlutterForegroundTask.init] simply overwrites
  /// the stored options.
  static void initialize() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ftp_server_channel',
        channelName: 'FTP Server',
        channelDescription: 'Shows while the FTP server is running.',
        // LOW importance / priority: no sound, no heads-up.  The user sees it
        // in the drawer but it does not interrupt them.
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
        playSound: false,
        enableVibration: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // We don't need periodic callbacks — the FTP engine drives itself.
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        // Keep Wi-Fi radio alive so the TCP socket does not time out when the
        // device screen is off.
        allowWifiLock: true,
        // Restart the service automatically if the OS kills it (Android 15
        // dataSync foreground service timeout mitigation).
        allowAutoRestart: true,
      ),
    );
  }

  /// Starts the foreground service notification.
  ///
  /// [address] — the bound FTP URL, e.g. `ftp://192.168.1.42:2121`, displayed
  /// as the notification body so the user can see the address at a glance.
  ///
  /// Also registers the [taskHandler] as the callback so the foreground
  /// service can receive "Stop" button events.  The handler is a top-level
  /// function as required by the Dart isolate rules.
  ///
  /// Returns the [ServiceRequestResult] so the caller can log failures.
  static Future<ServiceRequestResult> startForegroundTask({
    required String address,
  }) async {
    initialize();

    return FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.dataSync],
      notificationTitle: 'FTP Server Running',
      notificationText: address,
      notificationButtons: [
        const NotificationButton(id: _kStopButtonId, text: 'Stop'),
      ],
      // setTaskHandler is called separately via setForegroundTaskHandler() so
      // the top-level entry point is registered in main().
    );
  }

  /// Updates the notification text with a new address (e.g. after the port
  /// changes on restart) without stopping and restarting the service.
  static Future<ServiceRequestResult> updateAddress(String address) {
    return FlutterForegroundTask.updateService(
      notificationTitle: 'FTP Server Running',
      notificationText: address,
    );
  }

  /// Stops the foreground service and dismisses the notification.
  ///
  /// Safe to call even if the service is not running — the plugin returns a
  /// [ServiceRequestFailure] in that case, which we ignore here.
  static Future<void> stopForegroundTask() async {
    final result = await FlutterForegroundTask.stopService();
    if (result is ServiceRequestFailure) {
      // Log but do not rethrow — the server may already be stopped.
      // ignore: avoid_print
      print('[ForegroundServiceManager] stopService: ${result.error}');
    }
  }

  /// The notification button ID for the Stop action.
  ///
  /// Exposed so [FtpTaskHandler] can compare button IDs without a magic string.
  static const String stopButtonId = _kStopButtonId;
}

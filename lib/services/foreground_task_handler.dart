import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'foreground_service_manager.dart';

/// Top-level entry point called by [FlutterForegroundTask.setTaskHandler].
///
/// MUST be a top-level function — Dart isolate rules prohibit using a closure
/// or instance method here because the foreground task runs in a separate
/// isolate context on some platforms / versions.
///
/// Register this in main() via:
///   FlutterForegroundTask.setTaskHandler(FtpTaskHandler());
void startFtpTaskCallback() {
  FlutterForegroundTask.setTaskHandler(FtpTaskHandler());
}

/// [TaskHandler] for the FTP foreground service.
///
/// This handler runs inside the flutter_foreground_task isolate.  Its primary
/// role here is:
///   1. Receive the "Stop" notification button press and forward it to the
///      main isolate via [FlutterForegroundTask.sendDataToMain].
///   2. Handle [onDestroy] (service stopped externally by the OS) by sending
///      a stop signal to the main isolate so [ServerController] can clean up.
///
/// ISOLATE CHOICE — Option (b):
///   The actual [FtpEngine] lives in the main isolate.  The foreground
///   service just keeps the process alive.  Sending a "stop" message via the
///   communication port lets the main isolate call [ServerController.stopServer]
///   through the normal [ChangeNotifier] / Provider flow.
///
///   This avoids the need to pass [FtpServer] / [ServerSocket] across isolate
///   boundaries (which is not possible) and keeps the permission / storage
///   state management in the main isolate where UI code already lives.
class FtpTaskHandler extends TaskHandler {
  // -------------------------------------------------------------------------
  // Messages sent from this handler to the main isolate.
  // -------------------------------------------------------------------------

  /// Message sent when the "Stop" notification button is pressed or the
  /// OS destroys the service.  The main isolate listens for this value via
  /// [FlutterForegroundTask.addTaskDataCallback] and calls stopServer().
  static const String msgStop = 'ftp_stop';

  // -------------------------------------------------------------------------
  // TaskHandler overrides
  // -------------------------------------------------------------------------

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // The FTP engine is already running in the main isolate.
    // Nothing to initialise here — we just log.
    debugPrint('[FtpTaskHandler] onStart — starter: $starter');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // No periodic action needed.  ForegroundTaskEventAction.nothing() means
    // this callback is never invoked.
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // The OS (or the user via "Force stop") terminated the service.
    // Notify the main isolate so it can clean up the FTP engine state.
    debugPrint(
      '[FtpTaskHandler] onDestroy — isTimeout: $isTimeout. '
      'Sending stop signal to main isolate.',
    );
    FlutterForegroundTask.sendDataToMain(msgStop);
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == ForegroundServiceManager.stopButtonId) {
      debugPrint('[FtpTaskHandler] Stop button pressed — signalling main isolate.');
      // Tell the main isolate to stop the server.
      FlutterForegroundTask.sendDataToMain(msgStop);
    }
  }

  @override
  void onNotificationPressed() {
    // Bring the app to the foreground when the notification body is tapped.
    FlutterForegroundTask.launchApp('/');
  }
}

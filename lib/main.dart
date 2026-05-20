import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/network_manager.dart';
import 'services/server_controller.dart';
import 'services/settings_repository.dart';
import 'ui/screens/main_screen.dart';
import 'ui/screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FtpApp());
}

class FtpApp extends StatelessWidget {
  const FtpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SettingsRepository>(
          create: (_) => SettingsRepository(),
        ),
        Provider<NetworkManager>(
          create: (_) => NetworkManager(),
        ),
        // ServerController shares the same NetworkManager instance so Wi-Fi
        // checks inside startServer() are consistent with the UI's IP display.
        ChangeNotifierProxyProvider<NetworkManager, ServerController>(
          create: (ctx) =>
              ServerController(networkManager: ctx.read<NetworkManager>()),
          update: (ctx, nm, prev) => prev ?? ServerController(networkManager: nm),
        ),
      ],
      child: MaterialApp(
        title: 'FTP Server',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
          useMaterial3: true,
        ),
        initialRoute: '/',
        routes: {
          '/': (_) => const MainScreen(),
          '/settings': (_) => const SettingsScreen(),
        },
      ),
    );
  }
}

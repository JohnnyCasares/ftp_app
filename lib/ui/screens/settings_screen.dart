import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/settings_repository.dart';

/// Settings screen: password and port configuration.
///
/// Layout matches DESIGN.md §4.2:
///   - Security section: password field (obscured, show/hide toggle)
///   - Address section: port field (numeric, range validation)
///   - Save button
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _portController = TextEditingController();

  bool _passwordVisible = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    final repo = context.read<SettingsRepository>();
    final config = await repo.loadSettings();
    if (!mounted) return;
    setState(() {
      _usernameController.text = config.username;
      _passwordController.text = config.password;
      _portController.text = config.port.toString();
      _loading = false;
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _portController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  /// Password validator — optional; empty means anonymous access.
  /// No error is ever returned for an empty password (A6 user override 2026-05-19).
  String? _validatePassword(String? value) {
    // Empty is valid — server will start in anonymous mode.
    return null;
  }

  /// Port validator — must be 0 or 1024–65535.
  String? _validatePort(String? value) {
    if (value == null || value.isEmpty) {
      return 'Port must be 0 (random) or between 1024 and 65535';
    }
    final port = int.tryParse(value);
    if (port == null) {
      return 'Port must be a number';
    }
    if (port != 0 && (port < 1024 || port > 65535)) {
      return 'Port must be 0 (random) or between 1024 and 65535';
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final repo = context.read<SettingsRepository>();
    final existing = await repo.loadSettings();

    // Auth rule (Task 1 — 2026-05-19):
    //   - Both blank → anonymous login (username=null, password=null passed to FtpEngine).
    //   - Username blank, password set → use "ftp" as username + the given password.
    //   - Username set, password blank → use the given username + "" password.
    //   - Both set → use exactly what the user typed.
    // We store whatever the user typed (empty string is valid). ServerController
    // interprets empty username as "ftp" when a password is set.
    final updated = existing.copyWith(
      username: _usernameController.text,
      password: _passwordController.text,
      port: int.parse(_portController.text),
    );

    await repo.saveSettings(updated);

    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
    Navigator.pop(context);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final password = _passwordController.text;
    final strengthLabel = password.isEmpty
        ? ''
        : password.length < 8
            ? 'Weak'
            : 'OK';
    final strengthColor = password.length < 8 ? Colors.orange : Colors.green;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ----------------------------------------------------------------
            // Security section
            // ----------------------------------------------------------------
            Text('Security', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),

            // Username field — optional. When blank AND a password is set,
            // the server uses "ftp" as the effective username.
            // When both username and password are blank → anonymous mode.
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username (optional)',
                border: OutlineInputBorder(),
                helperText:
                    'Leave blank to use "ftp" as the default username.',
              ),
              // No validation — blank is valid (anonymous or default username).
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _passwordController,
              obscureText: !_passwordVisible,
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                helperText: 'Leave blank for anonymous access (no password required).',
                suffixIcon: IconButton(
                  icon: Icon(
                    _passwordVisible
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _passwordVisible = !_passwordVisible),
                ),
              ),
              validator: _validatePassword,
              onChanged: (_) => setState(() {}), // refresh strength indicator
            ),

            // Password strength indicator (only when a password is entered)
            if (_passwordController.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  'Strength: $strengthLabel',
                  style: TextStyle(fontSize: 12, color: strengthColor),
                ),
              ),

            const SizedBox(height: 24),

            // ----------------------------------------------------------------
            // Address / Port section
            // ----------------------------------------------------------------
            Text('Address', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextFormField(
              controller: _portController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Port',
                border: OutlineInputBorder(),
                helperText:
                    'Use 0 for a random port assigned by the OS. Default: 2121.',
              ),
              validator: _validatePort,
            ),

            const SizedBox(height: 32),

            // ----------------------------------------------------------------
            // Save button
            // ----------------------------------------------------------------
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

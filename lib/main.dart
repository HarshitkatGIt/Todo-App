import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/add_task_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/settings_screen.dart';
import 'services/github_service.dart';
import 'services/secure_storage.dart';
import 'state/app_state.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Commitment Device',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
      home: const Root(),
    );
  }
}

class Root extends StatefulWidget {
  const Root({super.key, this.storage});

  final CredentialsStore? storage;

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  static const _storageTimeout = Duration(seconds: 10);

  late final CredentialsStore _secure =
      widget.storage ?? SecureStorage();
  bool _checking = true;
  GithubCredentials? _creds;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<T> _withTimeout<T>(Future<T> future) =>
      future.timeout(_storageTimeout, onTimeout: () {
        throw Exception('Reading saved login timed out');
      });

  Future<void> _check() async {
    try {
      final has = await _withTimeout(_secure.hasCredentials());
      if (has) {
        _creds = await _withTimeout(_secure.loadCredentials());
      } else {
        _creds = null;
      }
    } catch (e) {
      _creds = null;
      _notice = 'Could not read saved login ($e). '
          'Please enter your GitHub details again.';
    }
    if (mounted) setState(() => _checking = false);
  }

  void _onSettingsSaved() {
    setState(() {
      _checking = true;
      _notice = null;
    });
    _check().then((_) {
      if (mounted) setState(() => _checking = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_creds == null) {
      return SettingsScreen(onSaved: _onSettingsSaved, notice: _notice);
    }
    final service = GithubApiService(
      owner: _creds!.owner,
      repo: _creds!.repo,
      token: _creds!.token,
    );
    return ChangeNotifierProvider(
      create: (ctx) {
        final app = AppState(github: service);
        app.refresh();
        return app;
      },
      child: const MainTabs(),
    );
  }
}

class MainTabs extends StatefulWidget {
  const MainTabs({super.key});

  @override
  State<MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<MainTabs> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const DashboardScreen(),
          AddTaskScreen(onDone: () => setState(() => _index = 0)),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list), label: 'Tasks'),
          NavigationDestination(icon: Icon(Icons.add), label: 'Add'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

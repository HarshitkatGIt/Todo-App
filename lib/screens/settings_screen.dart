import 'package:flutter/material.dart';

import '../services/github_service.dart';
import '../services/secure_storage.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onSaved, this.notice});

  final VoidCallback? onSaved;
  final String? notice;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _owner = TextEditingController();
  final _repo = TextEditingController();
  final _token = TextEditingController();
  final _secure = SecureStorage();
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final creds = await _secure.loadCredentials();
    _owner.text = creds.owner;
    _repo.text = creds.repo;
    _token.text = creds.token;
  }

  Future<void> _save() async {
    await _secure.saveCredentials(
      owner: _owner.text.trim(),
      repo: _repo.text.trim(),
      token: _token.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved')),
      );
      widget.onSaved?.call();
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final service = GithubApiService(
        owner: _owner.text.trim(),
        repo: _repo.text.trim(),
        token: _token.text.trim(),
      );
      await service.getState();
      _testResult = 'Connection OK - state.json found';
    } catch (e) {
      _testResult = 'Error: $e';
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GitHub Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            if (widget.notice != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.orange.shade100,
                child: Text(
                  widget.notice!,
                  style: const TextStyle(color: Colors.black87),
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Text(
              'Connect to the private repo that holds state.json. '
              'Use a fine-grained PAT scoped to this repo with contents: read & write.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _owner,
              decoration: const InputDecoration(
                labelText: 'GitHub owner (username)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _repo,
              decoration: const InputDecoration(
                labelText: 'Repo name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _token,
              decoration: const InputDecoration(
                labelText: 'Personal Access Token',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _testing ? null : _test,
                  child: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Test connection'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ],
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 12),
              Text(_testResult!),
            ],
          ],
        ),
      ),
    );
  }
}

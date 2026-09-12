import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

class GithubState {
  final String content;
  final String sha;

  GithubState({required this.content, required this.sha});
}

class ConflictException implements Exception {
  @override
  String toString() => 'ConflictException: state.json was modified elsewhere';
}

abstract class GithubService {
  Future<GithubState> getState();
  Future<void> putState(String rawJson, String sha);
}

class GithubApiService implements GithubService {
  GithubApiService({
    required this.owner,
    required this.repo,
    required this.token,
    http.Client? client,
    this.callTimeout = _defaultCallTimeout,
  }) : _client = client ?? http.Client();

  final String owner;
  final String repo;
  final String token;
  final Duration callTimeout;
  final http.Client _client;

  static const _defaultCallTimeout = Duration(seconds: 15);

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
      };

  static const _base = 'https://api.github.com';

  String get _url => '$_base/repos/$owner/$repo/contents/state.json';

  @override
  Future<GithubState> getState() async {
    final resp = await _client
        .get(Uri.parse(_url), headers: _headers)
        .timeout(callTimeout);
    if (resp.statusCode == 200) {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final raw = json['content'] as String;
      final cleaned = raw.replaceAll(RegExp(r'\s+'), '');
      final content = utf8.decode(base64Decode(cleaned));
      return GithubState(content: content, sha: json['sha'] as String);
    } else if (resp.statusCode == 404) {
      throw Exception('state.json not found in $owner/$repo');
    } else if (resp.statusCode == 401) {
      throw Exception('GitHub auth failed (401) - check your token');
    } else {
      throw Exception('GitHub get failed: ${resp.statusCode}');
    }
  }

  @override
  Future<void> putState(String rawJson, String sha) async {
    final encoded = base64Encode(utf8.encode(rawJson));
    final body = jsonEncode({
      'message': 'update state.json via app',
      'content': encoded,
      'sha': sha,
    });
    final resp = await _client
        .put(
          Uri.parse(_url),
          headers: _headers,
          body: body,
        )
        .timeout(callTimeout);
    if (resp.statusCode == 200 || resp.statusCode == 201) {
      return;
    } else if (resp.statusCode == 409) {
      throw ConflictException();
    } else if (resp.statusCode == 401) {
      throw Exception('GitHub auth failed (401) - check your token');
    } else {
      throw Exception('GitHub put failed: ${resp.statusCode}');
    }
  }
}

String generateId() {
  final rand = Random();
  return 'task-${DateTime.now().millisecondsSinceEpoch}-${rand.nextInt(10000)}';
}

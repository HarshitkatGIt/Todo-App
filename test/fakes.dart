import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fnb_commitment/services/github_service.dart';
import 'package:fnb_commitment/services/secure_storage.dart';

class FakeGithub extends GithubService {
  FakeGithub({
    this.initialContent,
    this.initialSha = 'SHA0',
    this.failPutWith409First = false,
  });

  String? initialContent;
  String initialSha;
  String? lastPutContent;
  String? lastPutSha;
  int getStateCalls = 0;
  int putStateCalls = 0;
  bool failPutWith409First;

  @override
  Future<GithubState> getState() async {
    getStateCalls++;
    if (initialContent == null) throw Exception('no content');
    final sha = getStateCalls == 1 ? initialSha : (lastPutSha ?? initialSha);
    return GithubState(content: initialContent!, sha: sha);
  }

  @override
  Future<void> putState(String rawJson, String sha) async {
    putStateCalls++;
    if (failPutWith409First && putStateCalls == 1) throw ConflictException();
    lastPutContent = rawJson;
    lastPutSha = sha;
  }
}

void setupTestMocks() {
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});
}

class FakeCredentialStore implements CredentialsStore {
  FakeCredentialStore({
    this.credentials,
    this.throwOnRead = false,
    this.hangOnRead = false,
  });

  GithubCredentials? credentials;
  bool throwOnRead;
  bool hangOnRead;
  int hasCalls = 0;

  @override
  Future<bool> hasCredentials() async {
    hasCalls++;
    if (hangOnRead) return Completer<bool>().future;
    if (throwOnRead) throw Exception('keystore corrupted');
    return credentials != null;
  }

  @override
  Future<GithubCredentials> loadCredentials() async {
    if (hangOnRead) return Completer<GithubCredentials>().future;
    if (throwOnRead) throw Exception('keystore corrupted');
    final c = credentials;
    if (c == null) throw Exception('no credentials');
    return c;
  }
}

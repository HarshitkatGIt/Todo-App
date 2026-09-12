import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class CredentialsStore {
  Future<bool> hasCredentials();
  Future<GithubCredentials> loadCredentials();
}

class SecureStorage implements CredentialsStore {
  static const _storage = FlutterSecureStorage();

  static const _ownerKey = 'github_owner';
  static const _repoKey = 'github_repo';
  static const _tokenKey = 'github_token';

  Future<void> saveCredentials({
    required String owner,
    required String repo,
    required String token,
  }) async {
    await _storage.write(key: _ownerKey, value: owner);
    await _storage.write(key: _repoKey, value: repo);
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> clearCredentials() async {
    await _storage.delete(key: _ownerKey);
    await _storage.delete(key: _repoKey);
    await _storage.delete(key: _tokenKey);
  }

  @override
  Future<bool> hasCredentials() async {
    final token = await _storage.read(key: _tokenKey);
    final owner = await _storage.read(key: _ownerKey);
    final repo = await _storage.read(key: _repoKey);
    return token != null && token.isNotEmpty && owner != null && repo != null;
  }

  @override
  Future<GithubCredentials> loadCredentials() async {
    return GithubCredentials(
      owner: (await _storage.read(key: _ownerKey)) ?? '',
      repo: (await _storage.read(key: _repoKey)) ?? '',
      token: (await _storage.read(key: _tokenKey)) ?? '',
    );
  }
}

class GithubCredentials {
  final String owner;
  final String repo;
  final String token;

  GithubCredentials({
    required this.owner,
    required this.repo,
    required this.token,
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fnb_commitment/services/github_service.dart';

String _enc(String s) => base64Encode(utf8.encode(s));

void main() {
  const owner = 'o';
  const repo = 'r';
  const token = 't';

  const sampleContent = '{"penalty":{"month":"2026-08","miss_count":0},"tasks":[]}';
  final okBody = jsonEncode({
    'content': _enc(sampleContent),
    'sha': 'SHA123',
  });

  test('getState decodes base64 content and sha, sends auth header', () async {
    final client = MockClient((req) async {
      expect(req.headers['Authorization'], 'Bearer $token');
      expect(req.url.path, '/repos/o/r/contents/state.json');
      expect(req.method, 'GET');
      return http.Response(okBody, 200);
    });
    final s = GithubApiService(owner: owner, repo: repo, token: token, client: client);
    final st = await s.getState();
    expect(st.content, sampleContent);
    expect(st.sha, 'SHA123');
  });

  test('getState strips GitHub newline padding from base64 content', () async {
    final padded = _enc(sampleContent).replaceAllMapped(
      RegExp('.{1,60}'),
      (m) => '${m.group(0)!}\n',
    );
    final body = jsonEncode({'content': padded, 'sha': 'SHA9'});
    final client = MockClient((_) async => http.Response(body, 200));
    final s = GithubApiService(owner: owner, repo: repo, token: token, client: client);
    final st = await s.getState();
    expect(st.content, sampleContent);
    expect(st.sha, 'SHA9');
  });

  test('getState 404 throws not-found error', () async {
    final client = MockClient((_) async => http.Response('', 404));
    final s = GithubApiService(owner: owner, repo: repo, token: token, client: client);
    expect(
      () => s.getState(),
      throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('not found'))),
    );
  });

  test('getState 401 throws auth error', () async {
    final client = MockClient((_) async => http.Response('', 401));
    final s = GithubApiService(owner: owner, repo: repo, token: token, client: client);
    expect(
      () => s.getState(),
      throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('auth'))),
    );
  });

  test('putState sends base64 body, sha and method PUT', () async {
    final client = MockClient((req) async {
      expect(req.method, 'PUT');
      final b = jsonDecode(req.body) as Map<String, dynamic>;
      expect(b['sha'], 'SHA123');
      expect(b['message'], contains('update state.json'));
      final decoded = utf8.decode(base64Decode(b['content'] as String));
      expect(decoded, sampleContent);
      return http.Response('', 200);
    });
    final s = GithubApiService(owner: owner, repo: repo, token: token, client: client);
    await s.putState(sampleContent, 'SHA123');
  });

  test('putState 409 throws ConflictException', () async {
    final client = MockClient((_) async => http.Response('', 409));
    final s = GithubApiService(owner: owner, repo: repo, token: token, client: client);
    expect(() => s.putState(sampleContent, 'x'), throwsA(isA<ConflictException>()));
  });

  test('getState times out when the request never completes', () async {
    final client = MockClient((_) => Completer<http.Response>().future);
    final s = GithubApiService(
      owner: owner,
      repo: repo,
      token: token,
      client: client,
      callTimeout: const Duration(milliseconds: 50),
    );
    await expectLater(s.getState(), throwsA(isA<TimeoutException>()));
  });

  test('putState times out when the request never completes', () async {
    final client = MockClient((_) => Completer<http.Response>().future);
    final s = GithubApiService(
      owner: owner,
      repo: repo,
      token: token,
      client: client,
      callTimeout: const Duration(milliseconds: 50),
    );
    await expectLater(
      s.putState(sampleContent, 'x'),
      throwsA(isA<TimeoutException>()),
    );
  });
}

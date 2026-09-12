import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fnb_commitment/models/task.dart';
import 'package:fnb_commitment/state/app_state.dart';

import 'fakes.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('refresh populates tasks, missCount and nextPenalty', () async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 2},
        'tasks': [
          {
            'id': 'a',
            'description': 'A',
            'type': 'normal',
            'deadline': '2099-01-01T10:00:00+05:30',
            'status': 'pending',
          }
        ],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();
    expect(app.tasks.length, 1);
    expect(app.missCount, 2);
    expect(app.nextPenalty, 20);
    expect(app.offline, isFalse);
  });

  test('markDone on a normal task deletes it', () async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 'a',
            'description': 'A',
            'type': 'normal',
            'deadline': '2099-01-01T10:00:00+05:30',
            'status': 'pending',
          }
        ],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();
    await app.markDone(app.tasks.first);
    final out = jsonDecode(fake.lastPutContent!) as Map<String, dynamic>;
    expect((out['tasks'] as List).isEmpty, isTrue);
    expect(fake.putStateCalls, 1);
  });

  test('markDone on a daily task advances deadline +24h and adds no status', () async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 'b',
            'description': 'B',
            'type': 'daily',
            'deadline': '2026-08-24T09:00:00+05:30',
          }
        ],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();
    await app.markDone(app.tasks.first);
    final out = jsonDecode(fake.lastPutContent!) as Map<String, dynamic>;
    final t = (out['tasks'] as List).first as Map<String, dynamic>;
    expect(t['deadline'], '2026-08-25T09:00:00+05:30');
    expect(t.containsKey('status'), isFalse);
  });

  test('addTask appends to tasks', () async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();
    await app.addTask(
      Task(
        id: 'new',
        description: 'N',
        type: 'normal',
        deadline: '2099-01-01T10:00:00+05:30',
        status: 'pending',
      ),
    );
    final out = jsonDecode(fake.lastPutContent!) as Map<String, dynamic>;
    expect((out['tasks'] as List).length, 1);
  });

  test('updateTask rewrites the existing entry by id, keeping id and status',
      () async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 'a',
            'description': 'A',
            'type': 'normal',
            'deadline': '2099-01-01T10:00:00+05:30',
            'status': 'pending',
          }
        ],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();
    await app.updateTask(Task(
      id: app.tasks.first.id,
      description: 'A edited',
      type: 'normal',
      deadline: '2099-02-02T11:30:00+05:30',
      status: app.tasks.first.status,
    ));
    final out = jsonDecode(fake.lastPutContent!) as Map<String, dynamic>;
    final list = out['tasks'] as List;
    expect(list.length, 1);
    final t = list.first as Map<String, dynamic>;
    expect(t['id'], 'a');
    expect(t['description'], 'A edited');
    expect(t['deadline'], '2099-02-02T11:30:00+05:30');
    expect(t['status'], 'pending');
    expect(app.tasks.first.description, 'A edited');
  });

  test('updateTask on a daily task replaces deadline and keeps no status',
      () async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 'b',
            'description': 'B',
            'type': 'daily',
            'deadline': '2026-08-24T09:00:00+05:30',
          }
        ],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();
    await app.updateTask(Task(
      id: 'b',
      description: 'B edited',
      type: 'daily',
      deadline: '2026-08-25T18:45:00+05:30',
    ));
    final out = jsonDecode(fake.lastPutContent!) as Map<String, dynamic>;
    final t = (out['tasks'] as List).first as Map<String, dynamic>;
    expect(t['type'], 'daily');
    expect(t['deadline'], '2026-08-25T18:45:00+05:30');
    expect(t.containsKey('status'), isFalse);
  });

  test('updateTask for a missing id leaves state unchanged', () async {
    final original = jsonEncode({
      'penalty': {'month': '2026-08', 'miss_count': 0},
      'tasks': [
        {
          'id': 'a',
          'description': 'A',
          'type': 'normal',
          'deadline': '2099-01-01T10:00:00+05:30',
          'status': 'pending',
        }
      ],
    });
    final fake = FakeGithub(initialContent: original);
    final app = AppState(github: fake);
    await app.refresh();
    await app.updateTask(Task(
      id: 'ghost',
      description: 'G',
      type: 'normal',
      deadline: '2099-01-01T10:00:00+05:30',
      status: 'pending',
    ));
    final out = jsonDecode(fake.lastPutContent!) as Map<String, dynamic>;
    expect(jsonEncode(out), jsonEncode(jsonDecode(original)));
    expect(app.tasks.length, 1);
  });

  test('deleteTask removes the entry from JSON and memory', () async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 'a',
            'description': 'A',
            'type': 'normal',
            'deadline': '2099-01-01T10:00:00+05:30',
            'status': 'pending',
          },
          {
            'id': 'b',
            'description': 'B',
            'type': 'daily',
            'deadline': '2026-08-24T09:00:00+05:30',
          }
        ],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();
    await app.deleteTask('b');
    final out = jsonDecode(fake.lastPutContent!) as Map<String, dynamic>;
    final list = out['tasks'] as List;
    expect(list.length, 1);
    expect((list.first as Map<String, dynamic>)['id'], 'a');
    expect(app.tasks.map((t) => t.id), ['a']);
  });

  test('edited state survives refresh round-trip via cache-free refetch',
      () async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 'b',
            'description': 'B',
            'type': 'daily',
            'deadline': '2026-08-24T09:00:00+05:30',
          }
        ],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();
    await app.updateTask(Task(
      id: 'b',
      description: 'B edited',
      type: 'daily',
      deadline: '2026-08-25T07:15:00+05:30',
    ));
    // Simulate the server now serving what we PUT.
    fake.initialContent = fake.lastPutContent;
    await app.refresh();
    expect(app.tasks.length, 1);
    expect(app.tasks.first.description, 'B edited');
    expect(app.tasks.first.deadline, '2026-08-25T07:15:00+05:30');
    expect(app.tasks.first.isDaily, isTrue);
  });

  test('409 conflict triggers one refetch + retry (put called twice)', () async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 'a',
            'description': 'A',
            'type': 'normal',
            'deadline': '2099-01-01T10:00:00+05:30',
            'status': 'pending',
          }
        ],
      }),
      failPutWith409First: true,
    );
    final app = AppState(github: fake);
    await app.refresh();
    await app.markDone(app.tasks.first);
    expect(fake.putStateCalls, 2);
    final out = jsonDecode(fake.lastPutContent!) as Map<String, dynamic>;
    expect((out['tasks'] as List).isEmpty, isTrue);
  });
}

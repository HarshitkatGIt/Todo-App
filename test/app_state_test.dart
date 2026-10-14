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

  test('refresh populates tasks, missCount and nextPenalty (capped at 20)', () async {
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
    // Formula: (5 * (2 + 1)) = 15
    expect(app.nextPenalty, 15);
    expect(app.crisisMode, isFalse);
    expect(app.offline, isFalse);
  });

  test('penalty progression 5 -> 10 -> 15 -> 20 max', () async {
    for (final (miss, expected) in [(0, 5), (1, 10), (2, 15), (3, 20), (4, 20), (10, 20)]) {
      final fake = FakeGithub(
        initialContent: jsonEncode({
          'penalty': {'month': '2026-08', 'miss_count': miss},
          'tasks': [],
        }),
      );
      final app = AppState(github: fake);
      await app.refresh();
      expect(app.nextPenalty, expected, reason: 'For miss_count $miss');
    }
  });

  test('crisis mode caps nextPenalty at 5 regardless of missCount', () async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'crisis_mode': true,
        'penalty': {'month': '2026-08', 'miss_count': 3},
        'tasks': [],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();
    expect(app.crisisMode, isTrue);
    expect(app.nextPenalty, 5);
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

  test('updateTask only changes description, not deadline or status, and sends no notice',
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
    // Attempting to pass a new deadline
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
    // Deadline must remain the original deadline
    expect(t['deadline'], '2099-01-01T10:00:00+05:30');
    expect(t['status'], 'pending');
    expect(app.tasks.first.description, 'A edited');

    // No notification sent for edit
    expect(out.containsKey('pending_notifications'), isFalse);
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

  test('deleteDailyTask deletes daily task and queues Rs.20 penalty', () async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 'a',
            'description': 'Normal A',
            'type': 'normal',
            'deadline': '2099-01-01T10:00:00+05:30',
            'status': 'pending',
          },
          {
            'id': 'b',
            'description': 'Daily B',
            'type': 'daily',
            'deadline': '2026-08-24T09:00:00+05:30',
          }
        ],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();
    final dailyTask = app.tasks.firstWhere((t) => t.id == 'b');
    await app.deleteDailyTask(dailyTask);

    final out = jsonDecode(fake.lastPutContent!) as Map<String, dynamic>;
    final list = out['tasks'] as List;
    expect(list.length, 1);
    expect((list.first as Map<String, dynamic>)['id'], 'a');
    expect(app.tasks.map((t) => t.id), ['a']);

    // Check penalty notice
    final notices = out['pending_notifications'] as List<dynamic>;
    expect(notices.length, 1);
    final notice = notices.first as Map<String, dynamic>;
    expect(notice['type'], 'penalty');
    expect(notice['amount'], 20);
    expect(notice['reason'], contains('Daily B'));
  });

  test('deleteDailyTask throws ArgumentError for non-daily task', () async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 'a',
            'description': 'Normal A',
            'type': 'normal',
            'deadline': '2099-01-01T10:00:00+05:30',
            'status': 'pending',
          }
        ],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();
    final normalTask = app.tasks.first;
    expect(() => app.deleteDailyTask(normalTask), throwsArgumentError);
  });

  test('activateCrisisMode deletes trivial tasks, sets flag, and queues Rs.20 penalty', () async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 2},
        'tasks': [
          {
            'id': 'n1',
            'description': 'Normal Task',
            'type': 'normal',
            'deadline': '2099-01-01T10:00:00+05:30',
            'status': 'pending',
          },
          {
            'id': 't1',
            'description': 'Trivial Task',
            'type': 'trivial',
            'deadline': '2026-08-24T18:00:00+05:30',
            'status': 'pending',
          }
        ],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();
    expect(app.tasks.length, 2);
    expect(app.nextPenalty, 15);

    await app.activateCrisisMode();

    expect(app.crisisMode, isTrue);
    expect(app.tasks.length, 1);
    expect(app.tasks.first.id, 'n1');
    expect(app.nextPenalty, 5);

    final out = jsonDecode(fake.lastPutContent!) as Map<String, dynamic>;
    expect(out['crisis_mode'], isTrue);
    final tasks = out['tasks'] as List;
    expect(tasks.length, 1);
    expect(tasks.first['id'], 'n1');

    final notices = out['pending_notifications'] as List<dynamic>;
    expect(notices.length, 1);
    final notice = notices.first as Map<String, dynamic>;
    expect(notice['type'], 'penalty');
    expect(notice['amount'], 20);
    expect(notice['reason'], contains('Crisis Mode activated'));
  });

  test('deactivateCrisisMode sets flag false and costs nothing (no penalty notice)', () async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'crisis_mode': true,
        'penalty': {'month': '2026-08', 'miss_count': 2},
        'tasks': [
          {
            'id': 'n1',
            'description': 'Normal Task',
            'type': 'normal',
            'deadline': '2099-01-01T10:00:00+05:30',
            'status': 'pending',
          }
        ],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();
    expect(app.crisisMode, isTrue);
    expect(app.nextPenalty, 5);

    await app.deactivateCrisisMode();

    expect(app.crisisMode, isFalse);
    expect(app.nextPenalty, 15);

    final out = jsonDecode(fake.lastPutContent!) as Map<String, dynamic>;
    expect(out['crisis_mode'], isFalse);
    expect(out.containsKey('pending_notifications'), isFalse);
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

  test('tasks are sorted by deadline ascending (soonest first)', () async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 't3',
            'description': 'Late',
            'type': 'normal',
            'deadline': '2099-01-03T10:00:00+05:30',
            'status': 'pending',
          },
          {
            'id': 't1',
            'description': 'Soonest',
            'type': 'normal',
            'deadline': '2099-01-01T10:00:00+05:30',
            'status': 'pending',
          },
          {
            'id': 't2',
            'description': 'Middle',
            'type': 'normal',
            'deadline': '2099-01-02T10:00:00+05:30',
            'status': 'pending',
          },
        ],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();
    expect(app.tasks.map((t) => t.id).toList(), ['t1', 't2', 't3']);
  });

  test('markDone on penalty task advances deadline +24h and keeps task', () async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 'p1',
            'description': 'Dont ruminate',
            'type': 'penalty',
            'deadline': '2026-08-24T23:59:00+05:30',
          }
        ],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();
    await app.markDone(app.tasks.first);
    final out = jsonDecode(fake.lastPutContent!) as Map<String, dynamic>;
    final t = (out['tasks'] as List).first as Map<String, dynamic>;
    expect(t['deadline'], '2026-08-25T23:59:00+05:30');
    expect(t['type'], 'penalty');
  });

  test('deletePenaltyTask removes penalty task with no fee (Rs. 0)', () async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 'p1',
            'description': 'Dont ruminate',
            'type': 'penalty',
            'deadline': '2026-08-24T23:59:00+05:30',
          }
        ],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();
    await app.deletePenaltyTask(app.tasks.first);
    final out = jsonDecode(fake.lastPutContent!) as Map<String, dynamic>;
    expect((out['tasks'] as List).isEmpty, isTrue);
    expect(out.containsKey('pending_notifications'), isFalse);
  });

  test('logDailyProgress updates last_progress_date and does not store logs', () async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 'n1',
            'description': 'Normal task',
            'type': 'normal',
            'deadline': '2099-01-01T23:59:00+05:30',
            'status': 'pending',
          }
        ],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();
    expect(app.tasksNeedingProgressToday.length, 1);
    expect(app.hasPendingToday, isTrue);

    await app.logDailyProgress({'n1': 'Today I made extensive progress on this task...'});
    final out = jsonDecode(fake.lastPutContent!) as Map<String, dynamic>;
    final t = (out['tasks'] as List).first as Map<String, dynamic>;
    expect(t['last_progress_date'], isNotNull);
    expect(t.containsKey('progress_logs'), isFalse);

    expect(app.tasksNeedingProgressToday.isEmpty, isTrue);
  });
}

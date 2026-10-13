import 'package:flutter_test/flutter_test.dart';

import 'package:fnb_commitment/models/task.dart';

void main() {
  test('normal task round trip keeps status', () {
    final t = Task(
      id: 'x',
      description: 'd',
      type: 'normal',
      deadline: '2026-08-24T16:25:00+05:30',
      status: 'pending',
    );
    final j = t.toJson();
    final t2 = Task.fromJson(j);
    expect(t2.id, 'x');
    expect(t2.isDaily, isFalse);
    expect(t2.isPending, isTrue);
    expect(j.containsKey('status'), isTrue);
  });

  test('daily task has no status and is not pending', () {
    final t = Task(
      id: 'y',
      description: 'e',
      type: 'daily',
      deadline: '2026-08-24T09:00:00+05:30',
    );
    expect(t.isDaily, isTrue);
    expect(t.toJson().containsKey('status'), isFalse);
    expect(t.isPending, isFalse);
  });

  test('done and failed flags', () {
    expect(
      Task(id: 'a', description: '', type: 'normal', deadline: 'x', status: 'done').isDone,
      isTrue,
    );
    expect(
      Task(id: 'a', description: '', type: 'normal', deadline: 'x', status: 'failed').isFailed,
      isTrue,
    );
  });

  test('trivial task flags', () {
    final t = Task(
      id: 'z',
      description: 'triv',
      type: 'trivial',
      deadline: '2026-08-24T18:00:00+05:30',
      status: 'pending',
    );
    expect(t.isTrivial, isTrue);
    expect(t.isDaily, isFalse);
    expect(t.isPending, isTrue);
  });

  test('colorCategory returns dueToday, dueNotToday, and doneToday correctly', () {
    // 2026-08-26 10:00:00 IST = 2026-08-26 04:30:00 UTC
    final now = DateTime.utc(2026, 8, 26, 4, 30);

    // 1. Daily task due today (later today at 16:00 IST)
    final dailyDueToday = Task(
      id: 'd1',
      description: 'Daily task today',
      type: 'daily',
      deadline: '2026-08-26T16:00:00+05:30',
    );
    expect(dailyDueToday.colorCategory(now), TaskColorCategory.dueToday);

    // 2. Daily task missed today (earlier today at 09:00 IST)
    final dailyMissedToday = Task(
      id: 'd2',
      description: 'Daily task missed',
      type: 'daily',
      deadline: '2026-08-26T09:00:00+05:30',
    );
    expect(dailyMissedToday.colorCategory(now), TaskColorCategory.dueToday);

    // 3. Daily task done today (deadline advanced to tomorrow 09:00 IST)
    final dailyDoneToday = Task(
      id: 'd3',
      description: 'Daily task done for today',
      type: 'daily',
      deadline: '2026-08-27T09:00:00+05:30',
    );
    expect(dailyDoneToday.colorCategory(now), TaskColorCategory.doneToday);

    // 4. Normal task due today (later today at 18:00 IST)
    final normalDueToday = Task(
      id: 'n1',
      description: 'Normal task today',
      type: 'normal',
      deadline: '2026-08-26T18:00:00+05:30',
      status: 'pending',
    );
    expect(normalDueToday.colorCategory(now), TaskColorCategory.dueToday);

    // 5. Normal task overdue / past deadline
    final normalOverdue = Task(
      id: 'n2',
      description: 'Normal task overdue',
      type: 'normal',
      deadline: '2026-08-25T18:00:00+05:30',
      status: 'pending',
    );
    expect(normalOverdue.colorCategory(now), TaskColorCategory.dueToday);

    // 6. Normal task due not today (due tomorrow or later)
    final normalDueNotToday = Task(
      id: 'n3',
      description: 'Normal task future',
      type: 'normal',
      deadline: '2026-08-27T18:00:00+05:30',
      status: 'pending',
    );
    expect(normalDueNotToday.colorCategory(now), TaskColorCategory.dueNotToday);

    // 7. Normal task done
    final normalDone = Task(
      id: 'n4',
      description: 'Normal task done',
      type: 'normal',
      deadline: '2026-08-27T18:00:00+05:30',
      status: 'done',
    );
    expect(normalDone.colorCategory(now), TaskColorCategory.doneToday);
  });

  test('penalty task flags and round-trip', () {
    final t = Task(
      id: 'p1',
      description: 'No ruminating',
      type: 'penalty',
      deadline: '2026-08-26T23:59:00+05:30',
    );
    expect(t.isPenalty, isTrue);
    expect(t.isDaily, isFalse);
    expect(t.isPending, isFalse);
    final j = t.toJson();
    final t2 = Task.fromJson(j);
    expect(t2.type, 'penalty');
  });

  test('progress logs and needsProgressToday', () {
    final now = DateTime.utc(2026, 8, 26, 4, 30);
    final t = Task(
      id: 'n1',
      description: 'Study',
      type: 'normal',
      deadline: '2026-08-28T23:59:00+05:30',
      status: 'pending',
    );
    expect(t.hasProgressToday(now), isFalse);
    expect(t.needsProgressToday(now), isTrue);

    final updated = Task(
      id: 'n1',
      description: 'Study',
      type: 'normal',
      deadline: '2026-08-28T23:59:00+05:30',
      status: 'pending',
      lastProgressDate: '2026-08-26',
      progressLogs: [{'date': '2026-08-26T10:00:00+05:30', 'text': 'Studied 50 words'}],
    );
    expect(updated.hasProgressToday(now), isTrue);
    expect(updated.needsProgressToday(now), isFalse);
    final json = updated.toJson();
    final restored = Task.fromJson(json);
    expect(restored.lastProgressDate, '2026-08-26');
    expect(restored.progressLogs?.length, 1);
  });
}


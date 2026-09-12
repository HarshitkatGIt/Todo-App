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
}

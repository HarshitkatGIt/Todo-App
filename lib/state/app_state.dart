import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/task.dart';
import '../services/github_service.dart';
import '../services/local_cache.dart';
import '../utils/ist.dart';

class AppState extends ChangeNotifier {
  AppState({required this.github});

  final GithubService github;
  final LocalCache _cache = LocalCache();

  List<Task> tasks = [];
  int missCount = 0;
  String penaltyMonth = '';
  bool offline = false;
  bool loading = false;
  String? error;

  int get nextPenalty {
    final amount = 5 * (1 << missCount);
    return amount > 80 ? 80 : amount;
  }

  Map<String, dynamic> _decodeState(String raw) =>
      jsonDecode(raw) as Map<String, dynamic>;

  void _applyState(String raw) {
    final state = _decodeState(raw);
    final pen = state['penalty'] as Map<String, dynamic>? ?? {};
    penaltyMonth = pen['month'] as String? ?? '';
    missCount = (pen['miss_count'] as int?) ?? 0;
    final rawTasks = state['tasks'] as List<dynamic>? ?? [];
    tasks = rawTasks
        .map((e) => Task.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await github.getState();
      _applyState(result.content);
      await _cache.save(result.content);
      offline = false;
    } catch (e) {
      final cached = await _cache.load();
      if (cached != null) {
        _applyState(cached);
        offline = true;
      }
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _commit(void Function(Map<String, dynamic>) mutate) async {
    var attempt = 0;
    while (true) {
      final latest = await github.getState();
      final state = _decodeState(latest.content);
      mutate(state);
      final raw = jsonEncode(state);
      try {
        await github.putState(raw, latest.sha);
        _applyState(raw);
        await _cache.save(raw);
        offline = false;
        error = null;
        notifyListeners();
        return;
      } on ConflictException {
        attempt++;
        if (attempt > 3) rethrow;
        continue;
      }
    }
  }

  void _queueNotification(Map<String, dynamic> state, String message) {
    final list = (state['pending_notifications'] as List<dynamic>?) != null
        ? List<dynamic>.from(state['pending_notifications'] as List<dynamic>)
        : <dynamic>[];
    list.add(message);
    state['pending_notifications'] = list;
  }

  Future<void> markDone(Task task) async {
    final id = task.id;
    final isDaily = task.isDaily;
    await _commit((state) {
      final list = state['tasks'] as List<dynamic>;
      final idx = list.indexWhere((x) => x['id'] == id);
      if (idx < 0) return;
      final t = list[idx] as Map<String, dynamic>;
      if (isDaily) {
        t['deadline'] = advanceDeadline24h(t['deadline'] as String);
      } else {
        list.removeAt(idx);
      }
    });
  }

  Future<void> skipTask(Task task) async {
    final id = task.id;
    await _commit((state) {
      final list = state['tasks'] as List<dynamic>;
      final idx = list.indexWhere((x) => x['id'] == id);
      if (idx < 0) return;
      final t = list[idx] as Map<String, dynamic>;
      if (task.isDaily) {
        final oldDeadline = t['deadline'] as String;
        final newDeadline = advanceDeadline24h(oldDeadline);
        t['deadline'] = newDeadline;
        _queueNotification(
          state,
          'NOTICE: Task skipped\n'
          'Task: "${task.description}"\n'
          'Daily task skipped for today (next due: ${formatIst(newDeadline)} IST).\n'
          '(Action at ${formatIst(nowUtc().toIso8601String())} IST)',
        );
      }
    });
  }


  Future<void> addTask(Task task) async {
    await _commit((state) {
      final list = state['tasks'] as List<dynamic>;
      list.add(task.toJson());
    });
  }

  Future<void> updateTask(Task task) async {
    final id = task.id;
    await _commit((state) {
      final list = state['tasks'] as List<dynamic>;
      final idx = list.indexWhere((x) => x['id'] == id);
      if (idx < 0) return;
      final old = list[idx] as Map<String, dynamic>;
      final oldDesc = old['description'] as String? ?? '';
      final oldDeadline = old['deadline'] as String? ?? '';
      list[idx] = task.toJson();

      final buffer = StringBuffer('NOTICE: Task edited\n');
      if (oldDesc.isNotEmpty && oldDesc != task.description) {
        buffer.writeln('Task: "${task.description}" (renamed from "$oldDesc")');
      } else {
        buffer.writeln('Task: "${task.description}"');
      }
      if (oldDeadline.isNotEmpty && oldDeadline != task.deadline) {
        buffer.writeln('Deadline changed to: ${formatIst(task.deadline)} IST');
      } else {
        buffer.writeln('Deadline: ${formatIst(task.deadline)} IST');
      }
      buffer.write('(Action at ${formatIst(nowUtc().toIso8601String())} IST)');
      _queueNotification(state, buffer.toString());
    });
  }

  Future<void> deleteTask(String id) async {
    await _commit((state) {
      final list = state['tasks'] as List<dynamic>;
      final idx = list.indexWhere((x) => x['id'] == id);
      if (idx < 0) return;
      final t = list[idx] as Map<String, dynamic>;
      final desc = t['description'] as String? ?? id;
      list.removeAt(idx);
      _queueNotification(
        state,
        'NOTICE: Task deleted\n'
        'Task: "$desc"\n'
        'Task was removed permanently.\n'
        '(Action at ${formatIst(nowUtc().toIso8601String())} IST)',
      );
    });
  }
}

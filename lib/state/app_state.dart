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
  bool crisisMode = false;
  bool offline = false;
  bool loading = false;
  String? error;

  int get nextPenalty {
    if (crisisMode) return 5;
    final amount = 5 * (missCount + 1);
    return amount > 20 ? 20 : amount;
  }

  Map<String, dynamic> _decodeState(String raw) =>
      jsonDecode(raw) as Map<String, dynamic>;

  void _applyState(String raw) {
    final state = _decodeState(raw);
    final pen = state['penalty'] as Map<String, dynamic>? ?? {};
    penaltyMonth = pen['month'] as String? ?? '';
    missCount = (pen['miss_count'] as int?) ?? 0;
    crisisMode = (state['crisis_mode'] as bool?) ?? false;
    final rawTasks = state['tasks'] as List<dynamic>? ?? [];
    final parsed = rawTasks
        .map((e) => Task.fromJson(e as Map<String, dynamic>))
        .toList();
    parsed.sort((a, b) => DateTime.parse(a.deadline).compareTo(DateTime.parse(b.deadline)));
    tasks = parsed;
  }

  List<Task> get tasksNeedingProgressToday {
    return tasks.where((t) => t.needsProgressToday()).toList();
  }

  bool get hasPendingToday => hasPendingTasksToday || hasPendingPenaltiesToday;

  bool get hasPendingTasksToday {
    final now = nowUtc();
    for (final t in tasks) {
      if (t.isPenalty) continue;
      if (t.isDaily) {
        if (isDailyActionableToday(t.deadline, now)) return true;
      } else {
        if (t.isPending) {
          if (isPastDeadline(t.deadline, now) || isSameIstDay(t.deadline, now)) return true;
          if (t.needsProgressToday(now)) return true;
        }
      }
    }
    return false;
  }

  bool get hasPendingPenaltiesToday {
    if (crisisMode) return false;
    final now = nowUtc();
    for (final t in tasks) {
      if (t.isPenalty) {
        if (isDailyActionableToday(t.deadline, now)) return true;
      }
    }
    return false;
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

  void _queuePenalty(Map<String, dynamic> state,
      {required String reason, required int amount}) {
    final list = (state['pending_notifications'] as List<dynamic>?) != null
        ? List<dynamic>.from(state['pending_notifications'] as List<dynamic>)
        : <dynamic>[];
    list.add({
      'type': 'penalty',
      'reason': reason,
      'amount': amount,
    });
    state['pending_notifications'] = list;
  }

  Future<void> markDone(Task task) async {
    final id = task.id;
    final isRecurring = task.isDaily || task.isPenalty;
    await _commit((state) {
      final list = state['tasks'] as List<dynamic>;
      final idx = list.indexWhere((x) => x['id'] == id);
      if (idx < 0) return;
      final t = list[idx] as Map<String, dynamic>;
      if (isRecurring) {
        t['deadline'] = advanceDeadline24h(t['deadline'] as String);
      } else {
        list.removeAt(idx);
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
      final existing = list[idx] as Map<String, dynamic>;
      existing['description'] = task.description;
    });
  }

  Future<void> deleteDailyTask(Task task) async {
    if (!task.isDaily) {
      throw ArgumentError('Only daily tasks can be deleted');
    }
    final id = task.id;
    await _commit((state) {
      final list = state['tasks'] as List<dynamic>;
      final idx = list.indexWhere((x) => x['id'] == id);
      if (idx < 0) return;
      list.removeAt(idx);
      _queuePenalty(
        state,
        reason: 'Daily task deleted — "${task.description}"',
        amount: 20,
      );
    });
  }

  Future<void> deletePenaltyTask(Task task) async {
    if (!task.isPenalty) {
      throw ArgumentError('Only penalty tasks can be deleted with deletePenaltyTask');
    }
    final id = task.id;
    await _commit((state) {
      final list = state['tasks'] as List<dynamic>;
      final idx = list.indexWhere((x) => x['id'] == id);
      if (idx < 0) return;
      list.removeAt(idx);
    });
  }

  Future<void> logDailyProgress(Map<String, String> progressMap) async {
    final today = todayIstDateString();
    final nowIso = toIsoIst(nowUtc());
    await _commit((state) {
      final list = state['tasks'] as List<dynamic>;
      for (final entry in progressMap.entries) {
        final taskId = entry.key;
        final text = entry.value.trim();
        final idx = list.indexWhere((x) => x['id'] == taskId);
        if (idx < 0) continue;
        final t = list[idx] as Map<String, dynamic>;
        t['last_progress_date'] = today;
        final logs = (t['progress_logs'] as List<dynamic>?) != null
            ? List<dynamic>.from(t['progress_logs'] as List<dynamic>)
            : <dynamic>[];
        logs.add({'date': nowIso, 'text': text});
        t['progress_logs'] = logs;
      }
    });
  }

  Future<void> activateCrisisMode() async {
    await _commit((state) {
      state['crisis_mode'] = true;
      final list = state['tasks'] as List<dynamic>;
      list.removeWhere((t) => (t as Map<String, dynamic>)['type'] == 'trivial');
      _queuePenalty(
        state,
        reason: 'Crisis Mode activated',
        amount: 20,
      );
    });
  }

  Future<void> deactivateCrisisMode() async {
    await _commit((state) {
      state['crisis_mode'] = false;
    });
  }
}

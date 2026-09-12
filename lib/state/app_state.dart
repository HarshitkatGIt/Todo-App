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
      list[idx] = task.toJson();
    });
  }

  Future<void> deleteTask(String id) async {
    await _commit((state) {
      final list = state['tasks'] as List<dynamic>;
      list.removeWhere((x) => x['id'] == id);
    });
  }
}

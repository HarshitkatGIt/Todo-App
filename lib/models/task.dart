import '../utils/ist.dart';

enum TaskColorCategory {
  dueToday,
  dueNotToday,
  doneToday,
}

class Task {
  final String id;
  final String description;
  final String type;
  final String deadline;
  final String? status;
  final String? lastProgressDate;
  final List<Map<String, dynamic>>? progressLogs;

  Task({
    required this.id,
    required this.description,
    required this.type,
    required this.deadline,
    this.status,
    this.lastProgressDate,
    this.progressLogs,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      description: json['description'] as String,
      type: json['type'] as String,
      deadline: json['deadline'] as String,
      status: json['status'] as String?,
      lastProgressDate: json['last_progress_date'] as String?,
      progressLogs: (json['progress_logs'] as List<dynamic>?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'description': description,
      'type': type,
      'deadline': deadline,
    };
    if (status != null) map['status'] = status;
    if (lastProgressDate != null) map['last_progress_date'] = lastProgressDate;
    if (progressLogs != null) map['progress_logs'] = progressLogs;
    return map;
  }

  bool get isDaily => type == 'daily';
  bool get isTrivial => type == 'trivial';
  bool get isPenalty => type == 'penalty';
  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';
  bool get isPending => !isDaily && !isPenalty && (status == null || status == 'pending');

  bool get requiresDailyProgress => type == 'normal' && isPending;

  bool hasProgressToday([DateTime? now]) {
    if (lastProgressDate == null) return false;
    return lastProgressDate == todayIstDateString(now);
  }

  bool needsProgressToday([DateTime? now]) {
    return requiresDailyProgress && !hasProgressToday(now);
  }

  TaskColorCategory colorCategory([DateTime? now]) {
    now ??= nowUtc();
    final late = isPastDeadline(deadline, now);
    final recurringDone = (isDaily || isPenalty) && !isDailyActionableToday(deadline, now) && !late;

    if (isDone || recurringDone) {
      return TaskColorCategory.doneToday;
    }
    if (late || isFailed || isSameIstDay(deadline, now)) {
      return TaskColorCategory.dueToday;
    }
    return TaskColorCategory.dueNotToday;
  }
}


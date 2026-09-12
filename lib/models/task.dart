class Task {
  final String id;
  final String description;
  final String type;
  final String deadline;
  final String? status;

  Task({
    required this.id,
    required this.description,
    required this.type,
    required this.deadline,
    this.status,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      description: json['description'] as String,
      type: json['type'] as String,
      deadline: json['deadline'] as String,
      status: json['status'] as String?,
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
    return map;
  }

  bool get isDaily => type == 'daily';
  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';
  bool get isPending => !isDaily && (status == null || status == 'pending');
}

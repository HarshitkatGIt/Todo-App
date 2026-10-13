import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/task.dart';
import '../state/app_state.dart';
import '../utils/ist.dart';
import 'add_task_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, this.showPenaltiesOnly = false});

  final bool showPenaltiesOnly;

  Future<void> _confirmDone(BuildContext context, Task task) async {
    final app = context.read<AppState>();
    if (isPastDeadline(task.deadline)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (task.isDaily || task.isPenalty)
                ? 'Deadline passed - already counted as missed for today.'
                : 'Deadline passed - this task is now marked missed.',
          ),
        ),
      );
      return;
    }
    if ((task.isDaily || task.isPenalty) && !isDailyActionableToday(task.deadline)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            task.isPenalty
                ? 'This penalty rule is already done for today.'
                : 'This daily task is already done for today.',
          ),
        ),
      );
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(task.isPenalty ? 'Are you sure rule is followed today?' : 'Are you sure task is completed?'),
        content: Text(task.description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'done'),
            child: const Text('Yes, mark done'),
          ),
        ],
      ),
    );
    if (!context.mounted || action != 'done') return;
    try {
      await app.markDone(task);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Marked done')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Future<void> _openActions(BuildContext context, Task task) async {
    final app = context.read<AppState>();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit task'),
              enabled: !app.offline,
              subtitle:
                  app.offline ? const Text('Offline - changes are disabled') : null,
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            if (task.isDaily)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete task', style: TextStyle(color: Colors.red)),
                subtitle: const Text('Incurs immediate Rs.20 penalty via UPI'),
                enabled: !app.offline,
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            if (task.isPenalty)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete penalty rule', style: TextStyle(color: Colors.red)),
                subtitle: const Text('Free — costs Rs. 0'),
                enabled: !app.offline,
                onTap: () => Navigator.pop(ctx, 'delete_penalty'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'edit') {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: app,
          child: AddTaskScreen(initial: task, app: app),
        ),
      ));
    } else if (action == 'delete' && task.isDaily) {
      await _confirmDeleteDaily(context, task);
    } else if (action == 'delete_penalty' && task.isPenalty) {
      await _confirmDeletePenalty(context, task);
    }
  }

  Future<void> _confirmDeleteDaily(BuildContext context, Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this daily task?'),
        content: Text(
          '"${task.description}" will be removed permanently.\n\n'
          '⚠️ Deleting a daily task incurs an immediate penalty of Rs. 20 payable via UPI.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete (Rs.20 penalty)'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<AppState>().deleteDailyTask(task);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Daily task deleted (Rs.20 penalty charged)')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Future<void> _confirmDeletePenalty(BuildContext context, Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this penalty rule?'),
        content: Text(
          '"${task.description}" will be removed permanently.\n\n'
          'Deleting a penalty rule is free (costs Rs. 0).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete (free)'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<AppState>().deletePenaltyTask(task);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Penalty rule deleted')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Future<void> _confirmCrisisMode(BuildContext context, bool currentActive) async {
    final app = context.read<AppState>();
    if (currentActive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Turn Off Crisis Mode?'),
          content: const Text(
            'Deactivating Crisis Mode is free (costs Rs. 0).\n\n'
            'Normal penalties (up to Rs. 20) and trivial tasks will be re-enabled.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Turn Off'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      try {
        await app.deactivateCrisisMode();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Crisis Mode deactivated')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: $e')),
          );
        }
      }
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Activate Crisis Mode?'),
          content: const Text(
            'Activating Crisis Mode incurs an immediate Rs. 20 penalty via UPI.\n\n'
            'While Crisis Mode is active:\n'
            '• Max penalty for any missed task is capped at Rs. 5\n'
            '• All existing trivial tasks will be deleted without penalty\n'
            '• New trivial tasks cannot be created\n\n'
            'Turning off Crisis Mode later is free.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Activate (Rs.20)'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      try {
        await app.activateCrisisMode();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Crisis Mode activated (Rs.20 charged)')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    // Blocking screen until 50-word daily progress is filled for each normal task
    if (app.tasksNeedingProgressToday.isNotEmpty) {
      return _BlockingDailyProgressView(tasks: app.tasksNeedingProgressToday);
    }

    final regularTasks = app.tasks.where((t) => !t.isPenalty).toList();
    final penaltyTasks = app.tasks.where((t) => t.isPenalty).toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: app.refresh,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (app.offline)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 8),
                color: Colors.orange.shade100,
                child: const Text(
                  'Offline - showing cached copy. Changes are disabled.',
                  style: TextStyle(color: Colors.black87),
                ),
              ),
            if (!showPenaltiesOnly) ...[
              Card(
                color: app.crisisMode ? Colors.red.shade50 : null,
                shape: app.crisisMode
                    ? RoundedRectangleBorder(
                        side: BorderSide(color: Colors.red.shade400, width: 1.5),
                        borderRadius: BorderRadius.circular(12),
                      )
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Miss count: ${app.missCount}'),
                          Text('Next penalty: Rs.${app.nextPenalty}'),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                app.crisisMode
                                    ? Icons.warning_amber_rounded
                                    : Icons.shield_outlined,
                                color: app.crisisMode ? Colors.red : Colors.grey.shade700,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                app.crisisMode
                                    ? 'Crisis Mode: ACTIVE (Max Rs.5)'
                                    : 'Crisis Mode: OFF',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: app.crisisMode ? Colors.red.shade800 : null,
                                ),
                              ),
                            ],
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: app.crisisMode
                                  ? Colors.grey.shade300
                                  : Colors.red.shade400,
                              foregroundColor:
                                  app.crisisMode ? Colors.black87 : Colors.white,
                            ),
                            onPressed: app.offline
                                ? null
                                : () => _confirmCrisisMode(context, app.crisisMode),
                            child: Text(app.crisisMode ? 'Turn Off' : 'Crisis Mode'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (app.loading) const LinearProgressIndicator(),
              if (app.error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('Error: ${app.error}',
                      style: const TextStyle(color: Colors.red)),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Tasks',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${regularTasks.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              ...regularTasks.map((task) => _TaskCard(
                    task: task,
                    onDone: () => _confirmDone(context, task),
                    onLongPress: () => _openActions(context, task),
                  )),
              if (regularTasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No tasks yet. Add one from the Add tab.')),
                ),
            ] else ...[
              Card(
                color: app.crisisMode ? Colors.grey.shade100 : Colors.deepOrange.shade50,
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: app.crisisMode ? Colors.grey.shade400 : Colors.deepOrange.shade300,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            app.crisisMode
                                ? Icons.pause_circle_outline
                                : Icons.warning_amber_rounded,
                            color: app.crisisMode ? Colors.grey.shade700 : Colors.deepOrange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              app.crisisMode
                                  ? 'Crisis Mode Active: Penalties Paused'
                                  : 'Fixed Rs. 10 Daily Penalty',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: app.crisisMode
                                    ? Colors.grey.shade800
                                    : Colors.deepOrange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        app.crisisMode
                            ? 'Penalty rules do not incur fines while Crisis Mode is active.'
                            : 'Rules reset daily at 23:59 IST. Deleting a penalty rule is free (costs Rs. 0).',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                      ),
                    ],
                  ),
                ),
              ),
              if (app.loading) const LinearProgressIndicator(),
              if (app.error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('Error: ${app.error}',
                      style: const TextStyle(color: Colors.red)),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.warning_amber_rounded, color: Colors.deepOrange),
                        SizedBox(width: 6),
                        Text(
                          'Penalties & Rules',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepOrange,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.deepOrange.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${penaltyTasks.length}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.deepOrange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ...penaltyTasks.map((task) => _TaskCard(
                    task: task,
                    onDone: () => _confirmDone(context, task),
                    onLongPress: () => _openActions(context, task),
                  )),
              if (penaltyTasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No penalty rules active. Add one from the Add tab.')),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.onDone,
    required this.onLongPress,
  });

  final Task task;
  final VoidCallback onDone;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final daily = task.isDaily;
    final trivial = task.isTrivial;
    final penalty = task.isPenalty;
    final crisisMode = context.read<AppState>().crisisMode;
    final late = isPastDeadline(task.deadline);
    final recurring = daily || penalty;
    final recurringDone = recurring && !isDailyActionableToday(task.deadline);
    final doneDisabled = recurring
        ? (late || recurringDone)
        : (late || task.isDone || task.isFailed);

    String subtitle;
    if (daily) {
      if (late) {
        subtitle = 'Missed today - resets ${formatIst(task.deadline)} IST';
      } else if (recurringDone) {
        subtitle = 'Daily - next ${formatIst(task.deadline)} IST';
      } else {
        subtitle = 'Daily - due ${formatIst(task.deadline)} IST';
      }
    } else if (penalty) {
      if (crisisMode) {
        subtitle = 'Paused in Crisis Mode (Rs.0 fine)';
      } else if (late) {
        subtitle = 'Missed today - resets ${formatIst(task.deadline)} IST';
      } else if (recurringDone) {
        subtitle = 'Done today - next ${formatIst(task.deadline)} IST';
      } else {
        subtitle = 'Due ${formatIst(task.deadline)} IST • Rs.10 fine';
      }
    } else if (trivial) {
      if (task.isDone) {
        subtitle = 'Completed';
      } else if (task.isFailed) {
        subtitle = 'Missed (failed)';
      } else if (late) {
        subtitle = 'OVERDUE - Rs.5 penalty';
      } else {
        subtitle = 'Trivial - due ${formatIst(task.deadline)}';
      }
    } else if (task.isDone) {
      subtitle = 'Completed';
    } else if (task.isFailed) {
      subtitle = 'Missed (failed)';
    } else if (late) {
      subtitle = 'OVERDUE - will be marked missed';
    } else {
      final progressText = task.hasProgressToday()
          ? ' • ✓ Progress logged'
          : '';
      subtitle = 'Due ${formatIst(task.deadline)}$progressText';
    }

    final category = task.colorCategory();
    final Color cardColor;
    final Color borderColor;
    final Color chipColor;

    switch (category) {
      case TaskColorCategory.dueToday:
        cardColor = Colors.red.shade100;
        borderColor = Colors.red.shade400;
        chipColor = Colors.red.shade200;
        break;
      case TaskColorCategory.dueNotToday:
        cardColor = Colors.yellow.shade100;
        borderColor = Colors.amber.shade600;
        chipColor = Colors.yellow.shade200;
        break;
      case TaskColorCategory.doneToday:
        cardColor = Colors.green.shade100;
        borderColor = Colors.green.shade400;
        chipColor = Colors.green.shade200;
        break;
    }

    final chipText = daily
        ? 'daily'
        : (penalty
            ? 'Rs.10'
            : (trivial ? 'trivial' : (task.status ?? 'pending')));

    final buttonText = daily
        ? 'Done (daily)'
        : 'Done';

    return Card(
      color: cardColor,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        onLongPress: appOffline(context) ? null : onLongPress,
        title: Text(
          task.description,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade800,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: chipColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                chipText,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: (appOffline(context) || doneDisabled) ? null : onDone,
              child: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }

  bool appOffline(BuildContext context) =>
      context.read<AppState>().offline;
}

class _BlockingDailyProgressView extends StatefulWidget {
  const _BlockingDailyProgressView({required this.tasks});

  final List<Task> tasks;

  @override
  State<_BlockingDailyProgressView> createState() =>
      _BlockingDailyProgressViewState();
}

class _BlockingDailyProgressViewState
    extends State<_BlockingDailyProgressView> {
  final Map<String, TextEditingController> _controllers = {};
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    for (final task in widget.tasks) {
      final c = TextEditingController();
      c.addListener(() => setState(() {}));
      _controllers[task.id] = c;
    }
  }

  @override
  void didUpdateWidget(covariant _BlockingDailyProgressView oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final task in widget.tasks) {
      if (!_controllers.containsKey(task.id)) {
        final c = TextEditingController();
        c.addListener(() => setState(() {}));
        _controllers[task.id] = c;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final app = context.read<AppState>();
    final map = <String, String>{};
    for (final task in widget.tasks) {
      map[task.id] = _controllers[task.id]!.text.trim();
    }
    setState(() => _submitting = true);
    try {
      await app.logDailyProgress(map);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Daily progress submitted!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allValid = widget.tasks.every(
      (t) => countWords(_controllers[t.id]?.text ?? '') >= 50,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Progress Required'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                border: Border.all(color: Colors.amber.shade400),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_note, color: Colors.amber, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Accountability check: Write a 50-word progress update for each task before continuing.',
                      style: TextStyle(
                        color: Colors.brown.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...widget.tasks.map((task) {
              final text = _controllers[task.id]?.text ?? '';
              final words = countWords(text);
              final valid = words >= 50;

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.description,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _controllers[task.id],
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText:
                              'What progress was made on this task today? (min 50 words)',
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            valid
                                ? '✓ $words words (Requirement met)'
                                : '$words / 50 words',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: valid
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                            ),
                          ),
                          if (!valid)
                            Text(
                              '${50 - words} more needed',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor:
                    allValid ? Colors.green.shade600 : Colors.grey.shade400,
                foregroundColor: Colors.white,
              ),
              onPressed: (allValid && !_submitting) ? _submit : null,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Submit Today\'s Progress',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

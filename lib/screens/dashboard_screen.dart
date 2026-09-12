import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/task.dart';
import '../state/app_state.dart';
import '../utils/ist.dart';
import 'add_task_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  Future<void> _confirmDone(BuildContext context, Task task) async {
    final app = context.read<AppState>();
    if (isPastDeadline(task.deadline)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            task.isDaily
                ? 'Deadline passed - already counted as missed for today.'
                : 'Deadline passed - this task is now marked missed.',
          ),
        ),
      );
      return;
    }
    if (task.isDaily && !isDailyActionableToday(task.deadline)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This daily task is already done for today.'),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Are you sure task is completed?'),
        content: Text(task.description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, mark done'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
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
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete task'),
              enabled: !app.offline,
              subtitle:
                  app.offline ? const Text('Offline - changes are disabled') : null,
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'edit') {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AddTaskScreen(initial: task),
      ));
    } else if (action == 'delete') {
      await _confirmDelete(context, task);
    }
  }

  Future<void> _confirmDelete(BuildContext context, Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this task?'),
        content: Text(task.isDaily
            ? '"${task.description}" will be removed permanently, including its daily schedule.'
            : '"${task.description}" will be removed permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<AppState>().deleteTask(task.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task deleted')),
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

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return RefreshIndicator(
      onRefresh: app.refresh,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (app.offline)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.orange.shade100,
              child: const Text(
                'Offline - showing cached copy. Changes are disabled.',
                style: TextStyle(color: Colors.black87),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Miss count: ${app.missCount}'),
                  Text('Next penalty if missed: Rs.${app.nextPenalty}'),
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
          ...app.tasks.map((task) => _TaskCard(
                task: task,
                onDone: () => _confirmDone(context, task),
                onLongPress: () => _openActions(context, task),
              )),
          if (app.tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No tasks yet. Add one.')),
            ),
        ],
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
    final late = isPastDeadline(task.deadline);
    final dailyDone = daily && !isDailyActionableToday(task.deadline);
    final doneDisabled = daily
        ? (late || dailyDone)
        : (late || task.isDone || task.isFailed);

    String subtitle;
    if (daily) {
      if (late) {
        subtitle = 'Missed today - resets ${formatIst(task.deadline)} IST';
      } else if (dailyDone) {
        subtitle = 'Daily - next ${formatIst(task.deadline)} IST';
      } else {
        subtitle = 'Daily - due ${formatIst(task.deadline)} IST';
      }
    } else if (task.isDone) {
      subtitle = 'Completed';
    } else if (task.isFailed) {
      subtitle = 'Missed (failed)';
    } else if (late) {
      subtitle = 'OVERDUE - will be marked missed';
    } else {
      subtitle = 'Due ${formatIst(task.deadline)}';
    }

    Color? chipColor;
    if (task.isFailed) chipColor = Colors.red.shade200;
    if (task.isDone) chipColor = Colors.green.shade200;

    return Card(
      child: ListTile(
        onLongPress: appOffline(context) ? null : onLongPress,
        title: Text(task.description),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Chip(
              label: Text(daily ? 'daily' : (task.status ?? 'pending')),
              backgroundColor: chipColor,
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: (appOffline(context) || doneDisabled) ? null : onDone,
              child: Text(daily ? 'Done (daily)' : 'Done'),
            ),
          ],
        ),
      ),
    );
  }

  bool appOffline(BuildContext context) =>
      context.read<AppState>().offline;
}

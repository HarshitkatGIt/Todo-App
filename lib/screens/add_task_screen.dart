import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/task.dart';
import '../services/github_service.dart';
import '../state/app_state.dart';
import '../utils/ist.dart';

class AddTaskScreen extends StatefulWidget {
  const AddTaskScreen({super.key, this.onDone, this.initial});

  final VoidCallback? onDone;
  final Task? initial;

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  late String _type = widget.initial?.type ?? 'normal';
  final _description = TextEditingController();
  TimeOfDay _dailyTime = const TimeOfDay(hour: 9, minute: 0);
  DateTime _normalDate = DateTime.now().add(const Duration(days: 1));

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _description.text = initial.description;
      final istWall = istWallFromIso(initial.deadline);
      if (initial.isDaily) {
        _dailyTime = TimeOfDay(hour: istWall.hour, minute: istWall.minute);
      } else {
        _normalDate = istWall;
      }
    }
  }

  Future<void> _pickDailyTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _dailyTime,
    );
    if (!mounted) return;
    if (picked != null) setState(() => _dailyTime = picked);
  }

  Future<void> _pickNormalDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _normalDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (!mounted) return;
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_normalDate),
    );
    if (!mounted) return;
    if (time == null) return;
    setState(() {
      _normalDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    final desc = _description.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a description')),
      );
      return;
    }
    final deadline = _type == 'daily'
        ? nextDailyDeadlineIso(_dailyTime.hour, _dailyTime.minute)
        : specificDeadlineIso(_normalDate);

    final app = context.read<AppState>();
    try {
      if (widget.initial != null) {
        final original = widget.initial!;
        await app.updateTask(Task(
          id: original.id,
          description: desc,
          type: original.type,
          deadline: deadline,
          status: original.status,
        ));
      } else {
        final task = Task(
          id: generateId(),
          description: desc,
          type: _type,
          deadline: deadline,
          status: _type == 'normal' ? 'pending' : null,
        );
        await app.addTask(task);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(widget.initial != null ? 'Task updated' : 'Task added'),
          ),
        );
        if (widget.initial != null) {
          Navigator.of(context).pop();
        } else {
          _description.clear();
          setState(() => _type = 'normal');
          widget.onDone?.call();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit Task' : 'Add Task')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            if (!editing)
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'normal', label: Text('Normal')),
                  ButtonSegment(value: 'daily', label: Text('Daily')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
            if (!editing) const SizedBox(height: 16),
            TextField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (_type == 'daily')
              ListTile(
                title: const Text('Time of day (IST)'),
                subtitle: Text(_dailyTime.format(context)),
                trailing: const Icon(Icons.access_time),
                onTap: _pickDailyTime,
              )
            else
              ListTile(
                title: const Text('Deadline (IST)'),
                subtitle: Text(
                  '${_normalDate.day}/${_normalDate.month}/${_normalDate.year} '
                  '${TimeOfDay.fromDateTime(_normalDate).format(context)}',
                ),
                trailing: const Icon(Icons.event),
                onTap: _pickNormalDateTime,
              ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _submit,
              child: Text(editing ? 'Save changes' : 'Add task'),
            ),
          ],
        ),
      ),
    );
  }
}

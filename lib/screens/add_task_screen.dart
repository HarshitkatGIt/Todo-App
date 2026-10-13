import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/task.dart';
import '../services/github_service.dart';
import '../state/app_state.dart';
import '../utils/ist.dart';

class AddTaskScreen extends StatefulWidget {
  const AddTaskScreen({super.key, this.onDone, this.initial, this.app});

  final VoidCallback? onDone;
  final Task? initial;
  final AppState? app;

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  late String _type = widget.initial?.type ?? 'normal';
  final _description = TextEditingController();
  DateTime _normalDate = DateTime.now().add(const Duration(days: 1));
  DateTime _trivialDate = DateTime.now();
  TimeOfDay _trivialTime = TimeOfDay.now();

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _description.text = initial.description;
    } else {
      final nowIst = istWallFromIso(toIsoIst(nowUtc()));
      _trivialDate = nowIst;
      _trivialTime = TimeOfDay(hour: (nowIst.hour + 1) % 24, minute: 0);
      _normalDate = nowIst.add(const Duration(days: 1));
    }
  }

  Future<void> _pickNormalDate() async {
    final nowIst = istWallFromIso(toIsoIst(nowUtc()));
    final date = await showDatePicker(
      context: context,
      initialDate: _normalDate.isBefore(nowIst) ? nowIst : _normalDate,
      firstDate: nowIst.subtract(const Duration(days: 30)),
      lastDate: nowIst.add(const Duration(days: 3650)),
    );
    if (!mounted || date == null) return;
    setState(() {
      _normalDate = DateTime(date.year, date.month, date.day);
    });
  }

  Future<void> _pickTrivialDateTime() async {
    final nowIst = istWallFromIso(toIsoIst(nowUtc()));
    final date = await showDatePicker(
      context: context,
      initialDate: _trivialDate.isBefore(nowIst) ? nowIst : _trivialDate,
      firstDate: nowIst.subtract(const Duration(days: 30)),
      lastDate: nowIst.add(const Duration(days: 3650)),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _trivialTime,
    );
    if (!mounted || time == null) return;
    setState(() {
      _trivialDate = DateTime(date.year, date.month, date.day);
      _trivialTime = time;
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

    final app = widget.app ?? context.read<AppState>();

    try {
      if (widget.initial != null) {
        // Editing: Only name/description can change
        final original = widget.initial!;
        await app.updateTask(Task(
          id: original.id,
          description: desc,
          type: original.type,
          deadline: original.deadline,
          status: original.status,
        ));
      } else {
        // Creating:
        final String deadline;
        if (_type == 'daily' || _type == 'penalty') {
          deadline = nextDailyDeadlineIso(23, 59);
        } else if (_type == 'trivial') {
          deadline = specificDeadlineIso(DateTime(
            _trivialDate.year,
            _trivialDate.month,
            _trivialDate.day,
            _trivialTime.hour,
            _trivialTime.minute,
          ));
        } else {
          // Normal task due at 23:59 of selected day
          deadline = specificDeadlineIso(DateTime(
            _normalDate.year,
            _normalDate.month,
            _normalDate.day,
            23,
            59,
          ));
        }

        final task = Task(
          id: generateId(),
          description: desc,
          type: _type,
          deadline: deadline,
          status: (_type == 'daily' || _type == 'penalty') ? null : 'pending',
        );
        await app.addTask(task);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.initial != null ? 'Task updated' : 'Task added'),
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
    final app = widget.app ?? context.watch<AppState>();
    final crisisActive = app.crisisMode;

    if (crisisActive && (_type == 'trivial' || _type == 'penalty')) {
      _type = 'normal';
    }

    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit Task' : 'Add Task')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            if (!editing) ...[
              SegmentedButton<String>(
                segments: [
                  const ButtonSegment(value: 'normal', label: Text('Normal')),
                  const ButtonSegment(value: 'daily', label: Text('Daily')),
                  ButtonSegment(
                    value: 'trivial',
                    label: const Text('Trivial'),
                    enabled: !crisisActive,
                  ),
                  ButtonSegment(
                    value: 'penalty',
                    label: const Text('Penalty'),
                    enabled: !crisisActive,
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              if (crisisActive)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Trivial & Penalty tasks disabled during Crisis Mode',
                    style: TextStyle(fontSize: 12, color: Colors.orange),
                  ),
                ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            if (!editing) ...[
              const SizedBox(height: 16),
              if (_type == 'daily')
                const ListTile(
                  leading: Icon(Icons.schedule),
                  title: Text('Due daily at 11:59 PM (23:59 IST)'),
                  subtitle: Text('Repeats every day without time customization'),
                )
              else if (_type == 'penalty')
                const ListTile(
                  leading: Icon(Icons.warning_amber_rounded, color: Colors.deepOrange),
                  title: Text('Penalty Rule (Due daily at 23:59 IST)'),
                  subtitle: Text('Fixed Rs. 10 fine if not completed today'),
                )
              else if (_type == 'normal')
                ListTile(
                  leading: const Icon(Icons.event),
                  title: const Text('Deadline Date (IST)'),
                  subtitle: Text(
                    '${_normalDate.day}/${_normalDate.month}/${_normalDate.year} at 11:59 PM',
                  ),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: _pickNormalDate,
                )
              else if (_type == 'trivial')
                ListTile(
                  leading: const Icon(Icons.access_time),
                  title: const Text('Deadline Date & Time (IST)'),
                  subtitle: Text(
                    '${_trivialDate.day}/${_trivialDate.month}/${_trivialDate.year} '
                    '${_trivialTime.format(context)}',
                  ),
                  trailing: const Icon(Icons.edit_calendar),
                  onTap: _pickTrivialDateTime,
                ),
            ],
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

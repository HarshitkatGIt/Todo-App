import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:fnb_commitment/main.dart';
import 'package:fnb_commitment/state/app_state.dart';
import 'package:fnb_commitment/screens/dashboard_screen.dart';
import 'package:fnb_commitment/screens/add_task_screen.dart';
import 'package:fnb_commitment/utils/ist.dart';

import 'fakes.dart';


void main() {
  setUp(() {
    setupTestMocks();
  });

  testWidgets('boots to settings when no credentials stored', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(find.text('GitHub Settings'), findsWidgets);
  });

  testWidgets('storage failure lands on settings with notice, not a hang',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Root(storage: FakeCredentialStore(throwOnRead: true)),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('GitHub Settings'), findsWidgets);
    expect(find.textContaining('Could not read saved login'), findsOneWidget);
  });

  testWidgets('hanging storage read times out to settings screen',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Root(storage: FakeCredentialStore(hangOnRead: true)),
      ),
    );
    // Still waiting before the timeout fires.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(seconds: 11));
    await tester.pump();

    expect(find.text('GitHub Settings'), findsWidgets);
    expect(find.textContaining('Could not read saved login'), findsOneWidget);
  });

  testWidgets('dashboard renders tasks, penalty and confirm dialog', (tester) async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 1},
        'tasks': [
          {
            'id': 'a',
            'description': 'Task A',
            'type': 'normal',
            'deadline': '2099-01-01T10:00:00+05:30',
            'status': 'pending',
          },
          {
            'id': 'b',
            'description': 'Task B',
            'type': 'daily',
            'deadline': '2099-01-01T09:00:00+05:30',
          },
        ],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<AppState>.value(
          value: app,
          child: const DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Task A'), findsOneWidget);
    expect(find.text('Task B'), findsOneWidget);
    expect(find.text('Next penalty if missed: Rs.10'), findsOneWidget);

    final doneBtn = find.widgetWithText(ElevatedButton, 'Done').first;
    await tester.tap(doneBtn);
    await tester.pumpAndSettle();

    expect(find.text('Are you sure task is completed?'), findsOneWidget);
  });

  testWidgets('done button is disabled once the deadline has passed', (tester) async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 'late',
            'description': 'Too late',
            'type': 'normal',
            'deadline': '2000-01-01T10:00:00+05:30',
            'status': 'pending',
          }
        ],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<AppState>.value(
          value: app,
          child: const DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final doneBtn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Done'),
    );
    expect(doneBtn.onPressed, isNull);
  });

  testWidgets('daily done button disabled when deadline is a future day',
      (tester) async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 'b',
            'description': 'Daily B',
            'type': 'daily',
            'deadline': '2099-01-01T09:00:00+05:30',
          }
        ],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<AppState>.value(
          value: app,
          child: const DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final doneBtn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Done (daily)'),
    );
    expect(doneBtn.onPressed, isNull);
    expect(find.textContaining('Daily - next'), findsOneWidget);
  });

  testWidgets('add task invokes onDone and commits the task', (tester) async {
    var doneCalled = false;
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<AppState>.value(
          value: app,
          child: AddTaskScreen(onDone: () => doneCalled = true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'New task');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add task'));
    await tester.pumpAndSettle();
    expect(doneCalled, isTrue);
    final out = jsonDecode(fake.lastPutContent!) as Map<String, dynamic>;
    expect((out['tasks'] as List).length, 1);
  });

  testWidgets('tasks are colored red (due today), yellow (due not today), and green (done today)',
      (tester) async {
    final nowIst = DateTime.now().toUtc().add(istOffset);
    final todayIso = specificDeadlineIso(DateTime(nowIst.year, nowIst.month, nowIst.day, 23, 59));
    final futureIso = specificDeadlineIso(DateTime(nowIst.year, nowIst.month, nowIst.day, 23, 59).add(const Duration(days: 3)));
    final tomorrowIso = specificDeadlineIso(DateTime(nowIst.year, nowIst.month, nowIst.day, 23, 59).add(const Duration(days: 1)));

    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 't1',
            'description': 'Task Due Today',
            'type': 'normal',
            'deadline': todayIso,
            'status': 'pending',
          },
          {
            'id': 't2',
            'description': 'Task Due Not Today',
            'type': 'normal',
            'deadline': futureIso,
            'status': 'pending',
          },
          {
            'id': 't3',
            'description': 'Daily Task Done Today',
            'type': 'daily',
            'deadline': tomorrowIso,
          },
        ],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<AppState>.value(
          value: app,
          child: const DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dueTodayCard = tester.widget<Card>(
      find.ancestor(
        of: find.text('Task Due Today'),
        matching: find.byType(Card),
      ),
    );
    expect(dueTodayCard.color, Colors.red.shade100);

    final dueNotTodayCard = tester.widget<Card>(
      find.ancestor(
        of: find.text('Task Due Not Today'),
        matching: find.byType(Card),
      ),
    );
    expect(dueNotTodayCard.color, Colors.yellow.shade100);

    final doneTodayCard = tester.widget<Card>(
      find.ancestor(
        of: find.text('Daily Task Done Today'),
        matching: find.byType(Card),
      ),
    );
    expect(doneTodayCard.color, Colors.green.shade100);
  });

  testWidgets('editing a task updates the task and saves changes successfully',
      (tester) async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 'edit-me',
            'description': 'Original description',
            'type': 'normal',
            'deadline': '2099-01-01T10:00:00+05:30',
            'status': 'pending',
          },
        ],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<AppState>.value(
          value: app,
          child: const DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Original description'), findsOneWidget);

    // Long-press to open actions sheet
    await tester.longPress(find.text('Original description'));
    await tester.pumpAndSettle();

    expect(find.text('Edit task'), findsOneWidget);
    await tester.tap(find.text('Edit task'));
    await tester.pumpAndSettle();

    // Verify AddTaskScreen is shown in edit mode
    expect(find.text('Edit Task'), findsOneWidget);
    expect(find.text('Original description'), findsOneWidget);

    // Edit description
    await tester.enterText(find.byType(TextField), 'Modified description');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save changes'));
    await tester.pumpAndSettle();

    // Verify screen popped and new description is rendered
    expect(find.text('Modified description'), findsOneWidget);
    expect(find.text('Original description'), findsNothing);

    // Verify changes were saved to backend
    final out = jsonDecode(fake.lastPutContent!) as Map<String, dynamic>;
    final tasksList = out['tasks'] as List<dynamic>;
    expect(tasksList.length, 1);
    expect((tasksList.first as Map<String, dynamic>)['description'], 'Modified description');
  });

  testWidgets('skip today advances daily task deadline and renders as done/green',
      (tester) async {
    final nowIst = DateTime.now().toUtc().add(istOffset);
    final todayIso = specificDeadlineIso(DateTime(nowIst.year, nowIst.month, nowIst.day, 23, 59));
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 'daily-skip',
            'description': 'Daily task to skip',
            'type': 'daily',
            'deadline': todayIso,
          },
        ],
      }),
    );
    final app = AppState(github: fake);
    await app.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<AppState>.value(
            value: app,
            child: const DashboardScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Long press to open actions
    await tester.longPress(find.text('Daily task to skip'));
    await tester.pumpAndSettle();

    // Verify Skip today is shown and tap it
    expect(find.text('Skip today'), findsOneWidget);
    await tester.tap(find.text('Skip today'));
    await tester.pumpAndSettle();

    // Verify confirmation dialog
    expect(find.text('Skip this task for today?'), findsOneWidget);
    await tester.tap(find.text('Yes, skip today'));
    await tester.pumpAndSettle();

    // Verify card is now green (done today)
    final card = tester.widget<Card>(
      find.ancestor(
        of: find.text('Daily task to skip'),
        matching: find.byType(Card),
      ),
    );
    expect(card.color, Colors.green.shade100);

    // Verify backend received updated deadline
    final out = jsonDecode(fake.lastPutContent!) as Map<String, dynamic>;
    final tasksList = out['tasks'] as List<dynamic>;
    expect(tasksList.length, 1);
    expect((tasksList.first as Map<String, dynamic>)['deadline'], contains('+05:30'));
  });
}




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
            'last_progress_date': todayIstDateString(),
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
    expect(find.text('Next penalty: Rs.10'), findsOneWidget);

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
            'last_progress_date': todayIstDateString(),
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
            'last_progress_date': todayIstDateString(),
          },
          {
            'id': 't2',
            'description': 'Task Due Not Today',
            'type': 'normal',
            'deadline': futureIso,
            'status': 'pending',
            'last_progress_date': todayIstDateString(),
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
            'last_progress_date': todayIstDateString(),
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

  testWidgets('crisis mode button shows confirmation and activates',
      (tester) async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 1},
        'tasks': [
          {
            'id': 't1',
            'description': 'Trivial task',
            'type': 'trivial',
            'deadline': '2026-08-25T18:00:00+05:30',
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

    expect(find.text('Crisis Mode: OFF'), findsOneWidget);
    expect(find.text('Trivial task'), findsOneWidget);

    // Tap Crisis Mode button
    await tester.tap(find.widgetWithText(ElevatedButton, 'Crisis Mode'));
    await tester.pumpAndSettle();

    // Verify confirmation dialog
    expect(find.text('Activate Crisis Mode?'), findsOneWidget);
    expect(find.textContaining('incurs an immediate Rs. 20 penalty'), findsOneWidget);

    // Confirm activation
    await tester.tap(find.text('Activate (Rs.20)'));
    await tester.pumpAndSettle();

    // Verify Crisis Mode is active and trivial task was deleted
    expect(find.text('Crisis Mode: ACTIVE (Max Rs.5)'), findsOneWidget);
    expect(find.text('Trivial task'), findsNothing);
    expect(find.text('Next penalty: Rs.5'), findsOneWidget);
  });

  testWidgets('daily task can be deleted with Rs. 20 penalty warning, normal task cannot be deleted',
      (tester) async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 'daily-1',
            'description': 'Daily task to delete',
            'type': 'daily',
            'deadline': '2099-01-01T23:59:00+05:30',
          },
          {
            'id': 'normal-1',
            'description': 'Normal task no delete',
            'type': 'normal',
            'deadline': '2099-01-01T23:59:00+05:30',
            'status': 'pending',
            'last_progress_date': todayIstDateString(),
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

    // 1. Long press normal task -> only Edit task, no Delete task, no Skip
    await tester.longPress(find.text('Normal task no delete'));
    await tester.pumpAndSettle();
    expect(find.text('Edit task'), findsOneWidget);
    expect(find.text('Delete task'), findsNothing);
    expect(find.text('Skip today'), findsNothing);
    // Dismiss bottom sheet
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // 2. Long press daily task -> Edit task and Delete task, no Skip
    await tester.longPress(find.text('Daily task to delete'));
    await tester.pumpAndSettle();
    expect(find.text('Edit task'), findsOneWidget);
    expect(find.text('Delete task'), findsOneWidget);
    expect(find.text('Skip today'), findsNothing);

    // Tap Delete task
    await tester.tap(find.text('Delete task'));
    await tester.pumpAndSettle();

    // Verify warning dialog
    expect(find.text('Delete this daily task?'), findsOneWidget);
    expect(find.textContaining('incurs an immediate penalty of Rs. 20'), findsOneWidget);

    // Confirm deletion
    await tester.tap(find.text('Delete (Rs.20 penalty)'));
    await tester.pumpAndSettle();

    // Daily task should be deleted
    expect(find.text('Daily task to delete'), findsNothing);
    expect(find.text('Normal task no delete'), findsOneWidget);

    final out = jsonDecode(fake.lastPutContent!) as Map<String, dynamic>;
    final tasksList = out['tasks'] as List<dynamic>;
    expect(tasksList.length, 1);
    expect((tasksList.first as Map<String, dynamic>)['id'], 'normal-1');
  });

  testWidgets('blocking 50-word progress view blocks dashboard until 50 words submitted',
      (tester) async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 'norm-progress',
            'description': 'Important normal task',
            'type': 'normal',
            'deadline': '2099-01-01T23:59:00+05:30',
            'status': 'pending',
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

    // 1. Verify blocking screen is shown
    expect(find.text('Daily Progress Required'), findsOneWidget);
    expect(find.text('Important normal task'), findsOneWidget);
    // Regular dashboard elements should NOT be shown
    expect(find.text('Miss count: 0'), findsNothing);

    // 2. Button is disabled when words < 50
    final submitBtnFinder = find.widgetWithText(ElevatedButton, 'Submit Today\'s Progress');
    expect(submitBtnFinder, findsOneWidget);
    final btnWidgetBefore = tester.widget<ElevatedButton>(submitBtnFinder);
    expect(btnWidgetBefore.onPressed, isNull);

    // 3. Enter less than 50 words
    await tester.enterText(find.byType(TextField), 'This is only five words.');
    await tester.pump();
    expect(find.text('5 / 50 words'), findsOneWidget);
    final btnWidgetMid = tester.widget<ElevatedButton>(submitBtnFinder);
    expect(btnWidgetMid.onPressed, isNull);

    // 4. Enter 50 words
    final fiftyWords = List.generate(50, (i) => 'word$i').join(' ');
    await tester.enterText(find.byType(TextField), fiftyWords);
    await tester.pump();
    expect(find.text('✓ 50 words (Requirement met)'), findsOneWidget);
    final btnWidgetAfter = tester.widget<ElevatedButton>(submitBtnFinder);
    expect(btnWidgetAfter.onPressed, isNotNull);

    // 5. Submit progress -> dashboard unblocks
    await tester.tap(submitBtnFinder);
    await tester.pumpAndSettle();

    expect(find.text('Daily Progress Required'), findsNothing);
    expect(find.text('Important normal task'), findsOneWidget);
    expect(find.text('Miss count: 0'), findsOneWidget);
  });

  testWidgets('penalty rule rendered in separate section and deleting is free',
      (tester) async {
    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 'p1',
            'description': 'No ruminating today',
            'type': 'penalty',
            'deadline': '2099-01-01T23:59:00+05:30',
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
            child: const DashboardScreen(showPenaltiesOnly: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Penalties & Rules section header and compact badge
    expect(find.text('Penalties & Rules'), findsOneWidget);
    expect(find.text('No ruminating today'), findsOneWidget);
    expect(find.text('Rs.10'), findsOneWidget);

    // Long-press to open actions
    await tester.longPress(find.text('No ruminating today'));
    await tester.pumpAndSettle();

    expect(find.text('Delete penalty rule'), findsOneWidget);
    await tester.tap(find.text('Delete penalty rule'));
    await tester.pumpAndSettle();

    expect(find.text('Delete this penalty rule?'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('free (costs Rs. 0)'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Delete (free)'));
    await tester.pumpAndSettle();

    expect(find.text('No ruminating today'), findsNothing);
    expect(find.text('No penalty rules active. Add one from the Add tab.'), findsOneWidget);

    final out = jsonDecode(fake.lastPutContent!) as Map<String, dynamic>;
    expect((out['tasks'] as List).isEmpty, isTrue);
    expect(out.containsKey('pending_notifications'), isFalse);
  });

  testWidgets('MainTabs separates tasks and penalties into distinct tabs with individual red dot badges',
      (tester) async {
    final nowIst = DateTime.now().toUtc().add(istOffset);
    final todayIso = specificDeadlineIso(DateTime(nowIst.year, nowIst.month, nowIst.day, 23, 59));

    final fake = FakeGithub(
      initialContent: jsonEncode({
        'penalty': {'month': '2026-08', 'miss_count': 0},
        'tasks': [
          {
            'id': 'task-1',
            'description': 'Regular Task Today',
            'type': 'normal',
            'deadline': todayIso,
            'status': 'pending',
            'last_progress_date': todayIstDateString(),
          },
          {
            'id': 'penalty-1',
            'description': 'Rule No Stress',
            'type': 'penalty',
            'deadline': todayIso,
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
          child: const MainTabs(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Both red dot badges are visible on bottom navigation bar
    expect(app.hasPendingTasksToday, isTrue);
    expect(app.hasPendingPenaltiesToday, isTrue);

    final badges = tester.widgetList<Badge>(find.byType(Badge)).toList();
    expect(badges.any((b) => b.isLabelVisible && b.child is Icon && (b.child as Icon).icon == Icons.list_alt), isTrue);
    expect(badges.any((b) => b.isLabelVisible && b.child is Icon && (b.child as Icon).icon == Icons.warning_amber_rounded), isTrue);

    // 2. Initial tab is Tasks (index 0): regular task is shown, penalty rule is NOT shown
    expect(find.text('Regular Task Today'), findsOneWidget);
    expect(find.text('Rule No Stress'), findsNothing);

    // 3. Switch to Penalties tab (index 1)
    await tester.tap(find.text('Penalties'));
    await tester.pumpAndSettle();

    // In Penalties tab: penalty rule is shown, regular task is NOT shown
    expect(find.text('Rule No Stress'), findsOneWidget);
    expect(find.text('Regular Task Today'), findsNothing);
    expect(find.text('Rs.10'), findsOneWidget);
  });
}




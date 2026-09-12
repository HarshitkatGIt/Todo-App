import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:fnb_commitment/main.dart';
import 'package:fnb_commitment/state/app_state.dart';
import 'package:fnb_commitment/screens/dashboard_screen.dart';
import 'package:fnb_commitment/screens/add_task_screen.dart';

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
}

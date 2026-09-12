import 'package:flutter_test/flutter_test.dart';

import 'package:fnb_commitment/utils/ist.dart';

void main() {
  group('ist utils', () {
    test('advanceDeadline24h adds exactly 24h, same time of day', () {
      expect(
        advanceDeadline24h('2026-08-24T16:25:00+05:30'),
        '2026-08-25T16:25:00+05:30',
      );
    });

    test('advanceDeadline24h crosses month boundary', () {
      expect(
        advanceDeadline24h('2026-08-31T23:00:00+05:30'),
        '2026-09-01T23:00:00+05:30',
      );
    });

    test('advanceDeadline24h crosses year boundary', () {
      expect(
        advanceDeadline24h('2026-12-31T09:00:00+05:30'),
        '2027-01-01T09:00:00+05:30',
      );
    });

    test('formatIst renders IST wall-clock time', () {
      final s = formatIst('2026-08-24T16:25:00+05:30');
      expect(s, contains('24 Aug 2026'));
      expect(s, contains('04:25'));
      expect(s, contains('PM'));
    });

    test('specificDeadlineIso builds a +05:30 string', () {
      expect(
        specificDeadlineIso(DateTime(2026, 8, 24, 16, 25)),
        '2026-08-24T16:25:00+05:30',
      );
    });

    test('nextDailyDeadlineIso returns +05:30 at the given hour', () {
      final iso = nextDailyDeadlineIso(9, 0);
      expect(iso.endsWith('T09:00:00+05:30'), isTrue);
    });

    test('isPastDeadline', () {
      expect(isPastDeadline('2000-01-01T00:00:00+05:30'), isTrue);
      expect(isPastDeadline('2099-01-01T00:00:00+05:30'), isFalse);
    });

    test('isSameIstDay compares only the IST calendar day', () {
      final now = DateTime.utc(2026, 8, 26, 12, 0); // 17:30 IST same day
      expect(
        isSameIstDay('2026-08-26T09:00:00+05:30', now),
        isTrue,
      );
      expect(
        isSameIstDay('2026-08-27T09:00:00+05:30', now),
        isFalse,
      );
      expect(
        isSameIstDay('2026-08-25T23:00:00+05:30', now),
        isFalse,
      );
    });

    test('isDailyActionableToday requires the deadline to be today and not past',
        () {
      final todayMorning = DateTime.utc(2026, 8, 26, 1, 0); // 06:30 IST
      // deadline later today -> actionable
      expect(
        isDailyActionableToday('2026-08-26T09:00:00+05:30', todayMorning),
        isTrue,
      );
      // deadline already past today -> not actionable
      expect(
        isDailyActionableToday('2026-08-26T05:00:00+05:30', todayMorning),
        isFalse,
      );
      // deadline tomorrow -> already done for today, not actionable
      expect(
        isDailyActionableToday('2026-08-27T09:00:00+05:30', todayMorning),
        isFalse,
      );
    });
  });
}

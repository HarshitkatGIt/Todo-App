import 'package:intl/intl.dart';

const istOffset = Duration(hours: 5, minutes: 30);

String pad2(int n) => n.toString().padLeft(2, '0');

DateTime parseDeadline(String iso) => DateTime.parse(iso);

DateTime istWallFromIso(String iso) => DateTime.parse(iso).toUtc().add(istOffset);

DateTime toUtcInstant(String iso) => DateTime.parse(iso).toUtc();

String toIsoIst(DateTime utcInstant) {
  final ist = utcInstant.toUtc().add(istOffset);
  return '${ist.year}-${pad2(ist.month)}-${pad2(ist.day)}T${pad2(ist.hour)}:${pad2(ist.minute)}:00+05:30';
}

String formatIst(String iso) {
  final ist = DateTime.parse(iso).toUtc().add(istOffset);
  return DateFormat('dd MMM yyyy, hh:mm a').format(ist);
}

String timeOnlyIst(String iso) {
  final ist = DateTime.parse(iso).toUtc().add(istOffset);
  return DateFormat('hh:mm a').format(ist);
}

DateTime nowUtc() => DateTime.now().toUtc();

String nextDailyDeadlineIso(int hour, int minute) {
  final nowIst = DateTime.now().toUtc().add(istOffset);
  var target = DateTime(nowIst.year, nowIst.month, nowIst.day, hour, minute);
  if (nowIst.isAfter(target)) {
    target = target.add(const Duration(days: 1));
  }
  return '${target.year}-${pad2(target.month)}-${pad2(target.day)}T${pad2(hour)}:${pad2(minute)}:00+05:30';
}

String specificDeadlineIso(DateTime istWall) {
  return '${istWall.year}-${pad2(istWall.month)}-${pad2(istWall.day)}T${pad2(istWall.hour)}:${pad2(istWall.minute)}:00+05:30';
}

String advanceDeadline24h(String iso) {
  final instant = DateTime.parse(iso).toUtc().add(const Duration(days: 1));
  return toIsoIst(instant);
}

bool isPastDeadline(String iso, [DateTime? now]) {
  now ??= nowUtc();
  return now.isAfter(DateTime.parse(iso).toUtc());
}

bool isSameIstDay(String iso, DateTime now) {
  final ist = DateTime.parse(iso).toUtc().add(istOffset);
  final nowIst = now.toUtc().add(istOffset);
  return ist.year == nowIst.year &&
      ist.month == nowIst.month &&
      ist.day == nowIst.day;
}

bool isDailyActionableToday(String iso, [DateTime? now]) {
  now ??= nowUtc();
  return !isPastDeadline(iso, now) && isSameIstDay(iso, now);
}

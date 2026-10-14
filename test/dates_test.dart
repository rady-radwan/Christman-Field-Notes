import 'package:christman_field_notes/util/dates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Tuesday, Oct 13 2026.
  final now = DateTime(2026, 10, 13, 12);
  final g = DateGroups(now);

  test('date groups do not overlap', () {
    expect(g.groupOf(DateTime(2026, 10, 12, 8)), DateGroup.thisWeek); // Monday
    expect(g.groupOf(DateTime(2026, 10, 11, 8)), DateGroup.pastWeek); // Sunday
    expect(g.groupOf(DateTime(2026, 10, 5, 8)), DateGroup.pastWeek);
    expect(g.groupOf(DateTime(2026, 10, 4, 8)), DateGroup.earlierThisMonth);
    expect(g.groupOf(DateTime(2026, 9, 30, 8)), DateGroup.older);
  });

  test('day text', () {
    expect(dayText(DateTime(2026, 10, 13, 9), now), 'Today');
    expect(dayText(DateTime(2026, 10, 12, 9), now), 'Yesterday');
  });

  test('time text', () {
    expect(timeText(DateTime(2026, 10, 13, 9, 5)), '9:05 AM');
    expect(timeText(DateTime(2026, 10, 13, 0, 30)), '12:30 AM');
    expect(timeText(DateTime(2026, 10, 13, 13, 0)), '1:00 PM');
  });

  test('reported, due and overdue text', () {
    expect(reportedText(DateTime(2026, 10, 13, 16, 31)), 'Tue, Oct 13 · 4:31 PM');
    expect(dueText(DateTime(2026, 10, 13, 23, 59), now), 'Due today');
    expect(dueText(DateTime(2026, 10, 14, 23, 59), now), 'Due tomorrow');
    expect(dueText(DateTime(2026, 10, 18, 23, 59), now), 'Due in 5 days');
    expect(spanText(const Duration(days: 3, hours: 4, minutes: 10)), '3 days, 4 hrs');
    expect(spanText(const Duration(hours: 1, minutes: 5)), '1 hr, 5 min');
    expect(spanText(const Duration(minutes: 20)), '20 min');
    expect(overdueText(DateTime(2026, 10, 11, 12), now), '🔴 OVERDUE · 2 days');
  });
}

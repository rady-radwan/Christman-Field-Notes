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
}

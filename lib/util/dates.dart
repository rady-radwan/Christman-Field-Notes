const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

String shortDate(DateTime d) {
  final now = DateTime.now();
  final s = '${_months[d.month - 1]} ${d.day}';
  return d.year == now.year ? s : '$s, ${d.year}';
}

/// "Today", "Yesterday" or "Oct 9".
String dayText(DateTime d, [DateTime? now]) {
  final today = _day(now ?? DateTime.now());
  final diff = today.difference(_day(d)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return shortDate(d);
}

String timeText(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

String dayTimeText(DateTime d) => '${dayText(d)}, ${timeText(d)}';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// When an observation was reported: "Tue, Oct 13 · 4:31 PM".
String reportedText(DateTime d) => '${_weekdays[d.weekday - 1]}, ${shortDate(d)} · ${timeText(d)}';

/// A length of time for people: "3 days, 4 hrs", "5 hrs, 12 min", "20 min".
String spanText(Duration d) {
  if (d.isNegative) d = -d;
  String unit(int n, String one, String many) => '$n ${n == 1 ? one : many}';
  final days = d.inDays, hours = d.inHours % 24, mins = d.inMinutes % 60;
  if (days > 0) return hours > 0 ? '${unit(days, 'day', 'days')}, ${unit(hours, 'hr', 'hrs')}' : unit(days, 'day', 'days');
  if (d.inHours > 0) return mins > 0 ? '${unit(d.inHours, 'hr', 'hrs')}, $mins min' : unit(d.inHours, 'hr', 'hrs');
  return '${d.inMinutes < 1 ? 1 : d.inMinutes} min';
}

/// Days until the due date: "Due today", "Due tomorrow", "Due in 5 days", "Was due 2 days ago".
String dueText(DateTime due, [DateTime? now]) {
  final days = _day(due).difference(_day(now ?? DateTime.now())).inDays;
  if (days == 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  if (days > 1) return 'Due in $days days';
  return days == -1 ? 'Was due yesterday' : 'Was due ${-days} days ago';
}

/// "🔴 OVERDUE · 3 days, 4 hrs".
String overdueText(DateTime due, [DateTime? now]) => '🔴 OVERDUE · ${spanText((now ?? DateTime.now()).difference(due))}';

/// The four non-overlapping date groups used by the "By date" tab.
enum DateGroup { thisWeek, pastWeek, earlierThisMonth, older }

class DateGroups {
  DateGroups(DateTime now) {
    final today = _day(now);
    thisWeekStart = today.subtract(Duration(days: today.weekday - 1)); // Monday
    pastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
    monthStart = DateTime(today.year, today.month, 1);
    this.today = today;
  }

  late final DateTime today, thisWeekStart, pastWeekStart, monthStart;

  DateGroup groupOf(DateTime d) {
    if (!d.isBefore(thisWeekStart)) return DateGroup.thisWeek;
    if (!d.isBefore(pastWeekStart)) return DateGroup.pastWeek;
    if (!d.isBefore(monthStart)) return DateGroup.earlierThisMonth;
    return DateGroup.older;
  }

  String label(DateGroup g) => switch (g) {
        DateGroup.thisWeek => 'This week',
        DateGroup.pastWeek => 'Past week',
        DateGroup.earlierThisMonth => 'Earlier this month',
        DateGroup.older => 'Older',
      };

  String range(DateGroup g) {
    String fmt(DateTime d) => '${_months[d.month - 1]} ${d.day}';
    DateTime yesterdayOf(DateTime d) => d.subtract(const Duration(days: 1));
    switch (g) {
      case DateGroup.thisWeek:
        return '${fmt(thisWeekStart)} to ${fmt(today)}';
      case DateGroup.pastWeek:
        return '${fmt(pastWeekStart)} to ${fmt(yesterdayOf(thisWeekStart))}';
      case DateGroup.earlierThisMonth:
        return '${fmt(monthStart)} to ${fmt(yesterdayOf(pastWeekStart))}';
      case DateGroup.older:
        final cut = monthStart.isBefore(pastWeekStart) ? monthStart : pastWeekStart;
        return 'Before ${fmt(cut)}';
    }
  }
}

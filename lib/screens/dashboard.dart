import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/dates.dart';
import '../widgets/common.dart';

/// Project dashboard: key numbers, observations by category, by person and by type.
class DashboardView extends StatelessWidget {
  const DashboardView({super.key, this.bottomPadding = 32});
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    final d = state.dashboard;

    return RefreshIndicator(
      onRefresh: () => state.reload(quiet: true),
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final metrics = <(String, int, Color?, String)>[
          ('Total', d.total, null, 'All observations except voided'),
          ('🔵 Open', d.open, c.statusFg(NoteStatus.open), NoteStatus.open.meaning),
          ('🟡 In Progress', d.inProgress, c.statusFg(NoteStatus.inProgress), NoteStatus.inProgress.meaning),
          ('🟠 Pending Verification', d.pendingVerification, c.statusFg(NoteStatus.pendingVerification),
              NoteStatus.pendingVerification.meaning),
          ('🟢 Resolved', d.resolved, c.statusFg(NoteStatus.resolved), NoteStatus.resolved.meaning),
          ('🔴 Overdue', d.overdue, c.urgentText, 'Past the due date and not resolved'),
          ('Critical / Urgent', d.criticalUrgent, Priority.critical.color, 'Open observations with Critical or Urgent priority'),
        ];

        final tiles = LayoutBuilder(builder: (context, b) {
          final cols = b.maxWidth >= 1000 ? 7 : (b.maxWidth >= 640 ? 4 : 2);
          final w = (b.maxWidth - (cols - 1) * 10) / cols;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final m in metrics) SizedBox(width: w, child: _MetricTile(label: m.$1, value: m.$2, color: m.$3, hint: m.$4)),
          ]);
        });

        final category = _Panel(
          title: 'Observations by category',
          trailing: _Legend(items: [('Open', c.accent), ('Resolved', c.line2)]),
          child: _CategoryBars(data: d.byCategory),
        );
        final people = _Panel(
          title: 'Observations by assigned person',
          child: _AssigneeTable(rows: d.byAssignee),
        );
        final types = _Panel(
          title: 'Open observations by type',
          child: _TypeBars(data: d.openByType),
        );
        final status = _Panel(title: 'Status overview', child: _StatusStrip(data: d));

        return ListView(
          padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPadding),
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  state.project?.name ?? '',
                  style: TextStyle(fontSize: 14, color: c.muted, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('Updated ${timeText(DateTime.now())}', style: TextStyle(fontSize: 12, color: c.muted)),
            ]),
            const SizedBox(height: 10),
            tiles,
            const SizedBox(height: 14),
            status,
            const SizedBox(height: 14),
            if (wide)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: category),
                const SizedBox(width: 14),
                Expanded(child: types),
              ])
            else ...[
              category,
              const SizedBox(height: 14),
              types,
            ],
            const SizedBox(height: 14),
            people,
          ],
        );
      }),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value, required this.hint, this.color});
  final String label;
  final int value;
  final String hint;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    return Tooltip(
      message: hint,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border(
            top: BorderSide(color: color ?? c.ink2, width: 3),
            left: BorderSide(color: c.line),
            right: BorderSide(color: c.line),
            bottom: BorderSide(color: c.line),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$value', style: condensed(34, color: color)),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.muted)),
        ]),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(title, style: condensed(20))),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.items});
  final List<(String, Color)> items;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    return Wrap(spacing: 10, children: [
      for (final i in items)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: i.$2, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 4),
          Text(i.$1, style: TextStyle(fontSize: 12, color: c.muted)),
        ]),
    ]);
  }
}

/// Horizontal bars: open (copper) and resolved (gray) per category. Tap a bar to open that category.
class _CategoryBars extends StatelessWidget {
  const _CategoryBars({required this.data});
  final Map<String, (int, int)> data;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    final state = context.read<AppState>();
    if (data.isEmpty) return Text('No categories yet.', style: TextStyle(color: c.muted));
    final max = data.values.map((v) => v.$1 + v.$2).fold<int>(0, (a, b) => a > b ? a : b);
    return Column(children: [
      for (final e in data.entries)
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            state.setCategoryTab(e.key);
            state.setTab(2);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(
                width: 110,
                child: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: LayoutBuilder(builder: (context, b) {
                  final unit = max == 0 ? 0.0 : b.maxWidth / max;
                  return Row(children: [
                    Container(
                      width: e.value.$1 * unit,
                      height: 18,
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: BorderRadius.horizontal(
                          left: const Radius.circular(4),
                          right: Radius.circular(e.value.$2 == 0 ? 4 : 0),
                        ),
                      ),
                    ),
                    Container(
                      width: e.value.$2 * unit,
                      height: 18,
                      decoration: BoxDecoration(
                        color: c.line2,
                        borderRadius: BorderRadius.horizontal(
                          right: const Radius.circular(4),
                          left: Radius.circular(e.value.$1 == 0 ? 4 : 0),
                        ),
                      ),
                    ),
                  ]);
                }),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 64,
                child: Text('${e.value.$1} / ${e.value.$1 + e.value.$2}',
                    textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: c.muted)),
              ),
            ]),
          ),
        ),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: Text('Open / total. Tap a category to see its observations.', style: TextStyle(fontSize: 12, color: c.muted)),
      ),
    ]);
  }
}

class _TypeBars extends StatelessWidget {
  const _TypeBars({required this.data});
  final Map<ObsType, int> data;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    final entries = data.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return Text('No open observations.', style: TextStyle(color: c.muted));
    final max = entries.first.value;
    return Column(children: [
      for (final e in entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Icon(e.key.icon, size: 16, color: c.avatarInk),
            const SizedBox(width: 6),
            SizedBox(
              width: 150,
              child: Text(e.key.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, b) => Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: b.maxWidth * e.value / max,
                    height: 14,
                    decoration: BoxDecoration(color: c.avatarInk.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(width: 28, child: Text('${e.value}', textAlign: TextAlign.right, style: TextStyle(color: c.muted))),
          ]),
        ),
    ]);
  }
}

/// One long bar split by status.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.data});
  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    final parts = <(NoteStatus, int)>[
      (NoteStatus.open, data.open),
      (NoteStatus.inProgress, data.inProgress),
      (NoteStatus.pendingVerification, data.pendingVerification),
      (NoteStatus.onHold, data.onHold),
      (NoteStatus.resolved, data.resolved),
      (NoteStatus.voided, data.voided),
    ];
    final total = parts.fold<int>(0, (a, p) => a + p.$2);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 22,
          child: total == 0
              ? Container(color: c.line)
              : Row(children: [
                  for (final p in parts)
                    if (p.$2 > 0)
                      Expanded(
                        flex: p.$2,
                        child: Tooltip(
                          message: '${p.$1.label}: ${p.$2}',
                          child: Container(color: c.statusFg(p.$1).withValues(alpha: 0.85)),
                        ),
                      ),
                ]),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 14, runSpacing: 6, children: [
        for (final p in parts)
          Text('${p.$1.emoji} ${p.$1.label}: ${p.$2}', style: TextStyle(fontSize: 13, color: c.ink2)),
      ]),
    ]);
  }
}

class _AssigneeTable extends StatelessWidget {
  const _AssigneeTable({required this.rows});
  final List<AssigneeRow> rows;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    if (rows.isEmpty) return Text('Nothing assigned yet.', style: TextStyle(color: c.muted));
    final head = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.muted, letterSpacing: 0.6);
    return LayoutBuilder(builder: (context, box) {
      final narrow = box.maxWidth < 560;
      final w = narrow ? 58.0 : 80.0;
      Widget num(int v, {Color? color}) => SizedBox(
            width: w,
            child: Text('$v',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: v > 0 ? FontWeight.w700 : FontWeight.w400,
                  color: v > 0 ? (color ?? c.ink) : c.muted,
                )),
          );
      Widget person(AssigneeRow r) => Row(children: [
            if (r.userId.isEmpty) Icon(Icons.groups_outlined, size: 26, color: c.muted) else Avatar(name: r.name, size: 26),
            const SizedBox(width: 8),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (narrow && r.company.isNotEmpty)
                  Text(r.company, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
              ]),
            ),
          ]);
      return Column(children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Expanded(flex: 3, child: Text(narrow ? 'PERSON / COMPANY' : 'PERSON', style: head)),
            if (!narrow) Expanded(flex: 3, child: Text('COMPANY / TRADE', style: head)),
            SizedBox(width: w, child: Text('OPEN', textAlign: TextAlign.right, style: head)),
            SizedBox(width: w, child: Text('OVERDUE', textAlign: TextAlign.right, style: head)),
            if (!narrow) SizedBox(width: w, child: Text('RESOLVED', textAlign: TextAlign.right, style: head)),
          ]),
        ),
        for (final r in rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
            child: Row(children: [
              Expanded(flex: 3, child: person(r)),
              if (!narrow)
                Expanded(
                  flex: 3,
                  child: Text(r.company.isEmpty ? '—' : r.company,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.ink2)),
                ),
              num(r.open, color: c.accentText),
              num(r.overdue, color: c.urgentText),
              if (!narrow) num(r.resolved),
            ]),
          ),
      ]);
    });
  }
}

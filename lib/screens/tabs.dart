import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/dates.dart';
import '../widgets/common.dart';
import '../widgets/note_cards.dart';

typedef OpenNote = void Function(Note note);

/// Tab 1: open notes (Active + Suspended), sorted by priority then date.
class OpenNotesView extends StatelessWidget {
  const OpenNotesView({super.key, required this.onOpen, this.selectedId, this.bottomPadding = 96});
  final OpenNote onOpen;
  final String? selectedId;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    final list = state.openNotes;
    final cats = state.project?.categories ?? const [];

    Widget stat(String label, int value, [Color? color]) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$value', style: condensed(24, color: color)),
              Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
            ]),
          ),
        );

    return RefreshIndicator(
      onRefresh: () => state.reload(quiet: true),
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPadding),
        children: [
          Row(children: [
            stat('Active', state.count((n) => n.status == NoteStatus.active)),
            const SizedBox(width: 8),
            stat('Suspended', state.count((n) => n.status == NoteStatus.suspended)),
            const SizedBox(width: 8),
            stat('Urgent', state.count((n) => !n.status.isClosed && n.priority == Priority.urgent), c.urgentText),
            const SizedBox(width: 8),
            stat('For me', state.count((n) => !n.status.isClosed && state.isAssignedToMe(n)), c.accentText),
          ]),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              FnChip(label: 'All', selected: state.openCategories.isEmpty, onTap: () => state.toggleOpenCategory(null)),
              for (final cat in cats) ...[
                const SizedBox(width: 8),
                FnChip(
                  label: cat,
                  selected: state.openCategories.contains(cat),
                  onTap: () => state.toggleOpenCategory(cat),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Text(
                '${list.length} open ${list.length == 1 ? 'note' : 'notes'} · by priority, then date',
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
            ),
            FnChip(
              label: 'Assigned to me',
              icon: Icons.person_outline,
              selected: state.onlyMine,
              onTap: () => state.setOnlyMine(!state.onlyMine),
            ),
          ]),
          const SizedBox(height: 12),
          if (list.isEmpty)
            _Empty(
              text: state.notes.isEmpty
                  ? 'No notes yet. Use "New note" to report the first issue.'
                  : 'No open notes match these filters.',
            ),
          for (final n in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: NoteCard(note: n, selected: n.id == selectedId, onTap: () => onOpen(n)),
            ),
        ],
      ),
    );
  }
}

/// Tab 2: every note, grouped This week / Past week / Earlier this month / Older.
class ByDateView extends StatelessWidget {
  const ByDateView({super.key, required this.onOpen, this.selectedId, this.bottomPadding = 96});
  final OpenNote onOpen;
  final String? selectedId;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    final groups = DateGroups(DateTime.now());
    final byGroup = <DateGroup, List<Note>>{};
    for (final n in state.notesByDate) {
      byGroup.putIfAbsent(groups.groupOf(n.createdAt), () => []).add(n);
    }
    return RefreshIndicator(
      onRefresh: () => state.reload(quiet: true),
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPadding),
        children: [
          if (byGroup.isEmpty) const _Empty(text: 'No notes yet.'),
          for (final g in DateGroup.values)
            if (byGroup[g] != null) ...[
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: Text(groups.label(g), style: condensed(20))),
                Text(
                  '${groups.range(g)} · ${byGroup[g]!.length} ${byGroup[g]!.length == 1 ? 'note' : 'notes'}',
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ]),
              const SizedBox(height: 8),
              for (final n in byGroup[g]!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: NoteRow(note: n, selected: n.id == selectedId, onTap: () => onOpen(n)),
                ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

/// Tab 3: the full history of one category.
class ByCategoryView extends StatelessWidget {
  const ByCategoryView({super.key, required this.onOpen, this.selectedId, this.bottomPadding = 96});
  final OpenNote onOpen;
  final String? selectedId;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = FnColors.of(context);
    final cats = state.project?.categories ?? const [];
    final list = state.categoryNotes;
    return RefreshIndicator(
      onRefresh: () => state.reload(quiet: true),
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 14, 16, bottomPadding),
        children: [
          Text('Choose a category to see its full history', style: TextStyle(fontSize: 13, color: c.muted)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final cat in cats)
              FnChip(label: cat, square: true, selected: cat == state.categoryTab, onTap: () => state.setCategoryTab(cat)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Text('${state.categoryTab ?? ''} · ${list.length} ${list.length == 1 ? 'note' : 'notes'}',
                  style: condensed(22)),
            ),
            FnChip(
              label: state.showClosed ? 'Hide solved' : 'Show solved',
              selected: false,
              onTap: () => state.setShowClosed(!state.showClosed),
            ),
          ]),
          const SizedBox(height: 10),
          if (list.isEmpty) const _Empty(text: 'No notes in this category yet.'),
          for (final n in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: NoteRow(note: n, byCategory: true, selected: n.id == selectedId, onTap: () => onOpen(n)),
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: FnColors.of(context).muted, fontSize: 14)),
      );
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/dates.dart';
import 'common.dart';

/// Large card used on the Open notes tab.
class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.note, required this.onTap, this.selected = false, this.showStatusBadge = false});
  final Note note;
  final VoidCallback onTap;
  final bool selected;
  final bool showStatusBadge;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    final state = context.watch<AppState>();
    return ClosedFade(
      closed: note.status.isClosed,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? c.accent : c.line, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NoteThumb(note),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        PriorityBadge(note.priority),
                        const SizedBox(width: 6),
                        Flexible(child: CategoryTag(note.category)),
                        if (showStatusBadge) ...[const SizedBox(width: 6), StatusBadge(note.status)],
                        const Spacer(),
                        Text(dayText(note.createdAt), style: TextStyle(fontSize: 12, color: c.muted)),
                      ]),
                      const SizedBox(height: 6),
                      Text(note.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, height: 1.2)),
                      const SizedBox(height: 4),
                      Text('${state.nameOf(note.issuerId)} → ${state.assignedText(note)}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.muted)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Text('● ${note.status.label}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.statusFg(note.status))),
                        const SizedBox(width: 10),
                        Text(note.replies.length == 1 ? '1 reply' : '${note.replies.length} replies',
                            style: TextStyle(fontSize: 12, color: c.muted)),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact row used on the By date and By category tabs.
class NoteRow extends StatelessWidget {
  const NoteRow({super.key, required this.note, required this.onTap, this.byCategory = false, this.selected = false});
  final Note note;
  final VoidCallback onTap;
  final bool byCategory;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    final state = context.watch<AppState>();
    final sub = byCategory
        ? '${note.priority.label} · ${state.nameOf(note.issuerId)} · ${dayText(note.createdAt)}'
        : '${note.category} · ${note.priority.label} · ${dayText(note.createdAt)}';
    return ClosedFade(
      closed: note.status.isClosed,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? c.accent : c.line, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              NoteThumb(note, size: 52, showCount: false),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(note.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(note.status),
            ]),
          ),
        ),
      ),
    );
  }
}

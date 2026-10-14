import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../util/dates.dart';
import 'common.dart';

/// Small icon + text pair used in card footers.
class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text, {this.color, this.bold = false});
  final IconData icon;
  final String text;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    final col = color ?? c.muted;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: col),
      const SizedBox(width: 4),
      Flexible(
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: col, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
      ),
    ]);
  }
}

/// Due date for a card: "Due in 3 days", or the overdue badge.
class DueLine extends StatelessWidget {
  const DueLine(this.note, {super.key});
  final Note note;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    if (note.dueAt == null) return const SizedBox.shrink();
    if (note.isOverdue) return OverdueBadge(note);
    final text = note.status.isClosed ? 'Due ${shortDate(note.dueAt!)}' : dueText(note.dueAt!);
    final soon = !note.status.isClosed && note.dueAt!.difference(DateTime.now()).inHours < 48;
    return _Meta(Icons.event_outlined, text, color: soon ? c.accentText : null, bold: soon);
  }
}

/// Large card used on the Open Observations tab.
class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.note, required this.onTap, this.selected = false, this.showStatusBadge = true});
  final Note note;
  final VoidCallback onTap;
  final bool selected;
  final bool showStatusBadge;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    final state = context.watch<AppState>();
    final overdue = note.isOverdue;
    final discussion = note.replies.length;
    final hasVoice = note.audio.isNotEmpty || note.replies.any((r) => r.audio.isNotEmpty);
    return ClosedFade(
      closed: note.status.isClosed,
      child: Material(
        color: c.card,
        elevation: c.dark ? 0 : 0.5,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? c.accent : (overdue ? c.urgentText.withValues(alpha: 0.55) : c.line),
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NoteThumb(note, size: 96),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        CodeTag(note),
                        const SizedBox(width: 8),
                        Flexible(child: TypeTag(note.obsType)),
                        const Spacer(),
                        Tooltip(
                          message: 'Reported on',
                          child: Text(reportedText(note.createdAt), style: TextStyle(fontSize: 12, color: c.muted)),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text(note.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, height: 1.2)),
                      const SizedBox(height: 7),
                      Wrap(spacing: 6, runSpacing: 5, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        PriorityBadge(note.priority),
                        CategoryTag(note.category),
                        if (showStatusBadge) StatusBadge(note.status),
                      ]),
                      if (note.location.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _Meta(Icons.place_outlined, note.location),
                      ],
                      const SizedBox(height: 5),
                      Text.rich(
                        TextSpan(style: TextStyle(fontSize: 12.5, color: c.muted), children: [
                          const TextSpan(text: 'Reported by '),
                          TextSpan(text: state.nameOf(note.issuerId), style: TextStyle(color: c.ink2, fontWeight: FontWeight.w600)),
                          const TextSpan(text: '  →  '),
                          TextSpan(text: state.assignedText(note), style: TextStyle(color: c.ink2, fontWeight: FontWeight.w600)),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        DueLine(note),
                        _Meta(Icons.forum_outlined, discussion == 1 ? '1 message' : '$discussion messages'),
                        if (hasVoice) const _Meta(Icons.mic_none_rounded, 'Voice'),
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

/// Compact row used on the By Date and By Category tabs.
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
        ? '${note.obsType.label} · ${note.priority.label} · ${state.nameOf(note.issuerId)} · ${reportedText(note.createdAt)}'
        : '${note.category} · ${note.obsType.label} · ${note.priority.label} · ${reportedText(note.createdAt)}';
    return ClosedFade(
      closed: note.status.isClosed,
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? c.accent : (note.isOverdue ? c.urgentText.withValues(alpha: 0.55) : c.line),
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              NoteThumb(note, size: 56, showCount: false),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      CodeTag(note),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(note.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                    ]),
                    const SizedBox(height: 3),
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
                    if (note.dueAt != null) ...[const SizedBox(height: 4), DueLine(note)],
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

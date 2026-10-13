import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Christman logo in the right color for light or dark mode.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.full = false, this.height = 20});
  final bool full;
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = FnColors.of(context).dark;
    final kind = full ? 'full' : 'mark';
    return Image.asset(
      'assets/logo/christman-$kind-${dark ? 'dark' : 'light'}.png',
      height: height,
      fit: BoxFit.contain,
      semanticLabel: full ? 'Christman, since 1894' : 'Christman',
    );
  }
}

class PriorityBadge extends StatelessWidget {
  const PriorityBadge(this.priority, {super.key, this.large = false});
  final Priority priority;
  final bool large;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: large ? 8 : 7, vertical: large ? 3 : 2),
        decoration: BoxDecoration(color: priority.color, borderRadius: BorderRadius.circular(5)),
        child: Text(
          priority.label.toUpperCase(),
          style: condensed(large ? 13 : 12, color: Colors.white, letterSpacing: 0.7),
        ),
      );
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.large = false});
  final NoteStatus status;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: large ? 3 : 2),
      decoration: BoxDecoration(color: c.statusBg(status), borderRadius: BorderRadius.circular(large ? 5 : 10)),
      child: Text(
        status.label,
        style: TextStyle(fontSize: large ? 13 : 12, fontWeight: FontWeight.w700, color: c.statusFg(status)),
      ),
    );
  }
}

class CategoryTag extends StatelessWidget {
  const CategoryTag(this.text, {super.key, this.large = false});
  final String text;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7, vertical: large ? 2 : 1),
      decoration: BoxDecoration(
        border: Border.all(color: c.line2),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(text, style: TextStyle(fontSize: large ? 13 : 12, fontWeight: FontWeight.w600, color: c.ink2)),
    );
  }
}

/// Rounded toggle chip used for filters and form choices.
class FnChip extends StatelessWidget {
  const FnChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.selectedColor,
    this.icon,
    this.square = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? selectedColor;
  final IconData? icon;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    final bg = selected ? (selectedColor ?? c.selBg) : c.surface;
    final fg = selected ? (selectedColor != null ? Colors.white : c.selFg) : c.ink;
    final bd = selected ? (selectedColor ?? c.selBg) : c.line2;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(square ? 8 : 20),
          side: BorderSide(color: bd),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(square ? 8 : 20),
          child: Container(
            constraints: const BoxConstraints(minHeight: 38),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
                Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.size = 34});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    final initials = AppUser(id: '', name: name, email: '').initials;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.avatarBg, shape: BoxShape.circle),
      child: Text(initials, style: TextStyle(color: c.avatarInk, fontWeight: FontWeight.w700, fontSize: size * 0.38)),
    );
  }
}

/// Shows a stored photo reference (on this computer or on the server).
class RefImage extends StatelessWidget {
  const RefImage(this.photoRef, {super.key, this.fit = BoxFit.cover});
  final String photoRef;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().repo;
    final c = FnColors.of(context);
    return FutureBuilder<ImageProvider>(
      future: repo.image(photoRef),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(color: c.surface2, child: snap.hasError ? Icon(Icons.broken_image_outlined, color: c.muted) : null);
        }
        return Image(
          image: snap.data!,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Container(color: c.surface2, child: Icon(Icons.broken_image_outlined, color: c.muted)),
        );
      },
    );
  }
}

/// Square thumbnail of a note's first photo, with a photo count.
class NoteThumb extends StatelessWidget {
  const NoteThumb(this.note, {super.key, this.size = 88, this.showCount = true});
  final Note note;
  final double size;
  final bool showCount;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size > 60 ? 10 : 8),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (note.photos.isEmpty)
              Container(
                color: c.surface2,
                child: Icon(Icons.photo_camera_outlined, color: c.muted, size: size * 0.32),
              )
            else
              RefImage(note.photos.first),
            if (showCount && note.photos.isNotEmpty)
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xE61A1A1A), borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    note.photos.length == 1 ? '1 photo' : '${note.photos.length} photos',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Grays out solved and deactivated notes.
class ClosedFade extends StatelessWidget {
  const ClosedFade({super.key, required this.closed, required this.child});
  final bool closed;
  final Widget child;

  static const _grayscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    if (!closed) return child;
    final dark = FnColors.of(context).dark;
    return Opacity(opacity: dark ? 0.5 : 0.6, child: ColorFiltered(colorFilter: _grayscale, child: child));
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = FnColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: Text(text.toUpperCase(), style: condensed(15, color: c.muted, letterSpacing: 1.1))),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Shows a message from a failed action.
void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
}

void showInfo(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'OK', bool danger = false}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Priority.urgent.color, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return res ?? false;
}

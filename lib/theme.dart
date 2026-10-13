import 'package:flutter/material.dart';

import 'models.dart';

/// Brand copper from the Christman logo.
const brandCopper = Color(0xFFAE734B);

/// All app colors for one mode. Matches the approved mockup.
@immutable
class FnColors extends ThemeExtension<FnColors> {
  const FnColors({
    required this.dark,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.ink2,
    required this.muted,
    required this.line,
    required this.line2,
    required this.head,
    required this.headLine,
    required this.pill,
    required this.accent,
    required this.accentInk,
    required this.accentText,
    required this.selBg,
    required this.selFg,
    required this.avatarBg,
    required this.avatarInk,
    required this.tabOff,
    required this.dashed,
    required this.urgentText,
    required this.statusColors,
  });

  final bool dark;
  final Color bg, surface, surface2, ink, ink2, muted, line, line2, head, headLine, pill;
  final Color accent, accentInk, accentText, selBg, selFg, avatarBg, avatarInk, tabOff, dashed, urgentText;

  /// Status -> (text color, background color).
  final Map<NoteStatus, (Color, Color)> statusColors;

  Color statusFg(NoteStatus s) => statusColors[s]!.$1;
  Color statusBg(NoteStatus s) => statusColors[s]!.$2;

  static const light = FnColors(
    dark: false,
    bg: Color(0xFFF4F2EE),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF8F7F4),
    ink: Color(0xFF1A1A1A),
    ink2: Color(0xFF3A3835),
    muted: Color(0xFF5C5A56),
    line: Color(0xFFDEDAD3),
    line2: Color(0xFFC9C4BB),
    head: Color(0xFFFFFFFF),
    headLine: Color(0xFFDEDAD3),
    pill: Color(0xFFF4F2EE),
    accent: Color(0xFF8C5A32),
    accentInk: Color(0xFFFFFFFF),
    accentText: Color(0xFF8C5A32),
    selBg: Color(0xFF1A1A1A),
    selFg: Color(0xFFFFFFFF),
    avatarBg: Color(0xFFEFE4DA),
    avatarInk: Color(0xFF6E4526),
    tabOff: Color(0xFF77736D),
    dashed: Color(0xFFA39E96),
    urgentText: Color(0xFFB3261E),
    statusColors: {
      NoteStatus.active: (Color(0xFF2E7D4F), Color(0xFFE3F1E8)),
      NoteStatus.suspended: (Color(0xFF8A5A00), Color(0xFFFBF0D9)),
      NoteStatus.solved: (Color(0xFF4B5258), Color(0xFFE6E8E6)),
      NoteStatus.deactivated: (Color(0xFF4B5258), Color(0xFFE6E8E6)),
    },
  );

  static const darkColors = FnColors(
    dark: true,
    bg: Color(0xFF121212),
    surface: Color(0xFF1C1C1C),
    surface2: Color(0xFF242424),
    ink: Color(0xFFEDEBE7),
    ink2: Color(0xFFD6D2CB),
    muted: Color(0xFFA9A49C),
    line: Color(0xFF2C2C2C),
    line2: Color(0xFF45423E),
    head: Color(0xFF0A0A0A),
    headLine: Color(0xFF242424),
    pill: Color(0xFF1F1F1F),
    accent: Color(0xFFB98052),
    accentInk: Color(0xFF141414),
    accentText: Color(0xFFD19A6C),
    selBg: Color(0xFFEDEBE7),
    selFg: Color(0xFF141414),
    avatarBg: Color(0xFF3A2B1F),
    avatarInk: Color(0xFFE3B48C),
    tabOff: Color(0xFF8E8982),
    dashed: Color(0xFF5A5650),
    urgentText: Color(0xFFF2867E),
    statusColors: {
      NoteStatus.active: (Color(0xFF7BC896), Color(0xFF1D3326)),
      NoteStatus.suspended: (Color(0xFFE2B05A), Color(0xFF3A2E17)),
      NoteStatus.solved: (Color(0xFFA5ABA8), Color(0xFF2A2D2C)),
      NoteStatus.deactivated: (Color(0xFFA5ABA8), Color(0xFF2A2D2C)),
    },
  );

  static FnColors of(BuildContext context) => Theme.of(context).extension<FnColors>() ?? light;

  @override
  FnColors copyWith() => this;

  @override
  FnColors lerp(ThemeExtension<FnColors>? other, double t) {
    if (other is! FnColors) return this;
    return t < 0.5 ? this : other;
  }
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? FnColors.darkColors : FnColors.light;
  final scheme = ColorScheme.fromSeed(seedColor: brandCopper, brightness: brightness).copyWith(
    primary: c.accent,
    onPrimary: c.accentInk,
    secondary: c.selBg,
    onSecondary: c.selFg,
    surface: c.surface,
    onSurface: c.ink,
    outline: c.line2,
    outlineVariant: c.line,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Barlow',
    scaffoldBackgroundColor: c.bg,
    extensions: [c],
  );
  OutlineInputBorder border(Color color, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: color, width: w));
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink, fontFamily: 'Barlow'),
    appBarTheme: AppBarTheme(
      backgroundColor: c.head,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: c.headLine)),
      titleTextStyle: TextStyle(
        fontFamily: 'BarlowCondensed',
        fontWeight: FontWeight.w700,
        fontSize: 22,
        color: c.ink,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(c.line2),
      enabledBorder: border(c.line2),
      focusedBorder: border(c.accent, 2),
      hintStyle: TextStyle(color: c.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.accentInk,
        minimumSize: const Size(64, 48),
        textStyle: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.ink,
        minimumSize: const Size(64, 44),
        side: BorderSide(color: c.line2),
        textStyle: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w600, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accentText,
        textStyle: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
    dividerColor: c.line,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.accent.withValues(alpha: 0.16),
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontFamily: 'Barlow',
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: states.contains(WidgetState.selected) ? c.accentText : c.tabOff,
          )),
      iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(color: states.contains(WidgetState.selected) ? c.accentText : c.tabOff)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.selBg,
      contentTextStyle: TextStyle(color: c.selFg, fontFamily: 'Barlow', fontSize: 14),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Condensed heading style used for section titles and the "Field Notes" wordmark.
TextStyle condensed(double size, {Color? color, double letterSpacing = 0}) => TextStyle(
      fontFamily: 'BarlowCondensed',
      fontWeight: FontWeight.w700,
      fontSize: size,
      height: 1.05,
      color: color,
      letterSpacing: letterSpacing,
    );

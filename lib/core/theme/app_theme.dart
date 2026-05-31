import 'package:flutter/material.dart';

// ── Aghieri Color System ──────────────────────────────────────────────────────
class AghieriColors {
  static const bg           = Color(0xFF0A0A0F);
  static const surface      = Color(0xFF12121A);
  static const surfaceHigh  = Color(0xFF1A1A24);
  static const textPrimary  = Color(0xFFF0EFE8);
  static const textSecondary= Color(0xFF8B8B9A);
  static const accent       = Color(0xFF88D498);  // green
  static const accentDim    = Color(0xFF3D7A54);

  // ── ADHD-optimized task color palette (Sachs Center research) ──────────────
  // Muted, calming hues — reduce anxiety, enhance focus.
  // No bright red/orange. Yellow reserved for attention (not urgency).
  static const taskColors = [
    Color(0xFFA0D8EF),  // Light Sky Blue  — calming focus
    Color(0xFF96C8A2),  // Sage Green      — restorative balance
    Color(0xFFCD79DD),  // Muted Purple    — creative focus
    Color(0xFFFFE888),  // Soft Yellow     — gentle attention
    Color(0xFFD2B48C),  // Tan / Earthy    — grounding stability
    Color(0xFFA4FFCA),  // Mint Green      — restorative, light
  ];

  // Task type → ADHD-appropriate color
  static const taskTypeColors = {
    'homework': Color(0xFFA0D8EF),  // Light Sky Blue — focused, calm
    'project':  Color(0xFFD2B48C),  // Tan — stability for sustained work
    'study':    Color(0xFF96C8A2),  // Sage — restoring, low-anxiety
    'meeting':  Color(0xFFCD79DD),  // Muted Purple — social/creative
    'lab':      Color(0xFFA4FFCA),  // Mint — active but gentle
    'reading':  Color(0xFF96C8A2),  // Sage — calm focus
    'exam':     Color(0xFF4A90E2),  // Medium Blue — focused urgency (no red)
    'personal': Color(0xFF88D498),  // Accent green — personal balance
    'work':     Color(0xFFA0D8EF),  // Light Sky Blue — professional focus
  };

  // LED state colors
  static const ledIdle  = Color(0xFF7BB8D4);
  static const ledFocus = Color(0xFFFFF8E7);
  static const ledBreak = Color(0xFF88D498);

  // NO RED anywhere in the UI (ADHD design constraint)
}

// ── Typography ────────────────────────────────────────────────────────────────
// Fonts loaded via web/index.html CSS links.
// Typography mode is set once at startup from user profile.
//
// Modes:
//   'default'  — Poppins (logo) · Poppins (heading) · DM Sans (body)
//   'classic'  — Verdana everywhere (legible, familiar)
//   'adaptive' — OpenDyslexic everywhere; headings use BionicText widget
class AghieriTextStyles {
  // ── Active mode ────────────────────────────────────────────────────────────
  static String _mode = 'default';
  static void setMode(String mode) => _mode = mode;
  static String get mode => _mode;

  // ── Font family resolvers ──────────────────────────────────────────────────
  static String get _logoFont => switch (_mode) {
    'classic'  => 'Verdana',
    'adaptive' => 'OpenDyslexic',
    _          => 'Poppins',
  };
  static String get _headingFont => switch (_mode) {
    'classic'  => 'Verdana',
    'adaptive' => 'OpenDyslexic',
    _          => 'Poppins',
  };
  static String get _bodyFont => switch (_mode) {
    'classic'  => 'Verdana',
    'adaptive' => 'OpenDyslexic',
    _          => 'DM Sans',
  };

  // ── Spacing tweaks per font ────────────────────────────────────────────────
  // OpenDyslexic needs more line-height; Verdana slightly wider tracking.
  static double get _lineHeight => switch (_mode) {
    'adaptive' => 1.75,
    'classic'  => 1.55,
    _          => 1.50,
  };
  static double _tracking(double size) => switch (_mode) {
    'classic'  => size * 0.015,
    'adaptive' => size * 0.005,
    _          => size * 0.01,
  };

  // ── Style factories ────────────────────────────────────────────────────────
  static TextStyle logo({double size = 32, Color? color}) => TextStyle(
    fontFamily: _logoFont,
    fontSize: size,
    fontWeight: FontWeight.w700,
    color: color ?? AghieriColors.textPrimary,
    letterSpacing: size * 0.02,
    decoration: TextDecoration.none,
  );

  static TextStyle heading({
    double size = 22,
    FontWeight weight = FontWeight.w500,
    Color? color,
  }) => TextStyle(
    fontFamily: _headingFont,
    fontSize: size,
    fontWeight: _mode == 'adaptive' ? FontWeight.w700 : weight,
    color: color ?? AghieriColors.textPrimary,
    letterSpacing: _tracking(size),
    height: _lineHeight,
    decoration: TextDecoration.none,
  );

  static TextStyle body({
    double size = 16,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) => TextStyle(
    fontFamily: _bodyFont,
    fontSize: _mode == 'adaptive' ? size + 1 : size,  // OD reads best 1pt larger
    fontWeight: weight,
    color: color ?? AghieriColors.textPrimary,
    height: _lineHeight,
    decoration: TextDecoration.none,
  );

  static TextStyle caption({double size = 13, Color? color}) => TextStyle(
    fontFamily: _bodyFont,
    fontSize: size,
    fontWeight: FontWeight.w300,
    color: color ?? AghieriColors.textSecondary,
    letterSpacing: size * 0.02,
    height: _lineHeight,
    decoration: TextDecoration.none,
  );

  static TextStyle label({double size = 11, Color? color}) => TextStyle(
    fontFamily: _headingFont,
    fontSize: size,
    fontWeight: FontWeight.w500,
    color: color ?? AghieriColors.textSecondary,
    letterSpacing: size * 0.10,
    textBaseline: TextBaseline.alphabetic,
    decoration: TextDecoration.none,
  );
}

// ── App Theme ─────────────────────────────────────────────────────────────────
class AghieriTheme {
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AghieriColors.bg,
    colorScheme: const ColorScheme.dark(
      surface: AghieriColors.bg,
      surfaceContainer: AghieriColors.surface,
      primary: AghieriColors.accent,
      secondary: AghieriColors.ledIdle,
      onSurface: AghieriColors.textPrimary,
      onPrimary: AghieriColors.bg,
    ),
    textTheme: TextTheme(
      displayLarge:   AghieriTextStyles.logo(size: 48),
      displayMedium:  AghieriTextStyles.logo(size: 32),
      headlineLarge:  AghieriTextStyles.heading(size: 26),
      headlineMedium: AghieriTextStyles.heading(size: 22),
      headlineSmall:  AghieriTextStyles.heading(size: 18),
      bodyLarge:      AghieriTextStyles.body(size: 18),
      bodyMedium:     AghieriTextStyles.body(size: 16),
      bodySmall:      AghieriTextStyles.body(size: 14),
      labelLarge:     AghieriTextStyles.label(size: 12),
      labelSmall:     AghieriTextStyles.label(size: 11),
    ),
    cardTheme: CardThemeData(
      color: AghieriColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AghieriColors.surfaceHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AghieriColors.accent, width: 1),
      ),
      hintStyle: AghieriTextStyles.body(color: AghieriColors.textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AghieriColors.accent,
        foregroundColor: AghieriColors.bg,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: AghieriTextStyles.body(size: 15, weight: FontWeight.w500),
        minimumSize: const Size(48, 48),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS:     CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      },
    ),
  );
}

// ── Motion ────────────────────────────────────────────────────────────────────
// Custom curves tuned for calm-tech feel. Default Material curves (easeInOut,
// fastOutSlowIn) read as "app-like." These curves read as physical — things
// settling, breathing, waking. Rooted in Weiser & Brown's calm-tech principle
// that motion should sit in the periphery, never demand attention.
class AghieriMotion {
  // Decelerates like an object coming to rest. No overshoot, no bounce.
  // Use for: cards landing, sheets settling, content arriving.
  static const settle = Cubic(0.22, 0.61, 0.36, 1.0);

  // Slow in, slow out — for ambient loops that should never feel mechanical.
  // Use for: breathing rings, aurora drift, idle pulses.
  static const breath = Cubic(0.45, 0.05, 0.55, 0.95);

  // Soft start, gentle finish — for elements appearing into view.
  // Use for: text fade-ins, button reveal, first paint after auth.
  static const wake = Cubic(0.16, 0.84, 0.44, 1.0);

  // Quick onset, soft tail — attention without alarm. ADHD-aware.
  // Use for: voice state ring color shifts, task completion ack.
  static const notice = Cubic(0.34, 1.12, 0.64, 1.0);

  // Standard durations (named, not numeric, so intent is readable).
  static const Duration glance = Duration(milliseconds: 180);
  static const Duration ease   = Duration(milliseconds: 320);
  static const Duration arrive = Duration(milliseconds: 540);
  static const Duration breathe= Duration(milliseconds: 4200);
}

// ── Spacing ───────────────────────────────────────────────────────────────────
// Named scale with intentional non-8px values. The 8px grid reads as
// engineered; small deviations (14, 22, 30) read as hand-tuned. Each value
// is named for the moment it creates, not its pixel count.
class AghieriSpacing {
  static const double hair    = 4;   // hairline gap between related glyphs
  static const double tight   = 10;  // intra-component padding
  static const double breath  = 14;  // between label and field (off-grid)
  static const double rest    = 22;  // between sibling sections (off-grid)
  static const double gather  = 30;  // between unrelated groups (off-grid)
  static const double horizon = 44;  // top/bottom screen breathing room
  static const double silence = 72;  // hero-only — empty space as a feature
}

// ── Radii ─────────────────────────────────────────────────────────────────────
// Varied corner radii break the "every card is 16px" AI-default look.
// Smaller surfaces (buttons, chips) get tighter corners; larger surfaces
// (sheets, content boxes) get broader corners. Mirrors how physical objects
// scale their fillets to their mass.
class AghieriRadii {
  static const double tight  = 10;  // buttons, chips, inputs
  static const double soft   = 14;  // mid cards, list items
  static const double gentle = 18;  // primary content surfaces
  static const double broad  = 22;  // sheets, dialogs, hero panels
}

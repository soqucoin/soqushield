import 'package:flutter/material.dart';
import 'colors.dart';
import 'instrument.dart';

/// SoquShield Material 3 theme — Arrival aesthetic.
/// Fonts: Archivo (display, titles, body), Martian Mono (data), both bundled.
/// Atmosphere: misty grays, matte obsidian, glass surfaces.
class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      // FOUNDRY type system: Archivo is the display/body face (any Text
      // without an explicit family inherits it); Martian Mono (kMono) owns
      // every number; SF Pro (kLabel) keeps the tiny eyebrows crisp.
      fontFamily: 'Archivo',
      scaffoldBackgroundColor: SoquColors.void_,
      colorScheme: const ColorScheme.dark(
        primary: SoquColors.guardian,
        onPrimary: SoquColors.void_,
        secondary: SoquColors.system,
        onSecondary: SoquColors.iso,
        tertiary: SoquColors.admin,
        error: SoquColors.threat,
        surface: SoquColors.surface,
        onSurface: SoquColors.textPrimary,
      ),
      cardTheme: CardThemeData(
        color: SoquColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: SoquColors.fog.withValues(alpha: 0.3)),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: SoquColors.void_,
        foregroundColor: SoquColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: _displayFont.copyWith(fontSize: 18, letterSpacing: 3),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: SoquColors.surface,
        selectedItemColor: SoquColors.ice,
        unselectedItemColor: SoquColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: _dataFont.copyWith(fontSize: 10, letterSpacing: 1),
        unselectedLabelStyle: _dataFont.copyWith(fontSize: 10, letterSpacing: 1),
        selectedIconTheme: const IconThemeData(size: 22),
        unselectedIconTheme: const IconThemeData(size: 22),
      ),
      textTheme: TextTheme(
        // Display — Archivo: for hero numbers, balances
        displayLarge: _displayFont.copyWith(fontSize: 48, fontWeight: FontWeight.w300, letterSpacing: 1),
        displayMedium: _displayFont.copyWith(fontSize: 32, fontWeight: FontWeight.w300, letterSpacing: 0.5),
        displaySmall: _displayFont.copyWith(fontSize: 24, fontWeight: FontWeight.w300, letterSpacing: 0.5),
        // Headline — Archivo Medium: for section titles
        headlineLarge: _titleFont.copyWith(fontSize: 22, fontWeight: FontWeight.w500),
        headlineMedium: _titleFont.copyWith(fontSize: 18, fontWeight: FontWeight.w500),
        headlineSmall: _titleFont.copyWith(fontSize: 15, fontWeight: FontWeight.w500),
        // Title — Archivo: for card titles, tab labels
        titleLarge: _titleFont.copyWith(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 2),
        titleMedium: _dataFont.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
        titleSmall: _dataFont.copyWith(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 1),
        // Body — Archivo: for descriptions, paragraphs
        bodyLarge: _bodyFont.copyWith(fontSize: 16),
        bodyMedium: _bodyFont.copyWith(fontSize: 14),
        bodySmall: _bodyFont.copyWith(fontSize: 12, color: SoquColors.textSecondary),
        // Label — Martian Mono: for stats, data values
        labelLarge: _dataFont.copyWith(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.8),
        labelMedium: _dataFont.copyWith(fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 0.5),
        labelSmall: _dataFont.copyWith(fontSize: 10, fontWeight: FontWeight.w400, letterSpacing: 1,
            color: SoquColors.textSecondary),
      ),
      // foundry .btn-pour / .btn: primary = solid copper slab + iron-ink text;
      // secondary = transparent + seam-hi border + text-hi. Uppercase mono.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Instrument.signal,
          foregroundColor: const Color(0xFF16100A),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          textStyle: const TextStyle(
              fontSize: 13,
              fontFamily: kMono,
              fontWeight: FontWeight.w600,
              letterSpacing: 13 * 0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Instrument.readout,
          side: const BorderSide(color: Instrument.lineHi, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          textStyle: const TextStyle(
              fontSize: 13,
              fontFamily: kMono,
              fontWeight: FontWeight.w600,
              letterSpacing: 13 * 0.1),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Instrument.label,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          textStyle: const TextStyle(
              fontSize: 12,
              fontFamily: kMono,
              fontWeight: FontWeight.w600,
              letterSpacing: 12 * 0.1),
        ),
      ),
      // Instrument inputs (2026-07-05 audit §2): the old cold-navy filled boxes
      // were the single biggest "patched together" tell against the warm canvas.
      // Quiet raised surface + hairline, emerald focus — every form inherits.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Instrument.void2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: const BorderSide(color: Instrument.line, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: const BorderSide(color: Instrument.line, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(
              color: Instrument.signalDim.withValues(alpha: 0.7), width: 1.2),
        ),
        labelStyle: const TextStyle(
            color: Instrument.label, fontFamily: kLabel, fontSize: 12),
        hintStyle: const TextStyle(
            color: Instrument.faint, fontFamily: kMono, fontSize: 14),
      ),
      dividerTheme: DividerThemeData(
        color: SoquColors.fog.withValues(alpha: 0.3),
        thickness: 0.5,
      ),
    );
  }

  // ── Font stacks ──

  // The bundled foundry faces (pubspec `fonts:`): Archivo for display, titles
  // and body, Martian Mono for data. Nothing is fetched at runtime.

  /// Archivo — display headlines, hero numbers
  static TextStyle get _displayFont => const TextStyle(
        fontFamily: kSans,
        color: SoquColors.textPrimary,
        fontWeight: FontWeight.w400,
      );

  /// Archivo — section titles, sub-headers (medium weight)
  static TextStyle get _titleFont => const TextStyle(
        fontFamily: kSans,
        color: SoquColors.textPrimary,
        fontWeight: FontWeight.w500,
      );

  /// Martian Mono — data values, stats, hashes
  static TextStyle get _dataFont => const TextStyle(
        fontFamily: kMono,
        color: SoquColors.textPrimary,
        fontWeight: FontWeight.w400,
      );

  /// Archivo — body text, descriptions
  static TextStyle get _bodyFont => const TextStyle(
        fontFamily: kSans,
        color: SoquColors.textPrimary,
        fontWeight: FontWeight.w400,
      );
}

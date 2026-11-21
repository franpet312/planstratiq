import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta: paus-papir, grafitna tinta i petrolej kao jedina boja naglaska.
class Pal {
  static const paper = Color(0xFFEFF2F0); // podloga nacrta
  static const paperDeep = Color(0xFFE3E8E5);
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFD5DBD8);
  static const lineSoft = Color(0xFFE6EAE8);
  static const ink = Color(0xFF1C2226);
  static const inkSoft = Color(0xFF3A4246);
  static const muted = Color(0xFF68726D);
  static const wall = Color(0xFF23292D);
  static const accent = Color(0xFF0E6B66);
  static const accentDeep = Color(0xFF094B48);
  static const accentSoft = Color(0xFFD7ECE9);
  static const danger = Color(0xFFB3261E);
  static const glass = Color(0xFFBFDDE6);
  static const grass = Color(0xFFDCE8D4);
  static const water = Color(0xFFBFE1EE);
}

class AppText {
  /// Sučelje.
  static TextStyle ui({double size = 13, FontWeight weight = FontWeight.w400, Color color = Pal.ink, double? height, double? spacing}) =>
      GoogleFonts.archivo(fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: spacing);

  /// Kote i natpisi na nacrtu (uži rez, kao tehničko pismo).
  static TextStyle narrow({double size = 11, FontWeight weight = FontWeight.w500, Color color = Pal.ink, double? height, double? spacing}) =>
      GoogleFonts.archivoNarrow(fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: spacing);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Pal.accent,
      primary: Pal.accent,
      onPrimary: Colors.white,
      primaryContainer: Pal.accentSoft,
      onPrimaryContainer: Pal.accentDeep,
      surface: Pal.surface,
      onSurface: Pal.ink,
      error: Pal.danger,
    ),
    scaffoldBackgroundColor: Pal.paper,
    visualDensity: VisualDensity.compact,
  );
  final tt = GoogleFonts.archivoTextTheme(base.textTheme).apply(bodyColor: Pal.ink, displayColor: Pal.ink);
  return base.copyWith(
    textTheme: tt.copyWith(
      titleLarge: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 20, letterSpacing: -0.2),
      titleMedium: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
      titleSmall: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
      bodyMedium: tt.bodyMedium?.copyWith(fontSize: 13),
      bodySmall: tt.bodySmall?.copyWith(fontSize: 12, color: Pal.muted),
      labelMedium: tt.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: Pal.inkSoft),
    ),
    dividerTheme: const DividerThemeData(color: Pal.lineSoft, thickness: 1, space: 1),
    iconTheme: const IconThemeData(color: Pal.inkSoft, size: 20),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: Pal.ink, borderRadius: BorderRadius.circular(6)),
      textStyle: AppText.ui(size: 12, color: Colors.white),
      waitDuration: const Duration(milliseconds: 350),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Pal.paper,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Pal.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Pal.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Pal.accent, width: 1.5)),
      labelStyle: AppText.ui(size: 12, color: Pal.muted),
      suffixStyle: AppText.ui(size: 12, color: Pal.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Pal.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: AppText.ui(size: 13, weight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Pal.ink,
        side: const BorderSide(color: Pal.line),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: AppText.ui(size: 13, weight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Pal.accent,
        textStyle: AppText.ui(size: 13, weight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(AppText.ui(size: 12, weight: FontWeight.w600)),
        side: const WidgetStatePropertyAll(BorderSide(color: Pal.line)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        visualDensity: VisualDensity.compact,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Pal.ink,
      contentTextStyle: AppText.ui(size: 13, color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Pal.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      titleTextStyle: AppText.ui(size: 18, weight: FontWeight.w700),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Pal.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Pal.lineSoft)),
      textStyle: AppText.ui(size: 13),
    ),
    sliderTheme: const SliderThemeData(trackHeight: 3, activeTrackColor: Pal.accent, thumbColor: Pal.accent, inactiveTrackColor: Pal.line),
  );
}

import 'package:flutter/material.dart';

class AstraColors {
  static const bg = Color(0xFF07090E);
  static const bgSoft = Color(0xFF0A0D14);
  static const surface = Color(0xFF0E121B);
  static const surface2 = Color(0xFF121826);
  static const line = Color(0x2194A3B8);
  static const lineStrong = Color(0x3894A3B8);
  static const text = Color(0xFFE7ECF6);
  static const muted = Color(0xFF8D97AB);
  static const faint = Color(0xFF5D6678);
  static const accent = Color(0xFF38BDF8);
  static const accent2 = Color(0xFF8B5CF6);
  static const ok = Color(0xFF34D399);
  static const warn = Color(0xFFFBBF24);
  static const err = Color(0xFFFB7185);
}

const List<String> kMonoFallback = [
  'SF Mono',
  'Menlo',
  'Consolas',
  'Courier New',
  'monospace',
];

const List<String> kSansFallback = [
  'PingFang SC',
  'Hiragino Sans GB',
  'Microsoft YaHei',
  'Segoe UI',
];

TextStyle monoStyle({
  double size = 12.5,
  Color color = AstraColors.text,
  FontWeight weight = FontWeight.w400,
  double? height,
}) =>
    TextStyle(
      fontFamily: 'Menlo',
      fontFamilyFallback: kMonoFallback,
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: height,
    );

ThemeData buildAstraTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AstraColors.bg,
    canvasColor: AstraColors.bg,
    colorScheme: base.colorScheme.copyWith(
      brightness: Brightness.dark,
      primary: AstraColors.accent,
      secondary: AstraColors.accent2,
      surface: AstraColors.surface,
      error: AstraColors.err,
    ),
    dividerColor: AstraColors.line,
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme.apply(
      bodyColor: AstraColors.text,
      displayColor: AstraColors.text,
      fontFamilyFallback: kSansFallback,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AstraColors.surface2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AstraColors.line),
      ),
      textStyle: const TextStyle(fontSize: 11.5, color: AstraColors.text),
      waitDuration: const Duration(milliseconds: 450),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(const Color(0x2E94A3B8)),
      thickness: WidgetStateProperty.all(6),
      radius: const Radius.circular(99),
    ),
  );
}

InputDecoration astraInput({
  String? hint,
  bool dense = true,
  EdgeInsetsGeometry? contentPadding,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AstraColors.faint, fontSize: 12.5),
    isDense: dense,
    filled: true,
    fillColor: const Color(0xFF0B0F17),
    contentPadding: contentPadding ??
        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    constraints: const BoxConstraints(minHeight: 36),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: AstraColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: AstraColors.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: Color(0x8038BDF8)),
    ),
  );
}

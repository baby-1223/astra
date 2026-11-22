import 'package:flutter/material.dart';

/// Semantic color palette. Two variants are provided so the desktop app can
/// follow the operating system appearance, matching the IntelliJ plugin that
/// tracks the IDE light / dark theme.
class AstraPalette {
  final bool isLight;
  final Color bg;
  final Color bgSoft;
  final Color surface;
  final Color surface2;
  final Color line;
  final Color lineStrong;
  final Color text;
  final Color muted;
  final Color faint;
  final Color accent;
  final Color accent2;
  final Color ok;
  final Color warn;
  final Color err;
  final Color inset;
  final Color topBar;
  final Color overlay;
  final Color accentSoft;
  final Color accentBorder;
  final Color accentLine;
  final Color accent2Soft;
  final Color okSoft;
  final Color warnSoft;
  final Color errSoft;
  final Color errBorder;
  final Color okContainer;
  final Color errContainer;
  final Color codeText;
  final Color codeString;
  final Color codeNumber;
  final Color codeKeyword;
  final Color codeMatch;
  final Color methodGet;
  final Color methodPost;
  final Color methodPut;
  final Color methodPatch;
  final Color methodDelete;
  final Color methodWs;
  final Color methodOther;

  const AstraPalette({
    required this.isLight,
    required this.bg,
    required this.bgSoft,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.lineStrong,
    required this.text,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.accent2,
    required this.ok,
    required this.warn,
    required this.err,
    required this.inset,
    required this.topBar,
    required this.overlay,
    required this.accentSoft,
    required this.accentBorder,
    required this.accentLine,
    required this.accent2Soft,
    required this.okSoft,
    required this.warnSoft,
    required this.errSoft,
    required this.errBorder,
    required this.okContainer,
    required this.errContainer,
    required this.codeText,
    required this.codeString,
    required this.codeNumber,
    required this.codeKeyword,
    required this.codeMatch,
    required this.methodGet,
    required this.methodPost,
    required this.methodPut,
    required this.methodPatch,
    required this.methodDelete,
    required this.methodWs,
    required this.methodOther,
  });
}

const AstraPalette darkPalette = AstraPalette(
  isLight: false,
  bg: Color(0xFF07090E),
  bgSoft: Color(0xFF0A0D14),
  surface: Color(0xFF0E121B),
  surface2: Color(0xFF121826),
  line: Color(0x2194A3B8),
  lineStrong: Color(0x3894A3B8),
  text: Color(0xFFE7ECF6),
  muted: Color(0xFF8D97AB),
  faint: Color(0xFF5D6678),
  accent: Color(0xFF38BDF8),
  accent2: Color(0xFF8B5CF6),
  ok: Color(0xFF34D399),
  warn: Color(0xFFFBBF24),
  err: Color(0xFFFB7185),
  inset: Color(0xFF0B0F17),
  topBar: Color(0xB307090E),
  overlay: Color(0x08FFFFFF),
  accentSoft: Color(0x1F38BDF8),
  accentBorder: Color(0x4038BDF8),
  accentLine: Color(0x8038BDF8),
  accent2Soft: Color(0x1F8B5CF6),
  okSoft: Color(0x1A34D399),
  warnSoft: Color(0x14F0C674),
  errSoft: Color(0x1AFB7185),
  errBorder: Color(0x3DFB7185),
  okContainer: Color(0xFF1B3A2A),
  errContainer: Color(0xFF3A1E24),
  codeText: Color(0xFFD6DEF0),
  codeString: Color(0xFF86D9A6),
  codeNumber: Color(0xFFF0C674),
  codeKeyword: Color(0xFFC4B5FD),
  codeMatch: Color(0xFFFFE7A3),
  methodGet: Color(0xFF67E8F9),
  methodPost: Color(0xFF86EFAC),
  methodPut: Color(0xFFFCD34D),
  methodPatch: Color(0xFFC4B5FD),
  methodDelete: Color(0xFFFDA4AF),
  methodWs: Color(0xFFA5B4FC),
  methodOther: Color(0xFFCBD5E1),
);

const AstraPalette lightPalette = AstraPalette(
  isLight: true,
  bg: Color(0xFFF3F5FA),
  bgSoft: Color(0xFFFFFFFF),
  surface: Color(0xFFFFFFFF),
  surface2: Color(0xFFF8FAFC),
  line: Color(0x1F1E293B),
  lineStrong: Color(0x331E293B),
  text: Color(0xFF0F172A),
  muted: Color(0xFF475569),
  faint: Color(0xFF64748B),
  accent: Color(0xFF0284C7),
  accent2: Color(0xFF7C3AED),
  ok: Color(0xFF059669),
  warn: Color(0xFFB45309),
  err: Color(0xFFDC2626),
  inset: Color(0xFFF1F5F9),
  topBar: Color(0xF7FFFFFF),
  overlay: Color(0x0A0F172A),
  accentSoft: Color(0x1A0284C7),
  accentBorder: Color(0x4D0284C7),
  accentLine: Color(0x800284C7),
  accent2Soft: Color(0x1A7C3AED),
  okSoft: Color(0x1A059669),
  warnSoft: Color(0x1AB45309),
  errSoft: Color(0x1ADC2626),
  errBorder: Color(0x4DDC2626),
  okContainer: Color(0xFFDCFCE7),
  errContainer: Color(0xFFFEE2E2),
  codeText: Color(0xFF1E293B),
  codeString: Color(0xFF047857),
  codeNumber: Color(0xFFB45309),
  codeKeyword: Color(0xFF6D28D9),
  codeMatch: Color(0xFF92400E),
  methodGet: Color(0xFF0E7490),
  methodPost: Color(0xFF047857),
  methodPut: Color(0xFFA16207),
  methodPatch: Color(0xFF6D28D9),
  methodDelete: Color(0xFFBE123C),
  methodWs: Color(0xFF4338CA),
  methodOther: Color(0xFF475569),
);

/// Static accessors kept for source compatibility. The active palette is
/// switched by [applyBrightness] when the OS appearance changes.
class AstraColors {
  static AstraPalette _palette = darkPalette;

  static AstraPalette get palette => _palette;
  static bool get isLight => _palette.isLight;

  static void applyBrightness(Brightness brightness) {
    _palette = brightness == Brightness.dark ? darkPalette : lightPalette;
  }

  static Color get bg => _palette.bg;
  static Color get bgSoft => _palette.bgSoft;
  static Color get surface => _palette.surface;
  static Color get surface2 => _palette.surface2;
  static Color get line => _palette.line;
  static Color get lineStrong => _palette.lineStrong;
  static Color get text => _palette.text;
  static Color get muted => _palette.muted;
  static Color get faint => _palette.faint;
  static Color get accent => _palette.accent;
  static Color get accent2 => _palette.accent2;
  static Color get ok => _palette.ok;
  static Color get warn => _palette.warn;
  static Color get err => _palette.err;
  static Color get inset => _palette.inset;
  static Color get topBar => _palette.topBar;
  static Color get overlay => _palette.overlay;
  static Color get accentSoft => _palette.accentSoft;
  static Color get accentBorder => _palette.accentBorder;
  static Color get accentLine => _palette.accentLine;
  static Color get accent2Soft => _palette.accent2Soft;
  static Color get okSoft => _palette.okSoft;
  static Color get warnSoft => _palette.warnSoft;
  static Color get errSoft => _palette.errSoft;
  static Color get errBorder => _palette.errBorder;
  static Color get okContainer => _palette.okContainer;
  static Color get errContainer => _palette.errContainer;
  static Color get codeText => _palette.codeText;
  static Color get codeString => _palette.codeString;
  static Color get codeNumber => _palette.codeNumber;
  static Color get codeKeyword => _palette.codeKeyword;
  static Color get codeMatch => _palette.codeMatch;
  static Color get methodGet => _palette.methodGet;
  static Color get methodPost => _palette.methodPost;
  static Color get methodPut => _palette.methodPut;
  static Color get methodPatch => _palette.methodPatch;
  static Color get methodDelete => _palette.methodDelete;
  static Color get methodWs => _palette.methodWs;
  static Color get methodOther => _palette.methodOther;
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
  Color? color,
  FontWeight weight = FontWeight.w400,
  double? height,
}) =>
    TextStyle(
      fontFamily: 'Menlo',
      fontFamilyFallback: kMonoFallback,
      fontSize: size,
      color: color ?? AstraColors.text,
      fontWeight: weight,
      height: height,
    );

ThemeData buildAstraTheme() {
  final palette = AstraColors.palette;
  final base = palette.isLight
      ? ThemeData.light(useMaterial3: true)
      : ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AstraColors.bg,
    canvasColor: AstraColors.bg,
    colorScheme: base.colorScheme.copyWith(
      brightness: palette.isLight ? Brightness.light : Brightness.dark,
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
      textStyle: TextStyle(fontSize: 11.5, color: AstraColors.text),
      waitDuration: const Duration(milliseconds: 450),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(
        palette.isLight ? const Color(0x330F172A) : const Color(0x2E94A3B8),
      ),
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
    hintStyle: TextStyle(color: AstraColors.faint, fontSize: 12.5),
    isDense: dense,
    filled: true,
    fillColor: AstraColors.inset,
    contentPadding: contentPadding ??
        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    constraints: const BoxConstraints(minHeight: 36),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: AstraColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: AstraColors.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: AstraColors.accentLine),
    ),
  );
}

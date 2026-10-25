import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';

const Color kForest = Color(0xFF145B45);
const Color kForestDark = Color(0xFF0E3B34);
const Color kGold = Color(0xFFC59A50);
const Color kInk = Color(0xFF1D2925);
const String kUrduFont = 'JameelNooriNastaleeq';
const String kArabicFont = 'Amiri';

/// English digits on the prayer card, the Qibla compass and the tasbeeh: the
/// Nastaliq face draws Latin numerals small, so numbers use the system sans.
const String kDigitFont = 'sans-serif';

/// One vivid colour per book. The home screen paints every book's icon in its
/// own colour, and the same colour follows the book into the bottom panel.
const List<Color> kBookPalette = <Color>[
  Color(0xFF1B7F5B), // green
  Color(0xFFD9466B), // rose
  Color(0xFF2F6FD6), // blue
  Color(0xFFE08A1E), // amber
  Color(0xFF7B4FD0), // violet
  Color(0xFF0E9AA7), // teal
  Color(0xFFC2452D), // brick
  Color(0xFF5B8C2A), // olive
  Color(0xFF3D5AFE), // indigo
  Color(0xFFB8860B), // dark gold
  Color(0xFF00897B), // emerald
  Color(0xFFAD1457), // plum
  Color(0xFF6D4C41), // brown
  Color(0xFF455A64), // slate
  Color(0xFF8E24AA), // purple
  Color(0xFF039BE5), // sky
  Color(0xFF7CB342), // lime
  Color(0xFFEF6C00), // orange
  Color(0xFF546E7A), // steel
  Color(0xFFC0CA33), // yellow-green
];

/// Book keys in the order the library first shipped them. Colours are picked
/// from this frozen order rather than from `BookDefinition.all`, so removing
/// a book (the Khamenei fatawa in 1.28, whose slot stays here on purpose)
/// never recolours the books that remain.
const List<String> _kBookAccentOrder = <String>[
  'sahifa', 'khamenei', 'sistani', 'najafi', 'tahzeeb', 'alkafi', 'alkhisal',
  'hakam', 'hidaya', 'hikmatprophet', 'imam', 'kamaledeen', 'maniakbar',
  'manlahyahzur', 'mezan', 'swab', 'towheed', 'wasail', 'quran', 'mafatih',
  'nahjul_balagha', 'athna_ashari_encyclopedia',
];

/// The icon colour of [book]: its position in the library, so neighbours in
/// the grid never share a colour.
Color bookAccent(BookDefinition book) {
  var index = _kBookAccentOrder.indexOf(book.key);
  if (index < 0) {
    // A book added after the order froze keeps the old rule: its place in
    // the live list.
    index = BookDefinition.all.indexWhere((item) => item.key == book.key);
  }
  return kBookPalette[(index < 0 ? 0 : index) % kBookPalette.length];
}

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kForest,
    primary: kForest,
    secondary: kGold,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // Light is the default look: a plain white page with coloured icons.
    scaffoldBackgroundColor: Colors.white,
    fontFamily: kUrduFont,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: kInk,
      centerTitle: false,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: kGold.withValues(alpha: 0.24)),
      ),
      margin: EdgeInsets.zero,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: kForest.withValues(alpha: 0.12),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: kUrduFont,
          fontSize: 12,
          color: states.contains(WidgetState.selected) ? kForest : Colors.black54,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFE7E2D8), thickness: 0.8),
  );
}

/// True-black AMOLED theme: pure #000000 surfaces so AMOLED pixels switch
/// fully off (battery saved, deeper contrast). Cards are lifted just enough
/// (#0D0D0F) to stay visible against the black.
ThemeData buildAmoledTheme() {
  final base = buildDarkTheme();
  final scheme = base.colorScheme.copyWith(
    surface: Colors.black,
    surfaceContainerLowest: Colors.black,
    surfaceContainerLow: const Color(0xFF0A0A0C),
    surfaceContainer: const Color(0xFF0D0D0F),
    surfaceContainerHigh: const Color(0xFF131316),
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.black,
    canvasColor: Colors.black,
    appBarTheme: base.appBarTheme.copyWith(backgroundColor: Colors.black),
    cardTheme: base.cardTheme.copyWith(color: const Color(0xFF0D0D0F)),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF0A0A0C),
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: const Color(0xFF111113),
    ),
  );
}

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kForest,
    brightness: Brightness.dark,
    primary: const Color(0xFF7AC4A2),
    secondary: const Color(0xFFE4BC70),
    surface: const Color(0xFF18211F),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF101715),
    fontFamily: kUrduFont,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF101715),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1A2421),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1A2421),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

class ReaderPalette {
  const ReaderPalette({
    required this.background,
    required this.foreground,
    required this.name,
    required this.key,
  });

  final Color background;
  final Color foreground;
  final String name;
  final String key;

  static const paper = ReaderPalette(
    background: Colors.white,
    foreground: kInk,
    name: 'سفید',
    key: 'paper',
  );
  static const sepia = ReaderPalette(
    background: Color(0xFFF3E8D1),
    foreground: Color(0xFF3F3322),
    name: 'سیپیا',
    key: 'sepia',
  );
  static const night = ReaderPalette(
    background: Color(0xFF171E1C),
    foreground: Color(0xFFE5E7DC),
    name: 'رات',
    key: 'night',
  );

  bool get isNight => key == 'night';
  Color get accent => isNight ? const Color(0xFFE4BC70) : kForest;
  Color get border => isNight ? const Color(0xFF625238) : const Color(0xFFE5D8BD);

  static const List<ReaderPalette> all = [paper, sepia, night];

  static ReaderPalette fromName(String? name) => switch (name) {
        'sepia' => sepia,
        'night' => night,
        _ => paper,
      };
}

/// The colours of the home dashboard (the fifteen containers of the approved
/// design): a light page, dark emerald glass cards, a plum rail and dial, an
/// amber "آیت / حدیثِ وقت" card, and gold hairlines on everything.
///
/// One place, both themes, so the dashboard, the prayer card over its sky and
/// the bottom panel always read as one screen.
class DashboardPalette {
  const DashboardPalette({
    required this.backdrop,
    required this.gold,
    required this.goldSoft,
    required this.cream,
    required this.creamInk,
    required this.ink,
    required this.onDark,
    required this.onDarkMuted,
    required this.moment,
    required this.momentInk,
    required this.search,
    required this.plum,
    required this.metal,
    required this.metalInk,
    required this.bead,
    required this.sunken,
  });

  /// Page behind the containers, top to bottom.
  final Gradient backdrop;

  /// The hairline around every container and the accent of the panels.
  final Color gold;
  final Color goldSoft;

  /// Paper fills: the search field, the round buttons on the dial.
  final Color cream;
  final Color creamInk;

  /// Text on the light page.
  final Color ink;

  /// Text on the dark glass containers.
  final Color onDark;
  final Color onDarkMuted;

  /// The amber "moment" card.
  final Gradient moment;
  final Color momentInk;

  /// The search bar: the emerald of the daily utilities, so the bar reads as
  /// part of the same family as the prayer card and the tasbeeh.
  final Gradient search;

  /// The rail and the dial's inner bead.
  final Gradient plum;

  /// The dial's brushed face and the ink of its labels.
  final Gradient metal;
  final Color metalInk;

  /// The dial's glowing count and the unfilled ring around it.
  final Color bead;
  final Color sunken;

  static DashboardPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  static const DashboardPalette _light = DashboardPalette(
    backdrop: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Colors.white, Colors.white],
    ),
    gold: kGold,
    goldSoft: Color(0xFFEBD5A8),
    cream: Colors.white,
    creamInk: Color(0xFF6E6A5C),
    ink: kInk,
    onDark: Color(0xFFF6FBF7),
    onDarkMuted: Color(0xFFB9D5C6),
    moment: LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: <Color>[Color(0xFFF3A93C), Color(0xFFD97E12)],
    ),
    momentInk: Color(0xFF4A2A05),
    search: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xFF1E7A5E), Color(0xFF0E3B34)],
    ),
    plum: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xFF45225C), Color(0xFF26103A)],
    ),
    metal: RadialGradient(
      center: Alignment(-0.4, -0.55),
      radius: 1.1,
      colors: <Color>[Color(0xFFFFFFFF), Color(0xFFE5E9EC), Color(0xFFADB6BF)],
      stops: <double>[0, 0.48, 1],
    ),
    metalInk: Color(0xFF3C4448),
    bead: Color(0xFF31204E),
    sunken: Color(0x221C2B27),
  );

  static const DashboardPalette _dark = DashboardPalette(
    backdrop: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xFF0B1211), Color(0xFF16211F)],
    ),
    gold: Color(0xFFE4BC70),
    goldSoft: Color(0xFFF0D9A8),
    cream: Color(0xFF1E2A27),
    creamInk: Color(0xFFB9C6C0),
    ink: Color(0xFFE8EEE8),
    onDark: Color(0xFFF2FAF4),
    onDarkMuted: Color(0xFFA9C9B8),
    moment: LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: <Color>[Color(0xFFD08A20), Color(0xFF9E5C08)],
    ),
    momentInk: Color(0xFF2A1703),
    search: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xFF17513F), Color(0xFF0A2B22)],
    ),
    plum: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[Color(0xFF4A2563), Color(0xFF241038)],
    ),
    metal: RadialGradient(
      colors: <Color>[Color(0xFF5A6367), Color(0xFF3C4448), Color(0xFF282F32)],
      stops: <double>[0, 0.62, 1],
    ),
    metalInk: Color(0xFFE6EDEE),
    bead: Color(0xFF2B1B45),
    sunken: Color(0x33FFFFFF),
  );
}

class JustifiedText extends StatelessWidget {
  const JustifiedText(
    this.text, {
    super.key,
    this.arabic = false,
    this.style,
    this.maxLines,
    this.selectable = false,
  });

  final String text;
  final bool arabic;
  final TextStyle? style;
  final int? maxLines;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final resolved = (arabic
            ? const TextStyle(fontFamily: kArabicFont, height: 1.7, letterSpacing: 0)
            : const TextStyle(fontFamily: kUrduFont, height: 1.55))
        .merge(style);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: selectable
          ? SelectableText(
              text,
              textAlign: TextAlign.justify,
              maxLines: maxLines,
              style: resolved,
            )
          : Text(
              text,
              textAlign: TextAlign.justify,
              maxLines: maxLines,
              overflow: maxLines == null ? TextOverflow.visible : TextOverflow.ellipsis,
              style: resolved,
            ),
    );
  }
}

TextDirection directionFor(String text) {
  for (final rune in text.runes) {
    if ((rune >= 0x0600 && rune <= 0x08FF) || (rune >= 0xFB50 && rune <= 0xFEFF)) {
      return TextDirection.rtl;
    }
  }
  return TextDirection.ltr;
}

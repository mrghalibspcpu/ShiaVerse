import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiaverse/astro/hijri_calendar.dart' show formatHijriUrdu;
import 'package:shiaverse/astro/prayer_format.dart' show weekdayUrdu;
import 'package:shiaverse/app_theme.dart';
import 'package:shiaverse/data_installer.dart';
import 'package:shiaverse/main.dart' show HomeShell;
import 'package:shiaverse/screens/settings_screen.dart';
import 'package:shiaverse/screens/quran_screen.dart';
import 'package:shiaverse/screens/islamic_calendar_screen.dart';
import 'package:shiaverse/screens/library_screen.dart';
import 'package:shiaverse/screens/crescent_screen.dart';
import 'package:shiaverse/screens/duas_screen.dart';
import 'package:shiaverse/screens/balagha_screen.dart';
import 'package:shiaverse/widgets/reader_chrome.dart';
import 'package:shiaverse/widgets/reader_kit.dart';
import 'package:shiaverse/widgets/mushaf_text.dart';
import 'package:shiaverse/widgets/reading_hub.dart';
import 'package:shiaverse/widgets/glass_panel.dart';
import 'package:shiaverse/library_repository.dart';
import 'package:shiaverse/models.dart';
import 'package:shiaverse/screens/prayer_times_screen.dart';
import 'package:shiaverse/screens/qibla_screen.dart';
import 'package:shiaverse/widgets/section_background.dart';
import 'package:shiaverse/screens/tasbeeh_screen.dart';
import 'package:shiaverse/services/alerts.dart';
import 'package:shiaverse/services/city_index.dart';
import 'package:shiaverse/services/prayer_controller.dart';
import 'package:shiaverse/services/prayer_locations.dart';
import 'package:shiaverse/services/prayer_scope.dart';
import 'package:shiaverse/services/tasbeeh_controller.dart';
import 'package:shiaverse/widgets/home_dashboard.dart';
import 'package:shiaverse/widgets/more_features.dart';
import 'package:shiaverse/screens/explore_screen.dart';

/// Layout checks for the 1.12 home dashboard and readers and the screens around it on a
/// small (360 dp) phone, with the app's real fonts: any overflow fails the
/// test. When `SHIAVERSE_PREVIEW_DIR` is set (CI does), each screen is also
/// saved as a PNG so the layout can be looked at without a device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final previewDir = Platform.environment['SHIAVERSE_PREVIEW_DIR'];
  final shotKey = GlobalKey();

  setUpAll(() async {
    Future<void> load(String family, String path) async {
      final file = File(path);
      if (!file.existsSync()) return;
      final bytes = file.readAsBytesSync();
      final loader = FontLoader(family)..addFont(Future.value(bytes.buffer.asByteData()));
      await loader.load();
    }

    await load(kUrduFont, 'assets/fonts/JameelNooriNastaleeq.ttf');
    await load(kArabicFont, 'assets/fonts/Amiri-Regular.ttf');
    // The phone's sans face is not available in tests; Amiri's Latin digits
    // have about the same width.
    await load(kDigitFont, 'assets/fonts/Amiri-Regular.ttf');
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot != null) {
      await load('MaterialIcons', '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    }
  });

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  /// Islamabad (UTC+5), at a local wall-clock time.
  DateTime localTime(int hour, int minute) => DateTime.utc(2026, 10, 15, hour - 5, minute);

  Future<(PrayerController, TasbeehController)> controllersAt(WidgetTester tester, DateTime device) async {
    final prayer = PrayerController(
      clock: () => device,
      feedback: const SilentFeedback(),
      locate: () async => const PrayerLocation(
        latitude: 33.6686,
        longitude: 72.9973,
        label: 'G-11، اسلام آباد',
        detail: 'اسلام آباد، پاکستان',
        source: LocationSource.gps,
        refined: true,
      ),
    );
    final tasbeeh = TasbeehController(clock: () => device, feedback: const SilentFeedback());
    await prayer.start();
    await tasbeeh.load();
    return (prayer, tasbeeh);
  }

  /// Unmounts the screen first (it listens to the controllers), then stops
  /// the controllers' clocks, so no timer outlives the test.
  Future<void> finish(WidgetTester tester, PrayerController prayer, TasbeehController tasbeeh) async {
    await tester.pumpWidget(const SizedBox.shrink());
    prayer.dispose();
    tasbeeh.dispose();
  }

  Widget host(PrayerController prayer, TasbeehController tasbeeh, Widget child, {double textScale = 1}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: PrayerScope(
          controller: prayer,
          child: TasbeehScope(
            controller: tasbeeh,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: RepaintBoundary(key: shotKey, child: inner ?? const SizedBox.shrink()),
            ),
          ),
        ),
      ),
      home: child,
    );
  }

  void phone(WidgetTester tester, {double height = 800, double width = 360}) {
    tester.view.physicalSize = Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  /// Lets real I/O (asset images) finish, then paints.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(seconds: 2));
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    if (previewDir == null) return;
    await tester.runAsync(() async {
      final boundary = shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(previewDir).createSync(recursive: true);
      File('$previewDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  /// The dashboard exactly as the app mounts it: the fifteen containers, the
  /// slim notice strip above them and the bottom panel below.
  ///
  /// Nothing is installed in a test, which is the honest worst case for the
  /// layout: every section card shows its download mark and the moment card
  /// falls back to its built-in lines.
  Widget homeScreen({LibraryRepository? library}) {
    final repository = library ?? LibraryRepository();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: HomeDashboard(
          library: repository,
          onSearch: () {},
          onOpenData: () {},
        ),
      ),
      bottomNavigationBar: HomeDockBar(
        selected: null,
        onSelected: (_) {},
      ),
    );
  }

  for (final (name, hour, minute) in <(String, int, int)>[
    ('dawn', 5, 40),
    ('day', 12, 10),
    ('evening', 16, 45),
    ('night', 21, 5),
  ]) {
    testWidgets('the home dashboard fits a 360 dp phone ($name)', (tester) async {
      phone(tester);
      final (prayer, tasbeeh) = await controllersAt(tester, localTime(hour, minute));
      for (var index = 0; index < 27; index++) {
        tasbeeh.tap();
      }
      await tester.pumpWidget(host(prayer, tasbeeh, homeScreen()));
      await settle(tester);
      // The fifteen containers of the design.
      expect(find.byType(HomeDashboard), findsOneWidget);
      // The two bugs this replaced: the panel's Center stretched it over the
      // whole screen (the dashboard was given zero height and painted nothing,
      // so every time-of-day shot was byte-identical), and the dashboard
      // itself laid out below the visible area. Both are sizes, so both are
      // asserted as sizes.
      expect(tester.getSize(find.byType(HomeDashboard)).height, greaterThan(400));
      expect(tester.getSize(find.byType(HomeDockBar)).height, lessThan(140));
      expect(find.text('ShiaVerse'), findsOneWidget);
      expect(find.text('G-11، اسلام آباد'), findsOneWidget);
      expect(find.text('قرآنِ کریم'), findsOneWidget);
      expect(find.text('ترجمہ و تفسیر کے ساتھ'), findsOneWidget);
      expect(find.text('ایک لاکھ کے قریب احادیث'), findsOneWidget);
      expect(find.text('مفاتیح الجنان و صحیفہ سجادیہ'), findsOneWidget);
      expect(find.text('مکمل'), findsOneWidget);
      expect(find.text('نہج البلاغہ'), findsOneWidget);
      expect(find.text('دینی مسائل'), findsOneWidget);
      expect(find.text('احکام و فتاویٰ'), findsOneWidget);
      expect(find.text('پوری لائبریری میں تلاش کریں…'), findsOneWidget);
      expect(find.byType(HomeDockBar), findsOneWidget);
      final prayerBottom = tester.getRect(find.byKey(const ValueKey<String>('home-prayer-card'))).bottom;
      final prayerRowBottom = tester.getRect(find.byKey(const ValueKey<String>('home-prayer-row'))).bottom;
      expect(prayerBottom - prayerRowBottom, lessThan(10), reason: 'prayers belong at the foot of the sky');
      final momentBottom = tester.getRect(find.byKey(const ValueKey<String>('home-moment-card'))).bottom;
      final dialTop = tester.getRect(find.byKey(const ValueKey<String>('home-tasbeeh'))).top;
      expect(dialTop - momentBottom, lessThan(14), reason: 'moment card should meet the dial');
      for (final item in HomeDockItem.values) {
        expect(find.text(item.label), findsOneWidget, reason: item.label);
      }
      await shoot(tester, 'home-$name');
      await finish(tester, prayer, tasbeeh);
    });
  }

  testWidgets('the dashboard keeps its shape with a large system font', (tester) async {
    phone(tester);
    final (prayer, tasbeeh) = await controllersAt(tester, localTime(13, 30));
    tasbeeh.saveWird(text: 'اللّٰهُمَّ صَلِّ عَلَىٰ مُحَمَّدٍ وَآلِ مُحَمَّدٍ وَعَجِّلْ فَرَجَهُمْ', target: 14000);
    for (var index = 0; index < 2345; index++) {
      tasbeeh.tap();
    }
    await tester.pumpWidget(host(prayer, tasbeeh, homeScreen(), textScale: 1.35));
    await settle(tester);
    expect(find.byType(HomeDashboard), findsOneWidget);
    expect(find.text('قرآنِ کریم'), findsOneWidget);
    await shoot(tester, 'home-large-font');
    await finish(tester, prayer, tasbeeh);
  });

  testWidgets('the dashboard fits a short phone without scrolling', (tester) async {
    // 640 dp tall: both columns still fill the screen and share a baseline.
    phone(tester, height: 640);
    final (prayer, tasbeeh) = await controllersAt(tester, localTime(18, 20));
    await tester.pumpWidget(host(prayer, tasbeeh, homeScreen()));
    await settle(tester);
    expect(find.byType(HomeDashboard), findsOneWidget);
    expect(find.text('دینی مسائل'), findsOneWidget);
    await shoot(tester, 'home-short');
    await finish(tester, prayer, tasbeeh);
  });

  for (final (width, height) in <(double, double)>[(320, 640), (412, 915), (800, 1280)]) {
    testWidgets('the dashboard and dock fit a ${width.toInt()} by ${height.toInt()} screen', (tester) async {
      phone(tester, width: width, height: height);
      final (prayer, tasbeeh) = await controllersAt(tester, localTime(12, 10));
      await tester.pumpWidget(host(prayer, tasbeeh, homeScreen()));
      await settle(tester);
      final search = tester.getRect(find.byKey(const ValueKey<String>('home-search')));
      final fatawa = tester.getRect(find.byKey(const ValueKey<String>('home-section-fatawa')));
      expect(search.bottom, closeTo(fatawa.bottom, 0.1));
      expect(tester.getRect(find.byType(HomeDockBar)).top - search.bottom, lessThan(10));
      expect(tester.takeException(), isNull);
      await shoot(tester, 'home-${width.toInt()}');
      await finish(tester, prayer, tasbeeh);
    });
  }

  testWidgets('the bottom panel runs the features behind its five buttons', (tester) async {
    phone(tester);
    final (prayer, tasbeeh) = await controllersAt(tester, localTime(10, 0));
    final tapped = <HomeDockItem>[];
    await tester.pumpWidget(host(
      prayer,
      tasbeeh,
      Scaffold(
        bottomNavigationBar: HomeDockBar(
          selected: null,
          onSelected: tapped.add,
        ),
      ),
    ));
    await tester.pump();
    for (final item in HomeDockItem.values) {
      await tester.tap(find.text(item.label));
      await tester.pump();
    }
    expect(tapped, <HomeDockItem>[
      HomeDockItem.settings,
      HomeDockItem.bookmarks,
      HomeDockItem.qibla,
      HomeDockItem.lastSeen,
      HomeDockItem.xplore,
    ]);
    await finish(tester, prayer, tasbeeh);
  });

  testWidgets('home starts at the status bar and shares its lower and side edges with the dock', (tester) async {
    phone(tester);
    tester.view.padding = const FakeViewPadding(top: 72, bottom: 72);
    final (prayer, tasbeeh) = await controllersAt(tester, localTime(12, 10));
    await tester.pumpWidget(host(prayer, tasbeeh, homeScreen()));
    await settle(tester);
    final canvas = tester.getRect(find.byKey(const ValueKey<String>('home-canvas')));
    final search = tester.getRect(find.byKey(const ValueKey<String>('home-search')));
    final fatawa = tester.getRect(find.byKey(const ValueKey<String>('home-section-fatawa')));
    final first = tester.getRect(find.byKey(const ValueKey<String>('home-section-quran')));
    final dock = tester.getRect(find.byType(HomeDockBar));
    final dockSurface = tester.widget<ColoredBox>(find.descendant(
      of: find.byType(HomeDockBar), matching: find.byType(ColoredBox)).first);
    expect(dockSurface.color, Colors.black, reason: 'the whole dock, not just its keys, is black');
    expect(canvas.top, closeTo(24, 0.1), reason: 'no centred-canvas gap under the status bar');
    expect(first.top - canvas.top, lessThan(7));
    expect(search.bottom, closeTo(fatawa.bottom, 0.1));
    expect(dock.top - search.bottom, lessThan(8));
    // The dock is laid out right-to-left, so the first of the five is the
    // square on the right and the last is the one on the left.
    final firstIcon = tester.getRect(find.byKey(const ValueKey<String>('dock-icon-settings')));
    final lastIcon = tester.getRect(find.byKey(const ValueKey<String>('dock-icon-xplore')));
    expect(firstIcon.right, closeTo(fatawa.right, 0.1));
    expect(lastIcon.left, closeTo(search.left, 0.1));
    // Qibla is the middle of the five, and it wears the Kaaba itself.
    expect(HomeDockItem.values[HomeDockItem.values.length ~/ 2], HomeDockItem.qibla);
    final qiblaIcon = tester.getRect(find.byKey(const ValueKey<String>('dock-icon-qibla')));
    expect(qiblaIcon.center.dx, closeTo((search.left + fatawa.right) / 2, 1.0));
    expect(
      tester
          .widget<Image>(find.descendant(
            of: find.byKey(const ValueKey<String>('dock-icon-qibla')),
            matching: find.byType(Image),
          ))
          .image,
      isA<AssetImage>().having((image) => image.assetName, 'the Kaaba',
          'assets/images/kaaba_center.png'),
    );
    for (final item in HomeDockItem.values) {
      final icon = tester.getRect(find.byKey(ValueKey<String>('dock-icon-${item.name}')));
      final label = tester.getRect(find.byKey(ValueKey<String>('dock-label-${item.name}')));
      expect(icon.height, greaterThanOrEqualTo(76));
      expect(label.top, greaterThan(icon.bottom), reason: 'the name belongs below, not inside, the box');
    }
    final rail = tester.widget<RotatedBox>(find.ancestor(of: find.text('ShiaVerse'), matching: find.byType(RotatedBox)).first);
    expect(rail.quarterTurns, 3);
    expect(find.text('قرآن'), findsNothing);
    expect(find.text('دعائیں'), findsNothing);
    expect(tester.takeException(), isNull);
    await shoot(tester, 'home-status-bar');
    await finish(tester, prayer, tasbeeh);
  });

  testWidgets('the crescent page reads the sky the reader lives under', (tester) async {
    phone(tester);
    final (prayer, tasbeeh) = await controllersAt(tester, localTime(20, 10));
    await tester.pumpWidget(host(prayer, tasbeeh, const CrescentScreen()));
    await settle(tester);
    // 15 October 2026 is 3 Jumada al-Awwal 1448 in Islamabad, and the
    // crescent that opened the month was sighted on the evening of the 12th
    // — six and a half on Odeh's scale, plain to the eye.
    expect(find.text('جاری مہینہ'), findsOneWidget);
    expect(find.text('یکم جمادی الاول 1448ھ'), findsOneWidget);
    expect(find.textContaining('13 اکتوبر 2026'), findsWidgets);
    expect(find.text('رویت کی شام'), findsOneWidget);
    expect(find.text('ننگی آنکھ سے دکھائی دے گا'), findsWidgets);
    expect(tester.takeException(), isNull);
    expect(find.byType(SectionBackground), findsOneWidget);
    expectWallpaperInsidePanels(tester);
    await shoot(tester, 'crescent');
    await finish(tester, prayer, tasbeeh);
  });

  testWidgets('the Islamic calendar dates this year\'s days for this city', (tester) async {
    phone(tester);
    final (prayer, tasbeeh) = await controllersAt(tester, localTime(12, 10));
    await tester.pumpWidget(host(prayer, tasbeeh, const IslamicCalendarScreen()));
    await settle(tester);
    expect(find.text('اس سال کے ایام'), findsOneWidget);
    expect(find.text('3 جمادی الاول 1448ھ — G-11، اسلام آباد'), findsOneWidget);
    final calendarList = find.byType(ListView).first;
    for (var attempt = 0;
        attempt < 12 && find.byKey(const ValueKey<String>('islamic-occasion-calendar')).evaluate().isEmpty;
        attempt++) {
      await tester.drag(calendarList, const Offset(0, -320));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey<String>('islamic-occasion-calendar')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('occasion-calendar-pages')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey<String>('occasion-calendar-next')));
    await tester.pumpAndSettle();

    final hijriYear = prayer.hijriToday.date.year;
    // The screen uses the reader's manual Hijri adjustment, or zero when it
    // is set to automatic, when it maps occasions onto the civil calendar.
    final adjustment = prayer.hijriAdjustment ?? 0;
    var visibleMonthIndex = 0;
    final baseMonth = DateTime.utc(2026, 10);
    Future<void> revealOccasion(int year, int month, int day, String title) async {
      final civil = prayer.lunarHijri
          .civilStartOfMonth(year, month)
          .add(Duration(days: day - 1 - adjustment));
      final targetMonthIndex = (civil.year - baseMonth.year) * 12 + civil.month - baseMonth.month;
      expect(targetMonthIndex, greaterThanOrEqualTo(0));
      expect(targetMonthIndex, lessThanOrEqualTo(12));
      while (visibleMonthIndex < targetMonthIndex) {
        await tester.tap(find.byKey(const ValueKey<String>('occasion-calendar-next')));
        await tester.pumpAndSettle();
        visibleMonthIndex++;
      }
      while (visibleMonthIndex > targetMonthIndex) {
        await tester.tap(find.byKey(const ValueKey<String>('occasion-calendar-previous')));
        await tester.pumpAndSettle();
        visibleMonthIndex--;
      }
      expect(find.text(title), findsOneWidget);
    }

    await revealOccasion(hijriYear, 6, 3, 'شہادتِ حضرت فاطمہ زہرا س');
    await revealOccasion(hijriYear + 1, 1, 10, 'یومِ عاشورہ');
    await revealOccasion(hijriYear, 12, 18, 'عیدِ غدیر');
    expect(tester.takeException(), isNull);
    expect(find.byType(SectionBackground), findsOneWidget);
    expectWallpaperInsidePanels(tester);
    await shoot(tester, 'islamic-calendar');
    await finish(tester, prayer, tasbeeh);
  });

  testWidgets('the calendar converter accepts a date and looks up its Shia occasion', (tester) async {
    phone(tester);
    final (prayer, tasbeeh) = await controllersAt(tester, localTime(12, 10));
    final hijriNewYear = prayer.lunarHijri.civilStartOfMonth(1449, 1);
    await tester.pumpWidget(host(prayer, tasbeeh, const IslamicCalendarScreen()));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('gregorian-date-input')),
      '${hijriNewYear.day.toString().padLeft(2, '0')}/${hijriNewYear.month.toString().padLeft(2, '0')}/${hijriNewYear.year}',
    );
    await tester.tap(find.text('تبدیل کریں'));
    await settle(tester);
    expect(find.text('آغازِ سالِ ہجری'), findsOneWidget);
    expect(find.textContaining('دن: ${weekdayUrdu(hijriNewYear)}'), findsOneWidget);
    expect(find.textContaining(formatHijriUrdu(prayer.lunarHijri.dateFor(hijriNewYear))), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester, prayer, tasbeeh);
  });

  testWidgets('the shell connects Settings, Bookmarks, Last seen and Xplore without touching the collections', (tester) async {
    phone(tester);
    final (prayer, tasbeeh) = await controllersAt(tester, localTime(12, 10));
    final library = LibraryRepository();
    final installer = DataInstaller(directory: () => Directory('.cache/ui-test-data'));
    final actions = <HubDestination>[];
    await tester.pumpWidget(host(prayer, tasbeeh, HomeShell(
      library: library,
      installer: installer,
      themeMode: ThemeMode.light,
      onThemeModeChanged: (_) {},
      onAction: actions.add,
    )));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey<String>('dock-settings')));
    await settle(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey<String>('dock-bookmarks')));
    await tester.tap(find.byKey(const ValueKey<String>('dock-xplore')));
    expect(actions, <HubDestination>[HubDestination.bookmarks, HubDestination.more]);
    await tester.tap(find.byKey(const ValueKey<String>('dock-lastSeen')));
    await settle(tester);
    expect(find.text('تمام آخری مطالعہ'), findsOneWidget);
    expect(find.text('ابھی کوئی آخری مطالعہ محفوظ نہیں ہوا۔ کوئی کتاب کھولیں گے تو وہ یہاں دکھائی دے گی۔'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester, prayer, tasbeeh);
    await installer.close();
  });

  testWidgets('every default page palette is white', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: buildLightTheme(), home: Builder(builder: (context) {
      expect(Theme.of(context).scaffoldBackgroundColor, Colors.white);
      expect(GlassPalette.of(context).scaffold, Colors.white);
      expect(DashboardPalette.of(context).backdrop.colors, everyElement(Colors.white));
      return const SizedBox.shrink();
    })));
    expect((await ReaderPreferences.load()).palette.background, Colors.white);
    expect(HomeDockItem.values.map((item) => item.label).toList(),
        <String>['Settings', 'Bookmarks', 'Qibla', 'Last seen', 'Xplore']);
  });

  for (final (name, palette, scale) in <(String, String, double)>[
    ('quran', 'paper', 1),
    ('night', 'night', 1),
    ('large-font', 'paper', 1.6),
  ]) {
    testWidgets('the refreshed reader fits and retains its preferences ($name)', (tester) async {
      phone(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{'reader_palette': palette, 'reader_font_scale': scale});
      final (prayer, tasbeeh) = await controllersAt(tester, localTime(12, 10));
      await tester.pumpWidget(host(prayer, tasbeeh, SurahReaderScreen(
        library: _PreviewReaderLibrary(),
        surah: _previewSurah,
      ), textScale: name == 'large-font' ? 1.35 : 1));
      await settle(tester);
      expect(find.byType(ReaderScaffold), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('reader-banner')), findsOneWidget);
      expect(find.byType(PassageCard), findsWidgets);
      final frame = tester.widget<ReaderScaffold>(find.byType(ReaderScaffold));
      expect(frame.preferences.palette.key, palette);
      expect(frame.preferences.fontScale, scale);
      expect(tester.takeException(), isNull);
      await shoot(tester, 'reader-$name');
      await finish(tester, prayer, tasbeeh);
    });
  }

  testWidgets('the continuous Mushaf page fits a phone with the real Arabic font', (tester) async {
    phone(tester);
    final (prayer, tasbeeh) = await controllersAt(tester, localTime(12, 10));
    await tester.pumpWidget(host(prayer, tasbeeh, SurahReaderScreen(
      library: _PreviewReaderLibrary(), surah: _previewSurah, startInMushaf: true,
    )));
    await settle(tester);
    expect(find.byType(MushafText), findsWidgets);
    expect(find.byType(PassageCard), findsNothing);
    expect(tester.takeException(), isNull);
    await shoot(tester, 'reader-mushaf');
    await finish(tester, prayer, tasbeeh);
  });

  testWidgets('reader appearance, bookmarks, notes and last position still work', (tester) async {
    phone(tester);
    final (prayer, tasbeeh) = await controllersAt(tester, localTime(12, 10));
    final library = _PreviewReaderLibrary();
    await tester.pumpWidget(host(prayer, tasbeeh, SurahReaderScreen(library: library, surah: _previewSurah)));
    await settle(tester);
    expect((await library.getLastReadFor('quran'))?.recordId, 1);
    await tester.tap(find.byTooltip('محفوظ کریں').first);
    await tester.pump();
    expect(await library.isBookmarked('quran', 1), isTrue);
    await tester.tap(find.byTooltip('نوٹ').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'میرا محفوظ نوٹ');
    await tester.tap(find.text('محفوظ کریں').last);
    await tester.pumpAndSettle();
    expect(await library.getNote('quran', 1), 'میرا محفوظ نوٹ');
    await tester.tap(find.byKey(const ValueKey<String>('reader-appearance')));
    await tester.pumpAndSettle();
    expect(find.text('مطالعے کا انداز'), findsOneWidget);
    await shoot(tester, 'reader-appearance');
    await tester.tap(find.byTooltip('حروف بڑے'));
    await tester.pumpAndSettle();
    expect((await ReaderPreferences.load()).fontScale, greaterThan(1));
    await tester.tap(find.byKey(const ValueKey<String>('reader-palette-night')));
    await tester.pumpAndSettle();
    expect((await ReaderPreferences.load()).palette, ReaderPalette.night);
    final frame = tester.widget<ReaderScaffold>(find.byType(ReaderScaffold));
    expect(frame.preferences.palette, ReaderPalette.night);
    expect(tester.takeException(), isNull);
    await finish(tester, prayer, tasbeeh);
  });

  for (final source in <CorpusSource>[CorpusSource.hadith, CorpusSource.sahifa, CorpusSource.fatwa, CorpusSource.balagha, CorpusSource.dua]) {
    testWidgets('the ${source.name} reader uses the shared chrome without changing its list', (tester) async {
      phone(tester);
      final (prayer, tasbeeh) = await controllersAt(tester, localTime(12, 10));
      final library = _PreviewReaderLibrary();
      final book = BookDefinition.bookFor(source)!;
      final Widget screen = switch (source) {
        CorpusSource.balagha => BalaghaReaderScreen(library: library, type: 1, typeNo: 1, title: 'آزمائشی مطالعہ'),
        CorpusSource.dua => DuaReaderScreen(library: library, item: const DuaItem(rowId: 1,
          name: 'آزمائشی مطالعہ', categoryId: 1, isHeader: false, isFeatured: false)),
        _ => ReaderScreen(library: library, book: book, sectionId: 1, sectionTitle: 'آزمائشی مطالعہ'),
      };
      await tester.pumpWidget(host(prayer, tasbeeh, screen));
      await settle(tester);
      expect(find.byType(ReaderScaffold), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('reader-banner')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('آزمائشی متن'), findsWidgets);
      expect(tester.takeException(), isNull);
      await finish(tester, prayer, tasbeeh);
    });
  }

  testWidgets('the tasbeeh dial locks its reset button on a long press', (tester) async {
    phone(tester);
    final (prayer, tasbeeh) = await controllersAt(tester, localTime(10, 0));
    tasbeeh.tap();
    await tester.pumpWidget(host(prayer, tasbeeh, homeScreen()));
    await settle(tester);
    expect(find.byIcon(Icons.restart_alt), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsNothing);

    // A long press locks the reset button; the same button is the lock now.
    await tester.longPress(find.byIcon(Icons.restart_alt));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byIcon(Icons.lock), findsOneWidget, reason: 'the long press locks the reset button');
    expect(find.byIcon(Icons.restart_alt), findsNothing);

    // A tap on a locked reset only says so: no dialog, no cleared count.
    await tester.tap(find.byIcon(Icons.lock));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('گنتی صفر کریں؟'), findsNothing, reason: 'a locked reset never asks to reset');
    expect(tasbeeh.count, 1);

    // Long press again: unlocked, and the button resets again (with its dialog).
    await tester.longPress(find.byIcon(Icons.lock));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byIcon(Icons.restart_alt), findsOneWidget);
    await tester.tap(find.byIcon(Icons.restart_alt));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('گنتی صفر کریں؟'), findsOneWidget);
    await tester.tap(find.text('ری سیٹ'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(tasbeeh.count, 0);
    await finish(tester, prayer, tasbeeh);
  });

  testWidgets('the prayer screen fits, top to bottom', (tester) async {
    phone(tester, height: 2600);
    final (prayer, tasbeeh) = await controllersAt(tester, localTime(19, 50));
    await tester.pumpWidget(host(prayer, tasbeeh, const PrayerTimesScreen()));
    await settle(tester);
    expect(find.text('نماز کے اوقات'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('prayer-details-wallpaper')), findsOneWidget);
    expect(find.textContaining('تاریخِ ہجری:'), findsOneWidget);
    expect(find.textContaining('اکتوبر'), findsWidgets);
    expect(find.text('تسبیح'), findsWidgets);
    await shoot(tester, 'prayer-screen');
    await finish(tester, prayer, tasbeeh);
  });

  testWidgets('the Qibla bearing carries the transparent Kaaba asset on a narrow phone', (tester) async {
    phone(tester, width: 320);
    final (prayer, tasbeeh) = await controllersAt(tester, localTime(15, 30));
    // No hardware in a widget test: the sensor-less bearing still points to
    // the Kaaba, without opening a real EventChannel subscription.
    await tester.pumpWidget(host(prayer, tasbeeh, const QiblaScreen(autoStartCompass: false)));
    await settle(tester);
    final marker = tester.widget<Image>(find.byKey(const ValueKey<String>('qibla-kaaba-marker')));
    final resized = marker.image as ResizeImage;
    expect((resized.imageProvider as AssetImage).assetName, 'assets/images/kaaba_icon.png');
    // 1.21 returns the live compass to the top of the page; the street map is
    // the card underneath it, and its Qibla line is drawn even when the
    // compass never reports a heading.
    expect(find.byKey(const ValueKey<String>('qibla-compass-card')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('qibla-street-map')),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    expect(find.byKey(const ValueKey<String>('qibla-street-map')), findsOneWidget);
    expect(find.text('اصل نقشہ — کعبہ کی سمت'), findsOneWidget);
    expect(find.textContaining('© OpenStreetMap'), findsOneWidget);
    await shoot(tester, 'qibla-map');
    // The schematic card below it is a north-up diagram: one thick arrow from
    // «آپ» to the Kaaba, with the degrees spelled out underneath.
    await tester.scrollUntilVisible(
      find.text('نقشے پر سمتِ قبلہ'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    expect(find.text('نقشے پر سمتِ قبلہ'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('qibla-map-diagram')), findsOneWidget);
    expect(find.textContaining('نقشہ شمال اوپر ہے'), findsOneWidget);
    expect(find.textContaining('اسی رخ منہ کر کے نماز پڑھیں'), findsOneWidget);
    expect(find.text('شمال اوپر'), findsNothing);
    expect(find.byType(SectionBackground), findsOneWidget);
    expectWallpaperInsidePanels(tester);
    expect(tester.takeException(), isNull);
    await shoot(tester, 'qibla-3d');
    await finish(tester, prayer, tasbeeh);
  });

  testWidgets('the next prayer is highlighted without a coloured container', (tester) async {
    phone(tester);
    // 16:00 on 15 October 2026 in Islamabad: عصر is the running window (it
    // folds into ظہرین) and مغربین is genuinely the next cell.
    final (prayer, tasbeeh) = await controllersAt(tester, localTime(16, 0));
    await tester.pumpWidget(host(prayer, tasbeeh, homeScreen()));
    await settle(tester);
    // The next cell carries the «باقی …» countdown …
    expect(find.byKey(const ValueKey<String>('mini-countdown-maghrib')), findsOneWidget);
    expect(find.textContaining('باقی '), findsOneWidget);
    // … and no coloured container or outline: only the running prayer keeps
    // its solid emerald tile with the white border.
    final bordered = tester
        .widgetList<AnimatedContainer>(find.descendant(
          of: find.byKey(const ValueKey<String>('home-prayer-row')),
          matching: find.byType(AnimatedContainer),
        ))
        .where((container) {
          final decoration = container.decoration;
          return decoration is BoxDecoration && decoration.border != null;
        })
        .toList();
    expect(bordered, isNotEmpty, reason: 'the running prayer keeps its tile');
    for (final container in bordered) {
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.gradient, isNotNull,
          reason: 'a bordered cell must be the running prayer, not the next one');
    }
    expect(tester.takeException(), isNull);
    await shoot(tester, 'home-next-prayer');
    await finish(tester, prayer, tasbeeh);
  });

  testWidgets('the countdown stays on the same cell when the next prayer folds into it', (tester) async {
    phone(tester);
    // 13:30: عصر is next, and the mini card folds it into ظہرین — the cell that
    // is already running. The countdown must ride inside that tile instead of
    // vanishing (the old behaviour left no time on screen at all).
    final (prayer, tasbeeh) = await controllersAt(tester, localTime(13, 30));
    await tester.pumpWidget(host(prayer, tasbeeh, homeScreen()));
    await settle(tester);
    expect(find.byKey(const ValueKey<String>('mini-countdown-dhuhr')), findsOneWidget);
    expect(find.text('Now'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await shoot(tester, 'home-next-folded');
    await finish(tester, prayer, tasbeeh);
  });

  testWidgets('the tasbeeh screen fits, with a saved wird and its own count', (tester) async {
    phone(tester, height: 2200);
    final (prayer, tasbeeh) = await controllersAt(tester, localTime(10, 0));
    tasbeeh.saveWird(text: 'یا علی مدد', note: 'مولا علی (ع) سے مدد', target: 110);
    tasbeeh.saveWird(text: 'یا حسین', target: 72);
    for (var index = 0; index < 41; index++) {
      tasbeeh.tap();
    }
    await tester.pumpWidget(host(prayer, tasbeeh, const TasbeehScreen()));
    await settle(tester);
    expect(find.text('تعداد (ہدف)'), findsOneWidget);
    expect(find.byType(SectionBackground), findsOneWidget);
    expectWallpaperInsidePanels(tester);
    await shoot(tester, 'tasbeeh-screen');
    await finish(tester, prayer, tasbeeh);
  });

  testWidgets('Tasbeeh-e-Zahra on the full counter', (tester) async {
    phone(tester, height: 1500);
    final (prayer, tasbeeh) = await controllersAt(tester, localTime(13, 0));
    tasbeeh.startZahra();
    for (var index = 0; index < 40; index++) {
      tasbeeh.tap();
    }
    await tester.pumpWidget(host(prayer, tasbeeh, const TasbeehScreen()));
    await settle(tester);
    await shoot(tester, 'tasbeeh-zahra');
    await finish(tester, prayer, tasbeeh);
  });

  testWidgets('the location picker finds towns from the offline list', (tester) async {
    phone(tester);
    final (prayer, tasbeeh) = await controllersAt(tester, localTime(11, 0));
    // The list is parsed in a background isolate: let that finish for real.
    final index = await tester.runAsync(CityIndexLoader.load);
    expect(index, isNotNull);
    await tester.pumpWidget(host(prayer, tasbeeh, const Scaffold(body: LocationPickerSheet())));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'chak');
    await settle(tester);
    expect(find.text('چکوال'), findsOneWidget);
    expect(find.text('Chak Jhumra'), findsWidgets);
    await shoot(tester, 'location-picker');
    await finish(tester, prayer, tasbeeh);
  });

  test('the moment card has built-in lines for a phone with no books', () {
    expect(kFallbackMoments.length, greaterThanOrEqualTo(3));
    for (final line in kFallbackMoments) {
      expect(line.kind, anyOf('آیت', 'حدیث'));
      expect(line.arabic.trim(), isNotEmpty);
      expect(line.urdu.trim(), isNotEmpty);
      expect(line.source.trim(), isNotEmpty);
      expect(line.isOpenable, isFalse);
    }
  });

  /// The Xplore lens plate: six destinations on the plate and the radial menu
  /// in its bottom-right corner. Titled exactly like `main.dart` names them, so
  /// every lens finds its feature and nothing is drawn as a dead control.
  List<MoreFeature> exploreFeatures(void Function(String) onOpen) => <MoreFeature>[
        for (final (title, subtitle, icon) in <(String, String, IconData)>[
          ('تسبیح و ذکر', 'تسبیحِ زہرا (س) اور اپنے ورد کا مکمل کاؤنٹر', Icons.touch_app),
          ('نماز کے اوقات', 'اہلِ تشیع (جعفری) اوقات، مقام اور قرات کا وقت', Icons.schedule),
          ('چاند کی رویت', 'ہجری مہینے کا آغاز، آپ ہی کے شہر کے حساب سے', Icons.nightlight_round),
          ('اسلامی تقویم', 'محرم سے ذو الحجہ تک، اس سال کی تاریخوں کے ساتھ', Icons.calendar_month_rounded),
          ('Xplore Xtra', 'روزانہ مطالعہ، آنے والی سہولتیں اور روزمرہ کے چھوٹے tools',
              Icons.auto_awesome_rounded),
          ('اثنا عشری انسائکلوپیڈیا', 'بارہ ائمہ، اہلِ بیت، عقائد، عبادات اور معتبر ماخذ',
              Icons.menu_book_rounded),
        ])
          MoreFeature(
            title: title,
            subtitle: subtitle,
            icon: icon,
            color: const Color(0xFF6B4E9B),
            onOpen: () => onOpen(title),
          ),
      ];

  for (final (label, height) in <(String, double)>[('tall', 800), ('short', 640)]) {
    testWidgets('the Xplore lens plate fits a 360 dp phone ($label)', (tester) async {
      phone(tester, height: height);
      if (label == 'tall') {
        tester.view.padding = const FakeViewPadding(top: 72, bottom: 60);
      }
      final (prayer, tasbeeh) = await controllersAt(tester, localTime(19, 20));
      final opened = <String>[];
      final observer = RouteObserver<PageRoute<dynamic>>();
      await tester.pumpWidget(host(
        prayer,
        tasbeeh,
        ExploreScreen(
          features: exploreFeatures(opened.add),
          onAction: (_) {},
          onHubVisibilityChanged: (_) {},
          routeObserver: observer,
        ),
      ));
      await settle(tester);
      expect(find.textContaining('Xplore'), findsWidgets);
      final lensKeys = <String>[
        'xplore-lens-tasbeeh',
        'xplore-lens-prayer',
        'xplore-lens-crescent',
        'xplore-lens-calendar',
        'xplore-lens-xtra',
      ];
      final lensRects = lensKeys
          .map((key) => tester.getRect(find.byKey(ValueKey<String>(key))))
          .toList(growable: false);
      for (final rect in lensRects.skip(1)) {
        expect(rect.size, lensRects.first.size, reason: 'all circular Xplore controls share one size');
      }
      final plateKeys = <String>[
        'xplore-top-right-plate',
        'xplore-left-plate',
        'xplore-bottom-right-plate',
      ];
      final plateRects = plateKeys
          .map((key) => tester.getRect(find.byKey(ValueKey<String>(key))))
          .toList(growable: false);
      for (final rect in plateRects.skip(1)) {
        expect(rect.size, plateRects.first.size, reason: 'all triangular Xplore plates share one size');
      }
      if (label == 'tall') {
        expect(plateRects.first.top, greaterThanOrEqualTo(24));
        expect(plateRects.last.bottom, lessThanOrEqualTo(height - 20));
      }
      // Nothing may overflow: an overflowing plate is a failed layout.
      expect(tester.takeException(), isNull);
      await shoot(tester, 'explore-1-24-$label');

      // Every lens is a live control.
      for (final title in <String>['تسبیح', 'نماز']) {
        final lens = find.text(title);
        if (lens.evaluate().isEmpty) continue;
        await tester.tap(lens.first, warnIfMissed: false);
        await tester.pump();
      }
      expect(opened, isNotEmpty);

      // The radial menu opens from its plate in the bottom-right corner, not
      // from the middle of the page.
      final plate = find.text('Radial menu');
      expect(plate, findsOneWidget, reason: 'the radial control sits in its own plate');
      final plateCentre = tester.getCenter(plate);
      expect(plateCentre.dx, greaterThan(360 * 0.5));
      expect(plateCentre.dy, greaterThan(height * 0.75));
      await tester.tap(plate, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Bookmarks'), findsOneWidget);
      expect(find.text('مینو بند کریں'), findsWidgets);
      await shoot(tester, 'explore-1-24-menu');
      // The five dials carry a caption under each one; a caption one pixel too
      // tall shows up here, not on a reader's phone.
      expect(tester.takeException(), isNull);

      await finish(tester, prayer, tasbeeh);
    });
  }
}


const _previewSurah = QuranSurah(number: 1, nameArabic: 'الفاتحة', nameUrdu: 'الفاتحہ',
    revelationPlace: 'مکی', verseCount: 7, revelationOrder: 5);

class _PreviewReaderLibrary extends LibraryRepository {
  @override
  Future<List<Passage>> getSurahVerses(int chapter) async => const <Passage>[
    Passage(recordId: 1, sectionId: 1, arabic: 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
      urdu: '(۱)اللہ کے نام کی مدد سے (شروع کرتا ہوں) جو سب کو فیض پہنچانے والا بڑا ہی مہربان ہے۔', locator: 'آیت 1'),
    Passage(recordId: 2, sectionId: 1, arabic: 'الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ',
      urdu: '(۲) ہر ایک تعریف اُس اللہ کے لیے ہے جو تمام کائنات کاپالنے والا ہے۔', locator: 'آیت 2'),
    Passage(recordId: 3, sectionId: 1, arabic: 'الرَّحْمَٰنِ الرَّحِيمِ',
      urdu: '(۳) سب کو فیض پہنچانے والا،مسلسل بے حدرحم کرنے والا۔', locator: 'آیت 3'),
  ];

  static const _layoutText = <Passage>[
    Passage(recordId: 1, sectionId: 1, arabic: '', urdu: 'آزمائشی متن — صرف لے آؤٹ کی جانچ کے لیے۔'),
  ];

  @override
  Future<List<Passage>> getSectionPassages(BookDefinition book, int sectionId) async => _layoutText;

  @override
  Future<List<Passage>> getDuaLines(int itemRowId) async => _layoutText;

  @override
  Future<List<Passage>> getBalaghaEntry(int type, int typeNo) async => _layoutText;
}

/// The section photograph must live INSIDE the glass containers now, not behind
/// the page: at least one panel paints a `DecorationImage`, and no full-page
/// wallpaper image is built.
void expectWallpaperInsidePanels(WidgetTester tester) {
  expect(find.byType(SectionWallpaper), findsOneWidget,
      reason: 'the section must publish its wallpaper to the panels');
  final papered = tester.widgetList<Container>(find.byType(Container)).where((container) {
    final decoration = container.decoration;
    return decoration is BoxDecoration && decoration.image != null;
  });
  expect(papered, isNotEmpty,
      reason: 'the wallpaper must be painted inside the containers');
  expect(
    find.byWidgetPredicate((widget) =>
        widget is Image &&
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith('section-background-')),
    findsNothing,
    reason: 'the page itself must not be painted with the wallpaper',
  );
}

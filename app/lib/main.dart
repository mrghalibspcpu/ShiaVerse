import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'data_installer.dart';
import 'library_repository.dart';
import 'models.dart';
import 'reader_navigation.dart';
import 'screens/crescent_screen.dart';
import 'screens/daily_study_screen.dart';
import 'screens/data_screen.dart';
import 'screens/explore_screen.dart';
import 'screens/islamic_calendar_screen.dart';
import 'screens/library_screen.dart';
import 'screens/new_books_screen.dart';
import 'screens/prayer_times_screen.dart';
import 'screens/qibla_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tasbeeh_screen.dart';
import 'screens/xplore_xtra_screen.dart';
import 'services/community_stats.dart';
import 'services/prayer_controller.dart';
import 'services/prayer_scope.dart';
import 'services/tasbeeh_controller.dart';
import 'widgets/home_dashboard.dart';
import 'widgets/last_seen_sheet.dart';
import 'widgets/more_features.dart';
import 'widgets/reading_hub.dart';

/// Set once the 1.10 light-by-default rule has run on this phone.
/// The first start of this version moves the reader to the dark look; a
/// choice made afterwards in the settings is kept.
const String _kDarkDefaultKey = 'dark_default_applied';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark.copyWith(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
  ));
  runApp(const ShiaLibraryApp());
}

class ShiaLibraryApp extends StatefulWidget {
  const ShiaLibraryApp({super.key});

  @override
  State<ShiaLibraryApp> createState() => _ShiaLibraryAppState();
}

class _ShiaLibraryAppState extends State<ShiaLibraryApp> {
  final LibraryRepository _library = LibraryRepository();
  late final DataInstaller _installer =
      DataInstaller(directory: () => _library.dataDirectoryHandle);
  // The prayer/tasbeeh state lives above the navigator for the whole session:
  // the timings screen, the home banner and the Qibla compass all read the
  // same coordinates and preferences, and the tasbeeh keeps counting while the
  // reader moves between screens.
  final PrayerController _prayer = PrayerController();
  final TasbeehController _tasbeeh = TasbeehController();
  final AppLinks _appLinks = AppLinks();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<HomeShellState> _homeShellKey = GlobalKey<HomeShellState>();
  StreamSubscription<Uri>? _linkSubscription;
  ReaderTarget? _pendingTarget;
  String? _lastHandledLink;
  DateTime? _lastHandledAt;
  /// Dark until the reader's own choice arrives from storage — the first
  /// frame is already dark.
  ThemeMode _themeMode = ThemeMode.dark;
  bool _amoled = false;
  // How many pages sit on top of the home screen, and the observer that counts
  // them: the circular hub is shown while the count is above zero.
  final ValueNotifier<int> _pageDepth = ValueNotifier<int>(0);
  final ValueNotifier<bool> _hideReadingHub = ValueNotifier<bool>(false);
  late final ReadingDepthObserver _depthObserver = ReadingDepthObserver(_pageDepth);
  final RouteObserver<PageRoute<dynamic>> _exploreRouteObserver = RouteObserver<PageRoute<dynamic>>();

  @override
  void initState() {
    super.initState();
    unawaited(_loadTheme());
    // Both start from what is already on the phone, so the home screen paints
    // correct times and a correct count on the very first frame.
    unawaited(_prayer.start());
    unawaited(_tasbeeh.load());
    // Privacy-safe anonymous install record (random ID + dates only, on-device)
    // and a refresh of the public community counters when online.
    unawaited(() async {
      final stats = CommunityStatsService();
      await stats.ensureInstallRecord();
      await stats.refresh();
    }());
    _linkSubscription = _appLinks.uriLinkStream.listen(_handleIncomingLink, onError: (_) {});
    unawaited(_appLinks.getInitialLink().then(_handleIncomingLink, onError: (_) {}));
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    // Dark is the app's look. The first start of this version moves the
    // reader to it — from light, from "system", or from no choice at all —
    // once; anything chosen afterwards in the settings is always kept.
    if (!prefs.containsKey(_kDarkDefaultKey)) {
      final previous = prefs.getString('theme_mode');
      if (previous == null || previous == 'system' || previous == 'light') {
        await prefs.setString('theme_mode', 'dark');
      }
      await prefs.setBool(_kDarkDefaultKey, true);
    }
    final stored = prefs.getString('theme_mode');
    if (!mounted) return;
    setState(() {
      _amoled = stored == 'amoled';
      _themeMode = switch (stored) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark, // 'dark', 'amoled', or nothing stored yet
      };
    });
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() {
      _themeMode = mode;
      _amoled = false;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'theme_mode',
      switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    );
  }

  /// AMOLED (true black) is stored as its own theme_mode value; everywhere
  /// else it simply behaves as dark.
  Future<void> _setAmoled(bool enabled) async {
    setState(() {
      _amoled = enabled;
      if (enabled) _themeMode = ThemeMode.dark;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', enabled ? 'amoled' : 'dark');
  }

  @override
  void dispose() {
    unawaited(_linkSubscription?.cancel() ?? Future<void>.value());
    unawaited(_installer.close());
    unawaited(_library.close());
    _prayer.dispose();
    _tasbeeh.dispose();
    _pageDepth.dispose();
    _hideReadingHub.dispose();
    super.dispose();
  }

  void _handleIncomingLink(Uri? uri) {
    if (uri == null || uri.scheme != 'shiaai' || uri.host != 'reader') return;
    final now = DateTime.now();
    final link = uri.toString();
    if (_lastHandledLink == link &&
        _lastHandledAt != null &&
        now.difference(_lastHandledAt!).inSeconds < 3) {
      return;
    }
    _lastHandledLink = link;
    _lastHandledAt = now;
    final book = uri.queryParameters['book'];
    final recordId = int.tryParse(uri.queryParameters['record_id'] ?? '');
    if (BookDefinition.byKey(book) == null || recordId == null || recordId <= 0) return;
    final target = ReaderTarget(
      book: book!.toLowerCase(),
      recordId: recordId,
      sectionId: int.tryParse(uri.queryParameters['section_id'] ?? ''),
      page: int.tryParse(uri.queryParameters['page'] ?? ''),
    );
    if (_library.isInitialized) {
      _openReaderTarget(target);
    } else {
      _pendingTarget = target;
    }
  }

  void _openPendingReaderTarget() {
    final target = _pendingTarget;
    _pendingTarget = null;
    if (target != null) _openReaderTarget(target);
  }

  void _openReaderTarget(ReaderTarget target) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final navigator = _navigatorKey.currentState;
      final book = BookDefinition.byKey(target.book);
      if (!mounted || navigator == null || book == null || !_library.isInstalled(book)) {
        _pendingTarget = target;
        return;
      }
      await pushReaderFor(
        navigator.context,
        library: _library,
        book: book,
        recordId: target.recordId,
        sectionId: target.sectionId,
      );
    });
  }

  /// What the bottom panel and the radial menu do. A page opens on top of the
  /// current one, so the book behind it stays exactly where it was.
  void _runHubAction(HubDestination destination) {
    final navigator = _navigatorKey.currentState;
    final homeContext = _homeShellKey.currentContext;
    if (navigator == null || homeContext == null) return;
    switch (destination) {
      case HubDestination.home:
        navigator.popUntil((route) => route.isFirst);
        _homeShellKey.currentState?.refresh();
      case HubDestination.search:
        // Search is the bar on the dashboard now, and it is a page: over a
        // page, the hub opens it on top of that page.
        unawaited(navigator.push(MaterialPageRoute<void>(
          builder: (_) => SearchScreen(
            library: _library,
            onOpenData: () => unawaited(navigator.push(MaterialPageRoute<void>(
              builder: (_) => DataScreen(library: _library, installer: _installer),
            ))),
          ),
        )));
      case HubDestination.bookmarks:
        unawaited(navigator.push(MaterialPageRoute<void>(
          builder: (_) => SavedItemsScreen(library: _library),
        )));
      case HubDestination.more:
        unawaited(navigator.push(MaterialPageRoute<void>(
          builder: (_) => ExploreScreen(
            features: _moreFeatures(homeContext),
            onAction: _runHubAction,
            onHubVisibilityChanged: (hidden) => _hideReadingHub.value = hidden,
            routeObserver: _exploreRouteObserver,
          ),
        )));
      case HubDestination.settings:
        _homeShellKey.currentState?.openSettings();
    }
  }

  /// The items of **Xplore** — every feature that is not one of the five
  /// buttons of the bottom panel, in one list. New extras are added here.
  /// The collections (نہج البلاغہ، دینی مسائل…) are NOT repeated here: they
  /// already live on the home screen's own cards.
  List<MoreFeature> _moreFeatures(BuildContext homeContext) => <MoreFeature>[
        // ShiaAi is opened from Xplore → Xplore Xtra (and from Settings).
        // The radial Xplore plate renders only its six curated features, so it
        // is intentionally not listed here.
        MoreFeature(
          title: 'نئی کتابیں',
          subtitle: 'شیعہ اردو ویکیپیڈیا — مضامین، ائمہ اور اصل ماخذ کے لنکس',
          icon: Icons.library_add_rounded,
          color: const Color(0xFF4B3B78),
          onOpen: () => unawaited(_navigatorKey.currentState?.push(MaterialPageRoute<void>(
            builder: (_) => NewBooksScreen(
              library: _library,
              onOpenData: () => _homeShellKey.currentState?.openData(),
            ),
          ))),
        ),
        // 1.22: a plan beats a library. Readers asked for a way to finish a
        // book rather than open it, so Xplore leads with the daily portion.
        MoreFeature(
          title: 'روزانہ مطالعہ',
          subtitle: 'قرآن یا نہج البلاغہ — روز کا مقررہ حصہ، ساتھ میں تسلسل کا حساب',
          icon: Icons.event_available_rounded,
          color: const Color(0xFF1F6E5A),
          onOpen: () => unawaited(_navigatorKey.currentState?.push(MaterialPageRoute<void>(
            builder: (_) => DailyStudyScreen(library: _library),
          ))),
        ),
        MoreFeature(
          title: 'نماز کے اوقات',
          subtitle: 'اہلِ تشیع (جعفری) اوقات، مقام اور قرات کا وقت',
          icon: Icons.schedule,
          color: kForest,
          onOpen: () => unawaited(_navigatorKey.currentState?.push(MaterialPageRoute<void>(
            builder: (_) => const PrayerTimesScreen(),
          ))),
        ),
        MoreFeature(
          title: 'تسبیح و ذکر',
          subtitle: 'تسبیحِ زہرا (س) اور اپنے ورد کا مکمل کاؤنٹر',
          icon: Icons.touch_app,
          color: const Color(0xFF6B4E9B),
          onOpen: () => unawaited(_navigatorKey.currentState?.push(MaterialPageRoute<void>(
            builder: (_) => const TasbeehScreen(),
          ))),
        ),
        MoreFeature(
          title: 'ڈیٹا ڈاؤن لوڈ',
          subtitle: 'کتب اور ڈیٹا پیکج کا انتظام',
          icon: Icons.download_rounded,
          color: const Color(0xFF2F6FD6),
          onOpen: () => _homeShellKey.currentState?.openData(),
        ),
        MoreFeature(
          title: 'چاند کی رویت',
          subtitle: 'ہجری مہینے کا آغاز، آپ ہی کے شہر کے حساب سے',
          icon: Icons.nightlight_round,
          color: const Color(0xFF8A6A2F),
          onOpen: () => unawaited(_navigatorKey.currentState?.push(MaterialPageRoute<void>(
            builder: (_) => const CrescentScreen(),
          ))),
        ),
        MoreFeature(
          title: 'اسلامی تقویم',
          subtitle: 'محرم سے ذو الحجہ تک، اس سال کی تاریخوں کے ساتھ',
          icon: Icons.calendar_month_rounded,
          color: const Color(0xFF146B70),
          onOpen: () => unawaited(_navigatorKey.currentState?.push(MaterialPageRoute<void>(
            builder: (_) => const IslamicCalendarScreen(),
          ))),
        ),
        MoreFeature(
          title: 'Xplore Xtra',
          subtitle: 'روزانہ مطالعہ، آنے والی سہولتیں اور روزمرہ کے چھوٹے tools',
          icon: Icons.auto_awesome_rounded,
          color: const Color(0xFFC38B3F),
          onOpen: () => unawaited(_navigatorKey.currentState?.push(MaterialPageRoute<void>(
            builder: (_) => XploreXtraScreen(library: _library),
          ))),
        ),
        MoreFeature(
          title: 'اثنا عشری انسائکلوپیڈیا',
          subtitle: 'بارہ ائمہ، اہلِ بیت، عقائد، عبادات اور معتبر ماخذ',
          icon: Icons.menu_book_rounded,
          color: const Color(0xFF547E9F),
          onOpen: () {
            final book = BookDefinition.byKey('athna_ashari_encyclopedia')!;
            unawaited(_navigatorKey.currentState?.push(MaterialPageRoute<void>(
              builder: (_) => _library.isInstalled(book)
                  ? EncyclopediaBrowseScreen(
                      library: _library,
                      book: book,
                      onOpenData: () => _homeShellKey.currentState?.openData(),
                    )
                  : NewBooksScreen(
                      library: _library,
                      onOpenData: () => _homeShellKey.currentState?.openData(),
                    ),
            )));
          },
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShiaVerse',
      navigatorKey: _navigatorKey,
      navigatorObservers: <NavigatorObserver>[_depthObserver, _exploreRouteObserver],
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: _amoled ? buildAmoledTheme() : buildDarkTheme(),
      themeMode: _themeMode,
      builder: (context, child) => PrayerScope(
        controller: _prayer,
        child: TasbeehScope(
          controller: _tasbeeh,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: ReadingHub(
              depth: _pageDepth,
              hidden: _hideReadingHub,
              onAction: _runHubAction,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
      home: LibraryBootstrap(
        library: _library,
        installer: _installer,
        themeMode: _themeMode,
        onThemeModeChanged: _setThemeMode,
        amoled: _amoled,
        onAmoledChanged: _setAmoled,
        onReady: _openPendingReaderTarget,
        homeShellKey: _homeShellKey,
        onAction: _runHubAction,
      ),
    );
  }
}

class LibraryBootstrap extends StatefulWidget {
  const LibraryBootstrap({
    super.key,
    required this.library,
    required this.installer,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onReady,
    this.amoled = false,
    this.onAmoledChanged,

    required this.homeShellKey,
    required this.onAction,
  });

  final LibraryRepository library;
  final DataInstaller installer;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final bool amoled;
  final ValueChanged<bool>? onAmoledChanged;
  final VoidCallback onReady;
  final GlobalKey<HomeShellState> homeShellKey;
  final ValueChanged<HubDestination> onAction;

  @override
  State<LibraryBootstrap> createState() => _LibraryBootstrapState();
}

class _LibraryBootstrapState extends State<LibraryBootstrap> {
  double _progress = 0;
  String _status = 'کتب کی تیاری ہو رہی ہے';
  String? _error;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    setState(() => _error = null);
    try {
      // Only the quick part happens here: unpack what is already on the phone
      // and open the books. The slow full-text index runs in the background so
      // the library opens straight away — even on a fresh install that has not
      // downloaded anything yet.
      await widget.library.initialize(
        onProgress: (progress, message) {
          if (!mounted) return;
          setState(() {
            _progress = progress;
            _status = message;
          });
        },
        buildSearchIndex: false,
      );
      if (mounted) widget.onReady();
      unawaited(widget.library.ensureSearchIndex());
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      _starting = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.library.isInitialized) {
      // The home screen always wins, with or without data on disk: a missing
      // book is a download button on the library, never a blocked app.
      return HomeShell(
        key: widget.homeShellKey,
        library: widget.library,
        installer: widget.installer,
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        amoled: widget.amoled,
        onAmoledChanged: widget.onAmoledChanged,
        onAction: widget.onAction,
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: Image.asset(
                      'assets/images/shiaverse_icon.png',
                      width: 116,
                      height: 116,
                      fit: BoxFit.cover,
                      // The asset is 512x512; decoding it at 240 px costs a
                      // fraction of a megabyte and paints without a stall.
                      cacheWidth: 240,
                      cacheHeight: 240,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text('ShiaVerse', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  JustifiedText(_error == null ? _status : 'کتب تیار کرتے ہوئے مسئلہ پیش آیا: $_error'),
                  const SizedBox(height: 18),
                  if (_error == null) ...[
                    LinearProgressIndicator(value: _progress == 0 ? null : _progress),
                    const SizedBox(height: 10),
                    Text('${(_progress * 100).round()}%'),
                  ] else
                    FilledButton.icon(
                      onPressed: _starting ? null : _start,
                      icon: const Icon(Icons.refresh),
                      label: const Text('دوبارہ کوشش کریں'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.library,
    required this.installer,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onAction,
    this.amoled = false,
    this.onAmoledChanged,
  });

  final LibraryRepository library;
  final DataInstaller installer;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final bool amoled;
  final ValueChanged<bool>? onAmoledChanged;

  /// The shared page actions used by the dock and the reading hub.
  final ValueChanged<HubDestination> onAction;

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  // Collections stay on the side rail; personal tools live in the dock.
  late final Widget _homePage = LibraryHomeScreen(
    library: widget.library,
    onOpenData: openData,
  );

  void openData() {
    if (!mounted) return;
    unawaited(Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => DataScreen(library: widget.library, installer: widget.installer),
        ))
        .then((_) {
      if (mounted) setState(() {});
    }));
  }

  void openSettings() {
    if (!mounted) return;
    unawaited(Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettingsScreen(
        library: widget.library,
        installer: widget.installer,
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        amoled: widget.amoled,
        onAmoledChanged: widget.onAmoledChanged,
      ),
    )));
  }

  /// Rebuilds the home page. Used after returning from a deep page, so the
  /// home never stays on a stale frame.
  void refresh() {
    if (mounted) setState(() {});
  }

  void _onDockSelected(HomeDockItem item) {
    switch (item) {
      case HomeDockItem.qibla:
        unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const QiblaScreen())));
      case HomeDockItem.settings:
        openSettings();
      case HomeDockItem.bookmarks:
        widget.onAction(HubDestination.bookmarks);
      case HomeDockItem.lastSeen:
        unawaited(showLastSeenSheet(context, library: widget.library, onOpened: refresh));
      case HomeDockItem.xplore:
        widget.onAction(HubDestination.more);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when a download finishes, so the dashboard's containers show the
    // new book immediately instead of after a manual refresh.
    return ValueListenableBuilder<int>(
      valueListenable: widget.library.catalogVersion,
      builder: (context, _, __) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: (Theme.of(context).brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark)
            .copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent),
        child: Scaffold(
          body: TickerMode(enabled: true, child: _homePage),
          bottomNavigationBar: HomeDockBar(
            selected: null,
            onSelected: _onDockSelected,
          ),
        ),
      ),
    );
  }
}

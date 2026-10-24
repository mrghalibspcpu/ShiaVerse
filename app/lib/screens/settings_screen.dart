import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../data_installer.dart';
import '../data_packages.dart';
import '../library_repository.dart';
import '../widgets/reader_kit.dart';
import 'data_screen.dart';
import 'shia_ai_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.library,
    required this.installer,
    required this.themeMode,
    required this.onThemeModeChanged,
    this.amoled = false,
    this.onAmoledChanged,
  });

  final LibraryRepository library;
  final DataInstaller installer;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final bool amoled;
  final ValueChanged<bool>? onAmoledChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Local copy: the screen is pushed as a route, so it must show the choice
  /// the reader just made without waiting for the app to rebuild it.
  late String _themeChoice = widget.amoled
      ? 'amoled'
      : switch (widget.themeMode) {
          ThemeMode.dark => 'dark',
          ThemeMode.system => 'system',
          ThemeMode.light => 'light',
        };
  double _fontScale = 1.0;
  String _script = 'both';
  bool _loading = true;
  bool _rebuilding = false;
  bool _verifying = false;
  String? _status;
  bool _statusError = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final preferences = await ReaderPreferences.load();
    if (!mounted) return;
    setState(() {
      _fontScale = preferences.fontScale;
      _script = preferences.script;
      _loading = false;
    });
  }

  Future<void> _saveFont(double value) async {
    setState(() => _fontScale = value);
    await ReaderPreferences().saveFontScale(value);
  }

  Future<void> _saveScript(String value) async {
    setState(() => _script = value);
    await ReaderPreferences().saveScript(value);
  }

  /// Opens a mail or dial link; failures are spoken in Urdu rather than
  /// leaving the reader with a button that did nothing.
  Future<void> _launch(String target) async {
    final uri = Uri.tryParse(target);
    if (uri == null) return;
    final opened = await launchUrl(uri);
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ایپ کھل نہیں سکی — ای میل یا فون ایپ دستیاب نہیں۔')),
    );
  }

  /// The public policy Page. It is also the URL entered on APKPure, so the two
  /// can never point at different texts.
  static final Uri _privacyPolicyUrl =
      Uri.parse('https://mrghalibspcpu.github.io/ShiaVerse/privacy-policy/');

  /// Where the texts come from, in the reader's words, so a question about
  /// rights can be answered without leaving the app.
  void _showSources() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ماخذ اور حقوق'),
        content: const SingleChildScrollView(
          child: Text(
            'قرآن، احادیث، مفاتیح الجنان، صحیفہ سجادیہ اور نہج البلاغہ کے عربی متون قدیم ہیں؛ '
            'ان کے اردو تراجم، حواشی اور تدوین کے حقوق متعلقہ مترجمین، مصنفین اور ناشرین کے ہیں۔\n\n'
            'فتاویٰ آیت اللہ خامنہ ای اور آیت اللہ سیستانی کے سرکاری اردو صفحات سے لیے گئے ہیں؛ '
            'ہر جواب کے ساتھ اصل ماخذ کا لنک موجود ہے۔ کسی حکم پر عمل سے پہلے اصل ماخذ یا مرجع کے دفتر سے تصدیق کریں۔\n\n'
            'اثنا عشری انسائیکلو پیڈیا اردو ویکیپیڈیا اور ویکی شیعہ کے مضامین پر مبنی ہے؛ ہر حصے کے ساتھ اصل صفحہ کا حوالہ محفوظ ہے۔\n\n'
            'قبلہ کے نقشے کی ٹائلیں © OpenStreetMap contributors اور Esri (HERE, Garmin) کی ہیں۔\n\n'
            'ShiaAi کا ہر حوالہ اسی ڈیوائس پر موجود کتب کی حقیقی ریکارڈ سے بنتا ہے۔ آن لائن موڈ میں پوری کتاب یا ڈیٹا بیس کبھی اپ لوڈ نہیں ہوتا؛ '
            'صرف چند منتخب متعلقہ عبارتیں آپ کے اپنے گیٹ وے اور وہاں سے Gemini کو جاتی ہیں، اور یہ صرف آپ کی واضح اجازت سے ہوتا ہے۔ '
            'Gemini کی کلید ایپ میں کبھی محفوظ نہیں ہوتی۔\n\n'
            'یہ ایپ کتب کے مصنفین یا اداروں کی طرف سے سرکاری طور پر تصدیق شدہ ہونے کا دعویٰ نہیں کرتی۔',
            style: TextStyle(height: 1.8),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('ٹھیک ہے'),
          ),
        ],
      ),
    );
  }

  Future<void> _rebuildIndex() async {
    if (_rebuilding) return;
    setState(() {
      _rebuilding = true;
      _status = null;
    });
    try {
      await widget.library.rebuildSearchIndex(onProgress: (_, __) {});
      if (!mounted) return;
      setState(() {
        _status = 'تلاش کی فہرست دوبارہ بن گئی۔';
        _statusError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = error.toString();
        _statusError = true;
      });
    } finally {
      if (mounted) setState(() => _rebuilding = false);
    }
  }

  Future<void> _verifyData() async {
    if (_verifying) return;
    setState(() {
      _verifying = true;
      _status = 'فائلوں کی تصدیق ہو رہی ہے…';
      _statusError = false;
    });
    try {
      await widget.installer.loadCatalog(allowNetwork: false);
      final results = await widget.installer.verifyInstalled();
      final broken = results.where((entry) => !entry.$2).toList();
      if (!mounted) return;
      setState(() {
        _status = broken.isEmpty
            ? '${results.length} فائلیں درست ہیں۔'
            : 'خراب فائلیں: ${broken.map((entry) => entry.$1.titleUrdu).join('، ')} — دوبارہ ڈاؤن لوڈ کریں۔';
        _statusError = broken.isNotEmpty;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = error.toString();
        _statusError = true;
      });
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _openDataScreen() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DataScreen(library: widget.library, installer: widget.installer),
    ));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final installed = widget.library.installedBooks;
    final installedBytes = widget.installer.installedBytes();
    return Scaffold(
      appBar: AppBar(title: const JustifiedText('ترتیبات')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
              children: [
                // A jewel-toned banner (plum -> teal -> gold) heads the page,
                // so Settings feels as crafted as the rest of the app.
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [Color(0xFF3B2358), Color(0xFF14586B), Color(0xFF8A6A2F)],
                    ),
                  ),
                  child: const Row(children: [
                    Icon(Icons.settings_suggest_rounded, color: Color(0xFFFFE1A1), size: 30),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        JustifiedText('اپنی پسند، اپنا انداز', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                        JustifiedText('تھیم (روشن، تاریک، AMOLED، نظام)، حروف کا سائز، متن اور ڈیٹا — سب کچھ یہیں سے اپنے ذوق کے مطابق ڈھالیں۔',
                            style: TextStyle(fontSize: 12.5, height: 1.5, color: Color(0xFFF3EAD2))),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                const _SectionTitle('ڈیٹا'),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.download_rounded),
                    title: const JustifiedText(
                      'ڈاؤن لوڈ اور انسٹال',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const JustifiedText(
                      'کتابیں ڈاؤن لوڈ اور انسٹال کریں، یا انسٹال شدہ ڈیٹا دیکھیں',
                      maxLines: 2,
                    ),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () {
                      Navigator.of(context)
                          .push(MaterialPageRoute<void>(
                            builder: (_) => DataScreen(
                              library: widget.library,
                              installer: widget.installer,
                            ),
                          ))
                          .then((_) {
                        if (mounted) setState(() {});
                      });
                    },
                  ),
                ),
                const SizedBox(height: 8),
                const _SectionTitle('مطالعہ'),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'light', label: Text('روشن'), icon: Icon(Icons.light_mode)),
                    ButtonSegment(value: 'dark', label: Text('تاریک'), icon: Icon(Icons.dark_mode)),
                    ButtonSegment(value: 'amoled', label: Text('AMOLED'), icon: Icon(Icons.brightness_1)),
                    ButtonSegment(value: 'system', label: Text('نظام'), icon: Icon(Icons.phone_android)),
                  ],
                  selected: {_themeChoice},
                  onSelectionChanged: (selection) {
                    final choice = selection.first;
                    setState(() => _themeChoice = choice);
                    switch (choice) {
                      case 'amoled':
                        widget.onAmoledChanged?.call(true);
                      case 'dark':
                        widget.onAmoledChanged?.call(false);
                        widget.onThemeModeChanged(ThemeMode.dark);
                      case 'system':
                        widget.onAmoledChanged?.call(false);
                        widget.onThemeModeChanged(ThemeMode.system);
                      default:
                        widget.onAmoledChanged?.call(false);
                        widget.onThemeModeChanged(ThemeMode.light);
                    }
                  },
                ),
                const SizedBox(height: 6),
                JustifiedText(
                  _themeChoice == 'amoled'
                      ? 'AMOLED: خالص سیاہ (#000000) — AMOLED اسکرین پر پکسل بند، بیٹری کی بچت اور گہرا کنٹراسٹ۔'
                      : _themeChoice == 'dark'
                          ? 'تاریک: عام نرم سیاہ/گرے — رات کے مطالعے کے لیے آنکھوں پر ہلکی۔'
                          : 'روشن: سفید تھیم؛ نظام: فون کی اپنی تھیم کے ساتھ خود بدلتی ہے۔',
                  style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                JustifiedText('حروف کا سائز (${(_fontScale * 100).round()}٪)'),
                Slider(
                  value: _fontScale,
                  min: 0.85,
                  max: 1.6,
                  divisions: 15,
                  label: '${(_fontScale * 100).round()}%',
                  onChanged: (value) => setState(() => _fontScale = value),
                  onChangeEnd: _saveFont,
                ),
                const SizedBox(height: 8),
                JustifiedText('ڈیفالٹ متن'),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'both', label: Text('عربی و اردو')),
                    ButtonSegment(value: 'arabic', label: Text('صرف عربی')),
                    ButtonSegment(value: 'urdu', label: Text('صرف اردو')),
                  ],
                  selected: {_script},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) => _saveScript(selection.first),
                ),
                const SizedBox(height: 26),
                const _SectionTitle('ڈیٹا'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        JustifiedText(
                          '${installed.length} کتب نصب ہیں • ${formatBytes(installedBytes)}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        JustifiedText(
                          widget.library.hasFastSearch
                              ? 'تلاش کا مقامی انجن تیار ہے۔'
                              : 'تلاش بنیادی طریقے پر چل رہی ہے؛ فہرست دوبارہ بنائیں۔',
                          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: _openDataScreen,
                              icon: const Icon(Icons.download_outlined),
                              label: const Text('ڈیٹا کا انتظام'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _verifying ? null : _verifyData,
                              icon: _verifying
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.verified_outlined),
                              label: const Text('فائلیں جانچیں'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _rebuilding ? null : _rebuildIndex,
                              icon: _rebuilding
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.refresh),
                              label: const Text('تلاش فہرست دوبارہ'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 10),
                  JustifiedText(
                    _status!,
                    style: TextStyle(
                      color: _statusError ? Theme.of(context).colorScheme.error : kForest,
                      fontSize: 14,
                    ),
                  ),
                ],
                const SizedBox(height: 26),
                const _SectionTitle('About ShiaVerse — شیعہ ورس کے بارے میں'),
                const JustifiedText(
                  'ShiaVerse محض ایک ایپ نہیں، ایک مکمل ڈیجیٹل دینی لائبریری اور روحانی رفیق ہے: '
                  'قرآنِ کریم اردو ترجمہ و تفسیری حواشی کے ساتھ، مفاتیح الجنان کی دعائیں و اعمال، '
                  'صحیفہ سجادیہ، نہج البلاغہ کے خطبات، خطوط اور حکمت بھرے اقوال، چودہ معتبر کتبِ احادیث، '
                  'فقہی مسائل و فتاویٰ، شیعہ (جعفری) اوقاتِ نماز چھ متحرک آسمانی وال پیپرز کے ساتھ، '
                  'لائیو قبلہ نما، اور تسبیحِ زہرا (س) سمیت مکمل ڈیجیٹل تسبیح۔ '
                  'کتابیں ایک بار انٹرنیٹ سے ڈاؤن لوڈ کرنی پڑتی ہیں (وہ APK میں شامل نہیں)؛ اس کے بعد وہ آپ کے فون میں محفوظ رہتی ہیں اور تلاش بھی مقامی طور پر چلتی ہے۔ '
                  'قبلہ کا نقشہ، مقام کا نام، شہر کی تلاش اور آئی پی سے مقام کا اندازہ انٹرنیٹ استعمال کرتے ہیں۔ خوب صورت تھیمز، واضح اردو و عربی خط، بک مارکس، نوٹس اور '
                  '「جہاں چھوڑا تھا وہیں سے آغاز」 جیسی سہولتیں اسے ہر مؤمن کے لیے روزمرہ کا ساتھی بناتی ہیں۔',
                  style: TextStyle(fontSize: 14, height: 1.8),
                ),
                const SizedBox(height: 26),
                const _SectionTitle('رازداری اور ماخذ'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        key: const ValueKey<String>('settings-privacy-policy'),
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: const JustifiedText(
                          'پرائیویسی پالیسی',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: const JustifiedText(
                          'ایپ کون سا ڈیٹا کہاں رکھتی ہے اور کن سروسز سے رابطہ کرتی ہے',
                          maxLines: 2,
                        ),
                        trailing: const Icon(Icons.open_in_new, size: 20),
                        onTap: () => unawaited(_launch(_privacyPolicyUrl.toString())),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        key: const ValueKey<String>('settings-sources'),
                        leading: const Icon(Icons.menu_book_outlined),
                        title: const JustifiedText(
                          'ماخذ اور حقوق',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: const JustifiedText(
                          'متون، تراجم، فتاویٰ اور نقشے کے ماخذ',
                          maxLines: 2,
                        ),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: _showSources,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        key: const ValueKey<String>('settings-shia-ai'),
                        leading: const Icon(Icons.auto_awesome),
                        title: const JustifiedText(
                          'ShiaAi — ذہین سوال و جواب',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: const JustifiedText(
                          'سوال و جواب کھولیں؛ گیٹ وے کی ترتیب چیٹ کے ترتیبات بٹن سے، کلید صرف سرور پر',
                          maxLines: 2,
                        ),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () => unawaited(
                          Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) =>
                                ShiaAiChatScreen(library: widget.library),
                          )),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                const _SectionTitle('کریڈٹس'),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [Color(0xFF3B2358), Color(0xFF14586B), Color(0xFF8A6A2F)],
                    ),
                    border: Border.all(color: const Color(0xFFC59A50).withValues(alpha: 0.55)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // The studio's own mark, first: the credit card is
                        // about the people and the name behind the app.
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(color: const Color(0x66FFE1A1)),
                              ),
                              child: Image.asset(
                                'assets/images/hashtech.png',
                                width: 104,
                                height: 104,
                                filterQuality: FilterQuality.medium,
                                semanticLabel: 'HashTech',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text('HashTech',
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontFamily: kDigitFont,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 1.1)),
                        const SizedBox(height: 6),
                        const JustifiedText(
                          'جس ادارے کے زیرِ سایہ شیعہ ورس کی تیاری ممکن ہوئی۔ مقصد یہ ہے کہ جدید سافٹ ویئر، سادہ ڈیزائن اور قاری کے وقت و اعتماد کا احترام یکجا ہو کر علم و عقیدت کی خدمت میں آئیں۔',
                          style: TextStyle(fontSize: 13.5, height: 1.7, color: Color(0xFFF3EAD2)),
                        ),
                        const SizedBox(height: 14),
                        // One tap each: the reader can write or call without
                        // copying a number out of the screen by hand.
                        _CreditContactRow(
                          icon: Icons.alternate_email,
                          label: 'ای میل',
                          value: 'sshaashmi@gmail.com',
                          ltr: true,
                          onTap: () => unawaited(_launch('mailto:sshaashmi@gmail.com')),
                        ),
                        const SizedBox(height: 8),
                        _CreditContactRow(
                          icon: Icons.call_outlined,
                          label: 'فون',
                          value: '+923046980280',
                          ltr: true,
                          onTap: () => unawaited(_launch('tel:+923046980280')),
                        ),
                        const Divider(height: 26, color: Color(0x66FFE1A1)),
                        const Text('Syed Sakhir Hashmi',
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFFE1A1))),
                        const SizedBox(height: 2),
                        const Text('سید ساخِر ہاشمی',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFF3EAD2))),
                        const SizedBox(height: 8),
                        const JustifiedText('بانی و مالک • نگرانِ منصوبہ • پروگرامر • محقق • مصنف • شاعر',
                            style: TextStyle(fontSize: 13, height: 1.6, color: Colors.white)),
                        const SizedBox(height: 8),
                        const JustifiedText(
                          'شیعہ ورس کا بنیادی تصور، کتب کی تحقیق و انتخاب، متن کی تدوین اور ہر سطرِ کوڈ و ڈیزائن کا فیصلہ — یہ سب سید ساخِر ہاشمی کی ذاتی کاوش ہے۔ تحریر سے لے کر ترتیب و پیشکش تک ہر مرحلے میں ان ہی کی رہنمائی شامل رہی ہے۔',
                          style: TextStyle(fontSize: 13.5, height: 1.8, color: Color(0xFFF3EAD2)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                JustifiedText(
                  'نصب شدہ کتب: ${installed.map((book) => book.titleUrdu).join('، ')}',
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 26,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF7B4FD0), Color(0xFF0E9AA7), Color(0xFFC59A50)],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: JustifiedText(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: dark ? const Color(0xFFE9D8FF) : const Color(0xFF3B2358),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One way to reach the studio from the credit card: icon, label and the
/// address/number itself, tappable for mail and dial apps.
class _CreditContactRow extends StatelessWidget {
  const _CreditContactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.ltr = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFFFFE1A1)),
              const SizedBox(width: 10),
              Text(label,
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFFF3EAD2))),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
                  textAlign: ltr ? TextAlign.left : TextAlign.right,
                  style: const TextStyle(
                    fontFamily: kDigitFont,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const Icon(Icons.open_in_new, size: 14, color: Color(0x99FFE1A1)),
            ],
          ),
        ),
      ),
    );
  }
}

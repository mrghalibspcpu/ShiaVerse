import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../astro/hijri_calendar.dart';
import '../astro/islamic_events.dart';
import '../astro/lunar_hijri.dart';
import '../astro/prayer_format.dart';
import '../services/prayer_scope.dart';
import '../widgets/glass_panel.dart';
import '../widgets/section_background.dart';

/// The year's days, dated in the reader's own calendar, with a Gregorian →
/// Hijri converter driven by the same local crescent model as the home card.
class IslamicCalendarScreen extends StatelessWidget {
  const IslamicCalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = PrayerScope.of(context);
    final calendar = controller.lunarHijri;
    final today = controller.hijriToday.date;
    // `now` is already the location's wall clock, so this is the civil day the
    // reader is living in, even when the device timezone differs.
    final now = controller.now.value;
    final civilToday = DateTime.utc(now.year, now.month, now.day);
    final adjustment = controller.hijriAdjustment ?? 0;

    final rows = <_OccasionRow>[
      for (final event in kShiaIslamicEvents)
        _OccasionRow(
          event: event,
          civil: _civilFor(calendar, event, today, civilToday, adjustDays: adjustment),
        ),
    ]..sort((a, b) => a.civil.compareTo(b.civil));
    return SectionBackground(
      asset: 'assets/images/wall_calendar.jpg',
      dim: 0.5,
      builder: (context) {
      final palette = GlassPalette.of(context);
      return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        // The wallpaper is always dark, so the status-bar icons are always
        // light, in both app themes.
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: const Text('اسلامی تقویم',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 26),
            children: <Widget>[
              _CalendarHero(today: today, palette: palette),
              const SizedBox(height: 12),
              _GregorianDateConverter(
                calendar: calendar,
                adjustment: adjustment,
                initialDate: civilToday,
                palette: palette,
              ),
              const SizedBox(height: 12),
              GlassPanel(
                radius: 20,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const GlassSectionHeader(title: 'اس سال کے ایام'),
                    const SizedBox(height: 8),
                    Text(
                      '${formatHijriUrdu(today)} — ${controller.location.label}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: palette.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'تاریخیں اسی شہر کے فلکیاتی ہلال کے مطابق ہیں؛ '
                      'مقامی رؤیت اور مرجع کے اعلان سے ایک دن فرق ہو سکتا ہے۔',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, height: 1.55, color: palette.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Calendar3DView(
                rows: rows,
                today: civilToday,
                calendar: calendar,
                adjustment: adjustment,
                palette: palette,
              ),
              const SizedBox(height: 10),
              GlassPanel(
                radius: 20,
                padding: const EdgeInsets.all(13),
                child: Text(
                  'جہاں تاریخی روایات مختلف ہیں وہاں معروف قول اور اختلاف کی وضاحت دی گئی ہے۔ '
                  'روزے اور عبادات کے فقہی حکم کے لیے اپنے مرجعِ تقلید کی رہنمائی دیکھیں۔',
                  style: TextStyle(fontSize: 12.5, height: 1.6, color: palette.muted),
                ),
              ),
            ],
          ),
      );
      },
    );
  }
}

class _CalendarHero extends StatelessWidget {
  const _CalendarHero({required this.today, required this.palette});

  final HijriDate today;
  final GlassPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 142,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        image: const DecorationImage(
          image: AssetImage('assets/images/sky_night.jpg'),
          fit: BoxFit.cover,
        ),
        border: Border.all(color: palette.gold.withValues(alpha: 0.75)),
        boxShadow: <BoxShadow>[
          BoxShadow(color: palette.shadow, blurRadius: 18, offset: const Offset(0, 7)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              colors: <Color>[Color(0xE6122928), Color(0xA611252B), Color(0xE609141B)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: <Widget>[
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.gold.withValues(alpha: 0.13),
                    border: Border.all(color: palette.gold.withValues(alpha: 0.7)),
                  ),
                  child: Icon(Icons.nights_stay_rounded, size: 42, color: palette.gold),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text('اسلامی تاریخ',
                          style: TextStyle(fontSize: 14, color: palette.gold)),
                      const SizedBox(height: 3),
                      Text(
                        formatHijriUrdu(today),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 23,
                          height: 1.35,
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'اہلِ بیت ع کی اہم مناسبتیں اور تاریخ تبدیل کرنے کا آلہ',
                        maxLines: 2,
                        style: TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFFE1E7DC)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact, editable Gregorian → Hijri converter. The date picker is a
/// convenience, while the text field also accepts dates directly as
/// DD/MM/YYYY or YYYY-MM-DD (1900–2100, the validated astronomy range).
class _GregorianDateConverter extends StatefulWidget {
  const _GregorianDateConverter({
    required this.calendar,
    required this.adjustment,
    required this.initialDate,
    required this.palette,
  });

  final LunarHijri calendar;
  final int adjustment;
  final DateTime initialDate;
  final GlassPalette palette;

  @override
  State<_GregorianDateConverter> createState() => _GregorianDateConverterState();
}

class _GregorianDateConverterState extends State<_GregorianDateConverter> {
  late final TextEditingController _input;
  late DateTime _gregorian;
  late HijriDate _hijri;
  String? _error;

  @override
  void initState() {
    super.initState();
    _gregorian = DateTime.utc(widget.initialDate.year, widget.initialDate.month, widget.initialDate.day);
    _hijri = widget.calendar.dateFor(_gregorian, adjustDays: widget.adjustment);
    _input = TextEditingController(text: _dateInput(_gregorian));
  }

  @override
  void didUpdateWidget(_GregorianDateConverter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.calendar != widget.calendar || oldWidget.adjustment != widget.adjustment) {
      _hijri = widget.calendar.dateFor(_gregorian, adjustDays: widget.adjustment);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  String _dateInput(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  DateTime? _parseDate(String text) {
    final value = displayDigits(text.trim());
    final match = RegExp(r'^(\d{1,4})[./-](\d{1,2})[./-](\d{1,4})$').firstMatch(value);
    if (match == null) return null;
    final first = match.group(1)!;
    final second = int.tryParse(match.group(2)!);
    final third = match.group(3)!;
    final yearFirst = first.length == 4;
    final year = int.tryParse(yearFirst ? first : third);
    final month = second;
    final day = int.tryParse(yearFirst ? third : first);
    if (year == null || month == null || day == null || year < 1900 || year > 2100) return null;
    final date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day) return null;
    return date;
  }

  void _convert([DateTime? date]) {
    final parsed = date ?? _parseDate(_input.text);
    if (parsed == null) {
      setState(() => _error = 'تاریخ DD/MM/YYYY یا YYYY-MM-DD میں درج کریں (سال 1900 تا 2100)۔');
      return;
    }
    setState(() {
      _gregorian = DateTime.utc(parsed.year, parsed.month, parsed.day);
      _hijri = widget.calendar.dateFor(_gregorian, adjustDays: widget.adjustment);
      _input.text = _dateInput(_gregorian);
      _error = null;
    });
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _gregorian,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'عیسوی تاریخ منتخب کریں',
    );
    if (selected != null) _convert(selected);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final events = kShiaIslamicEvents
        .where((event) => event.month == _hijri.month && event.day == _hijri.day)
        .toList(growable: false);
    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const GlassSectionHeader(title: 'عیسوی سے ہجری تاریخ'),
          const SizedBox(height: 5),
          Text(
            'کوئی بھی تاریخ لکھیں یا کیلنڈر سے چنیں۔',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: palette.muted),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey<String>('gregorian-date-input'),
            controller: _input,
            keyboardType: TextInputType.datetime,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              labelText: 'عیسوی تاریخ',
              hintText: '18/10/2026',
              suffixIcon: IconButton(
                tooltip: 'کیلنڈر سے تاریخ منتخب کریں',
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month_outlined),
              ),
            ),
            onSubmitted: (_) => _convert(),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 5),
            Text(_error!, style: TextStyle(fontSize: 12.5, color: palette.gold)),
          ],
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _convert(widget.initialDate),
                  icon: const Icon(Icons.today_outlined, size: 18),
                  label: const Text('آج'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _convert,
                  icon: const Icon(Icons.sync_alt, size: 18),
                  label: const Text('تبدیل کریں'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: palette.solid.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  formatDateUrdu(_gregorian),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: palette.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  formatHijriUrdu(_hijri),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 23,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                    color: palette.accent,
                  ),
                ),
                Text(
                  'دن: ${weekdayUrdu(_gregorian)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.ink),
                ),
                const SizedBox(height: 6),
                if (events.isEmpty)
                  Text(
                    'اس تاریخ کے لیے درج شدہ کوئی خاص مناسبت نہیں۔',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, height: 1.4, color: palette.muted),
                  )
                else
                  for (final event in events) ...<Widget>[
                    Text(
                      event.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: palette.gold),
                    ),
                    if (event.note != null)
                      Text(
                        event.note!,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, height: 1.4, color: palette.muted),
                      ),
                  ],
                const SizedBox(height: 5),
                Text(
                  'یہ مقامی فلکیاتی تخمینہ ہے؛ اصل رؤیت، مرجع اور برادری کے اعلان سے تاریخ ایک دن مختلف ہو سکتی ہے۔',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, height: 1.4, color: palette.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The civil day a Hijri occasion falls on: in the year running now, or — once
/// the day has gone by — in the year that follows.
DateTime _civilFor(
  LunarHijri calendar,
  IslamicEvent event,
  HijriDate today,
  DateTime civilToday, {
  int adjustDays = 0,
}) {
  // `dateFor(day, adjustDays: n)` shifts the Hijri day forward by n, so the
  // inverse mapping subtracts n from the civil start.
  DateTime forYear(int year) => calendar
      .civilStartOfMonth(year, event.month)
      .add(Duration(days: event.day - 1 - adjustDays));
  final thisYear = forYear(today.year);
  if (!thisYear.isBefore(civilToday)) return thisYear;
  return forYear(today.year + 1);
}

class _OccasionRow {
  const _OccasionRow({required this.event, required this.civil});

  final IslamicEvent event;
  final DateTime civil;
}

class _Calendar3DView extends StatefulWidget {
  const _Calendar3DView({
    required this.rows,
    required this.today,
    required this.calendar,
    required this.adjustment,
    required this.palette,
  });

  final List<_OccasionRow> rows;
  final DateTime today;
  final LunarHijri calendar;
  final int adjustment;
  final GlassPalette palette;

  @override
  State<_Calendar3DView> createState() => _Calendar3DViewState();
}

class _Calendar3DViewState extends State<_Calendar3DView> {
  static const int _monthCount = 13;
  late final PageController _pageController;
  int _pageIndex = 0;
  late DateTime _selectedDate;

  List<DateTime> get _months {
    final first = DateTime.utc(widget.today.year, widget.today.month);
    return List<DateTime>.generate(
      _monthCount,
      (index) => DateTime.utc(first.year, first.month + index),
    );
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.89);
    _selectedDate = _defaultSelection(_months.first);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool _sameMonth(DateTime first, DateTime second) =>
      first.year == second.year && first.month == second.month;

  DateTime _defaultSelection(DateTime month) {
    for (final row in widget.rows) {
      if (_sameMonth(row.civil, month) && !row.civil.isBefore(widget.today)) return row.civil;
    }
    if (_sameMonth(widget.today, month)) return widget.today;
    return DateTime.utc(month.year, month.month);
  }

  void _onPageChanged(int index) {
    setState(() {
      _pageIndex = index;
      _selectedDate = _defaultSelection(_months[index]);
    });
  }

  void _movePage(int direction) {
    final target = (_pageIndex + direction).clamp(0, _monthCount - 1).toInt();
    if (target != _pageIndex) {
      _pageController.animateToPage(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Map<String, List<_OccasionRow>> _eventsByDay(DateTime month) {
    final result = <String, List<_OccasionRow>>{};
    for (final row in widget.rows) {
      if (_sameMonth(row.civil, month)) {
        (result[_calendarDateKey(row.civil)] ??= <_OccasionRow>[]).add(row);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final months = _months;
    return Column(
      key: const ValueKey<String>('islamic-occasion-calendar'),
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton(
              key: const ValueKey<String>('occasion-calendar-previous'),
              tooltip: 'پچھلا مہینہ',
              onPressed: _pageIndex == 0 ? null : () => _movePage(-1),
              icon: const Icon(Icons.chevron_right_rounded),
              color: palette.accent,
            ),
            Expanded(
              child: Column(
                children: <Widget>[
                  Text(
                    'مناسبات',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: palette.ink),
                  ),
                  Text(
                    'نشان والی تاریخ منتخب کریں یا مہینہ بدلیں',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: palette.muted),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey<String>('occasion-calendar-next'),
              tooltip: 'اگلا مہینہ',
              onPressed: _pageIndex == _monthCount - 1 ? null : () => _movePage(1),
              icon: const Icon(Icons.chevron_left_rounded),
              color: palette.accent,
            ),
          ],
        ),
        SizedBox(
          height: 482,
          child: PageView.builder(
            key: const ValueKey<String>('occasion-calendar-pages'),
            controller: _pageController,
            itemCount: _monthCount,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              final month = months[index];
              final events = _eventsByDay(month);
              final selected = _sameMonth(_selectedDate, month) ? _selectedDate : null;
              return AnimatedBuilder(
                animation: _pageController,
                child: _CalendarMonthPage(
                  month: month,
                  today: widget.today,
                  selectedDate: selected,
                  events: events,
                  calendar: widget.calendar,
                  adjustment: widget.adjustment,
                  palette: palette,
                  onSelectDate: (date) => setState(() => _selectedDate = date),
                ),
                builder: (context, child) {
                  final page = _pageController.hasClients &&
                          _pageController.position.hasContentDimensions
                      ? (_pageController.page ?? _pageIndex.toDouble())
                      : _pageIndex.toDouble();
                  final distance = (index - page).clamp(-1.0, 1.0).toDouble();
                  final transform = Matrix4.identity()
                    ..setEntry(3, 2, 0.0015)
                    ..rotateY(-distance * 0.15)
                    ..scaleByDouble(
                      1.0 - distance.abs() * 0.045,
                      1.0 - distance.abs() * 0.045,
                      1.0 - distance.abs() * 0.045,
                      1.0,
                    );
                  return Transform(
                    alignment: distance < 0 ? Alignment.centerRight : Alignment.centerLeft,
                    transform: transform,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                      child: child,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CalendarMonthPage extends StatelessWidget {
  const _CalendarMonthPage({
    required this.month,
    required this.today,
    required this.selectedDate,
    required this.events,
    required this.calendar,
    required this.adjustment,
    required this.palette,
    required this.onSelectDate,
  });

  final DateTime month;
  final DateTime today;
  final DateTime? selectedDate;
  final Map<String, List<_OccasionRow>> events;
  final LunarHijri calendar;
  final int adjustment;
  final GlassPalette palette;
  final ValueChanged<DateTime> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final monthStart = DateTime.utc(month.year, month.month);
    final firstDayOffset = monthStart.weekday % 7; // Sunday is the rightmost column.
    final hijriMonth = calendar.dateFor(monthStart, adjustDays: adjustment);
    return Semantics(
      label: '${kGregorianMonthsUrdu[month.month - 1]} ${month.year}، ${hijriMonth.monthNameUrdu}',
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 8,
            right: 2,
            top: 9,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF071116).withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  const Color(0xFF293A40),
                  const Color(0xFF15252C),
                ],
              ),
              border: Border.all(color: _calendarPageGold.withValues(alpha: 0.65)),
              boxShadow: <BoxShadow>[
                BoxShadow(color: const Color(0xFF071116).withValues(alpha: 0.78), blurRadius: 16, offset: const Offset(0, 7)),
                BoxShadow(color: Colors.white.withValues(alpha: 0.07), blurRadius: 1, offset: const Offset(0, -1)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(21),
              child: Stack(
                children: <Widget>[
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 18,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            _calendarPageGold.withValues(alpha: 0.35),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 11),
                    child: Column(
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    '${kGregorianMonthsUrdu[month.month - 1]} ${month.year}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                      color: _calendarPageGold,
                                    ),
                                  ),
                                  Text(
                                    'ہجری مہینہ: ${hijriMonth.monthNameUrdu} ${hijriMonth.year}ھ',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11.5, color: _calendarPageMuted),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.calendar_month_rounded, color: Color(0xFFD8BD81), size: 28),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: const <String>[
                            'اتوار', 'پیر', 'منگل', 'بدھ', 'جمعرات', 'جمعہ', 'ہفتہ',
                          ].map((day) => Expanded(
                                child: Text(
                                  day,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFD6DED6),
                                  ),
                                ),
                              )).toList(growable: false),
                        ),
                        const SizedBox(height: 5),
                        Expanded(
                          child: GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            padding: EdgeInsets.zero,
                            itemCount: 42,
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7,
                              mainAxisExtent: 34,
                              mainAxisSpacing: 2,
                              crossAxisSpacing: 2,
                            ),
                            itemBuilder: (context, index) {
                              final date = monthStart.add(Duration(days: index - firstDayOffset));
                              final inMonth = date.month == month.month;
                              final dateEvents = events[_calendarDateKey(date)] ?? const <_OccasionRow>[];
                              final selected = selectedDate != null &&
                                  date.year == selectedDate!.year &&
                                  date.month == selectedDate!.month &&
                                  date.day == selectedDate!.day;
                              final isToday = date.year == today.year &&
                                  date.month == today.month &&
                                  date.day == today.day;
                              return _CalendarDayCell(
                                date: date,
                                inMonth: inMonth,
                                isToday: isToday,
                                selected: selected,
                                eventCount: dateEvents.length,
                                calendar: calendar,
                                adjustment: adjustment,
                                palette: palette,
                                onTap: inMonth ? () => onSelectDate(date) : null,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        _SelectedCalendarDay(
                          date: selectedDate ?? monthStart,
                          events: events[_calendarDateKey(selectedDate ?? monthStart)] ?? const <_OccasionRow>[],
                          calendar: calendar,
                          adjustment: adjustment,
                          palette: palette,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: 12,
                    right: 12,
                    child: IgnorePointer(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List<Widget>.generate(
                          7,
                          (index) => Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: const Color(0xFF24343B),
                              shape: BoxShape.circle,
                              border: Border.all(color: _calendarPageGold.withValues(alpha: 0.7), width: 1.2),
                              boxShadow: <BoxShadow>[
                                BoxShadow(color: palette.shadow.withValues(alpha: 0.8), blurRadius: 2, offset: const Offset(0, 1)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.date,
    required this.inMonth,
    required this.isToday,
    required this.selected,
    required this.eventCount,
    required this.calendar,
    required this.adjustment,
    required this.palette,
    required this.onTap,
  });

  final DateTime date;
  final bool inMonth;
  final bool isToday;
  final bool selected;
  final int eventCount;
  final LunarHijri calendar;
  final int adjustment;
  final GlassPalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hijri = calendar.dateFor(date, adjustDays: adjustment);
    final dateLabel = '${formatDateUrdu(date)}، ${formatHijriUrdu(hijri)}';
    return Opacity(
      opacity: inMonth ? 1 : 0.26,
      child: Semantics(
        button: inMonth,
        label: eventCount > 0 ? '$dateLabel، مناسبت' : dateLabel,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey<String>('occasion-day-${_calendarDateKey(date)}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              decoration: BoxDecoration(
                color: selected
                    ? _calendarPageAccent.withValues(alpha: 0.26)
                    : (eventCount > 0 ? _calendarPageGold.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.035)),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isToday
                      ? _calendarPageAccent
                      : (eventCount > 0 ? _calendarPageGold.withValues(alpha: 0.8) : _calendarPageMuted.withValues(alpha: 0.32)),
                  width: selected || isToday ? 1.4 : 0.7,
                ),
              ),
              child: Stack(
                children: <Widget>[
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '${date.day}',
                          style: TextStyle(
                            fontFamily: kDigitFont,
                            fontSize: 13,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                            color: selected ? _calendarPageAccent : _calendarPageInk,
                          ),
                        ),
                        Text(
                          '${hijri.day}',
                          style: TextStyle(
                            fontFamily: kDigitFont,
                            fontSize: 8.5,
                            height: 1.0,
                            color: _calendarPageMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (eventCount > 0)
                    Positioned(
                      top: 1,
                      left: 2,
                      child: const Icon(Icons.star_rounded, size: 8, color: _calendarPageGold),
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

class _SelectedCalendarDay extends StatelessWidget {
  const _SelectedCalendarDay({
    required this.date,
    required this.events,
    required this.calendar,
    required this.adjustment,
    required this.palette,
  });

  final DateTime date;
  final List<_OccasionRow> events;
  final LunarHijri calendar;
  final int adjustment;
  final GlassPalette palette;

  @override
  Widget build(BuildContext context) {
    final hijri = calendar.dateFor(date, adjustDays: adjustment);
    return Container(
      key: const ValueKey<String>('occasion-selected-date'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF13232A).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _calendarPageMuted.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              events.isEmpty ? Icons.event_note_rounded : Icons.event_available_rounded,
              color: events.isEmpty ? _calendarPageMuted : _calendarPageGold,
              size: 19,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${formatDateUrdu(date)} • ${formatHijriUrdu(hijri)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: _calendarPageMuted),
                ),
                if (events.isEmpty)
                  Text(
                    'اس تاریخ پر کوئی درج شدہ مناسبت نہیں۔',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: _calendarPageMuted),
                  )
                else
                  for (final row in events) ...<Widget>[
                    Text(
                      row.event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _calendarPageGold),
                    ),
                    if (row.event.note != null)
                      Text(
                        row.event.note!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, height: 1.25, color: _calendarPageMuted),
                      ),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _calendarDateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

const Color _calendarPageInk = Color(0xFFF1F4EE);
const Color _calendarPageMuted = Color(0xFFB5C0B9);
const Color _calendarPageGold = Color(0xFFE4BC70);
const Color _calendarPageAccent = Color(0xFF7AC4A2);

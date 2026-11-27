/// The Hijri (lunar) date for the prayer card.
///
/// Inside 1430–1480 AH (2009–2058) the date comes from the Umm al-Qura
/// calendar's published month starts, which is what most printed calendars
/// follow; outside it, from the arithmetical (tabular) calendar. Neither can
/// know the local moon sighting, so the reader can shift the date by up to two
/// days — and South Asia, which usually sights the new moon a day after Makkah,
/// starts one day behind by default.
library;

/// One Hijri date.
class HijriDate {
  const HijriDate(this.year, this.month, this.day);

  final int year;

  /// 1 = Muharram … 12 = Dhu al-Hijjah.
  final int month;
  final int day;

  String get monthNameUrdu => kHijriMonthsUrdu[(month - 1).clamp(0, 11)];

  /// The Hijri date of a Gregorian calendar day (only the date fields of
  /// [date] are read), moved by [adjustDays] for the local moon sighting.
  static HijriDate fromGregorian(DateTime date, {int adjustDays = 0}) {
    final julianDay = julianDayNumber(date.year, date.month, date.day) + adjustDays;
    return fromJulianDay(julianDay);
  }

  /// The Hijri date of a Julian Day Number.
  static HijriDate fromJulianDay(int julianDay) {
    final reduced = julianDay - 2400000;
    if (reduced >= _kUmmAlQuraMonthStarts.first && reduced < _kUmmAlQuraMonthStarts.last) {
      var low = 0;
      var high = _kUmmAlQuraMonthStarts.length - 2;
      while (low < high) {
        final mid = (low + high + 1) >> 1;
        if (_kUmmAlQuraMonthStarts[mid] <= reduced) {
          low = mid;
        } else {
          high = mid - 1;
        }
      }
      final months = low + (_kUmmAlQuraFirstYear - 1) * 12;
      return HijriDate(
        months ~/ 12 + 1,
        months % 12 + 1,
        reduced - _kUmmAlQuraMonthStarts[low] + 1,
      );
    }
    return _tabular(julianDay);
  }

  /// The arithmetical Islamic calendar (Kuwaiti algorithm).
  static HijriDate _tabular(int julianDay) {
    var l = julianDay - 1948440 + 10632;
    final n = (l - 1) ~/ 10631;
    l = l - 10631 * n + 354;
    final j = ((10985 - l) ~/ 5316) * ((50 * l) ~/ 17719) + (l ~/ 5670) * ((43 * l) ~/ 15238);
    l = l - ((30 - j) ~/ 15) * ((17719 * j) ~/ 50) - (j ~/ 16) * ((15238 * j) ~/ 43) + 29;
    final month = (24 * l) ~/ 709;
    final day = l - (709 * month) ~/ 24;
    final year = 30 * n + j - 30;
    return HijriDate(year, month, day);
  }

  /// Julian Day Number of a proleptic Gregorian date.
  static int julianDayNumber(int year, int month, int day) {
    final a = (14 - month) ~/ 12;
    final y = year + 4800 - a;
    final m = month + 12 * a - 3;
    return day + (153 * m + 2) ~/ 5 + 365 * y + y ~/ 4 - y ~/ 100 + y ~/ 400 - 32045;
  }

  /// Proleptic Gregorian UTC date for a Julian Day Number (exact inverse of
  /// [julianDayNumber]).
  static DateTime gregorianFromJulianDay(int julianDay) {
    final a = julianDay + 32044;
    final b = (4 * a + 3) ~/ 146097;
    final c = a - (146097 * b) ~/ 4;
    final d = (4 * c + 3) ~/ 1461;
    final e = c - (1461 * d) ~/ 4;
    final m = (5 * e + 2) ~/ 153;
    final day = e - (153 * m + 2) ~/ 5 + 1;
    final month = m + 3 - 12 * (m ~/ 10);
    final year = 100 * b + d - 4800 + (m ~/ 10);
    return DateTime.utc(year, month, day);
  }

  /// Exact inverse of [fromJulianDay]: returns the Julian Day Number of this
  /// Hijri date in the Umm al-Qura (1430–1480 AH) or tabular calendar.
  int toJulianDay() {
    final mIndex = (year - _kUmmAlQuraFirstYear) * 12 + (month - 1);
    if (mIndex >= 0 && mIndex < _kUmmAlQuraMonthStarts.length - 1) {
      return 2400000 + _kUmmAlQuraMonthStarts[mIndex] + (day - 1);
    }
    var low = (1948440 + ((year - 1) * 12 + (month - 1)) * 29.530588853 + (day - 1) - 45).floor();
    var high = low + 90;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      final d = fromJulianDay(mid);
      final cmp = d.year != year
          ? d.year.compareTo(year)
          : (d.month != month ? d.month.compareTo(month) : d.day.compareTo(day));
      if (cmp < 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  /// Exact inverse of [fromGregorian], accounting for [adjustDays].
  DateTime toGregorian({int adjustDays = 0}) =>
      gregorianFromJulianDay(toJulianDay() - adjustDays);

  @override
  bool operator ==(Object other) =>
      other is HijriDate && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}

/// The month names as they are written in Urdu calendars.
const List<String> kHijriMonthsUrdu = <String>[
  'محرم',
  'صفر',
  'ربیع الاول',
  'ربیع الثانی',
  'جمادی الاول',
  'جمادی الثانی',
  'رجب',
  'شعبان',
  'رمضان',
  'شوال',
  'ذی القعدہ',
  'ذی الحجہ',
];

/// `4 جمادی الاول 1448ھ` — English digits, like the rest of the prayer card.
String formatHijriUrdu(HijriDate date) => '${date.day} ${date.monthNameUrdu} ${date.year}ھ';

/// The default moon-sighting shift for a location: South Asia (Pakistan,
/// India, Bangladesh…) usually begins each month one day after the Umm
/// al-Qura calendar; elsewhere the calendar is used as published.
int autoHijriAdjustment(double latitude, double longitude) {
  final southAsia = latitude >= 5 && latitude <= 38 && longitude >= 60 && longitude <= 98;
  return southAsia ? -1 : 0;
}

/// The day the table starts at: 1 Muharram 1430.
const int _kUmmAlQuraFirstYear = 1430;

/// Umm al-Qura month starts as Reduced Julian Days (JDN − 2400000), one per
/// month from Muharram 1430 to Dhu al-Hijjah 1480, plus the start of 1481 as a
/// sentinel. Source: the Umm al-Qura calendar tables (via `hijri-converter`).
const List<int> _kUmmAlQuraMonthStarts = <int>[
  54830, 54859, 54889, 54919, 54948, 54977, 55007, 55036, 55066, 55095, 55125, 55154,  // 1430
  55184, 55213, 55243, 55273, 55302, 55332, 55361, 55391, 55420, 55450, 55479, 55508,  // 1431
  55538, 55567, 55597, 55627, 55657, 55686, 55716, 55745, 55775, 55804, 55834, 55863,  // 1432
  55892, 55922, 55951, 55981, 56011, 56040, 56070, 56100, 56129, 56159, 56188, 56218,  // 1433
  56247, 56276, 56306, 56335, 56365, 56394, 56424, 56454, 56483, 56513, 56543, 56572,  // 1434
  56601, 56631, 56660, 56690, 56719, 56749, 56778, 56808, 56837, 56867, 56897, 56926,  // 1435
  56956, 56985, 57015, 57044, 57074, 57103, 57133, 57162, 57192, 57221, 57251, 57280,  // 1436
  57310, 57340, 57369, 57399, 57429, 57458, 57487, 57517, 57546, 57576, 57605, 57634,  // 1437
  57664, 57694, 57723, 57753, 57783, 57813, 57842, 57871, 57901, 57930, 57959, 57989,  // 1438
  58018, 58048, 58077, 58107, 58137, 58167, 58196, 58226, 58255, 58285, 58314, 58343,  // 1439
  58373, 58402, 58432, 58461, 58491, 58521, 58551, 58580, 58610, 58639, 58669, 58698,  // 1440
  58727, 58757, 58786, 58816, 58845, 58875, 58905, 58934, 58964, 58994, 59023, 59053,  // 1441
  59082, 59111, 59141, 59170, 59200, 59229, 59259, 59288, 59318, 59348, 59377, 59407,  // 1442
  59436, 59466, 59495, 59525, 59554, 59584, 59613, 59643, 59672, 59702, 59731, 59761,  // 1443
  59791, 59820, 59850, 59879, 59909, 59939, 59968, 59997, 60027, 60056, 60086, 60115,  // 1444
  60145, 60174, 60204, 60234, 60264, 60293, 60323, 60352, 60381, 60411, 60440, 60469,  // 1445
  60499, 60528, 60558, 60588, 60618, 60647, 60677, 60707, 60736, 60765, 60795, 60824,  // 1446
  60853, 60883, 60912, 60942, 60972, 61002, 61031, 61061, 61090, 61120, 61149, 61179,  // 1447
  61208, 61237, 61267, 61296, 61326, 61356, 61385, 61415, 61445, 61474, 61504, 61533,  // 1448
  61563, 61592, 61621, 61651, 61680, 61710, 61739, 61769, 61799, 61828, 61858, 61888,  // 1449
  61917, 61947, 61976, 62006, 62035, 62064, 62094, 62123, 62153, 62182, 62212, 62242,  // 1450
  62271, 62301, 62331, 62360, 62390, 62419, 62448, 62478, 62507, 62537, 62566, 62596,  // 1451
  62625, 62655, 62685, 62715, 62744, 62774, 62803, 62832, 62862, 62891, 62921, 62950,  // 1452
  62980, 63009, 63039, 63069, 63099, 63128, 63157, 63187, 63216, 63246, 63275, 63305,  // 1453
  63334, 63363, 63393, 63423, 63453, 63482, 63512, 63541, 63571, 63600, 63630, 63659,  // 1454
  63689, 63718, 63747, 63777, 63807, 63836, 63866, 63895, 63925, 63955, 63984, 64014,  // 1455
  64043, 64073, 64102, 64131, 64161, 64190, 64220, 64249, 64279, 64309, 64339, 64368,  // 1456
  64398, 64427, 64457, 64486, 64515, 64545, 64574, 64603, 64633, 64663, 64692, 64722,  // 1457
  64752, 64782, 64811, 64841, 64870, 64899, 64929, 64958, 64987, 65017, 65047, 65076,  // 1458
  65106, 65136, 65166, 65195, 65225, 65254, 65283, 65313, 65342, 65371, 65401, 65431,  // 1459
  65460, 65490, 65520, 65549, 65579, 65608, 65638, 65667, 65697, 65726, 65755, 65785,  // 1460
  65815, 65844, 65874, 65903, 65933, 65963, 65992, 66022, 66051, 66081, 66110, 66140,  // 1461
  66169, 66199, 66228, 66258, 66287, 66317, 66346, 66376, 66405, 66435, 66465, 66494,  // 1462
  66524, 66553, 66583, 66612, 66641, 66671, 66700, 66730, 66760, 66789, 66819, 66849,  // 1463
  66878, 66908, 66937, 66967, 66996, 67025, 67055, 67084, 67114, 67143, 67173, 67203,  // 1464
  67233, 67262, 67292, 67321, 67351, 67380, 67409, 67439, 67468, 67497, 67527, 67557,  // 1465
  67587, 67617, 67646, 67676, 67705, 67735, 67764, 67793, 67823, 67852, 67882, 67911,  // 1466
  67941, 67971, 68000, 68030, 68060, 68089, 68119, 68148, 68177, 68207, 68236, 68266,  // 1467
  68295, 68325, 68354, 68384, 68414, 68443, 68473, 68502, 68532, 68561, 68591, 68620,  // 1468
  68650, 68679, 68708, 68738, 68768, 68797, 68827, 68857, 68886, 68916, 68946, 68975,  // 1469
  69004, 69034, 69063, 69092, 69122, 69152, 69181, 69211, 69240, 69270, 69300, 69330,  // 1470
  69359, 69388, 69418, 69447, 69476, 69506, 69535, 69565, 69595, 69624, 69654, 69684,  // 1471
  69713, 69743, 69772, 69802, 69831, 69861, 69890, 69919, 69949, 69978, 70008, 70038,  // 1472
  70067, 70097, 70126, 70156, 70186, 70215, 70245, 70274, 70303, 70333, 70362, 70392,  // 1473
  70421, 70451, 70481, 70510, 70540, 70570, 70599, 70629, 70658, 70687, 70717, 70746,  // 1474
  70776, 70805, 70835, 70864, 70894, 70924, 70954, 70983, 71013, 71042, 71071, 71101,  // 1475
  71130, 71159, 71189, 71218, 71248, 71278, 71308, 71337, 71367, 71397, 71426, 71455,  // 1476
  71485, 71514, 71543, 71573, 71602, 71632, 71662, 71691, 71721, 71751, 71781, 71810,  // 1477
  71839, 71869, 71898, 71927, 71957, 71986, 72016, 72046, 72075, 72105, 72135, 72164,  // 1478
  72194, 72223, 72253, 72282, 72311, 72341, 72370, 72400, 72429, 72459, 72489, 72518,  // 1479
  72548, 72577, 72607, 72637, 72666, 72695, 72725, 72754, 72784, 72813, 72843, 72872,  // 1480
  72902,  // sentinel
];

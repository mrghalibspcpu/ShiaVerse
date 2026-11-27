/// The Moon's own calendar: Hijri dates computed from the crescent itself.
///
/// Until 1.16 the app printed the Umm al-Qura date and leaned on a manual
/// shift (one day back in South Asia) to guess the local one. This file
/// replaces the guess with astronomy:
///
/// * the true new moon (geocentric conjunction) is found where the Moon's and
///   the Sun's apparent ecliptic longitudes meet — Meeus, *Astronomical
///   Algorithms* (2nd ed.), ch. 25 for the Sun and ch. 47 for the Moon, with
///   the full 60-term series (about 10" of longitude, i.e. well under a
///   minute of time);
/// * for every evening after it the crescent is tested at Yallop's best time
///   (sunset + 4/9 of the lag) with Odeh's criterion (2004), which is fitted
///   to 737 observations and works from the reader's own horizon:
///
///       V = ARCV − (−0.1018·W³ + 0.7319·W² − 6.3226·W + 7.1651)
///
///   where ARCV is the topocentric arc of vision in degrees and W the
///   topocentric crescent width in arc minutes. V ≥ 5.65: visible to the
///   naked eye; V ≥ 2: visible with optical aid and probably without it;
///   V ≥ −0.96: optical aid needed; below that: not visible;
/// * the month begins on the day after the first evening the crescent is
///   visible, and no month is shorter than 29 days or longer than 30.
///
/// Nothing here touches the network: the series are on the device, so the
/// date is right on the first run and on every month after it, with no
/// offset for the reader to set.
library;

import 'dart:math' as math;

import 'hijri_calendar.dart';

// ---------------------------------------------------------------------------
// Angles are in degrees, times are Julian Days in Universal Time.
// ---------------------------------------------------------------------------

double _sin(double degrees) => math.sin(degrees * math.pi / 180.0);
double _cos(double degrees) => math.cos(degrees * math.pi / 180.0);
double _tan(double degrees) => math.tan(degrees * math.pi / 180.0);
double _asin(double x) => math.asin(x) * 180.0 / math.pi;
double _acos(double x) => math.acos(x) * 180.0 / math.pi;
double _atan2(double y, double x) => math.atan2(y, x) * 180.0 / math.pi;

/// [degrees] reduced to 0…360 (`%` is Euclidean in Dart, so it stays
/// positive for the negative arguments the series produce).
double _norm360(double degrees) => degrees % 360.0;

/// Terrestrial Time minus UT, in seconds (Espenak & Meeus, 2006). The series
/// below are functions of TT; a phone's clock runs on UTC. The difference is
/// two arc-minutes of lunar motion at most — far below what the visibility
/// criterion can resolve — but it costs nothing to be correct.
double _deltaTSeconds(double year) {
  final t = year - 2000;
  if (year > 2005) return 62.92 + 0.32217 * t + 0.005589 * t * t;
  return 63.86 +
      0.3345 * t -
      0.060374 * t * t +
      0.0017275 * t * t * t +
      0.000651814 * t * t * t * t +
      0.00002373599 * t * t * t * t * t;
}

/// Julian centuries of Terrestrial Time after J2000.0.
double _centuries(double julianDay) {
  final year = 2000.0 + (julianDay - 2451545.0) / 365.25;
  return (julianDay + _deltaTSeconds(year) / 86400.0 - 2451545.0) / 36525.0;
}

// ---------------------------------------------------------------------------
// The Moon — Meeus ch. 47.
// ---------------------------------------------------------------------------

/// Meeus table 47.B: the amplitudes of the periodic terms, in units of
/// 1e-6 degree for the longitude and the latitude and 1e-3 km for the
/// distance. Each row is (D, M, M′, F): the mean elongation, the Sun's mean
/// anomaly, the Moon's mean anomaly and the Moon's argument of latitude.
const List<int> _kMoonLongitudeAmplitudes = <int>[
  6288774, 1274027, 658314, 213618, -185116, -114332,  58793,  57066,  53322,  45758,
  -40923, -34720, -30383,  15327, -12528,  10980,  10675,  10034,   8548,  -7888,
   -6766,  -5163,   4987,   4036,   3994,   3861,   3665,  -2689,  -2602,   2390,
   -2348,   2236,  -2120,  -2069,   2048,  -1773,  -1595,   1215,  -1110,   -892,
    -810,    759,   -713,   -700,    691,    596,    549,    537,    520,   -487,
    -399,   -381,    351,   -340,    330,    327,   -323,    299,    294,      0,
];

const List<int> _kMoonLongitudeArgs = <int>[
       0,      0,      1,      0,      2,      0,     -1,      0,      2,      0,      0,      0,      0,      0,      2,      0,
       0,      1,      0,      0,      0,      0,      0,      2,      2,      0,     -2,      0,      2,     -1,     -1,      0,
       2,      0,      1,      0,      2,     -1,      0,      0,      0,      1,     -1,      0,      1,      0,      0,      0,
       0,      1,      1,      0,      2,      0,      0,     -2,      0,      0,      1,      2,      0,      0,      1,     -2,
       4,      0,     -1,      0,      0,      0,      3,      0,      4,      0,     -2,      0,      2,      1,     -1,      0,
       2,      1,      0,      0,      1,      0,     -1,      0,      1,      1,      0,      0,      2,     -1,      1,      0,
       2,      0,      2,      0,      4,      0,      0,      0,      2,      0,     -3,      0,      0,      1,     -2,      0,
       2,      0,     -1,      2,      2,     -1,     -2,      0,      1,      0,      1,      0,      2,     -2,      0,      0,
       0,      1,      2,      0,      0,      2,      0,      0,      2,     -2,     -1,      0,      2,      0,      1,     -2,
       2,      0,      0,      2,      4,     -1,     -1,      0,      0,      0,      2,      2,      3,      0,     -1,      0,
       2,      1,      1,      0,      4,     -1,     -2,      0,      0,      2,     -1,      0,      2,      2,     -1,      0,
       2,      1,     -2,      0,      2,     -1,      0,     -2,      4,      0,      1,      0,      0,      0,      4,      0,
       4,     -1,      0,      0,      1,      0,     -2,      0,      2,      1,      0,     -2,      0,      0,      2,     -2,
       1,      1,      1,      0,      3,      0,     -2,      0,      4,      0,     -3,      0,      2,     -1,      2,      0,
       0,      2,      1,      0,      1,      1,     -1,      0,      2,      0,      3,      0,      2,      0,     -1,     -2,
];

const List<int> _kMoonDistanceAmplitudes = <int>[
  -20905355, -3699111, -2955968, -569925,  48888,  -3149, 246158, -152138, -170733, -204586,
  -129620, 108743, 104755,  10321,      0,  79661, -34782, -23210, -21636,  24208,
   30824,  -8379, -16675, -12831, -10445, -11650,  14403,  -7003,      0,  10056,
    6322,  -9884,   5751,      0,  -4950,   4130,      0,  -3958,      0,   3258,
    2616,  -1897,  -2117,   2354,      0,      0,  -1423,  -1117,  -1571,  -1739,
       0,  -4421,      0,      0,      0,      0,   1165,      0,      0,   8752,
];

const List<int> _kMoonLatitudeAmplitudes = <int>[
  5128122, 280602, 277693, 173237,  55413,  46271,  32573,  17198,   9266,   8822,
    8216,   4324,   4200,  -3359,   2463,   2211,   2065,  -1870,   1828,  -1794,
   -1749,  -1565,  -1491,  -1475,  -1410,  -1344,  -1335,   1107,   1021,    833,
     777,    671,    607,    596,    491,   -451,    439,    422,    421,   -366,
    -351,    331,    315,    302,   -283,   -229,    223,    223,   -220,   -220,
    -185,    181,   -177,    176,    166,   -164,    132,   -119,    115,    107,
];

const List<int> _kMoonLatitudeArgs = <int>[
       0,      0,      0,      1,      0,      0,      1,      1,      0,      0,      1,     -1,      2,      0,      0,     -1,
       2,      0,     -1,      1,      2,      0,     -1,     -1,      2,      0,      0,      1,      0,      0,      2,      1,
       2,      0,      1,     -1,      0,      0,      2,     -1,      2,     -1,      0,     -1,      2,      0,     -2,     -1,
       2,      0,      1,      1,      2,      1,      0,     -1,      2,     -1,     -1,      1,      2,     -1,      0,      1,
       2,     -1,     -1,     -1,      0,      1,     -1,     -1,      4,      0,     -1,     -1,      0,      1,      0,      1,
       0,      0,      0,      3,      0,      1,     -1,      1,      1,      0,      0,      1,      0,      1,      1,      1,
       0,      1,      1,     -1,      0,      1,      0,     -1,      1,      0,      0,     -1,      0,      0,      3,      1,
       4,      0,      0,     -1,      4,      0,     -1,      1,      0,      0,      1,     -3,      4,      0,     -2,      1,
       2,      0,      0,     -3,      2,      0,      2,     -1,      2,     -1,      1,     -1,      2,      0,     -2,      1,
       0,      0,      3,     -1,      2,      0,      2,      1,      2,      0,     -3,     -1,      2,      1,     -1,      1,
       2,      1,      0,      1,      4,      0,      0,      1,      2,     -1,      1,      1,      2,     -2,      0,     -1,
       0,      0,      1,      3,      2,      1,      1,     -1,      1,      1,      0,     -1,      1,      1,      0,      1,
       0,      1,     -2,     -1,      2,      1,     -1,     -1,      1,      0,      1,      1,      2,     -1,     -2,     -1,
       0,      1,      2,      1,      4,      0,     -2,     -1,      4,     -1,     -1,     -1,      1,      0,      1,     -1,
       4,      0,      1,     -1,      1,      0,     -1,     -1,      4,     -1,      0,     -1,      2,     -2,      0,      1,
];

/// Geocentric ecliptic position of the Moon (equinox of date) and its
/// distance in kilometres.
class _MoonPlace {
  const _MoonPlace(this.longitude, this.latitude, this.distanceKm);

  final double longitude;
  final double latitude;
  final double distanceKm;
}

_MoonPlace _moon(double julianDay) {
  final t = _centuries(julianDay);
  final t2 = t * t;
  final lp = _norm360(218.3164477 +
      481267.88123421 * t -
      0.0015786 * t2 +
      t * t2 / 538841.0 -
      t2 * t2 / 65194000.0);
  final d = _norm360(297.8501921 +
      445267.1114034 * t -
      0.0018819 * t2 +
      t * t2 / 545868.0 -
      t2 * t2 / 113065000.0);
  final m = _norm360(
      357.5291092 + 35999.0502909 * t - 0.0001536 * t2 + t * t2 / 24490000.0);
  final mm = _norm360(134.9633964 +
      477198.8675055 * t +
      0.0087414 * t2 +
      t * t2 / 69699.0 -
      t2 * t2 / 14712000.0);
  final f = _norm360(93.2720950 +
      483202.0175233 * t -
      0.0036539 * t2 -
      t * t2 / 3526000.0 +
      t2 * t2 / 863310000.0);
  final a1 = _norm360(119.75 + 131.849 * t);
  final a2 = _norm360(53.09 + 479264.290 * t);
  final a3 = _norm360(313.45 + 481266.484 * t);
  final e = 1 - 0.002516 * t - 0.0000047 * t2;

  var sumLongitude = 0.0;
  var sumDistance = 0.0;
  var sumLatitude = 0.0;
  for (var i = 0; i < 60; i++) {
    final row = i * 4;
    final argument = _kMoonLongitudeArgs[row] * d +
        _kMoonLongitudeArgs[row + 1] * m +
        _kMoonLongitudeArgs[row + 2] * mm +
        _kMoonLongitudeArgs[row + 3] * f;
    final eccentric = switch (_kMoonLongitudeArgs[row + 1].abs()) {
      1 => e,
      2 => e * e,
      _ => 1.0,
    };
    sumLongitude += _kMoonLongitudeAmplitudes[i] * _sin(argument) * eccentric;
    sumDistance += _kMoonDistanceAmplitudes[i] * _cos(argument) * eccentric;

    final latRow = i * 4;
    final latArgument = _kMoonLatitudeArgs[latRow] * d +
        _kMoonLatitudeArgs[latRow + 1] * m +
        _kMoonLatitudeArgs[latRow + 2] * mm +
        _kMoonLatitudeArgs[latRow + 3] * f;
    final latEccentric = switch (_kMoonLatitudeArgs[latRow + 1].abs()) {
      1 => e,
      2 => e * e,
      _ => 1.0,
    };
    sumLatitude += _kMoonLatitudeAmplitudes[i] * _sin(latArgument) * latEccentric;
  }

  sumLongitude +=
      3958 * _sin(a1) + 1962 * _sin(lp - f) + 318 * _sin(a2);
  sumLatitude += -2235 * _sin(lp) +
      382 * _sin(a3) +
      175 * _sin(a1 - f) +
      175 * _sin(a1 + f) +
      127 * _sin(lp - mm) -
      115 * _sin(lp + mm);

  var longitude = lp + sumLongitude / 1e6;
  final omega = _norm360(125.0445 - 1934.1363 * t);
  longitude = _norm360(longitude - 0.004778 * _sin(omega));
  return _MoonPlace(longitude, sumLatitude / 1e6, 385000.56 + sumDistance / 1000.0);
}

/// The true obliquity of the ecliptic (mean value plus the principal nutation
/// term), Meeus ch. 22 and 25.
double _obliquity(double julianDay) {
  final t = _centuries(julianDay);
  final omega = _norm360(125.0445 - 1934.1363 * t);
  return 23.439291 - 0.0130042 * t - 0.000000164 * t * t + 0.000000504 * t * t * t + 0.002556 * _cos(omega);
}

// ---------------------------------------------------------------------------
// The Sun — Meeus ch. 25.
// ---------------------------------------------------------------------------

/// Geocentric apparent ecliptic longitude of the Sun (equinox of date) and its
/// distance in astronomical units.
class _SunPlace {
  const _SunPlace(this.longitude, this.distanceAu);

  final double longitude;
  final double distanceAu;
}

_SunPlace _sun(double julianDay) {
  final t = _centuries(julianDay);
  final meanLongitude = _norm360(280.46646 + 36000.76983 * t + 0.0003032 * t * t);
  final meanAnomaly = _norm360(357.52911 + 35999.05029 * t - 0.0001537 * t * t);
  final equationOfCentre = (1.914602 - 0.004817 * t - 0.000014 * t * t) * _sin(meanAnomaly) +
      (0.019993 - 0.000101 * t) * _sin(2 * meanAnomaly) +
      0.000289 * _sin(3 * meanAnomaly);
  final omega = _norm360(125.04 - 1934.136 * t);
  final longitude = _norm360(meanLongitude + equationOfCentre - 0.00569 - 0.00478 * _sin(omega));
  const eccentricity = 0.016708634;
  final distance = 1.000001018 *
      (1 - eccentricity * eccentricity) /
      (1 + eccentricity * _cos(meanAnomaly + equationOfCentre));
  return _SunPlace(longitude, distance);
}

// ---------------------------------------------------------------------------
// Frames: ecliptic → equatorial → the reader's horizon.
// ---------------------------------------------------------------------------

class _Equatorial {
  const _Equatorial(this.rightAscension, this.declination);

  final double rightAscension;
  final double declination;
}

_Equatorial _eclipticToEquatorial(double longitude, double latitude, double obliquity) {
  return _Equatorial(
    _norm360(_atan2(
        _sin(longitude) * _cos(obliquity) - _tan(latitude) * _sin(obliquity), _cos(longitude))),
    _asin(_sin(latitude) * _cos(obliquity) + _cos(latitude) * _sin(obliquity) * _sin(longitude)),
  );
}

/// Greenwich mean sidereal time in degrees, Meeus ch. 12.
double _gmst(double julianDay) {
  final t = (julianDay - 2451545.0) / 36525.0;
  final t2 = t * t;
  return _norm360(280.46061837 +
      360.98564736629 * (julianDay - 2451545.0) +
      0.000387933 * t2 -
      t * t2 / 38710000.0);
}

class _Horizontal {
  const _Horizontal(this.altitude, this.azimuth);

  /// Degrees above the horizon, refraction and parallax aside.
  final double altitude;

  /// Degrees, measured from north through east.
  final double azimuth;
}

_Horizontal _toHorizontal(_Equatorial place, double latitude, double longitude, double julianDay) {
  final hourAngle = _norm360(_gmst(julianDay) + longitude - place.rightAscension);
  final altitude = _asin(_sin(latitude) * _sin(place.declination) +
      _cos(latitude) * _cos(place.declination) * _cos(hourAngle));
  final azimuth = _norm360(_atan2(
          _sin(hourAngle),
          _cos(hourAngle) * _sin(latitude) - _tan(place.declination) * _cos(latitude)) +
      180.0);
  return _Horizontal(altitude, azimuth);
}

/// The Moon as the reader sees it: parallax lifts it out of the geocentric
/// place, and the topocentric semi-diameter (Odeh's W is measured in it)
/// comes out of the same distance.
class _Topocentric {
  const _Topocentric(this.altitude, this.azimuth, this.semiDiameterArcMinutes, this.distanceKm);

  final double altitude;
  final double azimuth;
  final double semiDiameterArcMinutes;
  final double distanceKm;
}

const double _kEarthRadiusKm = 6378.14;

_Topocentric _topocentricMoon(
    _MoonPlace place, double latitude, double longitude, double julianDay) {
  final obliquity = _obliquity(julianDay);
  final geocentric = _eclipticToEquatorial(place.longitude, place.latitude, obliquity);
  // Both vectors are equatorial, of date, in kilometres: the Moon's geocentric
  // place and the reader's own. A spherical Earth is enough — the flattening
  // moves the parallax by three thousandths of a degree.
  final x = place.distanceKm * _cos(geocentric.declination) * _cos(geocentric.rightAscension) -
      _kEarthRadiusKm * _cos(latitude) * _cos(_gmst(julianDay) + longitude);
  final y = place.distanceKm * _cos(geocentric.declination) * _sin(geocentric.rightAscension) -
      _kEarthRadiusKm * _cos(latitude) * _sin(_gmst(julianDay) + longitude);
  final z = place.distanceKm * _sin(geocentric.declination) - _kEarthRadiusKm * _sin(latitude);
  final distance = math.sqrt(x * x + y * y + z * z);
  final seen = _Equatorial(_norm360(_atan2(y, x)), _asin(z / distance));
  final horizontal = _toHorizontal(seen, latitude, longitude, julianDay);
  final parallax = _asin(_kEarthRadiusKm / distance);
  return _Topocentric(
      horizontal.altitude, horizontal.azimuth, 0.27245 * parallax * 60.0, distance);
}

/// Where one body stands over the reader's horizon at [julianDay].
class _BodyState {
  const _BodyState(this.altitude, this.azimuth, this.rightAscension, this.declination, this.parallax);

  final double altitude;
  final double azimuth;
  final double rightAscension;
  final double declination;
  final double parallax;
}

_BodyState _bodyAt(double julianDay, double latitude, double longitude, {required bool moon}) {
  final obliquity = _obliquity(julianDay);
  if (moon) {
    final place = _moon(julianDay);
    final geocentric = _eclipticToEquatorial(place.longitude, place.latitude, obliquity);
    final seen = _topocentricMoon(place, latitude, longitude, julianDay);
    return _BodyState(seen.altitude, seen.azimuth, geocentric.rightAscension, geocentric.declination,
        _asin(_kEarthRadiusKm / place.distanceKm));
  }
  final place = _sun(julianDay);
  final geocentric = _eclipticToEquatorial(place.longitude, 0.0, obliquity);
  final horizontal = _toHorizontal(geocentric, latitude, longitude, julianDay);
  return _BodyState(
      horizontal.altitude, horizontal.azimuth, geocentric.rightAscension, geocentric.declination, 0.0);
}

// ---------------------------------------------------------------------------
// Rising and setting — Meeus ch. 15, refined by bisection.
// ---------------------------------------------------------------------------

/// The standard altitude of the centre at the moment of setting: −0.8333° for
/// the Sun (semi-diameter and refraction at the horizon), and for the Moon the
/// parallax of the hour (Meeus ch. 15).
double _settingAltitude(_BodyState body, {required bool moon}) =>
    moon ? 0.7275 * body.parallax - 0.5667 : -0.8333;

/// The Julian Day the body sets on the day that begins at [midnight], or null
/// where it never reaches the horizon (the polar summer and winter).
double? _setting(double midnight, double latitude, double longitude, {required bool moon}) {
  var time = midnight + (18.0 - longitude / 15.0) / 24.0;
  var goal = _settingAltitude(_bodyAt(time, latitude, longitude, moon: moon), moon: moon);
  for (var step = 0; step < 4; step++) {
    final body = _bodyAt(time, latitude, longitude, moon: moon);
    goal = _settingAltitude(body, moon: moon);
    final cosine = (_sin(goal) - _sin(latitude) * _sin(body.declination)) /
        (_cos(latitude) * _cos(body.declination));
    if (cosine > 1.0 || cosine < -1.0) return null;
    time = midnight +
        _norm360(body.rightAscension + _acos(cosine) - longitude - _gmst(midnight)) /
            360.98564736629;
  }
  final body = _bodyAt(time, latitude, longitude, moon: moon);
  goal = _settingAltitude(body, moon: moon);
  var low = time - 0.05;
  var high = time + 0.05;
  var flow = _bodyAt(low, latitude, longitude, moon: moon).altitude - goal;
  var fhigh = _bodyAt(high, latitude, longitude, moon: moon).altitude - goal;
  if (flow < 0 || fhigh > 0) {
    low = time - 0.2;
    high = time + 0.2;
    flow = _bodyAt(low, latitude, longitude, moon: moon).altitude - goal;
    fhigh = _bodyAt(high, latitude, longitude, moon: moon).altitude - goal;
    if (flow < 0 || fhigh > 0) return time;
  }
  // Forty halvings of an 84-minute window land inside a ten-thousandth of a
  // second: the criterion cannot use more.
  for (var step = 0; step < 40; step++) {
    final middle = (low + high) / 2;
    final fmiddle = _bodyAt(middle, latitude, longitude, moon: moon).altitude - goal;
    if ((flow >= 0) == (fmiddle >= 0)) {
      low = middle;
      flow = fmiddle;
    } else {
      high = middle;
    }
  }
  return (low + high) / 2;
}

// ---------------------------------------------------------------------------
// The crescent.
// ---------------------------------------------------------------------------

/// Odeh's zones for the visibility of the young crescent.
const double kCrescentNakedEye = 5.65;
const double kCrescentLikely = 2.0;
const double kCrescentOpticalAid = -0.96;

/// One evening's new moon, measured the way the sighting committees measure
/// it, for one place.
class CrescentObservation {
  const CrescentObservation({
    required this.sunset,
    required this.moonset,
    required this.bestTime,
    required this.lagMinutes,
    required this.arcOfLight,
    required this.arcOfVision,
    required this.relativeAzimuth,
    required this.crescentWidth,
    required this.visibility,
    required this.moonAltitude,
    required this.sunAltitude,
  });

  /// When the Sun goes down (the centre at −0.8333°).
  final DateTime sunset;

  /// When the Moon follows it.
  final DateTime moonset;

  /// Yallop's best time: sunset plus four ninths of the lag.
  final DateTime bestTime;

  /// Minutes between sunset and moonset.
  final double lagMinutes;

  /// The Moon's altitude, topocentric and airless, at the best time.
  final double moonAltitude;

  /// The Sun's altitude at the best time (negative: it is below the horizon).
  final double sunAltitude;

  /// ARCL — the angular separation of the two centres, in degrees.
  final double arcOfLight;

  /// ARCV — the difference of their altitudes, in degrees.
  final double arcOfVision;

  /// DAZ — the difference of their azimuths, in degrees.
  final double relativeAzimuth;

  /// W — the width of the lit crescent, in arc minutes.
  final double crescentWidth;

  /// V — Odeh's visibility number.
  final double visibility;

  /// Easily visible, with the unaided eye, to anyone who looks.
  bool get visibleToTheEye => visibility >= kCrescentNakedEye;

  /// Visible with optical aid, and probably without it under a good sky.
  bool get probablyVisible => visibility >= kCrescentLikely;

  /// Reachable with a telescope or binoculars, not with the eye alone.
  bool get visibleWithAid => visibility >= kCrescentOpticalAid;

  /// One word for the footer of the calendar: what the sky will do.
  String verdictUrdu() => visibleToTheEye
      ? 'ننگی آنکھ سے دکھائی دے گا'
      : (probablyVisible
          ? 'اچھے موسم میں نظر آنے کی توقع'
          : (visibleWithAid
              ? 'صرف دوربین سے ممکن'
              : 'نظر نہیں آئے گا'));
}

/// Measures the crescent on the evening of the civil day that begins at
/// [midnight] (a Julian Day at 00:00 UT), or returns null where the Sun does
/// not set at all.
CrescentObservation? observeEvening(double midnight, double latitude, double longitude) {
  final sunset = _setting(midnight, latitude, longitude, moon: false);
  if (sunset == null) return null;
  var moonset = _setting(midnight, latitude, longitude, moon: true);
  if (moonset == null) return null;
  // A Moon that is already down when the Sun goes: the sighting belongs to the
  // following evening, when the same Moon sets after the Sun again.
  if (moonset < sunset) {
    final following = _setting(midnight + 1, latitude, longitude, moon: true);
    if (following == null) return null;
    moonset = following;
  }
  final bestTime = sunset + (4.0 / 9.0) * (moonset - sunset);
  final moon = _bodyAt(bestTime, latitude, longitude, moon: true);
  final sun = _bodyAt(bestTime, latitude, longitude, moon: false);
  final separation = math.acos(
    (_sin(moon.altitude) * _sin(sun.altitude) +
            _cos(moon.altitude) * _cos(sun.altitude) * _cos(moon.azimuth - sun.azimuth))
        .clamp(-1.0, 1.0),
  );
  final arcOfLight = separation * 180.0 / math.pi;
  final arcOfVision = moon.altitude - sun.altitude;
  final relativeAzimuth = (_norm360(moon.azimuth - sun.azimuth + 180.0) - 180.0).abs();
  final place = _moon(bestTime);
  final width = _topocentricMoon(place, latitude, longitude, bestTime).semiDiameterArcMinutes *
      (1.0 - _cos(arcOfLight));
  final visibility = arcOfVision -
      (-0.1018 * width * width * width +
          0.7319 * width * width -
          6.3226 * width +
          7.1651);
  return CrescentObservation(
    sunset: _dateTimeFromJulianDay(sunset),
    moonset: _dateTimeFromJulianDay(moonset),
    bestTime: _dateTimeFromJulianDay(bestTime),
    lagMinutes: (moonset - sunset) * 24.0 * 60.0,
    moonAltitude: moon.altitude,
    sunAltitude: sun.altitude,
    arcOfLight: arcOfLight,
    arcOfVision: arcOfVision,
    relativeAzimuth: relativeAzimuth,
    crescentWidth: width,
    visibility: visibility,
  );
}

// ---------------------------------------------------------------------------
// The new moon.
// ---------------------------------------------------------------------------

/// The Moon's elongation from the Sun, signed and reduced to ±180.
double _elongation(double julianDay) =>
    _norm360(_moon(julianDay).longitude - _sun(julianDay).longitude + 180.0) - 180.0;

/// The Julian Day of the [lunation]-th new moon, counted the way Meeus counts
/// them (lunation 0 fell on 6 January 2000). Found by bisection on the
/// elongation, which crosses zero only at conjunction — so it needs no
/// separate series and stays consistent with the positions above.
double _newMoon(double lunation) {
  final mean = 2451550.09765 + 29.530588853 * lunation;
  var low = mean - 1.6;
  var high = mean + 1.6;
  var flow = _elongation(low);
  for (var step = 0; step < 50; step++) {
    final middle = (low + high) / 2;
    final fmiddle = _elongation(middle);
    if ((flow >= 0) == (fmiddle >= 0)) {
      low = middle;
      flow = fmiddle;
    } else {
      high = middle;
    }
  }
  return (low + high) / 2;
}

// ---------------------------------------------------------------------------
// Civil dates and Julian Days.
// ---------------------------------------------------------------------------

/// The Julian Day Number of a civil date: an integer, as
/// [HijriDate.julianDayNumber] and the Umm al-Qura table count days.
int _julianDayNumber(DateTime date) =>
    HijriDate.julianDayNumber(date.year, date.month, date.day);

/// The Julian Day at 00:00 UT of a civil date.
double _midnightOf(DateTime date) => _julianDayNumber(date).toDouble() - 0.5;

DateTime _dateFromJulianDayNumber(int julianDayNumber) {
  final a = julianDayNumber + 32044;
  final b = (4 * a + 3) ~/ 146097;
  final c = a - (146097 * b) ~/ 4;
  final d = (4 * c + 3) ~/ 1461;
  final e = c - (1461 * d) ~/ 4;
  final m = (5 * e + 2) ~/ 153;
  final day = e - (153 * m + 2) ~/ 5 + 1;
  final month = m + 3 - 12 * (m ~/ 10);
  final year = 100 * b + d - 4800 + m ~/ 10;
  return DateTime.utc(year, month, day);
}

/// The civil date of a Julian Day that stands at 00:00 UT.
DateTime _civilDateOf(double midnight) => _dateFromJulianDayNumber((midnight + 0.5).round());

DateTime _dateTimeFromJulianDay(double julianDay) {
  const microsecondsPerDay = 86400.0 * 1000000.0;
  final shifted = julianDay + 0.5;
  final day = shifted.floor();
  final fraction = shifted - day;
  return _dateFromJulianDayNumber(day)
      .add(Duration(microseconds: (fraction * microsecondsPerDay).round()));
}

// ---------------------------------------------------------------------------
// The Hijri month, and the calendar built on it.
// ---------------------------------------------------------------------------

/// The Hijri calendar of one place.
///
/// Every day of the month (and every month the calendar screen shows) is
/// derived from the same three cached tables, so opening the calendar or
/// moving a month costs one crescent, not a new calculation of the year.
class LunarHijri {
  LunarHijri({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  /// Lunation number → the Julian Day (00:00 UT) of the month's first day.
  final Map<int, double> _monthStarts = <int, double>{};

  /// The last day asked for, so the prayer card — which asks every second —
  /// never runs the series twice for the same day.
  int? _cachedDay;
  HijriDate? _cachedDate;

  /// The Hijri date of a civil date. Only the year, month and day are read,
  /// so the reader's own wall clock (or a UTC-coded one) both work.
  HijriDate dateFor(DateTime civilDate, {int adjustDays = 0}) {
    if (adjustDays == 0 && _cachedDay != null) {
      final key = _julianDayNumber(civilDate);
      if (key == _cachedDay) return _cachedDate!;
    }
    final midnight = _midnightOf(civilDate) + adjustDays;
    // The mean lunation of the day, and the three months around it: the
    // crescent the day belongs to was either this month's or the one before.
    final lunation = ((midnight + 0.5 - 2451550.09765) / 29.530588853).round();
    _fillMonths(lunation - 3, lunation + 2);
    var start = _monthStarts[lunation - 3]!;
    for (var k = lunation - 3; k <= lunation + 2; k++) {
      final candidate = _monthStarts[k]!;
      if (midnight >= candidate && candidate > start) start = candidate;
    }
    final day = (midnight - start).round() + 1;
    final month = _monthOf(start);
    final date = HijriDate(month.$1, month.$2, day);
    if (adjustDays == 0) {
      _cachedDay = _julianDayNumber(civilDate);
      _cachedDate = date;
    }
    return date;
  }

  /// The civil date (00:00 UT) of the first day of a Hijri month.
  DateTime civilStartOfMonth(int hijriYear, int hijriMonth) =>
      _civilDateOf(_monthStartOfMonth(hijriYear, hijriMonth));

  /// How many days the Hijri month has: 29 or 30.
  int lengthOfMonth(int hijriYear, int hijriMonth) {
    final start = _monthStartOfMonth(hijriYear, hijriMonth);
    final next = hijriMonth >= 12
        ? _monthStartOfMonth(hijriYear + 1, 1)
        : _monthStartOfMonth(hijriYear, hijriMonth + 1);
    return (next - start).round();
  }

  /// Exact inverse of [dateFor]: returns the UTC civil date on which [hijri]
  /// occurs for this location and [adjustDays], or `null` if `hijri.day`
  /// exceeds that lunar month's actual length (e.g. 30th of a 29-day month).
  DateTime? civilDateFor(HijriDate hijri, {int adjustDays = 0}) {
    if (hijri.month < 1 || hijri.month > 12 || hijri.day < 1 || hijri.day > 30) {
      return null;
    }
    final monthLen = lengthOfMonth(hijri.year, hijri.month);
    if (hijri.day > monthLen) return null;
    final start = civilStartOfMonth(hijri.year, hijri.month);
    final candidate = DateTime.utc(
      start.year,
      start.month,
      start.day + hijri.day - 1 - adjustDays,
    );
    // Verify exact round-trip; if an adjacent lunation cache boundary shifted
    // by 1 day, step onto the exact matching civil date.
    if (dateFor(candidate, adjustDays: adjustDays) == hijri) {
      return candidate;
    }
    for (final delta in const <int>[-1, 1, -2, 2]) {
      final alt = DateTime.utc(candidate.year, candidate.month, candidate.day + delta);
      if (dateFor(alt, adjustDays: adjustDays) == hijri) return alt;
    }
    return candidate;
  }

  /// The evening that opened a month: what the crescent did, and when.
  CrescentObservation? sightingOfMonth(int hijriYear, int hijriMonth) {
    final start = _monthStartOfMonth(hijriYear, hijriMonth);
    return observeEvening(start - 1, latitude, longitude);
  }

  /// The conjunction that opens a month, for the calendar's footnote.
  DateTime conjunctionOfMonth(int hijriYear, int hijriMonth) =>
      _dateTimeFromJulianDay(
          _newMoon(_lunationOf(_monthStartOfMonth(hijriYear, hijriMonth)).toDouble()));

  /// The crescent on the evening of any civil date.
  CrescentObservation? observationFor(DateTime civilDate) =>
      observeEvening(_midnightOf(civilDate), latitude, longitude);

  // -- internals -----------------------------------------------------------

  /// The first civil day of lunation [lunation] (a Julian Day at 00:00 UT).
  double _monthStart(int lunation) {
    _fillMonths(lunation - 1, lunation);
    return _monthStarts[lunation]!;
  }

  /// Fills the table from [from] to [to] in order, so that the month before
  /// each one is already known: the 29/30-day rule below needs it. A month
  /// whose predecessor is not in the table keeps its own answer — in the
  /// ordinary case (reading one day, or walking the calendar a month at a
  /// time) the chain is never broken.
  void _fillMonths(int from, int to) {
    for (var lunation = from; lunation <= to; lunation++) {
      if (_monthStarts.containsKey(lunation)) continue;
      var day = _visibleDay(lunation);
      final previous = _monthStarts[lunation - 1];
      // A lunar month is 29 or 30 days: never shorter, never longer. The
      // crescent alone can overrun both at high latitudes, where the Sun
      // barely sets.
      if (previous != null) {
        day = math.min(math.max(day, previous + 29), previous + 30);
      }
      _monthStarts[lunation] = day;
    }
  }

  /// The day after the first evening the crescent is visible to lunation
  /// [lunation]. An evening that has no sunset at all is skipped; if no
  /// evening reaches the crescent, the first one tried is used, and the
  /// 29/30-day rule above settles the length.
  double _visibleDay(int lunation) {
    final conjunction = _newMoon(lunation.toDouble());
    // The evening is the reader's, not Greenwich's: the conjunction may fall
    // on the far side of midnight for them.
    final evening = (conjunction + longitude / 360.0 - 0.5).floor() + 0.5;
    var day = evening + 1;
    var tried = false;
    for (var attempt = 0; attempt < 4; attempt++) {
      final observation = observeEvening(evening + attempt, latitude, longitude);
      if (observation == null) continue;
      if (!tried) {
        day = evening + attempt + 1;
        tried = true;
      }
      if (observation.probablyVisible) {
        day = evening + attempt + 1;
        break;
      }
    }
    return day;
  }

  /// The lunation whose crescent opens the month, found from the reference
  /// calendar: it is the one whose mean start falls nearest.
  int _lunationOf(double monthStart) =>
      ((monthStart + 0.5 - 2451550.09765) / 29.530588853).round();

  /// The Julian Day (00:00 UT) of the first day of a named Hijri month.
  ///
  /// The reference calendar (Umm al-Qura) supplies the name of the month; the
  /// astronomy supplies its first day. Asking the reference for the day in the
  /// middle of the month means a day's difference can never change the name.
  double _monthStartOfMonth(int hijriYear, int hijriMonth) {
    final estimate = 2454830.0 + ((hijriYear - 1430) * 12 + (hijriMonth - 1)) * 29.530588853;
    final reference = _referenceMonthStart(hijriYear, hijriMonth, estimate);
    var lunation = ((reference + 0.5 - 2451550.09765) / 29.530588853).round();
    _fillMonths(lunation - 2, lunation + 2);
    for (var step = 0; step < 3; step++) {
      final start = _monthStart(lunation);
      final month = _monthOf(start);
      if (month.$1 == hijriYear && month.$2 == hijriMonth) return start;
      final order = (month.$1 * 12 + month.$2) - (hijriYear * 12 + hijriMonth);
      lunation += order < 0 ? 1 : -1;
    }
    return _monthStart(lunation);
  }

  /// The Umm al-Qura / arithmetical first day of a Hijri month, by bisection
  /// on the reference calendar (which rises monotonically with the days).
  double _referenceMonthStart(int hijriYear, int hijriMonth, double estimate) {
    var low = (estimate - 40).round();
    var high = (estimate + 40).round();
    for (var step = 0; step < 20 && low < high; step++) {
      final middle = (low + high) ~/ 2;
      final date = HijriDate.fromJulianDay(middle);
      final order = (date.year * 12 + date.month) - (hijriYear * 12 + hijriMonth);
      if (order < 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low - 0.5;
  }

  /// The (year, month) of a month that begins at [start], named from the
  /// middle of the month where the difference cannot matter.
  (int, int) _monthOf(double start) {
    final middle = _dateFromJulianDayNumber((start + 14.5).round());
    final reference = HijriDate.fromGregorian(middle);
    return (reference.year, reference.month);
  }
}

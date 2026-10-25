import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/more_features.dart';
import '../widgets/reading_hub.dart';

/// The Xplore dashboard, filling the screen below the status bar.
///
/// The page is the camera-lens plate of the reference artwork, in portrait:
/// five amber lenses (all one size) on a brushed-metal body, and three red
/// plates (also all one size) cut into
/// the edges of that body — the brand wedge in the top-right corner, the
/// pointing wedge on the left edge, and the corner wedge in the bottom-right
/// that carries the radial-menu button. Lens one sits top-left, lens two
/// steps down towards the middle, three reaches the right edge, four comes
/// back to the centre, five closes at the bottom-left — the same diagonal
/// climb as the artwork, so the controls read as a machine and not as a grid.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    super.key,
    required this.features,
    required this.onAction,
    required this.onHubVisibilityChanged,
    required this.routeObserver,
  });

  final List<MoreFeature> features;
  final ValueChanged<HubDestination> onAction;
  final ValueChanged<bool> onHubVisibilityChanged;
  final RouteObserver<PageRoute<dynamic>> routeObserver;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> with RouteAware {
  bool _menuOpen = false;
  PageRoute<dynamic>? _subscribedRoute;

  MoreFeature? _feature(String title) {
    for (final feature in widget.features) {
      if (feature.title == title) return feature;
    }
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && route != _subscribedRoute) {
      if (_subscribedRoute != null) widget.routeObserver.unsubscribe(this);
      _subscribedRoute = route;
      widget.routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPush() => widget.onHubVisibilityChanged(true);

  @override
  void didPopNext() => widget.onHubVisibilityChanged(true);

  @override
  void didPushNext() => widget.onHubVisibilityChanged(false);

  @override
  void didPop() => widget.onHubVisibilityChanged(false);

  @override
  void dispose() {
    widget.routeObserver.unsubscribe(this);
    widget.onHubVisibilityChanged(false);
    super.dispose();
  }

  void _toggleMenu() => setState(() => _menuOpen = !_menuOpen);

  void _selectDestination(HubDestination destination) {
    setState(() => _menuOpen = false);
    widget.onAction(destination);
  }

  @override
  Widget build(BuildContext context) {
    final tasbeeh = _feature('تسبیح و ذکر');
    final prayer = _feature('نماز کے اوقات');
    final crescent = _feature('چاند کی رویت');
    final calendar = _feature('اسلامی تقویم');
    final extra = _feature('Xplore Xtra');
    final encyclopedia = _feature('اثنا عشری انسائکلوپیڈیا');

    // The whole plate sits BELOW the status bar (and above the navigation
    // bar): readers asked for the clock and the signal icons to stay visible
    // instead of the machine running edge to edge under them. The scaffold's
    // dark background fills the strip the bars leave, and the overlay style
    // paints the status icons light so they read against it.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
      backgroundColor: const Color(0xFF0B1218),
      body: SafeArea(
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final padding = MediaQuery.paddingOf(context);
        // Inside the SafeArea the remaining padding is whatever the safe
        // area did not consume (normally zero), so the plates are flush with
        // the safe box: the left wedge's base is its left edge and its
        // midpoint is the box's vertical centre; all three red plates share
        // one size and sit flush in their corners.
        final safeLeft = padding.left;
        final safeTop = padding.top;
        final safeWidth = math.max(1.0, width - padding.left - padding.right);
        final safeHeight = math.max(1.0, height - padding.top - padding.bottom);
        // Every lens is cut the same size (readers asked for one size, not a
        // big-mid-small staircase): the diagonal climb comes from the
        // centres below, not from the diameters.
        final lens = math.min(safeWidth * 0.40, safeHeight * 0.20);
        final brand = _PlateGeometry.brand(width, height);
        final wedge = _PlateGeometry.wedge(width, height);
        final corner = _PlateGeometry.corner(width, height);
        final buttonCentre = corner.incentre(corner.size);
        final anchor = Offset(
          width - corner.width + buttonCentre.dx,
          height - corner.height + buttonCentre.dy,
        );

        Widget at(Offset centre, double diameter, Widget child) => Positioned(
              left: centre.dx - diameter / 2,
              top: centre.dy - diameter / 2,
              width: diameter,
              height: diameter,
              child: child,
            );

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: <Widget>[
            const _MachineBody(),
            Positioned(
              key: const ValueKey<String>('xplore-top-right-plate'),
              right: 0,
              top: 0,
              width: brand.width,
              height: brand.height,
              child: _BrandPlate(geometry: brand),
            ),
            Positioned(
              key: const ValueKey<String>('xplore-left-plate'),
              left: 0,
              top: (height - wedge.height) / 2,
              width: wedge.width,
              height: wedge.height,
              child: _WedgePlate(geometry: wedge, feature: encyclopedia),
            ),
            Positioned(
              key: const ValueKey<String>('xplore-bottom-right-plate'),
              right: 0,
              bottom: 0,
              width: corner.width,
              height: corner.height,
              child: _CornerPlate(
                geometry: corner,
                open: _menuOpen,
                onTap: _toggleMenu,
                width: width,
              ),
            ),
            Positioned(
              left: safeLeft,
              top: safeTop,
              width: safeWidth,
              height: safeHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  _TopBar(onBack: () => Navigator.maybePop(context)),
                  at(
                    Offset(safeWidth * 0.20, safeHeight * 0.155),
                    lens,
                    _LensControl(
                      title: 'تسبیح',
                      subtitle: 'تسبیح و ذکر',
                      icon: Icons.fingerprint_rounded,
                      accent: const Color(0xFFE9A05A),
                      feature: tasbeeh,
                    ),
                  ),
                  at(
                    Offset(safeWidth * 0.505, safeHeight * 0.335),
                    lens,
                    _LensControl(
                      title: 'نماز',
                      subtitle: 'اوقات و قرات',
                      icon: Icons.access_time_filled_rounded,
                      accent: const Color(0xFF6FBDB8),
                      feature: prayer,
                    ),
                  ),
                  at(
                    Offset(safeWidth * 0.795, safeHeight * 0.505),
                    lens,
                    _LensControl(
                      title: 'چاند کی رویت',
                      subtitle: 'رویتِ ہلال',
                      icon: Icons.nightlight_round,
                      accent: const Color(0xFFB5A7EC),
                      feature: crescent,
                    ),
                  ),
                  at(
                    Offset(safeWidth * 0.515, safeHeight * 0.675),
                    lens,
                    _LensControl(
                      title: 'اسلامی تقویم',
                      subtitle: 'ہجری تاریخیں',
                      icon: Icons.calendar_month_rounded,
                      accent: const Color(0xFF7FC7A7),
                      feature: calendar,
                    ),
                  ),
                  at(
                    Offset(safeWidth * 0.215, safeHeight * 0.838),
                    lens,
                    _LensControl(
                      title: 'Xplore Xtra',
                      subtitle: 'روزانہ مطالعہ',
                      icon: Icons.auto_awesome_rounded,
                      accent: const Color(0xFFEBC06B),
                      feature: extra,
                    ),
                  ),
                ],
              ),
            ),
            if (_menuOpen)
              Positioned.fill(
                child: _RadialMenu(
                  anchor: anchor,
                  onSelect: _selectDestination,
                  onDismiss: _toggleMenu,
                ),
              ),
          ],
        );
      }),
      ),
      ),
    );
  }
}

/// The back button, painted over the top of the metal. The brand wordmark
/// lives on the red wedge in the corner, not here.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: SizedBox(
          height: 62,
          child: Stack(
            children: <Widget>[
              Positioned(
                left: 8,
                top: 8,
                child: Material(
                  color: Colors.white.withValues(alpha: .06),
                  shape: const CircleBorder(
                    side: BorderSide(color: Color(0x66C9D4DA), width: 1),
                  ),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onBack,
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 21),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/// The shape of one edge plate: the box it is cut in and the three corners of
/// the triangle inside that box, in unit coordinates.
class _PlateGeometry {
  const _PlateGeometry({
    required this.width,
    required this.height,
    required this.vertices,
  });

  /// The brand wedge in the top-right corner. Same width and height as
  /// [corner], so the two right-hand plates line up with each other and with
  /// the screen's right edge.
  factory _PlateGeometry.brand(double width, double height) => _PlateGeometry(
        width: width * _cornerWidth,
        height: height * _cornerHeight,
        vertices: const <Offset>[Offset(0, 0), Offset(1, 0), Offset(1, 1)],
      );

  /// The wedge on the left edge: its base is the edge of the body itself and
  /// its point reaches into the plate. The caller centres this box on the
  /// screen's vertical midline, so the base's midpoint is the centre of the
  /// left edge. Same box as the two corner plates — all three triangles of
  /// the plate are one size, as readers asked.
  factory _PlateGeometry.wedge(double width, double height) => _PlateGeometry(
        width: width * _cornerWidth,
        height: height * _cornerHeight,
        vertices: const <Offset>[Offset(0, 0), Offset(0, 1), Offset(1, 0.5)],
      );

  /// The corner wedge in the bottom right. Same size as [brand], flush with
  /// the screen's bottom and right edges.
  factory _PlateGeometry.corner(double width, double height) => _PlateGeometry(
        width: width * _cornerWidth,
        height: height * _cornerHeight,
        vertices: const <Offset>[Offset(1, 0), Offset(1, 1), Offset(0, 1)],
      );

  /// Shared by all three plates so they stay equal as the phone changes.
  static const double _cornerWidth = 0.50;
  static const double _cornerHeight = 0.22;

  final double width;
  final double height;
  final List<Offset> vertices;

  Size get size => Size(width, height);

  /// The triangle inside a box of [size].
  Path path(Size size) {
    final path = Path();
    for (var index = 0; index < vertices.length; index++) {
      final vertex = vertices[index];
      final point = Offset(vertex.dx * size.width, vertex.dy * size.height);
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  /// The centre of the triangle's inscribed circle: the one point where a
  /// control can sit without crossing any of the three edges.
  Offset incentre(Size size) {
    final points = <Offset>[
      for (final vertex in vertices)
        Offset(vertex.dx * size.width, vertex.dy * size.height),
    ];
    final a = (points[1] - points[2]).distance;
    final b = (points[0] - points[2]).distance;
    final c = (points[0] - points[1]).distance;
    final perimeter = a + b + c;
    if (perimeter <= 0) return points.first;
    return Offset(
      (a * points[0].dx + b * points[1].dx + c * points[2].dx) / perimeter,
      (a * points[0].dy + b * points[1].dy + c * points[2].dy) / perimeter,
    );
  }
}

/// A red plate cut into the body of the machine: a triangle with a bevelled
/// edge, the brushed lines of the red steel, and the control that lives on it.
class _TrianglePlate extends StatelessWidget {
  const _TrianglePlate({
    required this.geometry,
    required this.child,
    required this.tint,
    required this.sheen,
  });

  final _PlateGeometry geometry;
  final Widget child;
  final Color tint;
  final Color sheen;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TrianglePainter(geometry: geometry, tint: tint, sheen: sheen),
      child: ClipPath(
        clipper: _TriangleClipper(geometry),
        child: child,
      ),
    );
  }
}

/// Keeps whatever sits on a plate inside the plate.
class _TriangleClipper extends CustomClipper<Path> {
  const _TriangleClipper(this.geometry);

  final _PlateGeometry geometry;

  @override
  Path getClip(Size size) => geometry.path(size);

  @override
  bool shouldReclip(covariant _TriangleClipper oldClipper) =>
      oldClipper.geometry.width != geometry.width ||
      oldClipper.geometry.height != geometry.height ||
      !identical(oldClipper.geometry.vertices, geometry.vertices);
}

/// The red plate: a bevelled edge, brushed steel, and the shadow the plate
/// casts on the metal body.
class _TrianglePainter extends CustomPainter {
  const _TrianglePainter({
    required this.geometry,
    required this.tint,
    required this.sheen,
  });

  final _PlateGeometry geometry;
  final Color tint;
  final Color sheen;

  @override
  void paint(Canvas canvas, Size size) {
    final path = geometry.path(size);

    // The plate stands off the metal: a soft shadow under the whole triangle.
    canvas.save();
    canvas.translate(0, 7);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xCC04080B)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.restore();

    // The body of the plate, lit from the top-left.
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[sheen, tint, const Color(0xFF3A0E14)],
          stops: const <double>[0, .48, 1],
        ).createShader(Offset.zero & size),
    );

    // The brushed lines of the plate, and a soft sheen across its top.
    canvas.save();
    canvas.clipPath(path);
    final hatch = Paint()
      ..color = Colors.white.withValues(alpha: .05)
      ..strokeWidth = .8;
    for (var offset = -size.height; offset < size.width; offset += 7) {
      canvas.drawLine(
        Offset(offset, size.height),
        Offset(offset + size.height, 0),
        hatch,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * .38),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.white.withValues(alpha: .10),
            Colors.transparent,
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.restore();

    // The bevel: a dark rim, and a bright edge where the light catches it.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0x66000000),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xAAFFC0B4),
    );
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) =>
      oldDelegate.tint != tint ||
      oldDelegate.sheen != sheen ||
      oldDelegate.geometry.width != geometry.width ||
      oldDelegate.geometry.height != geometry.height ||
      !identical(oldDelegate.geometry.vertices, geometry.vertices);
}

/// The wordmark on the top-right wedge, laid along the plate's hypotenuse.
class _BrandPlate extends StatelessWidget {
  const _BrandPlate({required this.geometry});

  final _PlateGeometry geometry;

  @override
  Widget build(BuildContext context) {
    return _TrianglePlate(
      geometry: geometry,
      tint: const Color(0xFF8E2330),
      sheen: const Color(0xFFC23C4B),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final centre = geometry.incentre(size);
          // The wordmark lies along the hypotenuse, at the angle of the plate.
          final angle = math.atan2(size.height, size.width);
          final blockWidth = size.width * 0.48;
          const blockHeight = 52.0;
          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned(
                left: centre.dx - blockWidth / 2,
                top: centre.dy - blockHeight / 2,
                width: blockWidth,
                height: blockHeight,
                child: Transform.rotate(
                  angle: angle,
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          'Xplore',
                          style: TextStyle(
                            fontFamily: 'sans-serif',
                            fontSize: 25,
                            height: 1.05,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .8,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'by ShiaVerse',
                          style: TextStyle(
                            fontFamily: 'sans-serif',
                            fontSize: 12.5,
                            letterSpacing: 1.1,
                            color: Color(0xCCFFFFFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The wedge on the left edge: the encyclopaedia, cut into the body's edge.
class _WedgePlate extends StatelessWidget {
  const _WedgePlate({required this.geometry, required this.feature});

  final _PlateGeometry geometry;
  final MoreFeature? feature;

  @override
  Widget build(BuildContext context) {
    final encyclopedia = feature;
    return Semantics(
      button: true,
      label: encyclopedia == null
          ? 'اثنا عشری انسائکلوپیڈیا'
          : '${encyclopedia.title} — ${encyclopedia.subtitle}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: encyclopedia?.onOpen,
          child: _TrianglePlate(
            geometry: geometry,
            tint: const Color(0xFF7E2731),
            sheen: const Color(0xFFA93040),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                final centre = geometry.incentre(size);
                const iconSize = 40.0;
                // The stack (glyph over its two lines) is centred on the
                // incentre — the one spot with room on every side — since
                // the wedge now shares the corner plates' shorter, wider
                // box. The label is narrower than the wedge's midline so
                // its lower line stays inside the sloping edges.
                final labelWidth = size.width * 0.46;
                final labelLeft = math.max(4.0, centre.dx - labelWidth / 2);
                return Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned(
                      left: centre.dx - iconSize / 2,
                      top: centre.dy - iconSize - 2,
                      width: iconSize,
                      height: iconSize,
                      child: const Icon(
                        Icons.menu_book_rounded,
                        color: Color(0xFFFFE1CE),
                        size: iconSize,
                      ),
                    ),
                    Positioned(
                      left: labelLeft,
                      top: centre.dy + 2,
                      width: labelWidth,
                      height: 40,
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              'انسائکلوپیڈیا',
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.2,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'بارہ ائمہ • عقائد',
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.3,
                                color: Color(0xFFFFD9C9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The corner wedge in the bottom right: the plate that carries the radial
/// menu, the same affordance as the app-wide hub, redrawn in this plate's
/// language.
class _CornerPlate extends StatelessWidget {
  const _CornerPlate({
    required this.geometry,
    required this.open,
    required this.onTap,
    required this.width,
  });

  final _PlateGeometry geometry;
  final bool open;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: open ? 'مینو بند کریں' : 'مینو کھولیں',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: _TrianglePlate(
            geometry: geometry,
            tint: const Color(0xFF8B2635),
            sheen: const Color(0xFFB43643),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                final centre = geometry.incentre(size);
                final buttonSize = math.min(64.0, width * 0.17);
                // On a short plate the caption under the button would run
                // past the plate's bottom edge and be clipped in half. The
                // button is smaller than the triangle's inscribed circle,
                // so the pair can step up a little until the caption fits.
                const labelHeight = 22.0;
                final overflow =
                    centre.dy + buttonSize / 2 + 2 + labelHeight - size.height;
                final shift = overflow.clamp(0.0, 12.0);
                return Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned(
                      left: centre.dx - buttonSize / 2,
                      top: centre.dy - shift - buttonSize / 2,
                      width: buttonSize,
                      height: buttonSize,
                      child: _RadialButton(open: open, size: buttonSize),
                    ),
                    Positioned(
                      left: centre.dx - size.width * 0.34,
                      top: centre.dy - shift + buttonSize / 2 + 2,
                      width: size.width * 0.68,
                      height: labelHeight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          open ? 'مینو بند کریں' : 'Radial menu',
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFFE3D6),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// One camera lens: a knurled metal barrel, an amber glass element, and the
/// destination engraved on a dark disc at the centre.
class _LensControl extends StatelessWidget {
  const _LensControl({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.feature,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final MoreFeature? feature;

  /// Whether [title] is painted on one line inside the engraving at [size].
  bool _fitsOneLine(BuildContext context, double size, double disc) {
    final painter = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(fontSize: size * 0.098, fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.center,
      maxLines: 2,
    )..layout(maxWidth: disc * 0.80);
    final lines = painter.computeLineMetrics().length;
    painter.dispose();
    return lines <= 1;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title — $subtitle',
      child: LayoutBuilder(builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        final glass = size * 0.74;
        final disc = size * 0.55;
        // A two-line title already fills the engraving; the subtitle would
        // collide with it, so it is dropped and only the title is shown.
        final singleLine = _fitsOneLine(context, size, disc);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: feature?.onOpen,
            child: Ink(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6C7A83), Color(0xFF39454C), Color(0xFF171F25)],
                ),
                boxShadow: const [
                  BoxShadow(color: Color(0xCC05090C), blurRadius: 22, offset: Offset(0, 10)),
                  BoxShadow(color: Color(0x33FFFFFF), blurRadius: 4, offset: Offset(-2, -3)),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  Positioned.fill(
                    child: CustomPaint(painter: _BarrelPainter(accent: accent)),
                  ),
                  Container(
                    width: glass,
                    height: glass,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-.35, -.45),
                        radius: .95,
                        colors: <Color>[
                          const Color(0xFFE9A25A),
                          const Color(0xFFC67424),
                          const Color(0xFF6E3A10),
                          const Color(0xFF241109),
                          const Color(0xFF0A0D0F),
                        ],
                        stops: const <double>[0, .32, .58, .82, 1],
                      ),
                      border: Border.all(color: const Color(0x88707C83), width: size * 0.018),
                      boxShadow: const [
                        BoxShadow(color: Color(0xB3000000), blurRadius: 10, offset: Offset(0, 4)),
                        BoxShadow(color: Color(0x66FFC071), blurRadius: 16, spreadRadius: 1),
                      ],
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(painter: _GlassPainter(accent: accent, discRatio: disc / size)),
                  ),
                  SizedBox(
                    width: disc,
                    height: disc,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(icon, color: accent, size: size * 0.145),
                        SizedBox(height: size * 0.035),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: disc * 0.10),
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              fontSize: size * 0.098,
                              height: 1.22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              shadows: const [Shadow(color: Colors.black87, blurRadius: 6)],
                            ),
                          ),
                        ),
                        if (size > 96 && singleLine) ...<Widget>[
                          SizedBox(height: size * 0.016),
                          SizedBox(
                            width: disc * 0.82,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                subtitle,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                textDirection: TextDirection.rtl,
                                style: TextStyle(
                                  fontSize: size * 0.07,
                                  color: const Color(0xFFDDCCC2),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// The logo button that opens the radial menu — the same affordance as the
/// app-wide hub, redrawn in this plate's language.
class _RadialButton extends StatefulWidget {
  const _RadialButton({required this.open, required this.size});

  final bool open;
  final double size;

  @override
  State<_RadialButton> createState() => _RadialButtonState();
}

class _RadialButtonState extends State<_RadialButton> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(covariant _RadialButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open != widget.open) {
      if (widget.open) {
        _spin.forward();
      } else {
        _spin.reverse();
      }
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _spin,
      builder: (context, child) {
        final turn = Curves.easeOutCubic.transform(_spin.value);
        return Transform.rotate(
          angle: turn * math.pi * 0.25,
          child: Opacity(opacity: 1 - turn * 0.05, child: child),
        );
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            center: Alignment(-.35, -.4),
            colors: [Color(0xFF5FD0A6), Color(0xFF1B6B52), Color(0xFF0B2D23)],
            stops: [0, .62, 1],
          ),
          border: Border.all(color: const Color(0xFFD9FFEF), width: 1.6),
          boxShadow: const [
            BoxShadow(color: Color(0xAA000000), blurRadius: 10, offset: Offset(0, 4)),
            BoxShadow(color: Color(0x5534D39B), blurRadius: 16, spreadRadius: 2),
          ],
        ),
        child: Icon(
          Icons.apps_rounded,
          size: widget.size * 0.46,
          color: const Color(0xFFF2FFF9),
        ),
      ),
    );
  }
}

/// The five destinations, fanned along an arc out of the launch plate. The fan
/// opens on the same page: nothing underneath moves, and tapping the scrim
/// closes it again.
class _RadialMenu extends StatefulWidget {
  const _RadialMenu({required this.anchor, required this.onSelect, required this.onDismiss});

  final Offset anchor;
  final ValueChanged<HubDestination> onSelect;
  final VoidCallback onDismiss;

  @override
  State<_RadialMenu> createState() => _RadialMenuState();
}

class _RadialMenuState extends State<_RadialMenu> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const destinations = HubDestination.values;
    final size = MediaQuery.sizeOf(context);
    // The dials sit on an arc 90 degrees wide, so neighbours are
    // radius * pi / 8 apart. Each one carries a caption underneath, and the
    // next dial has to stay clear of it: that needs
    // radius * pi / 8 >= dial + caption, i.e. a radius of about 0.53 of the
    // short side for a ~58 dp dial. Smaller values buried the captions under
    // the neighbouring circle.
    final radius = math.min(size.width, size.height) * 0.535;
    final itemSize = math.min(58.0, size.width * 0.16);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_controller.value);
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.onDismiss,
                child: ColoredBox(color: Color.fromRGBO(6, 11, 15, .78 * t)),
              ),
            ),
            for (var index = 0; index < destinations.length; index++)
              _item(destinations[index], index, destinations.length, radius, itemSize, t),
            Positioned(
              left: widget.anchor.dx - itemSize * 0.5,
              top: widget.anchor.dy - itemSize * 0.5,
              width: itemSize,
              height: itemSize,
              child: Opacity(
                opacity: t,
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(side: BorderSide(color: Color(0xAAE8F6FF), width: 1.4)),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: widget.onDismiss,
                    child: const Center(
                      child: Icon(Icons.close_rounded, color: Colors.white, size: 24),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _item(
    HubDestination destination,
    int index,
    int count,
    double radius,
    double itemSize,
    double t,
  ) {
    // 180° (left of the plate) to 272° (straight up), stepping evenly.
    final angle = math.pi * (1.0 + (index / (count - 1)) * 0.50);
    final dx = widget.anchor.dx + math.cos(angle) * radius * t;
    final dy = widget.anchor.dy + math.sin(angle) * radius * t;
    return Positioned(
      left: dx - itemSize / 2,
      top: dy - itemSize / 2,
      width: itemSize,
      // Room for the dial plus its caption. The dial is a circle of
      // `itemSize`; the old `+ 20` left the caption one pixel too tall, which
      // Flutter paints as an overflow stripe under every menu item.
      height: itemSize + 26,
      child: Opacity(
        opacity: t,
        child: Transform.scale(
          scale: .7 + .3 * t,
          child: Column(
            children: <Widget>[
              Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => widget.onSelect(destination),
                  child: Container(
                    width: itemSize,
                    height: itemSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-.3, -.4),
                        colors: <Color>[
                          Color.lerp(destination.color, Colors.white, .28)!,
                          destination.color,
                          const Color(0xFF0D1418),
                        ],
                        stops: const <double>[0, .58, 1],
                      ),
                      border: Border.all(color: const Color(0xCCE8F1F6), width: 1.3),
                      boxShadow: const [
                        BoxShadow(color: Color(0xAA000000), blurRadius: 12, offset: Offset(0, 6)),
                      ],
                    ),
                    child: Icon(destination.icon, color: Colors.white, size: itemSize * 0.42),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              // Flexible, so a long label shrinks instead of overflowing the
              // fixed-height box the menu positions the item in.
              Flexible(
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'sans-serif',
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Brushed metal with the diagonal seams and the hatched wedge marks of the
/// reference plate.
class _MachineBody extends StatelessWidget {
  const _MachineBody();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3A464E), Color(0xFF1B252C), Color(0xFF0A1015)],
            stops: [0, .55, 1],
          ),
        ),
        child: CustomPaint(painter: _EtchPainter(), child: SizedBox.expand()),
      );
}

class _EtchPainter extends CustomPainter {
  const _EtchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final seam = Paint()
      ..color = const Color(0xFFAEB9BF).withValues(alpha: .10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final shade = Paint()
      ..color = const Color(0xFF05090C).withValues(alpha: .35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    // Two long diagonal seams, as in the plate: top-left to middle, then a
    // step out to the right edge.
    final plate = Path()
      ..moveTo(-size.width * .05, size.height * .06)
      ..lineTo(size.width * .58, -size.height * .03)
      ..lineTo(size.width * 1.04, size.height * .15)
      ..lineTo(size.width * 1.02, size.height * .97)
      ..lineTo(size.width * .42, size.height * 1.03)
      ..lineTo(-size.width * .04, size.height * .86)
      ..close();
    canvas.drawPath(plate, shade);
    canvas.drawPath(plate, seam);

    final step = Path()
      ..moveTo(-size.width * .05, size.height * .34)
      ..lineTo(size.width * .44, size.height * .40)
      ..lineTo(size.width * .30, size.height * .72)
      ..lineTo(size.width * .06, size.height * .98);
    canvas.drawPath(step, seam);

    // Hatched wedges: little graticule triangles scattered between the lenses.
    void wedge(Offset origin, double scale, bool flip) {
      final hatch = Paint()
        ..color = const Color(0xFFC3CDD3).withValues(alpha: .075)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .9;
      final triangle = Path()
        ..moveTo(0, 0)
        ..lineTo(flip ? -scale : scale, 0)
        ..lineTo(0, flip ? scale * .62 : scale * .62)
        ..close();
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      canvas.drawPath(triangle, hatch);
      for (var i = 1; i <= 5; i++) {
        final f = i / 6;
        canvas.drawLine(
          Offset((flip ? -scale : scale) * f, 0),
          Offset(0, scale * .62 * f),
          hatch,
        );
      }
      canvas.restore();
    }

    wedge(Offset(size.width * .50, size.height * .10), size.width * .17, false);
    wedge(Offset(size.width * .70, size.height * .26), size.width * .13, true);
    wedge(Offset(size.width * .10, size.height * .30), size.width * .12, true);
    wedge(Offset(size.width * .15, size.height * .62), size.width * .14, false);
    wedge(Offset(size.width * .64, size.height * .80), size.width * .12, true);
  }

  @override
  bool shouldRepaint(covariant _EtchPainter oldDelegate) => false;
}

/// Knurled barrel around the glass: fine radially-combed teeth plus a highlight
/// on the side the light comes from.
class _BarrelPainter extends CustomPainter {
  const _BarrelPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final centre = Offset(radius, radius);
    final comb = Paint()
      ..color = const Color(0xFFB9C4CA).withValues(alpha: .20)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    final count = 90;
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * math.pi * 2;
      final inner = radius * 0.945;
      final outer = radius * 0.995;
      canvas.drawLine(
        centre + Offset(math.cos(angle) * inner, math.sin(angle) * inner),
        centre + Offset(math.cos(angle) * outer, math.sin(angle) * outer),
        comb,
      );
    }
    final highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: .16);
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius * .90),
      math.pi * 1.05,
      math.pi * .5,
      false,
      highlight,
    );
    final tint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: .35);
    canvas.drawCircle(centre, radius * .885, tint);
  }

  @override
  bool shouldRepaint(covariant _BarrelPainter oldDelegate) => oldDelegate.accent != accent;
}

/// The glass itself: concentric coatings, a crescent of light, and the dark
/// disc the destination is engraved on.
class _GlassPainter extends CustomPainter {
  const _GlassPainter({required this.accent, required this.discRatio});

  final Color accent;
  final double discRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final centre = Offset(radius, radius);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    for (var i = 0; i < 5; i++) {
      ring.color = i.isEven
          ? const Color(0xFFF7BE83).withValues(alpha: .16)
          : accent.withValues(alpha: .22);
      canvas.drawCircle(centre, radius * (.30 + i * .083), ring);
    }
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFE3BE).withValues(alpha: .35);
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius * .46),
      math.pi * 1.15,
      math.pi * .55,
      false,
      glow,
    );
    final disc = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-.3, -.35),
        colors: [Color(0xFF20272B), Color(0xFF0B0E10), Color(0xFF050708)],
        stops: [0, .7, 1],
      ).createShader(Rect.fromCircle(center: centre, radius: radius * discRatio));
    canvas.drawCircle(centre, radius * discRatio, disc);
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = accent.withValues(alpha: .5);
    canvas.drawCircle(centre, radius * discRatio, rim);
  }

  @override
  bool shouldRepaint(covariant _GlassPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.discRatio != discRatio;
}

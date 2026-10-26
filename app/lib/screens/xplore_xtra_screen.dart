import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../library_repository.dart';
import 'daily_study_screen.dart';

/// A practical shelf for small utilities, starting with the reading plan.
///
/// Only **روزانہ مطالعہ** exists today; the rest of the shelf is marked as
/// coming soon with a plain container, so nothing on it promises a feature
/// that is not in the app yet.
class XploreXtraScreen extends StatelessWidget {
  const XploreXtraScreen({super.key, required this.library});

  final LibraryRepository library;

  @override
  Widget build(BuildContext context) => Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: const Color(0xFF0A1512),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
          foregroundColor: Colors.white,
          title: const JustifiedText('Xplore Xtra', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF123A31), Color(0xFF0B1D19), Color(0xFF07100E)])),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), gradient: const LinearGradient(colors: [Color(0xFF5E4526), Color(0xFF29231D)]), border: Border.all(color: kGold.withValues(alpha: .5))),
                  child: const Row(
                    children: <Widget>[
                      Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFD992), size: 34),
                      SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                        JustifiedText('چھوٹے tools، بڑا فائدہ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                        SizedBox(height: 5),
                        JustifiedText('روزمرہ مطالعے اور عبادت کے کام ایک آسان جگہ پر۔', style: TextStyle(fontSize: 12.5, height: 1.6, color: Color(0xFFE5D8C3))),
                      ])),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _XtraCard(
                  icon: Icons.event_available_rounded,
                  title: 'روزانہ مطالعہ',
                  subtitle: 'قرآن، دعاؤں، نہج البلاغہ، احادیث اور دوسری نصب شدہ کتابوں میں سے ایک یا کئی چنیں؛ آج کا حصہ کھولیں اور اپنی پیش رفت و مسلسل دن محفوظ رکھیں۔ مکمل طور پر آف لائن۔',
                  accent: const Color(0xFF42A78B),
                  badge: 'ابھی دستیاب',
                  onTap: () => unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DailyStudyScreen(library: library)))),
                ),
                const SizedBox(height: 12),
                _ComingSoonTile(icon: Icons.checklist_rounded, title: 'آج کے اعمال کی فہرست', accent: const Color(0xFF657BC4)),
                const SizedBox(height: 10),
                _ComingSoonTile(icon: Icons.bookmark_add_rounded, title: 'ذاتی مطالعہ فہرست', accent: const Color(0xFFB87555)),
                const SizedBox(height: 10),
                _ComingSoonTile(icon: Icons.notifications_active_rounded, title: 'نرم روزانہ یاددہانی', accent: const Color(0xFFB08B42)),
                const SizedBox(height: 16),
                const JustifiedText('فی الحال روزانہ مطالعہ مکمل طور پر کام کرتا ہے؛ باقی سہولتیں آنے والی تازہ کاریوں میں شامل ہوں گی۔', style: TextStyle(fontSize: 12, height: 1.7, color: Color(0xFFB9CEC4))),
              ],
            ),
          ),
        ),
      );
}

/// A feature that is on the shelf but not in the app yet: a plain container
/// with a name and a "coming soon" mark, and nothing more.
class _ComingSoonTile extends StatelessWidget {
  const _ComingSoonTile({required this.icon, required this.title, required this.accent});

  final IconData icon;
  final String title;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: .04),
        border: Border.all(color: accent.withValues(alpha: .30)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: accent.withValues(alpha: .12),
            ),
            child: Icon(icon, color: accent.withValues(alpha: .85), size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: JustifiedText(
              title,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              color: accent.withValues(alpha: .14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.lock_clock_rounded, size: 13, color: accent.withValues(alpha: .9)),
                const SizedBox(width: 5),
                Text(
                  'جلد آ رہا ہے',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Color.lerp(accent, Colors.white, .35),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _XtraCard extends StatelessWidget {
  const _XtraCard({required this.icon, required this.title, required this.subtitle, required this.accent, required this.badge, this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final String badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), color: Colors.white.withValues(alpha: .055), border: Border.all(color: accent.withValues(alpha: .48))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(width: 48, height: 48, decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), color: accent.withValues(alpha: .19)), child: Icon(icon, color: accent, size: 25)),
                const SizedBox(width: 13),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                  Row(children: <Widget>[Expanded(child: JustifiedText(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white))), const SizedBox(width: 8), Icon(onTap == null ? Icons.lock_clock_rounded : Icons.arrow_back_rounded, size: 17, color: accent)]),
                  const SizedBox(height: 6),
                  JustifiedText(subtitle, style: const TextStyle(fontSize: 12, height: 1.65, color: Color(0xFFB9CEC4))),
                  const SizedBox(height: 8),
                  Align(alignment: AlignmentDirectional.centerStart, child: Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), color: accent.withValues(alpha: .16)), child: Text(badge, style: TextStyle(fontSize: 10.5, color: Color.lerp(accent, Colors.white, .3), fontWeight: FontWeight.w700)))),
                ])),
              ],
            ),
          ),
        ),
      );
}

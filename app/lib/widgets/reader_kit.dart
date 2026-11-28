import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../library_repository.dart';
import '../models.dart';
import '../text_utils.dart' show searchMatchRanges;
import 'highlighted_text.dart';

/// Reader appearance shared by every collection.
class ReaderPreferences {
  const ReaderPreferences({
    this.palette = ReaderPalette.paper,
    this.fontScale = 1.0,
    this.script = 'both',
  });

  final ReaderPalette palette;
  final double fontScale;

  /// `both`, `arabic`, or `urdu`.
  final String script;

  static Future<ReaderPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ReaderPreferences(
      palette: ReaderPalette.fromName(prefs.getString('reader_palette')),
      fontScale: (prefs.getDouble('reader_font_scale') ?? 1.0).clamp(0.85, 1.6).toDouble(),
      script: prefs.getString('reader_script') ?? 'both',
    );
  }

  Future<void> savePalette(ReaderPalette palette) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reader_palette', palette.key);
  }

  Future<void> saveFontScale(double scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('reader_font_scale', scale);
  }

  Future<void> saveScript(String script) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reader_script', script);
  }

  ReaderPreferences copyWith({ReaderPalette? palette, double? fontScale, String? script}) =>
      ReaderPreferences(
        palette: palette ?? this.palette,
        fontScale: fontScale ?? this.fontScale,
        script: script ?? this.script,
      );
}

/// One compact appearance button instead of three competing app-bar buttons.
/// The same font range and palette keys are retained, so saved choices survive.
class ReaderControls extends StatelessWidget {
  const ReaderControls({
    super.key,
    required this.preferences,
    required this.onChanged,
    this.extra = const [],
    this.showLabel = false,
  });

  final ReaderPreferences preferences;
  final ValueChanged<ReaderPreferences> onChanged;
  final List<Widget> extra;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    void openAppearance() => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: false,
          backgroundColor: Colors.transparent,
          builder: (_) => _ReaderAppearanceSheet(preferences: preferences, onChanged: onChanged),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ...extra,
        if (showLabel)
          TextButton.icon(
            key: const ValueKey<String>('reader-appearance'),
            onPressed: openAppearance,
            style: TextButton.styleFrom(
              foregroundColor: preferences.palette.accent,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              minimumSize: const Size(0, 40),
            ),
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('ترتیبات', style: TextStyle(fontSize: 13)),
          )
        else
          IconButton(
            key: const ValueKey<String>('reader-appearance'),
            tooltip: 'مطالعے کا انداز',
            style: IconButton.styleFrom(
              foregroundColor: preferences.palette.accent,
              backgroundColor: preferences.palette.accent.withValues(alpha: 0.07),
            ),
            onPressed: openAppearance,
            icon: const Icon(Icons.tune_rounded, size: 22),
          ),
      ],
    );
  }
}

class _ReaderAppearanceSheet extends StatefulWidget {
  const _ReaderAppearanceSheet({required this.preferences, required this.onChanged});

  final ReaderPreferences preferences;
  final ValueChanged<ReaderPreferences> onChanged;

  @override
  State<_ReaderAppearanceSheet> createState() => _ReaderAppearanceSheetState();
}

class _ReaderAppearanceSheetState extends State<_ReaderAppearanceSheet> {
  late ReaderPreferences _preferences = widget.preferences;

  void _font(double scale) {
    final next = scale.clamp(0.85, 1.6).toDouble();
    setState(() => _preferences = _preferences.copyWith(fontScale: next));
    widget.onChanged(_preferences);
    unawaited(_preferences.saveFontScale(next));
  }

  void _palette(ReaderPalette palette) {
    setState(() => _preferences = _preferences.copyWith(palette: palette));
    widget.onChanged(_preferences);
    unawaited(_preferences.savePalette(palette));
  }

  @override
  Widget build(BuildContext context) {
    final palette = _preferences.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: palette.border),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          // The reading hub floats above the navigator; keep controls clear.
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 92),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: palette.border, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'مطالعے کا انداز',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: palette.accent),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Text('حروف کا سائز', style: TextStyle(fontSize: 16, color: palette.foreground)),
                  const Spacer(),
                  Text(
                    '${(_preferences.fontScale * 100).round()}%',
                    style: TextStyle(fontFamily: kDigitFont, fontSize: 14, color: palette.accent),
                  ),
                ],
              ),
              Row(
                children: <Widget>[
                  IconButton(
                    tooltip: 'حروف چھوٹے',
                    color: palette.accent,
                    onPressed: () => _font(_preferences.fontScale - 0.08),
                    icon: const Icon(Icons.text_decrease),
                  ),
                  Expanded(
                    child: Slider(
                      value: _preferences.fontScale,
                      min: 0.85,
                      max: 1.6,
                      activeColor: palette.accent,
                      onChanged: _font,
                    ),
                  ),
                  IconButton(
                    tooltip: 'حروف بڑے',
                    color: palette.accent,
                    onPressed: () => _font(_preferences.fontScale + 0.08),
                    icon: const Icon(Icons.text_increase),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('صفحے کا رنگ', style: TextStyle(fontSize: 16, color: palette.foreground)),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  for (final entry in ReaderPalette.all) ...<Widget>[
                    if (entry != ReaderPalette.all.first) const SizedBox(width: 10),
                    Expanded(
                      child: Semantics(
                        selected: entry.key == palette.key,
                        button: true,
                        child: InkWell(
                          key: ValueKey<String>('reader-palette-${entry.key}'),
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _palette(entry),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: entry.background,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: entry.key == palette.key ? kGold : palette.border,
                                width: entry.key == palette.key ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  entry.key == palette.key ? Icons.check_circle_rounded : Icons.circle_outlined,
                                  color: entry.accent,
                                  size: 24,
                                ),
                                const SizedBox(height: 5),
                                Text(entry.name, style: TextStyle(color: entry.foreground, fontSize: 15)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One record rendered as a card: text, translation, notes, and user actions.
class PassageCard extends StatefulWidget {
  const PassageCard({
    super.key,
    required this.library,
    required this.book,
    required this.passage,
    required this.palette,
    this.fontScale = 1.0,
    this.script = 'both',
    this.indexLabel,
    this.stateId,
    this.searchQuery = '',
    this.focusMatch = false,
  });

  final LibraryRepository library;
  final BookDefinition book;
  final Passage passage;
  final ReaderPalette palette;
  final double fontScale;
  final String script;
  final String? indexLabel;

  /// Record the bookmark/note is stored against. Readers that show one document
  /// as many cards (a supplication, a khutba) point every card at the document,
  /// while `passage.recordId` stays unique per card.
  final int? stateId;
  final String searchQuery;
  final bool focusMatch;

  @override
  State<PassageCard> createState() => _PassageCardState();
}

class _PassageCardState extends State<PassageCard> {
  bool _bookmarked = false;
  String? _note;

  /// Tafseer and footnotes stay folded until the reader asks for them; a wall
  /// of auto-expanded commentary under every verse made surahs unreadable.
  bool _showCommentary = false;
  bool _showFootnote = false;

  int get _stateId => widget.stateId ?? widget.passage.recordId;

  /// Match ranges cost a pass over the whole string, so never run the search
  /// for the (overwhelmingly common) case of a reader with no query.
  List<({int start, int end})> _matches(String text) =>
      widget.searchQuery.isEmpty ? const [] : searchMatchRanges(text, widget.searchQuery);

  /// Paints with the cached bookmark/note state; `_refresh` then corrects it.
  /// Doing it this way keeps a card at one build instead of three.
  void _syncFromCache() {
    _bookmarked = widget.library.isBookmarkedNow(widget.book.key, _stateId);
    _note = widget.library.noteNow(widget.book.key, _stateId);
  }

  @override
  void initState() {
    super.initState();
    _showCommentary = _matches(widget.passage.commentary).isNotEmpty;
    _showFootnote = _matches(widget.passage.footnote).isNotEmpty;
    _syncFromCache();
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant PassageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.passage.recordId != widget.passage.recordId ||
        oldWidget.book.key != widget.book.key ||
        oldWidget.stateId != widget.stateId) {
      _showCommentary = false;
      _showFootnote = false;
      _syncFromCache();
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    final bookmarked = await widget.library.isBookmarked(widget.book.key, _stateId);
    final note = await widget.library.getNote(widget.book.key, _stateId);
    if (!mounted) return;
    if (bookmarked == _bookmarked && note == _note) return;
    setState(() {
      _bookmarked = bookmarked;
      _note = note;
    });
  }

  Future<void> _editNote() async {
    final controller = TextEditingController(text: _note ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const JustifiedText('اپنا نوٹ'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          textAlign: TextAlign.start,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(hintText: 'یہاں لکھیں'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('منسوخ')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('محفوظ کریں'),
          ),
        ],
      ),
    );
    if (note == null) return;
    await widget.library.saveNote(widget.book.key, _stateId, note);
    if (mounted) setState(() => _note = note.trim().isEmpty ? null : note.trim());
  }

  /// Opens the official page this ruling was taken from.
  ///
  /// The fatawa databases store one `source_url` per answer, so a reader can
  /// check the wording against the marja's own site instead of trusting a copy.
  Future<void> _openSource() async {
    final uri = Uri.tryParse(widget.passage.sourceUrl);
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('یہ لنک نہیں کھل سکا — انٹرنیٹ چیک کریں۔')),
    );
  }

  Future<void> _copyText() async {
    final value = widget.passage.copyableText;
    if (value.trim().isEmpty) return;
    final header = [
      widget.book.titleUrdu,
      if (widget.passage.sectionTitle.isNotEmpty) widget.passage.sectionTitle,
      if (widget.passage.locator.isNotEmpty) widget.passage.locator,
    ].join(' — ');
    await Clipboard.setData(ClipboardData(text: '$header\n$value'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('کاپی ہو گیا۔')));
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.palette.foreground;
    final passage = widget.passage;
    final showArabic = widget.script != 'urdu' && passage.arabic.trim().isNotEmpty;
    final showUrdu = widget.script != 'arabic' && passage.urdu.trim().isNotEmpty;
    final showCommentary =
        widget.script != 'arabic' && passage.commentary.trim().isNotEmpty;
    final showFootnote = widget.script != 'arabic' && passage.footnote.trim().isNotEmpty;
    // Never fall back to the raw database id: Parags.ID 562276 is a storage
    // key, not a hadith number, and printing it as one confused readers.
    // Callers pass a proper indexLabel (آیت ٦, حدیث ۵) or a locator instead.
    final header = widget.indexLabel ?? passage.locator;
    final isTitle = passage.format == 1;
    final isSubHeading = passage.format == 3;

    // Isolating each card keeps a scroll (or a bookmark tap) from repainting
    // the whole list — with 286 verse cards that was visible as jank.
    return RepaintBoundary(
      child: Card(
        color: widget.palette.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: widget.palette.border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsetsDirectional.only(start: 10, end: 2, top: 2, bottom: 2),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: widget.palette.accent.withValues(alpha: 0.055),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        header,
                        style: TextStyle(color: widget.palette.accent, fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: _bookmarked ? 'محفوظ سے ہٹائیں' : 'محفوظ کریں',
                      constraints: const BoxConstraints.tightFor(width: 36, height: 40),
                      padding: EdgeInsets.zero,
                      onPressed: () async {
                        await widget.library.toggleBookmark(widget.book.key, _stateId);
                        if (mounted) setState(() => _bookmarked = !_bookmarked);
                      },
                      icon: Icon(
                        _bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                        size: 21,
                        color: _bookmarked ? kGold : widget.palette.accent,
                      ),
                    ),
                    IconButton(
                      tooltip: 'کاپی',
                      constraints: const BoxConstraints.tightFor(width: 36, height: 40),
                      padding: EdgeInsets.zero,
                      onPressed: _copyText,
                      icon: Icon(Icons.copy_rounded, size: 19, color: widget.palette.accent),
                    ),
                    IconButton(
                      tooltip: 'نوٹ',
                      constraints: const BoxConstraints.tightFor(width: 36, height: 40),
                      padding: EdgeInsets.zero,
                      onPressed: _editNote,
                      icon: Icon(Icons.edit_note_rounded, size: 23, color: widget.palette.accent),
                    ),
                  ],
                ),
              ),
              if (showArabic) ...[
                // Plain Text on purpose, inside a SelectionArea provided by the
                // reader screens: a SelectableText per card made long lists
                // (286 verse cards, each with three of them) render as grey,
                // unpainted blocks on slower phones.
                HighlightedText(
                  passage.arabic,
                  query: widget.searchQuery,
                  scrollToMatch: widget.focusMatch,
                  arabic: true,
                  style: TextStyle(
                    fontSize: (isTitle ? 25 : isSubHeading ? 21 : 24) * widget.fontScale,
                    height: 1.85,
                    fontWeight: isTitle || isSubHeading ? FontWeight.bold : null,
                    color: isTitle || isSubHeading ? widget.palette.accent : textColor,
                  ),
                ),
                if (showUrdu || showCommentary) ...[
                  const SizedBox(height: 12),
                  Divider(color: widget.palette.border),
                  const SizedBox(height: 8),
                ],
              ],
              if (showUrdu)
                HighlightedText(
                  passage.urdu,
                  query: widget.searchQuery,
                  scrollToMatch: widget.focusMatch && _matches(passage.arabic).isEmpty,
                  style: TextStyle(
                    fontSize: (isTitle ? 18 : 19) * widget.fontScale,
                    height: 1.6,
                    fontWeight: isTitle ? FontWeight.bold : null,
                    color: textColor,
                  ),
                ),
              if (showCommentary) ...[
                const SizedBox(height: 10),
                _ExpandableNote(
                  query: widget.searchQuery,
                  focusMatch: widget.focusMatch && _matches('${passage.arabic} ${passage.urdu}').isEmpty,
                  label: 'تفسیری حاشیہ',
                  body: passage.commentary,
                  expanded: _showCommentary,
                  onToggle: () => setState(() => _showCommentary = !_showCommentary),
                  textColor: textColor,
                  fontScale: widget.fontScale,
                ),
              ],
              if (showFootnote) ...[
                const SizedBox(height: 10),
                _ExpandableNote(
                  query: widget.searchQuery,
                  focusMatch: widget.focusMatch && _matches('${passage.arabic} ${passage.urdu} ${passage.commentary}').isEmpty,
                  label: 'حاشیہ',
                  body: passage.footnote,
                  expanded: _showFootnote,
                  onToggle: () => setState(() => _showFootnote = !_showFootnote),
                  textColor: textColor,
                  fontScale: widget.fontScale,
                ),
              ],
              if (_note != null) ...[
                const SizedBox(height: 12),
                _AnnotatedBox(
                  label: 'نوٹ',
                  body: _note!,
                  color: kGold,
                  textColor: textColor,
                  fontScale: widget.fontScale,
                ),
              ],
              if (passage.hasSource) ...[
                const SizedBox(height: 14),
                _SourceLink(
                  url: passage.sourceUrl,
                  reference: passage.sourceRef,
                  textColor: textColor,
                  fontScale: widget.fontScale,
                  onOpen: _openSource,
                  // A Wikipedia section gets the small chip: the heading on the
                  // card is already the section, and a full-width box under
                  // every paragraph would bury the article.
                  compact: widget.book.source == CorpusSource.encyclopedia,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The "verify it at the source" button under a fatawa answer.
///
/// Every row of `question_answers` carries the marja's own page, so the ruling
/// can be checked against the published original instead of a local copy. The
/// address is printed as well — a button alone hides where it leads.
class _SourceLink extends StatelessWidget {
  const _SourceLink({
    required this.url,
    required this.reference,
    required this.textColor,
    required this.fontScale,
    required this.onOpen,
    this.compact = false,
  });

  final String url;
  final String reference;
  final Color textColor;
  final double fontScale;
  final VoidCallback onOpen;

  /// True for the Wikipedia collection: one small «ماخذ» button rather than a
  /// full panel with the address printed twice.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = textColor.computeLuminance() > 0.5 ? const Color(0xFFE4BC70) : kForest;
    if (compact) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Tooltip(
          message: url,
          child: InkWell(
            key: const ValueKey<String>('passage-source-chip'),
            borderRadius: BorderRadius.circular(20),
            onTap: onOpen,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: accent.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.open_in_new_rounded, size: 13, color: accent),
                  const SizedBox(width: 5),
                  Text(
                    'ماخذ',
                    style: TextStyle(
                      color: accent,
                      fontSize: 12 * fontScale,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_left_rounded, size: 14, color: accent.withValues(alpha: 0.8)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final label = reference.trim().isEmpty
        ? 'اصل ماخذ پر جائیں'
        : 'اصل ماخذ پر جائیں — مسئلہ ${reference.trim()}';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            url,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 11 * fontScale,
              color: textColor.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new, size: 16),
            label: JustifiedText(label, style: TextStyle(fontSize: 14 * fontScale)),
          ),
        ],
      ),
    );
  }
}

/// A folded annotation — tafseer or footnote — that opens only on tap.
class _ExpandableNote extends StatelessWidget {
  const _ExpandableNote({
    required this.label,
    required this.body,
    required this.expanded,
    required this.onToggle,
    required this.textColor,
    required this.fontScale,
    this.query = '',
    this.focusMatch = false,
  });

  final String label;
  final String body;
  final bool expanded;
  final VoidCallback onToggle;
  final Color textColor;
  final double fontScale;
  final String query;
  final bool focusMatch;

  @override
  Widget build(BuildContext context) {
    final accent = textColor.computeLuminance() > 0.5 ? const Color(0xFFE4BC70) : kForest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: accent,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 6),
          _AnnotatedBox(
            label: '',
            body: body,
            query: query,
            focusMatch: focusMatch,
            color: accent,
            textColor: textColor,
            fontScale: fontScale,
          ),
        ],
      ],
    );
  }
}

class _AnnotatedBox extends StatelessWidget {
  const _AnnotatedBox({
    required this.label,
    required this.body,
    required this.color,
    required this.textColor,
    required this.fontScale,
    this.query = '',
    this.focusMatch = false,
  });

  final String label;
  final String body;
  final Color color;
  final Color textColor;
  final double fontScale;
  final String query;
  final bool focusMatch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label.isNotEmpty) ...[
            Text(
              label,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 4),
          ],
          HighlightedText(
            body,
            query: query,
            scrollToMatch: focusMatch,
            style: TextStyle(color: textColor, fontSize: 16 * fontScale, height: 1.55),
          ),
        ],
      ),
    );
  }
}

/// Shared empty/loading/error panels for the collection screens.
class CollectionMessage extends StatelessWidget {
  const CollectionMessage(this.message, {super.key, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.45)),
              const SizedBox(height: 12),
            ],
            JustifiedText(message, style: const TextStyle(fontSize: 17)),
          ],
        ),
      ),
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: JustifiedText(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      );
}

/// Previous / Next navigation shown at the END of a reading list, so a reader
/// on any ayat, riwayat or fatwa can move forward/back without scrolling up.
class ReaderPrevNextBar extends StatelessWidget {
  const ReaderPrevNextBar({
    super.key,
    required this.hasPrevious,
    required this.hasNext,
    required this.onPrevious,
    required this.onNext,
    this.label = '',
    this.previousLabel = 'پچھلا',
    this.nextLabel = 'اگلا',
  });

  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final String label;
  final String previousLabel;
  final String nextLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey<String>('reader-prev-next'),
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        children: [
          if (label.isNotEmpty) ...[
            Text(label, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: hasPrevious ? onPrevious : null,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(previousLabel),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: hasNext ? onNext : null,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: Text(nextLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

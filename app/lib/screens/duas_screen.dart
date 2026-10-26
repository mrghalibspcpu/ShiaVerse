import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../library_repository.dart';
import '../models.dart';
import '../widgets/reader_kit.dart';
import '../widgets/reader_chrome.dart';
import '../widgets/reader_display.dart';
import '../widgets/chapter_wallpaper.dart';
import '../widgets/resume_card.dart';
import '../widgets/highlighted_text.dart';
import '../text_utils.dart' show arabicNumerals, searchMatchRanges;

/// Mafatih al-Jinan: chapters, supplications, and the reader.
class DuasHomeScreen extends StatefulWidget {
  const DuasHomeScreen({super.key, required this.library, this.focusCategoryId});

  final LibraryRepository library;

  /// Highlights the chapter the last-seen dua belongs to.
  final int? focusCategoryId;

  @override
  State<DuasHomeScreen> createState() => _DuasHomeScreenState();
}

class _DuasHomeScreenState extends State<DuasHomeScreen> {
  /// Re-reads this collection's saved position after the reader closes.
  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final library = widget.library;
    return Scaffold(
      appBar: AppBar(title: const JustifiedText('دعائیں و اعمال')),
      body: FutureBuilder<List<DuaCategory>>(
        future: library.getDuaCategories(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return ErrorPanel(error: snapshot.error.toString());
          final categories = snapshot.data ?? const [];
          if (categories.isEmpty) {
            return const CollectionMessage('دعائیں دستیاب نہیں۔', icon: Icons.mosque_outlined);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              ResumeCard(
                library: library,
                book: BookDefinition.bookFor(CorpusSource.dua)!,
                onOpened: _refresh,
              ),
              _FeaturedDuas(library: library),
              const SizedBox(height: 16),
              for (final category in categories) ...[
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: widget.focusCategoryId == category.id
                        ? Border.all(color: kGold, width: 1.8)
                        : null,
                  ),
                  child: ChapterWallpaperCard(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: const Icon(Icons.mosque, size: 20),
                    ),
                    title: JustifiedText(
                      category.titleUrdu,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                      maxLines: 2,
                    ),
                    subtitle: Text(
                      '${category.itemCount} عنوانات',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => DuaCategoryScreen(library: library, category: category),
                    )),
                  ),
                ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _FeaturedDuas extends StatelessWidget {
  const _FeaturedDuas({required this.library});

  final LibraryRepository library;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DuaItem>>(
      future: library.getFeaturedDuas(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const [];
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const JustifiedText('منتخب دعائیں', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            SizedBox(
              height: 118,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                reverse: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return SizedBox(
                    width: 178,
                    child: ChapterWallpaperCard(
                      child: InkWell(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => DuaReaderScreen(library: library, item: item),
                        )),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Icon(Icons.auto_awesome, size: 18, color: Theme.of(context).colorScheme.primary),
                              const Spacer(),
                              JustifiedText(
                                item.name,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                maxLines: 3,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class DuaCategoryScreen extends StatelessWidget {
  const DuaCategoryScreen({
    super.key,
    required this.library,
    required this.category,
    this.focusRowId,
  });

  final LibraryRepository library;
  final DuaCategory category;

  /// The dua that was opened, so back from last seen shows that row.
  final int? focusRowId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: JustifiedText(category.titleUrdu, maxLines: 1)),
      body: FutureBuilder<List<DuaItem>>(
        future: library.getDuaItems(category.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return ErrorPanel(error: snapshot.error.toString());
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return const CollectionMessage('اس حصے میں کوئی عنوان نہیں۔');
          }
          final focus = focusRowId;
          final focusIndex = focus == null ? 0 : items.indexWhere((item) => item.rowId == focus);
          return ScrollablePositionedList.builder(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 26),
            initialScrollIndex: focusIndex < 0 ? 0 : focusIndex,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              if (item.isHeader) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                  child: JustifiedText(
                    item.name,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: kForest,
                    ),
                    maxLines: 2,
                  ),
                );
              }
              final highlighted = focus != null && item.rowId == focus;
              return DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: highlighted ? Border.all(color: kGold, width: 1.8) : null,
                ),
                child: ChapterWallpaperCard(
                child: ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: JustifiedText(item.name, style: const TextStyle(fontSize: 16), maxLines: 2),
                  trailing: item.isFeatured
                      ? Icon(Icons.star, size: 18, color: kGold)
                      : const Icon(Icons.chevron_left),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DuaReaderScreen(library: library, item: item),
                  )),
                ),
              ),
              );
            },
          );
        },
      ),
    );
  }
}

class DuaReaderScreen extends StatefulWidget {
  const DuaReaderScreen({
    super.key,
    required this.library,
    required this.item,
    this.searchQuery = '',
    this.studyItems,
  });

  final LibraryRepository library;
  final DuaItem item;
  final String searchQuery;

  /// The portion's ordered dua entries. Null for an ordinary reader session.
  final List<DuaItem>? studyItems;

  @override
  State<DuaReaderScreen> createState() => _DuaReaderScreenState();
}

class _DuaReaderScreenState extends State<DuaReaderScreen> with ReaderDisplayMode<DuaReaderScreen> {
  final ItemScrollController _scroll = ItemScrollController();
  final BookDefinition _book = BookDefinition.bookFor(CorpusSource.dua)!;

  List<Passage> _lines = const [];
  int _matchIndex = -1;
  ReaderPreferences _preferences = const ReaderPreferences();
  bool _loading = true;
  String? _error;
  bool _bookmarked = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    disposeReaderDisplay();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final preferences = await ReaderPreferences.load();
      final lines = await widget.library.getDuaLines(widget.item.rowId);
      final bookmarked = await widget.library.isBookmarked(_book.key, widget.item.rowId);
      final note = await widget.library.getNote(_book.key, widget.item.rowId);
      if (!mounted) return;
      setState(() {
        _preferences = preferences;
        _lines = lines;
        _matchIndex = lines.indexWhere((line) => searchMatchRanges('${line.arabic} ${line.urdu}', widget.searchQuery).isNotEmpty);
        if (widget.searchQuery.isNotEmpty) _preferences = preferences.copyWith(script: 'both');
        _bookmarked = bookmarked;
        _note = note;
        _loading = false;
      });
      if (lines.isNotEmpty) {
        unawaited(widget.library.saveLastRead(
          bookKey: _book.key,
          recordId: widget.item.rowId,
          sectionId: widget.item.categoryId,
          title: widget.item.name,
          reference: '${duaCategoryTitles[widget.item.categoryId] ?? 'مفاتیح الجنان'} • دعا',
        ));
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
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
    await widget.library.saveNote(_book.key, widget.item.rowId, note);
    if (mounted) setState(() => _note = note.trim().isEmpty ? null : note.trim());
  }

  Future<void> _copyAll() async {
    final buffer = StringBuffer(widget.item.name);
    for (final line in _lines) {
      if (line.format == 2) continue;
      if (line.arabic.trim().isNotEmpty) buffer.write('\n\n${line.arabic.trim()}');
      if (line.urdu.trim().isNotEmpty) buffer.write('\n${line.urdu.trim()}');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('کاپی ہو گیا۔')));
  }

  int get _studyIndex {
    final items = widget.studyItems;
    return items == null ? -1 : items.indexWhere((item) => item.rowId == widget.item.rowId);
  }

  void _moveStudyItem(int delta) {
    final items = widget.studyItems;
    final next = _studyIndex + delta;
    if (items == null || next < 0 || next >= items.length) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => DuaReaderScreen(
        library: widget.library,
        item: items[next],
        searchQuery: widget.searchQuery,
        studyItems: items,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = _preferences.palette;
    final textColor = palette.foreground;
    return ReaderScaffold(
      book: _book,
      title: widget.item.name,
      preferences: _preferences,
      onPreferencesChanged: (value) => setState(() => _preferences = value),
      fullScreen: readerFullScreen,
      overlay: readerDisplayOverlay(context),
      actions: <Widget>[readerDisplayActions(context, color: palette.accent)],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorPanel(error: _error!)
              : _lines.isEmpty
                  ? const CollectionMessage('اس دعا کا متن موجود نہیں۔')
                  : SelectionArea(
                      child: ScrollablePositionedList.builder(
                        itemScrollController: _scroll,
                        scrollOffsetController: scrollOffsetController,
                        initialScrollIndex: _matchIndex < 0 ? 0 : _matchIndex + 1,
                        initialAlignment: 0.04,
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 112),
                        itemCount: _lines.length + 1 + (widget.studyItems == null ? 0 : 1),
                        addAutomaticKeepAlives: false,
                        minCacheExtent: 350,
                        itemBuilder: (context, index) {
                          if (index == 0) return _header(textColor);
                          if (index > _lines.length) {
                            final studyIndex = _studyIndex;
                            final items = widget.studyItems ?? const <DuaItem>[];
                            return ReaderPrevNextBar(
                              key: const ValueKey<String>('study-dua-prev-next'),
                              hasPrevious: studyIndex > 0,
                              hasNext: studyIndex >= 0 && studyIndex < items.length - 1,
                              onPrevious: () => _moveStudyItem(-1),
                              onNext: () => _moveStudyItem(1),
                              previousLabel: 'پچھلی دعا',
                              nextLabel: 'اگلی دعا',
                              label: 'روزانہ مطالعہ — دعا ${arabicNumerals(studyIndex + 1)} از ${arabicNumerals(items.length)}',
                            );
                          }
                          return _lineBlock(_lines[index - 1], textColor);
                        },
                      ),
                    ),
    );
  }

  /// Title and the item-level actions (one bookmark for the whole dua,
  /// not one per line as the old card-per-line layout suggested).
  Widget _header(Color textColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _preferences.palette.accent.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _preferences.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HighlightedText(
            widget.item.name,
            query: widget.searchQuery,
            scrollToMatch: _matchIndex < 0,
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: _preferences.palette.accent),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton(
                tooltip: _bookmarked ? 'محفوظ سے ہٹائیں' : 'محفوظ کریں',
                onPressed: () async {
                  await widget.library.toggleBookmark(_book.key, widget.item.rowId);
                  if (mounted) setState(() => _bookmarked = !_bookmarked);
                },
                icon: Icon(
                  _bookmarked ? Icons.bookmark : Icons.bookmark_border,
                  color: _bookmarked ? kGold : textColor,
                ),
              ),
              IconButton(
                tooltip: 'کاپی',
                onPressed: _copyAll,
                icon: Icon(Icons.copy, color: textColor),
              ),
              IconButton(
                tooltip: 'نوٹ',
                onPressed: _editNote,
                icon: Icon(Icons.edit_note, color: textColor),
              ),
            ],
          ),
          if (_note != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kGold.withValues(alpha: 0.3)),
              ),
              child: JustifiedText(_note!, style: TextStyle(color: textColor, fontSize: 15)),
            ),
          const Divider(height: 22),
        ],
      ),
    );
  }

  /// One row of the supplication, rendered the way the printed book lays it
  /// out: dua text with its translation, and Urdu instructions as guidance
  /// strips between segments — no "سطر نمبر" badges, no card per line.
  Widget _lineBlock(Passage line, Color textColor) {
    if (line.format == 2) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: _preferences.palette.accent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _preferences.palette.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 17, color: _preferences.palette.accent),
            const SizedBox(width: 8),
            Expanded(
              child: HighlightedText(
                line.urdu,
                query: widget.searchQuery,
                scrollToMatch: _matchIndex >= 0 && _lines[_matchIndex].recordId == line.recordId,
                style: TextStyle(fontSize: 15.5 * _preferences.fontScale, color: textColor),
              ),
            ),
          ],
        ),
      );
    }
    final showArabic = _preferences.script != 'urdu' && line.arabic.trim().isNotEmpty;
    final showUrdu = _preferences.script != 'arabic' && line.urdu.trim().isNotEmpty;
    if (!showArabic && !showUrdu) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showArabic)
            HighlightedText(
              line.arabic,
              query: widget.searchQuery,
              scrollToMatch: _matchIndex >= 0 && _lines[_matchIndex].recordId == line.recordId,
              arabic: true,
              style: TextStyle(fontSize: 24 * _preferences.fontScale, height: 1.85, color: textColor),
            ),
          if (showArabic && showUrdu) const SizedBox(height: 6),
          if (showUrdu)
            HighlightedText(
              line.urdu,
              query: widget.searchQuery,
              scrollToMatch: _matchIndex >= 0 && _lines[_matchIndex].recordId == line.recordId && searchMatchRanges(line.arabic, widget.searchQuery).isEmpty,
              style: TextStyle(
                fontSize: 16.5 * _preferences.fontScale,
                height: 1.6,
                color: textColor.withValues(alpha: 0.88),
              ),
            ),
        ],
      ),
    );
  }
}

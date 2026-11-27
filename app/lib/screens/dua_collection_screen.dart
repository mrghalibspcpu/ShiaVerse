import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../library_repository.dart';
import '../models.dart';
import '../widgets/resume_card.dart';
import 'duas_screen.dart';
import 'library_screen.dart' show ChapterListScreen;

/// The screen behind the single "مفاتیح الجنان و صحیفہ سجادیہ و علویہ" library tile.
///
/// The three prayer books are one entry on the home row. They are shown as a
/// grid, and each tile keeps that book's own last-seen row, refreshed when
/// the book closes.
class DuaCollectionScreen extends StatefulWidget {
  const DuaCollectionScreen({
    super.key,
    required this.library,
    this.onOpenData,
  });

  final LibraryRepository library;
  final VoidCallback? onOpenData;

  @override
  State<DuaCollectionScreen> createState() => _DuaCollectionScreenState();
}

class _DuaCollectionScreenState extends State<DuaCollectionScreen> {
  var _generation = 0;

  Future<void> _open(BookDefinition book) async {
    if (!widget.library.isInstalled(book)) {
      widget.onOpenData?.call();
      return;
    }
    final mafatih = book.source == CorpusSource.dua;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => mafatih
          ? DuasHomeScreen(library: widget.library)
          : ChapterListScreen(library: widget.library, book: book),
    ));
    if (mounted) setState(() => _generation++);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final books = duaCollectionBooks;
    return Scaffold(
      appBar: AppBar(title: const JustifiedText(kDuaCollectionTitle, maxLines: 1)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const JustifiedText(
                  kDuaCollectionHint,
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                JustifiedText(
                  'دعاؤں کی تینوں مستند کتابیں ایک جگہ: مفاتیح الجنان میں روزانہ کی دعائیں، زیارات '
                  'اور اعمال؛ صحیفہ سجادیہ میں امام زین العابدین (ع) کی مناجات؛ اور صحیفہ علویہ میں '
                  'امیرالمومنین حضرت علی (ع) کی دعائیں۔',
                  style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.68,
              ),
              itemCount: books.length,
              itemBuilder: (context, index) {
                final book = books[index];
                return _DuaBookCard(
                  key: ValueKey<String>('${book.key}-$_generation'),
                  library: widget.library,
                  book: book,
                  onOpen: () => _open(book),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DuaBookCard extends StatelessWidget {
  const _DuaBookCard({
    super.key,
    required this.library,
    required this.book,
    required this.onOpen,
  });

  final LibraryRepository library;
  final BookDefinition book;
  final VoidCallback onOpen;

  bool get _isMafatih => book.source == CorpusSource.dua;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final installed = library.isInstalled(book);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _BookCover(book: book)),
              const SizedBox(height: 8),
              JustifiedText(
                book.titleUrdu,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                maxLines: 2,
              ),
              const SizedBox(height: 4),
              if (!installed)
                JustifiedText(
                  'ابھی نصب نہیں',
                  style: TextStyle(fontSize: 11, color: colors.error),
                  maxLines: 1,
                )
              else
                _BookCount(library: library, book: book, mafatih: _isMafatih),
              if (installed) ...[
                const SizedBox(height: 6),
                _LastSeenChip(library: library, book: book),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of where this book was left, tappable into that passage.
class _LastSeenChip extends StatelessWidget {
  const _LastSeenChip({required this.library, required this.book});

  final LibraryRepository library;
  final BookDefinition book;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LastReadEntry?>(
      future: library.getLastReadFor(book.key),
      builder: (context, snapshot) {
        final entry = snapshot.data;
        if (entry == null) return const SizedBox.shrink();
        final label = entry.referenceOrTitle.isEmpty ? 'جاری رکھیں' : entry.referenceOrTitle;
        return Align(
          alignment: Alignment.centerRight,
          child: InkWell(
            onTap: () => openLastRead(context, library, entry, includeCollection: false),
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11.5, color: kGold, fontWeight: FontWeight.w700),
            ),
          ),
        );
      },
    );
  }
}

/// "N عنوانات" for Mafatih, "N دعائیں" for Sahifa Sajjadiyya / Sahifa Alawiyya.
class _BookCount extends StatelessWidget {
  const _BookCount({required this.library, required this.book, required this.mafatih});

  final LibraryRepository library;
  final BookDefinition book;
  final bool mafatih;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = TextStyle(fontSize: 11.5, color: colors.primary, fontWeight: FontWeight.w600);
    if (mafatih) {
      return FutureBuilder<int>(
        future: library.countRecords(book),
        builder: (context, snapshot) {
          final count = snapshot.data ?? 0;
          if (count <= 0) return const SizedBox.shrink();
          return JustifiedText('$count عنوانات', style: style, maxLines: 1);
        },
      );
    }
    return FutureBuilder<List<Map<String, Object?>>>(
      future: library.getChapters(book),
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;
        if (count <= 0) return const SizedBox.shrink();
        return JustifiedText('$count دعائیں', style: style, maxLines: 1);
      },
    );
  }
}

/// Painted illuminated covers for Mafatih (gold), Sahifa Sajjadiyya (emerald),
/// and Sahifa Alawiyya (royal indigo-teal).
class _BookCover extends StatelessWidget {
  const _BookCover({required this.book});

  final BookDefinition book;

  @override
  Widget build(BuildContext context) {
    final (colors, icon, arabicTitle) = switch (book.key) {
      'mafatih' => (
          const <Color>[Color(0xFF7A5418), kGold],
          Icons.mosque,
          'مفاتيح الجنان',
        ),
      'sahifa_alawiyya' => (
          const <Color>[Color(0xFF1A2956), Color(0xFF13687A)],
          Icons.menu_book_rounded,
          'الصحيفة العلوية',
        ),
      _ => (
          const <Color>[kForestDark, kForest],
          Icons.auto_stories,
          'الصحيفة السجادية',
        ),
    };
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
        border: Border.all(color: kGold.withValues(alpha: 0.6), width: 1.2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 32),
          const SizedBox(height: 8),
          Text(
            arabicTitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(
              fontFamily: kArabicFont,
              fontSize: 14,
              height: 1.3,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

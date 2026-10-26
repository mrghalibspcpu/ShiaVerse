# Library 1.5 — فتاویٰ، آخری مطالعہ اور فوری آغاز

Four changes asked for by readers, all of them local: nothing new leaves the
device except the source links the reader chooses to open.

## 1. Every ruling links back to its source

Both fatawa databases already carried a `source_url` and a `source_ref` per
answer. The reader now surfaces them: each question/answer card ends with the
official address and an **اصل ماخذ پر جائیں** button that opens the marja's own
page in the browser, so a ruling can be verified instead of trusted.

- `Passage` gained `sourceUrl` / `sourceRef`; both come from the same
  `_extraQuery` that feeds the reader, the search hydration and the index.
- `scripts/verify_client_sql.py` fails the build if any answer loses its
  `https://` source or its reference number.
- Links open with `url_launcher` in `externalApplication` mode. They are the only
  outbound requests the app makes.

## 2. One “دینی مسائل (احکام و فتاویٰ)” entry, then pick your marja

The two Urdu fatawa books used to be two nearly identical cards on the home row.
They are now a single collection tile; tapping it opens a marja picker with both
authorities (name, portrait, and the number of rulings), and each one opens its
own category list.

- `models.dart` holds `kFatawaCollectionTitle` and `fatawaBooks`.
- `screens/fatawa_screen.dart` is the picker; it degrades to a download button
  when that marja's database is not installed yet.
- Both books stay separate entries in the download manager — they are two files.

## 3. Sahifa Sajjadiyya stops at 83

`saheefa_data` holds more than the book: besides the supplications it carries the
Imam's biography, "ہمارے بارے میں", lecture-video lists and quiz pages
(`t_id` 5–8, 115–116). Those used to be listed as duas 84 and up.

The reader now shows only `t_id IN (1, 2, 3, 4)`:

| `t_id` | Contents | Count |
|---|---|---|
| 1 | دعائیں صحیفہ سجادیہ | 54 |
| 2 | مزید دعائیں | 7 |
| 3 | ایامِ ہفتہ کی دعائیں | 7 |
| 4 | مناجات خمسہ عشر | 15 |
| | **Total** | **83** |

At the time of this release, row data was untouched — only the query narrowed,
so 4,318 of the original 4,993 rows were read and indexed. `_countIndexableRows`
counts through the same filtered query, which keeps `_indexBook`'s "wrote every
row" assertion honest.

### Data refresh in 1.29

The bundled `Sahifa_Sajjadiyya_full_runtime.sqlite3` is now the replacement
from Google Drive's **NEW ALTERNATIVE DATA** folder. It contains 2,103 Arabic
and Urdu text rows across the same 83 indexed supplications; the existing
`t_id IN (1, 2, 3, 4)` reader filter remains in place. Mafatih al-Jinan is also
replaced with the matching Drive edition (677 entries and 5,378 lines). Existing
installations atomically replace these read-only databases on first launch of
the update, then rebuild the search index.

## 4. Two kinds of last-seen, and a home screen that opens at once

**Last seen.** `saveLastRead` now writes a `LastReadEntry` (book, record,
section, chapter title, locator, timestamp) twice:

- `last_read_v2` — the global position, shown as **آخری مطالعہ جاری رکھیں** on
  the home screen with the book, the reference (آیت ۱۲ • پارہ ۱, مسئلہ ۱۸۹۴, …)
  and when it was left (آج / کل / date).
- `last_read_book_<key>` — one per book, so the Quran keeps its own surah while
  Mafatih, Sahifa, Nahj al-Balagha and each hadith book keep theirs. Those appear
  under **ہر کتاب کا آخری مقام** on the home screen and as a **جاری رکھیں** card
  at the top of each book, Quran index, Mafatih and Nahj al-Balagha.

Old `book:recordId:sectionId` values are still read on upgrade.

**Instant start.** `initialize()` now takes `buildSearchIndex`. The bootstrap
passes `false`, opens the home screen as soon as the installed books are open,
and then runs `ensureSearchIndex()` in the background. The 96,513-record walk
never blocks the library again: books are readable immediately, and a thin
progress strip (home and search) reports the index catching up. A build that is
interrupted simply resumes next launch.

## Name, icon, and downloads appearing at once

- The launcher label and the in-app title are **ShiaVerse**; the icon is the
  supplied artwork (`docs/app-icon-source.jpg`, scaled to 512²). The Android
  package id deliberately stays `com.shiaai.app` — renaming it would make the
  phone treat the build as a different app, so an update could not install over
  the old one and every downloaded database would be lost.
- `LibraryRepository.catalogVersion` is bumped whenever a database lands, and
  both the home shell and the library screen listen to it. A finished download
  shows up as installed immediately; no pull-to-refresh needed.

## Smooth scrolling

- **Index yields.** `_indexBook` awaits a 1 ms timer between batches. The index
  is built while the reader is already scrolling, and the tight loop starved the
  UI thread — that was the single largest source of stutter right after a
  download.
- **Bookmarks and notes are cached.** Every card made two
  `SharedPreferences` round trips (platform-channel calls) and then rebuilt
  twice from the async results. Both sets are now read once, cached, and served
  synchronously through `isBookmarkedNow` / `noteNow`, so a card paints once.
- **Fewer live elements.** Reader lists set `addAutomaticKeepAlives: false` and
  each `PassageCard` sits behind a `RepaintBoundary`.
- **No wasted search work.** `searchMatchRanges` is skipped entirely when there
  is no query, instead of walking every field of every card.
- **Cheaper row text.** `_compact` guards each replacement with a `contains`
  check and reuses pre-compiled patterns, so loading a long chapter no longer
  runs five regex passes over every field.
- **Images decode at display size** (`cacheWidth` / `cacheHeight`); the 1338×1480
  banner asset was being decoded into an ~8 MB bitmap for an 80 dp logo.

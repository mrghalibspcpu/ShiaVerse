# Library 1.4 reader/search update

## Included data (20 databases)

The three uploaded databases are preserved **byte-for-byte** with their original
names and native 4096-byte pages. Runtime reader indexes are created only in the
app's private installed copies. Existing source files and their checksums do not
change.

- Sahifa Sajjadiyya: 4,993 rows, including all four source roles (`a/u/v/f`).
- Khamenei Urdu Fatawa: all 428 supplied question/answer records.
- Sistani Urdu Fatawa: all 1,619 supplied question/answer records.

**Data refresh in ShiaVerse 1.29:** the Sahifa file was replaced with the newer
Drive edition (2,103 Arabic/Urdu rows across 83 reader supplications). The
historical counts above describe the original 1.4 snapshot only; the current
manifest and `README.md` list the refreshed data.

Fatawa entries retain the supplied source URL and reference. These files are
snapshots; searching every supplied record does not imply that they contain
all rulings published by either authority.

## Reader and search

- Quran cards are built lazily with `ScrollablePositionedList`, keyed by verse,
  instead of laying out every verse, translation and action up front.
- The initial ayah is positioned directly, including late ayat of long surahs.
  Last-read tracking examines only visible item positions.
- Surah/ayah jump is available in the Quran index and surah/juz/page readers,
  validates each surah's verse count and accepts Latin, Urdu and Arabic digits.
- Literal Arabic/Urdu search checks the complete normalized installed index.
  Each page contains 40 results; the total count and “more results” button expose
  subsequent matches. Pagination never restricts which book pages are searched.
- Existing expanded/FTS search helpers remain available; their old eight-result
  per-query truncation is removed.
- Tafseer, Nahj introductions and footnotes are searchable too. Negative IDs
  distinguish supplementary Nahj tables. Ten readable Tahdhib introduction rows
  lacking a source `ID` use stable negative rowids rather than being skipped.
  All previously valid positive identities are unchanged.
- Result taps pass the query through every reader, position the matching verse,
  paragraph or supplication line, highlight normalized matches (including Arabic
  marks and Persian/Arabic letter variants), and scroll to the word inside long
  text. Matching folded notes expand on arrival. Search readers temporarily show
  both scripts without overwriting the user's saved script preference.
- Index version 5 rebuilds derived search data on update. Saved notes, bookmarks,
  settings and installed books are not deleted. Incomplete indexing cannot be
  marked complete; interrupted incremental indexing is safely rebuilt.

## Verification

`python3 -m unittest discover -v` includes actual 400-record index-page replay
for every one of the 20 databases, unique/resolvable identities, final records,
and search pagination reaching juz 30. `verify_corpus.py` verifies all source
checksums and tables; `verify_client_sql.py` replays reader and index SQL.
Flutter tests cover normalized offset ranges, localized jump digits, late-ayah
lazy rendering and exact-word scrolling inside SelectionArea.

Physical Android profiling remains necessary to confirm smooth rendering on
low-end devices; lazy construction removes the known full-surah layout cost,
not every possible font/shaping or device-specific bottleneck.

# ShiaVerse

## New in 1.28 — one marja fewer, a new Sahifa, every book a study plan

- **دینی مسائل keeps two marjas.** The آیت اللہ خامنہ ای Urdu fatawa edition
  is removed from the app, the corpus manifest and the downloads, at the
  owner's request (آیت اللہ سیستانی and آیت اللہ حافظ بشیر حسین نجفی remain).
  A copy already downloaded is deleted on the next launch, and the data
  screen never offers the book again, even while an older published
  manifest still names it. The corpus is 21 databases now.
- **صحیفہ سجادیہ is the new Drive edition** (`Sahifa_Sajjadiyya_83_duas`):
  exactly the 83 supplications — 2,103 Arabic/Urdu rows, no site furniture —
  replacing the old runtime file in `assets/` and in both manifests. The
  Drive مفاتیح الجنان file turned out byte-for-byte identical to
  `mafatihdb-v4.db` (same MD5), so that book needed no change. Phones that
  already hold the old Sahifa see **«نیا ایڈیشن دستیاب ہے»** in ڈیٹا: the
  installer notices the size change, downloads the new file, and the
  library re-reads and re-indexes it (`refreshAfterUpdate`).
- **Xplore sits below the status bar** instead of running full-screen under
  it, with light status icons on the dark strip. **All five amber lenses
  are one size** and **all three red triangle plates are one size** (the
  left wedge now shares the corner plates' box), and the triangle text —
  the wordmark, «انسائکلوپیڈیا», the radial-menu caption and its button —
  is a step larger.
- **روزانہ مطالعہ accepts every installed book, added one by one.** Beside
  the Quran and Nahj al-Balagha tracks, each installed collection can join
  the plan on its own: hadith books walk their ابواب, مفاتیح الجنان and
  صحیفہ سجادیہ their دعائیں, the fatawa their زمرے, the encyclopaedia its
  مضامین. Old plans load unchanged.
- **The launcher widget adjusts instead of cutting.** It re-cuts its plate
  the moment it is resized (`onAppWidgetOptionsChanged`; on Android 12+ a
  responsive two-plate `RemoteViews`), keeps the hour's line stable across
  resizes, rolls to a new line **every hour** (`updatePeriodMillis`
  3600000), and sizes the text by its length — short ayat/ahadith large,
  long ones a step smaller but never below a readable 11.5sp, wrapped
  inside the cell instead of clipped.
- **قرآنِ کریم has one jump**: «سورہ / آیت پر جائیں». The separate
  go-to-mushaf-page button and field are gone; the page reader itself
  remains for the daily portion of روزانہ مطالعہ.
- Version 1.28.0 (versionCode 10041) — above the unpublished 1.27.3
  attempt (10040), so it installs over it and over 1.27.1 without losing
  downloaded books.

## New in 1.24 — the lens plate, a third marja, the notes in their place

- **The three red plates of Xplore are triangles, as in the artwork.** The
  brand plate in the top-right corner, the pointing wedge on the left edge and
  the corner wedge in the bottom-right are cut as triangles now — the brand
  wordmark runs along the hypotenuse, the book's glyph sits on the incentre of
  the left wedge, and the round radial-menu button sits on the incentre of the
  bottom-right wedge, with the menu fanning out of the button it belongs to.
  The five amber lenses keep their place and their glass, and **none of the
  containers carries a number tag any more**: the number was an annotation of
  the drawing, and on a phone it reads as a dial to be counted. The geometry
  and the reasoning are in `docs/explore-lens-plate-1-24.md`.
- **روزانہ مطالعہ now studies more than one book at a time.** The picker is
  a multi-select — the Quran and the sections of Nahj al-Balagha can be
  studied together — and every book of the plan gets its own portion of the
  day and its own card. Opening a book opens the whole run of that day's
  pages or entries, and at the end of the run the reader offers **the surah
  before and after** the pages on the screen and **the run of pages before and
  after** this one, so the reader can walk on without looking anything up.
  The features of Xplore Xtra that do not exist yet are plain «جلد آ رہا ہے»
  containers and nothing more.
- **The launcher widget is a plate that fits the cell.** It is drawn in five
  layers now — the shadow on the wallpaper, the steel, the light along its top
  edge, the shadow under it, the gold rim — with a raised amber lens badge and
  a round refresh knob, and it picks a full plate or a compact one from the
  size the launcher gives it. It may be resized down to a single row of text.
  The app writes the next prayer and the Hijri date into its own preferences
  and the widget reads them from there, so the plate and the app can never
  disagree; everything the widget did before still works.
- **The mini prayer card's names are one size.** All five prayers are drawn
  at the same measured size, so «فجر» and «مغربین» sit on one line with one
  treatment instead of the mixed sizes the card grew.
- **Xplore is the camera-lens plate of the design.** The page is one full-screen
  portrait body of brushed metal: five amber lenses climb it diagonally
  (تسبیح ← نماز ← چاند کی رویت ← اسلامی تقویم ← Xplore Xtra), and the sixth
  destination — **اثنا عشری انسائکلوپیڈیا** — hangs off the left edge on a red
  plate. The **radial menu** button is no longer a bar at the bottom centre of
  the page: it lives in the bottom-right plate, as the artwork places it, and
  fans the five destinations out over the plate when tapped.
  `docs/previews/explore.png` is
  the layout re-drawn at the app's own fractions
  (`scripts/render_explore_preview.py`); `docs/previews/xplore-1-24/` holds the
  phone-sized renderings of the real widget tree, and the layout test mounts
  the screen at 800 dp and 640 dp tall so an overflowing plate fails CI instead
  of a reader's phone.
- **دینی مسائل gains a third marja: آیت اللہ العظمیٰ شیخ حافظ بشیر حسین نجفی.**
  8,104 Urdu question/answer pairs in 417 chapters, every one carrying the
  official alnajafy.com page it came from and the publisher's own reference
  number, so a reader can check a ruling at its source exactly as with the
  Khamenei and Sistani editions. The Drive archive
  (`Hafiz_Bashir_Hussain_Najafi_Urdu_Fatawa_Compact.sqlite`) is a provenance
  database of 4 tables, 11 views and 8 mirrors; `scripts/build_najafi_fatawa_db.py`
  rewrites it into the two-table shape the other marjas use, drops only the
  provenance machinery, keeps the archive's own translation note, and writes
  `assets/najafi_urdu_fatawa.sqlite(.gz)`. The card uses the uploaded portrait,
  cropped to the same 288 × 420 frame as the other two.
- **نہج البلاغہ: the commentary now stands with the text it belongs to.** The
  `balaghatext_hawashi.ParaNo` column is the note's place in an entry's
  footnote *sequence*, not the paragraph it annotates — sermon 1 holds 74 notes
  numbered 1–75 above 30 paragraphs, sermon 3 holds 151 notes numbered 1–152
  above 20 — so pairing a note with the paragraph of the same number put
  «حاشیہ» under the wrong متن, which is exactly how it read. Notes are now
  shown after the matn in the book's own order, each labelled
  **حاشیہ ۱، حاشیہ ۲ …**, and a note stays under a paragraph only where the
  printed matn still carries its own marker («الْوَالِدِ الْفَانِ٢»). One case,
  151 notes, is pinned by a test.
- Version 1.26.0 (versionCode 36) — it installs over the published 1.25.0
  (versionCode 35) without losing downloaded books.

## New in 1.22 — a reading plan, a proofread Nahj al-Balagha, bigger prayer names

- **Xplore gains «روزانہ مطالعہ»** — pick the Quran (ختمِ قرآن) or one section
  of Nahj al-Balagha (خطبات، خطوط، حکمت), pick 30/60/90/180 days, and the app
  works out today's portion, opens the reader at exactly that page or entry,
  and counts the streak. Pure offline arithmetic; nothing to download.
- **نہج البلاغہ کا اردو ترجمہ** is proofread in the database itself (see
  1.21.1 below), and the app no longer repairs text that is already correct:
  every rule in `lib/nahjul_balagha_urdu.dart` is now guarded by a damage test,
  so a phone reading the new file gets it byte for byte. The guard exists for
  phones that still hold the **old** file: the 21 paragraphs whose letters were
  stored mirrored, and **32 sermon introductions the old file cut off
  mid-sentence** («…اسی [بصرہ کی مذمت] کے بارے میں» with no «فرمایا:»), are
  replaced with the proofread sentences as they are read. A test replays the
  tables over the checked-in database and fails if a correct paragraph is
  touched or a damaged one stops being repaired.
- **Prayer names are a step larger** on the home card (فجر، ظہرین، مغربین …),
  and the **آیت / حدیثِ وقت** container now reaches further down towards the
  mini tasbeeh instead of leaving a gap above it.
- **کریڈٹس** shows the **HashTech** logo and carries the studio's contact:
  **sshaashmi@gmail.com** and **+923046980280**, both tappable. The same artwork
  is the developer icon of the APKPure listing (`docs/store/`), and the address
  and number are on the privacy-policy page as well.
- Version 1.23.0 (versionCode 33) — it installs over the published 1.22.0
  (versionCode 32) without losing downloaded books.

## New in 1.21.1 — Qibla map fixed, Nahj al-Balagha text repaired

- **قبلہ نما map**: CARTO tiles removed (they began showing «API key required»);
  Esri World Street Map first, German OSM mirror as fall-back. Details below.
- **نہج البلاغہ — mirrored Urdu repaired.** Khutbas 4–10 (plus the Radi note of
  Khutba 31, rows 697/698 and 701–723, and a few more rows) had been
  stored with the letters of every word reversed («ںیم» for «میں»,
  «ہیلع» for «علیہ»). Each such paragraph was decoded and **proofread against
  the Arabic by hand**; stray fragments left by the same fault («تق», «کت»,
  «تع»…), a «مت»/«تم» swap that flipped the meaning of rows 349/353, and
  ~30 headers/occasion lines split mid-parenthesis (sermons 11–37 and others)
  were repaired too. `scripts/verify_corpus.py` now fails if mirrored words or a
  split header come back. The database SHA-256 in `assets/database-manifest.json`
  changed (new file: `nahjul_balagha.db`, 6,510,592 bytes).
  *Existing installs keep their old copy until Nahj al-Balagha is removed and
  downloaded again from «ڈیٹا» — 1.22 softens that with the guarded repair
  layer described above.*
- Some other paragraphs of the translation still contain glued words
  («زیادہبلیغ») from the original import; these are cosmetic and listed in
  `docs/nahj-repair-notes.md`.

## New in 1.21 — one corpus, a compass first, a real Xplore

- **قبلہ نما**: the live **compass is back at the top** of the page, where the
  thumb reaches it, followed by the street map and then the offline diagram.
- **The Qibla map no longer shows «API key required» (1.21.1 fix).** CARTO's
  public CDN began answering keyless requests with a *successful* image that
  says «API key required» (the same trap as the earlier OSM «Access blocked»
  page — `errorBuilder` can never catch a successful image). CARTO is removed.
  Tiles now come from Esri's World Street Map (two hosts), then the German OSM
  mirror; attribution «© OpenStreetMap contributors · Esri, HERE, Garmin» is
  always on the card, and the offline graticule only paints when every service
  fails.
- **آیت / حدیثِ وقت actually rolls.** The card used to cache its very first
  answer — usually the empty one, because the home screen paints before the
  library finishes scanning — in a `static` field, so a phone with books
  installed still showed the built-in lines for the whole session. It now
  re-rolls on every `catalogVersion` change, retries while the library is
  still starting, and opens on a line chosen by the clock.
- **The encyclopaedia is one corpus again**: **574 articles, 3,320 sections,
  8,142 references**, built straight from
  «اثنا عشری انسائکلوپیڈیا (منتخب).zip». The Wikishia notes merged in 1.20 are
  **removed** (their source pages were not reachable for readers), and every
  «ماخذ» link is an `ur.wikipedia.org` revision.
- **نہج البلاغہ** ships the newly uploaded Drive database (the same 3,742
  paragraphs, 2,352 footnotes, 504 introductions, normalised to the 1 KiB page
  size the other assets use).
- **Xplore is now a page, not a sheet**: a gradient header, one hero card for
  **نئی کتابیں**, then a two-column grid of the remaining five features — the
  same visual language as the home screen, without its prayer strip or dial.
- **Whole-surah bookmarks**: every row of **قرآن کریم** carries a bookmark
  button, the surah reader repeats it in the app bar, and saved surahs appear
  as a shelf above the verse bookmarks in **محفوظات**.
- The **universal 76 MB APK** is published again next to the per-CPU builds.

## New in 1.20 — the real Qibla map, the merged encyclopaedia, calmer cards

- **قبلہ نما** now opens on a **real OpenStreetMap street map**, not just a
  diagram. North stays up, a thick emerald line runs from the reader to the
  Kaaba with the live distance on it, and — when the magnetometer works — a
  translucent gold cone shows where the phone is actually pointing. This is
  the answer to "the compass failed": match two nearby streets on the screen
  with the ones in front of you and face the line. No sensor, no calibration,
  no network needed for the bearing itself (tiles cache after the first look),
  and the schematic north-up card stays right underneath as a second opinion.
- **نئی کتابیں** now opens **اثنا عشری انسائکلوپیڈیا** proper: the 574 curated
  Urdu-Wikipedia articles **plus** the detailed topic notes from
  **ویکی شیعہ** (`wikishia_urdu_twelver_detailed_notes.sqlite`) merged into one
  book — **635 articles, 3,615 prose sections, 8,325 references**. A note on a
  topic the Wikipedia edition already had (the twelve Imams, فاطمہ زہرا,
  واقعہ کربلا, خمس …) is appended to that article, so one مضمون shows both
  sources, and every section card keeps the exact page revision it came from.
  Notes on new topics became new articles in the chapter they belong to.
  Every article also gains **«ماخذ — براہِ راست کھولیں»**: its references as
  tappable rows that open the exact source page in the browser.
  The «(منتخب)» suffix is gone: the book is now titled **اثنا عشری انسائکلوپیڈیا**.
- **The mini prayer card** highlights the **next prayer without a coloured
  container**: no tile, no border — gold lettering, a two-pixel gold rule and
  the live `باقی 2:07:45` countdown do the work, so the sky shows through.
  (The running prayer keeps its solid emerald tile.)
- **The four section wallpapers** (تسبیح، قبلہ نما، چاند کی رویت، اسلامی تقویم)
  are new photographs, still painted **inside every glass container** rather
  than behind the page.
- **نہج البلاغہ** is the newly uploaded corpus, normalised to the app's page
  size and indexes: same 3,742 paragraphs / 810 headings, revised Urdu
  translation throughout.
- The Dart package, every import and the tooling now say **shiaverse**
  instead of `shia_ai`; the Android applicationId is unchanged, so an update
  installs over the existing app and keeps its downloaded books.

## New in 1.19 — the encyclopaedia, paper inside the cards, a clearer Qibla

- **نئی کتابیں** in **Xplore** now opens **اثنا عشری انسائکلوپیڈیا (منتخب)**
  (`athna_ashari_encyclopedia.db`, 574 curated articles / 3,320 prose sections /
  8,142 references, CC BY-SA 4.0). It ships as a normal library book: ten
  chapters (ائمہ، اہل بیت و کربلا، عقائد، عبادات، کتب و دعائیں، علما، مقامات،
  تاریخ، ادارے، دیگر), a shelf of the twelve Imams, six curated topics,
  in-book search, bookmarks, notes and the same reader. Every section card
  carries a small **ماخذ** button that opens the exact `oldid` revision, each
  article closes with a numbered **ماخذ و حوالہ جات** card, and a
  **مزید پڑھیں** row links only to articles this edition really contains. The
  previous Shia Urdu Wikipedia collection is removed from the model, the
  repository, the manifest, the scripts, the tests and the release assets.
- **The four section wallpapers** (تسبیح، قبلہ نما، چاند کی رویت، اسلامی تقویم)
  are now painted **inside every glass container** rather than behind the page,
  which is what readers asked for. The page keeps a calm dark backdrop.
- **Auto-scroll** gains much slower paces: the ladder now starts at **0.10×**
  (0.10 → 0.15 → 0.20 → 0.25 → 0.30 → 0.35 → 0.40 → 0.50 → … → 4.00×), so
  careful reading no longer needs the 0.50× floor that still felt fast.
- The **mini prayer card** highlights the running prayer with a solid **emerald**
  tile, never the rejected gold/yellow fill; the next prayer keeps its gold
  outline.
- **قبلہ نما**'s map is now an honest north-up diagram: north marked at the top,
  a thick emerald arrow from «آپ» to a Kaaba mark, the bearing in degrees and
  the distance right underneath. No tile downloads, no procedural streets, no
  rotating map — it reads the same offline. *(1.20 adds the real street map
  above it; the diagram stays as the sensor-free second opinion.)*
- The **آیت / حکمتِ وقت** card also draws from **ہدایۃ العلم**: those lines show
  the Urdu sentence and its reference only, in noticeably larger type.

## New in 1.18 — reader polish

- **Every متن page** (Quran, all hadith books, Mafatih, Nahj al-Balagha and the
  encyclopaedia) gains a full-screen mode and a smooth, adjustable auto-scroll.
- **مصحف موڈ** has become a reading surface: tapping any ayah (or its ﴿n﴾
  marker) opens the ayah with its Urdu translation, and **تفسیر دکھائیں /
  چھپائیں** folds the tafseer note in and out.
- The **mini prayer card** keeps Isha marked after midnight (until Fajr) instead
  of going blank for the second half of the night.

The APK still downloads databases on first launch: the encyclopaedia edition is
published gzipped with the rest of the corpus and verified against its SHA-256
before it is installed. `assets/athna_ashari_encyclopedia.db.gz` is the committed
packaged copy (built by `scripts/build_encyclopedia_db.py`); `google_drive/` (the
raw Drive ZIP) is git-ignored.

## New in 1.13 — reading and home polish

The home has a black dock and raised glass keys, closer mini-prayer and
ayah/tasbeeh spacing, and a separate full-screen prayer wallpaper. Quran adds
labelled top actions and a reversible **مصحف موڈ** for continuous, justified
Arabic-only text; ordinary translated/annotated reading is still available.
Chapter names have their own parchment card wallpaper, Nahj al-Balagha shows
**خطبات**, and the three-dimensional Qibla rose points with a Kaaba PNG.
See [`docs/visual-mushaf-1-13.md`](docs/visual-mushaf-1-13.md) for behaviour,
preservation and checks. The Android workflow builds and publishes the signed
APK/ZIP as a pre-release (`app-v1.13.1`). The 1.13.1 release is gated by
APK signature verification plus a real Android emulator clean-install and
launch test before the download is published. CI also checks that extracting
the ZIP gives the exact same APK that passed the installation test.

An offline Shia study library for Android: the Quran with Urdu translation and
tafseer notes, Mafatih al-Jinan, Nahj al-Balagha, and the 14-book Urdu/Arabic
hadith corpus — with full-text search, bookmarks, notes, and reader themes that
all run on the device.

> The AI chat/Gemini integration was removed from this project. Everything here
> is local: no API keys, no backend service, no network calls except the optional
> corpus download described below.

## What is in this repository

- `app/` — Flutter client: library home, Quran (surah/juz/page), Mafatih
  al-Jinan, Nahj al-Balagha, hadith reader, unified search, bookmarks/notes,
  data download manager, and settings.
- `assets/shia-databases.zip` — the 14 original hadith databases (~222 MiB
  expanded, 43 MiB compressed).
- `assets/quran.db`, `assets/mafatihdb-v4.db`, `assets/nahjul_balagha.db` — the
  three standalone collections, normalised to the same SQLite settings as the
  other books.
- `assets/athna_ashari_encyclopedia.db.gz` — the prose-only encyclopaedia
  edition (~2.5 MB gzipped / ~10 MB expanded), rebuilt from the Drive corpus by
  `scripts/build_encyclopedia_db.py`.
- `assets/najafi_urdu_fatawa.sqlite.gz` — the third marja's fatawa (~3 MB
  gzipped / ~15 MB expanded), built from the Drive archive by
  `scripts/build_najafi_fatawa_db.py`.
- `assets/database-manifest.json` — sizes, SHA-256 digests, row counts, titles,
  and download locations for all 22 databases (the encyclopaedia and the third
  marja included).
  `app/assets/database-manifest.json` is the identical copy bundled into the APK.
- `scripts/` — normalisation, packaging, publishing, and verification tools.
- `docs/apk-analysis.md` — findings and signing/licensing limits of the supplied
  compiled APK.

## Reader/search update (1.4)

Sahifa Sajjadiyya and the uploaded Khamenei/Sistani Urdu fatawa are now part of
both the library and unified search. Quran scrolling is lazy, with surah/ayah
jump controls. Search shows total matches and additional pages, and opens the
matching text with normalized highlighting. See
[`docs/reader-search-update.md`](docs/reader-search-update.md) for preservation,
coverage, migration and verification details.

## Fatawa, last-seen, and instant start (1.5)

- Every fatawa answer ends with the official page it was taken from and an
  **اصل ماخذ پر جائیں** button, so a ruling can be verified at the source.
- The two Urdu fatawa books are one library entry, **دینی مسائل (احکام و فتاویٰ)**;
  tapping it opens a marja picker with both authorities.
- Sahifa Sajjadiyya shows the book's 83 supplications and nothing else — the
  site's biography, lecture and quiz pages are no longer listed as duas.
- Two kinds of last-seen: the global **آخری مطالعہ** (book, reference, time) and
  one saved position per book, shown on the home screen and inside each book.
- The home screen opens immediately, with or without downloaded data, and a
  download prompt at the top; the search index builds in the background.

See [`docs/library-1-5-update.md`](docs/library-1-5-update.md).

## One slim last-seen strip, real book names, and the ShiaVerse icon (1.7)

- The home screen used to list every saved position as its own full-width card
  under **ہر کتاب کا آخری مقام**, which buried the library. All of it now fits
  in a single 54 dp strip: a fixed **آخری مطالعہ** label, the books scrolling
  through it sideways (newest first, the most recent one filled), and a button
  that opens the complete list with every reference. See
  [`docs/library-1-7-update.md`](docs/library-1-7-update.md).
- Five books now carry their real titles: **غرر الحکم** (`hakam.db`),
  **ہدایۃ العلم** (`hidaya.db`), **حکمت نامۂ رسول اکرم(ص)**
  (`hikmatprophet.db`), **حکمت نامہ امام حسین(ع)** (`imam.db`) and
  **کتاب التوحید** (`towheed.db`). Only labels changed — no file name, key,
  digest or row count moved, so installed data is untouched.
- The launcher icon and the in-app logo are the uploaded **ShiaVerse** plate.
  `scripts/make_app_icons.py` renders it into the adaptive icon (Android 8+),
  the round icon (API 25) and every legacy density, so no launcher mask can
  clip the wordmark.

## Prayer timings, Qibla compass, and the digital tasbeeh (1.8)

Three daily utilities, sharing one set of coordinates and one design language.
They open from the home screen — a glass banner with the next prayer and its
live countdown, and a row with the counter and the compass — and each has its
own screen.

- **Shia (Jafari) prayer timings.** `adhan_dart` with the Jafari/Leva-Qum preset
  (Fajr 16°, Isha 14°, Maghrib at 4° — the disappearance of the eastern red
  twilight), or the Tehran reading (Fajr 17.7°, Maghrib 4.5°). Nisf al-Layl is
  the midpoint of sunset to the next Fajr, with the precautionary
  maghrib-based reading printed beside it. Every time on the card is the wall
  clock of *the place*, not of the phone, so a phone set to the wrong timezone
  cannot print Isha in the afternoon. A hero header paints the mosque wallpaper
  with the place, the date and the day's times on glass over it.
- **Location, asked for once.** GPS → IP lookup → manual city (70 cities, offline
  list) → Islamabad. Whatever wins is stored, so later launches open instantly,
  offline, and the compass never asks for a second fix.
- **Qibla compass.** The specification's bearing formula from those same
  coordinates, and the phone's own magnetometer for the heading, smoothed by a
  filter that cannot snap through the north seam. A green
  **الائن / کیلیبریٹڈ** state (with a short haptic) when the phone is within 5°
  of the Qibla; the bearing, the compass point and the distance to the Kaaba are
  shown even on a phone with no sensor at all.
- **Digital tasbeeh.** Tasbeeh-e-Zahra (s.a.) advances by itself
  (34× Allahu Akbar → 33× Alhamdulillah → 33× Subhanallah), plus salawat,
  istighfar, tawheed and a custom counter with 33/100/1000/unlimited targets. A
  ripple, a selection haptic and a quiet click on every tap; a double haptic and
  a three-note chime when a step completes. Counts, today's total and the
  lifetime total survive a kill, and the daily counter rolls over by itself.
- **Post-prayer shortcut.** Within half an hour of a prayer's time (and of Fajr's
  window closing at sunrise) the dashboard offers **تسبیحِ زہرا (س) شروع کریں**,
  which arms the sequence and opens the counter.

See [`docs/prayer-qibla-tasbeeh-1-8.md`](docs/prayer-qibla-tasbeeh-1-8.md), and
`docs/previews/home-1-8.png` for the home layout re-rendered with the new
widgets.

## Exact location, the home prayer card, and your own wirds (1.9)

- **The exact place.** A GPS fix is named at once from a bundled list of
  73,023 places (GeoNames; every place of ~500+ people in Pakistan and the
  region, every town of ~5,000+ elsewhere) and, when online, upgraded to the
  exact neighbourhood by OpenStreetMap — «G-11، اسلام آباد». High-accuracy fix
  first, then network, then last known; a clear message and a one-tap fix when
  location is off or refused; quiet re-detection of stale or guessed
  locations on launch (never a prompt, never over a chosen city).
- **Every city.** The picker searches 181 curated cities with Urdu names, the
  73,000 offline places, and any village online.
- **Readable numbers.** Larger text throughout the prayer section, and English
  digits (5:04, 256°, 33/100) in prayer times, Qibla and tasbeeh.
- **Home prayer card.** Place, date, Hijri date (Umm al-Qura, turning at
  Maghrib, adjustable ±2 days; South Asia one day behind by default), live
  clock, the running and next prayer, and the five times — over an animated
  sky for dawn, day, evening and night.
- **Circular mini tasbeeh** on the home screen (ring, +, reset, wird), next to
  a small Qibla dial.
- **Your own count and wird.** Any count (quick choices or typed) for every
  one-step zikr; write and save your own wirds; undo one bead.
- **One tile** for «مفاتیح الجنان و صحیفہ سجادیہ», like the fatawa.

See [`docs/prayer-home-tasbeeh-1-9.md`](docs/prayer-home-tasbeeh-1-9.md). The
home card under its four skies, `docs/previews/home-skies-1-9.jpg`, and the
prayer, tasbeeh and location screens, `docs/previews/screens-1-9.jpg`, are
rendered by `app/test/ui_layout_test.dart` with the app's own fonts on a
360 dp phone (the test fails on any overflow).

## Bottom panel, reading hub, and light home (1.10)

- **One bottom panel, five buttons.** کتب, تلاش, آخری مطالعہ, قبلہ نما and
  ڈاؤن لوڈ. The top bar is gone; the download button moved into the panel, and
  the last-seen list, the Qibla compass and the search open from it.
- **Home, tidied.** The prayer card keeps the place, the Hijri date, the clock
  and the five times. The Gregorian date, the separate "next prayer" block, the
  "now" line and the Qibla dial were removed from it. The running prayer carries
  a **Now** tag; the next prayer is outlined in gold and shows its countdown
  inside its own box. The green ShiaVerse card is gone; bookmarks and settings
  are two plain buttons under the tasbeeh.
- **Circular hub on every page.** Any page opened from the home screen (a book,
  a chapter list, a reader, search, Qibla, the download screen) hides the panel
  and shows a round ShiaVerse button at the bottom centre. Tapping it opens the
  five buttons as a radial menu over the page. Choosing one opens it on top of
  the page, so the book underneath keeps its position; tapping the centre again
  (or the dimmed background) closes the menu and returns to the book as it was.
- **Light by default**, on a white page, and each book's icon has its own
  colour (`bookAccent` in `app/lib/app_theme.dart`). A phone that never chose a
  theme moves to light once; a theme picked in settings is kept.

The code lives in `app/lib/widgets/reading_hub.dart` (the panel, the hub and the
page counter) and `app/lib/widgets/last_seen_sheet.dart` (the last-seen list).
See [`docs/home-dock-1-10.md`](docs/home-dock-1-10.md).

## Dock, More Features, and the home sections (1.10.1)

- **Bottom panel, five buttons on black.** Home (renamed from کتب), تلاش,
  محفوظات, مزید خصوصیات and ترتیبات. The bar is pure black and every icon is a
  rounded square. Home and تلاش are tabs; the other three open a page or a sheet.
- **مزید خصوصیات** is a sheet of extra features. It holds قبلہ نما and آخری
  مطالعہ now. A new extra is one more `MoreFeature` in `_moreFeatures` in
  `app/lib/main.dart`; `app/lib/widgets/more_features.dart` does the rest.
- **Download is in Settings.** ترتیبات opens with a ڈیٹا section that opens the
  download screen.
- **Home sections, in order:** قرآنِ کریم, احادیث, مفاتیح الجنان و صحیفہ سجادیہ,
  نہج البلاغہ, دینی مسائل (احکام و فتاویٰ). Each is a full-width card. احادیث
  opens `HadithBooksScreen`, which holds the hadith book grid.
- **Last-seen fix.** Opening an entry from آخری مطالعہ now closes the sheet
  first, then opens the reader from the page underneath. Before, the sheet stayed
  on the stack under the reader, and returning through the radial menu left the
  home screen blank until the app was reopened.
- **Radial menu text** uses Jameel Noori Nastaleeq.
- **Circular mini tasbeeh.** The card is a 290 px circle with the count ring at
  its centre.
- **Prayer card.** Centred layout. The place name and its detail fade out 10
  seconds after the home opens; the pin stays.
- **Icon** replaced with the new ShiaVerse artwork (`app/ShiaVerseIcon.png`).
- **Marja portraits** in فتاویٰ have square corners.

See [`docs/home-1-10-1.md`](docs/home-1-10-1.md).

## The home dashboard (1.11)

The home screen is now the fifteen containers of the approved design, drawn on
one fixed canvas and scaled as a single piece, so the shapes and the positions
hold on a 360 dp phone, on a tall phone and on a tablet alike:

1. the **ShiaVerse** rail down the left edge, the name written on the spine;
2. the mini prayer card — place, live clock, Hijri date, the five times with the
   running prayer tagged **Now** and the next one counting down — over the
   animated sky of the hour;
3. **قرآنِ کریم** — «ترجمہ و تفسیر کے ساتھ»;
4. **احادیث** — «ایک لاکھ کے قریب احادیث»;
5. **مفاتیح الجنان و صحیفہ سجادیہ** — «مکمل»;
6. **نہج البلاغہ** — «خطب، خطوط اور حکمت»;
7. **دینی مسائل** — «احکام و فتاویٰ»;
8. **آیت / حدیثِ وقت** — a short verse with its Urdu translation, or a short
   narration from Mizan al-Hikmah, rolled once per app start and changed by the
   button at its end; tapping it opens the passage in its own reader;
9. the circular tasbeeh — the wird in the Arabic face, the count glowing in the
   middle, **+** on one side, reset on the other (long press locks it, and the
   same button unlocks), and the expand button for the full counter;
10. the search bar, moved off the bottom panel: it opens the working search with
    the keyboard already up;
11–15. the bottom panel: گھر, قرآن, احادیث, دعائیں and مزید. Everything else —
    نہج البلاغہ, دینی مسائل, نماز کے اوقات, تسبیح, قبلہ نما, محفوظات, آخری مطالعہ,
    ڈیٹا ڈاؤن لوڈ and ترتیبات — lives under **مزید**.

A collection whose books are not installed shows the download mark and opens the
data screen; the download notice and the search-index progress are one slim strip
above the dashboard, and both disappear on their own.

See [`docs/home-dashboard-1-11.md`](docs/home-dashboard-1-11.md), and
`docs/previews/home-1-11.png` for the layout re-drawn at the app's own
measurements (`scripts/render_home_preview.py`).

## White home, personal dock, and coordinated readers (1.12)

The bottom dock now carries **Home, Settings, Bookmarks, Last seen, More**, with
larger icon containers, smaller gaps and English names underneath. Collections
remain on their side rail, whose titles are larger and centred. The spine faces
the opposite way. Home fills the available height, so the search field and
**دینی مسائل** finish on one baseline immediately above the dock, without the
old gap beneath the status bar.

Prayer information is arranged in a clean two-row grid and the mini tasbeeh is
larger, with a bevelled metallic 3D face. Home, utility pages, the dock and the
default reader paper are white. All readers share a collection-coloured,
gold-edged header and a compact appearance sheet, while preserving their lazy
lists, search targets, bookmarks, notes and reading positions.

See [`docs/home-reader-1-12.md`](docs/home-reader-1-12.md) for the layout,
preservation details and regression checks.

## App name and icon

The launcher label and the in-app title are **ShiaVerse**. The icon artwork is
`app/ShiaVerseIcon.png`; `python3 scripts/make_app_icons.py` derives
`app/assets/images/shiaverse_icon.png` (the logo the UI paints) and every
Android density, round and adaptive icon from it — rerun it after replacing the
artwork. The Android package id stays
`com.shiaai.app` on purpose: changing it would make the phone treat the build
as a different app, so an update could not install over the old one and every
downloaded database would be lost.

## Speed

The 1.5 work (background search index, cached bookmarks, lazy readers) also
applies here, and the last-seen strip keeps it that way: the whole home screen
still reads `SharedPreferences` once for the strip instead of once per card, the
chips are built lazily as they scroll in, and only the two images the UI
actually paints are bundled — `logo.png` and `tasneemlogo.png` left the bundle
when the ShiaVerse plate replaced them, which is dead weight off the APK and off
first-launch unpack.

## Smooth scrolling

- The search index yields to the UI between batches, so the ~96k-row walk no
  longer starves the frame while a reader is scrolling.
- Bookmarks and notes are cached in memory; every card used to make two
  `SharedPreferences` round trips (and rebuild twice) as it scrolled in.
- Reader lists drop automatic keep-alives and each card sits behind a
  `RepaintBoundary`, which keeps long chapters from accumulating elements.
- Images decode at their display size instead of at full resolution.


## The corpus

| Collection | File | Contents |
|---|---|---|
| Quran | `quran.db` | 6,236 verses, 114 surahs, Urdu translation (`tr`), tafseer notes (`talighe`), juz/page locators |
| Mafatih al-Jinan | `mafatihdb-v4.db` | 677 catalogue entries and 5,378 text lines across 6 chapters |
| Nahj al-Balagha | `nahjul_balagha.db` | 3,742 paragraphs, 810 entries, 2,352 footnotes, 504 introduction paragraphs |
| Sahifa Sajjadiyya | `Sahifa_Sajjadiyya_full_runtime.sqlite3` | The book's 83 supplications (4,318 of the 4,993 supplied rows; the rest is site furniture) |
| Khamenei Urdu fatawa | `khamenei_urdu_fatawa.sqlite` | All 428 supplied question/answer records with source references |
| Sistani Urdu fatawa | `sistani_urdu_fatawa.sqlite` | All 1,619 supplied question/answer records with source references |
| 14 hadith books | `shia-databases.zip` | 96,513 records, 17,855 sections, 845 chapters |

`python3 scripts/normalize_databases.py` rewrites the three standalone files so
every database shares one configuration: SQLite `page_size` 1024 (the setting the
original 14 books use), UTF-8, the `shia_*` reader indexes, fresh statistics, and
no free pages. Row data is never modified — the script re-checks row counts and a
content fingerprint before it replaces a file.

```sh
python3 scripts/normalize_databases.py --dry-run   # report only
python3 scripts/normalize_databases.py             # rebuild in place
python3 scripts/prepare_databases.py --write-manifest
```

## Data delivery: small APK, fast first launch

The APK does **not** have to carry the corpus. `app/lib/data_installer.dart`
downloads each database on demand:

1. The bundled manifest (`app/assets/database-manifest.json`) lists every file,
   its size, and its SHA-256.
2. The app fetches `<name>.db.gz` from GitHub — a build-pinned mirror first
   (`--dart-define=SHIA_DATA_BASE_URL`), then the latest release, then the
   repository itself.
3. Interrupted downloads resume with HTTP `Range` requests.
4. The stream is gunzipped straight to disk while it is hashed; a file whose
   digest does not match the manifest is deleted, never opened.
5. `LibraryRepository.refreshAfterInstall()` picks the new book up and appends it
   to the search index without rebuilding what is already there.

Books can also be bundled at build time (see below); when a file is already in
app storage the download is skipped, and when it is missing the library shows it
as "not installed" with a download button instead of failing.

Publish the corpus once per change:

```sh
python3 scripts/prepare_databases.py --write-manifest
python3 scripts/publish_databases.py          # writes dist/*.db.gz (222 MiB -> ~53 MiB)
gh release create databases-v1 dist/*.gz dist/database-manifest.json \
    --title "Corpus v1" --notes "SQLite collections for the Shia library app"
```

## Build and run the app

Requirements: Flutter stable, Android SDK, Java 17, and a device or emulator.

```sh
cd app
flutter pub get
flutter run
```

That builds a small APK that downloads its data on first launch. To ship an
offline APK with everything inside (~230 MiB of assets), unpack the databases
first:

```sh
python3 scripts/prepare_databases.py --output app/assets/databases
cd app && flutter build apk --release
```

## Checks

```sh
python3 -m unittest discover -v          # packaging/manifest unit tests
python3 scripts/verify_corpus.py         # every database opens; sample lookups work
python3 scripts/verify_client_sql.py     # the Dart queries replayed against real data
python3 scripts/check_dart.py            # syntax/imports/removed symbols without a Dart SDK
cd app && flutter analyze && flutter test
```

`verify_client_sql.py` extracts each statement from
`app/lib/library_repository.dart` and executes it, so the Dart and the schema
cannot drift apart unnoticed. `check_dart.py` needs
`pip install tree-sitter tree-sitter-dart` and is a guard for environments
without Flutter; `flutter analyze` remains the real type check.

## Build a signed APK in GitHub Actions

`.github/workflows/android-apk.yml` validates the corpus, replays the client
SQL, runs the Python and Flutter checks, then builds a release APK and uploads a
30-day artifact. The workflow has a `bundle_databases` switch
(`workflow_dispatch`) for offline APKs; by default the APK ships without data.
Without owner signing secrets it uses the Android debug key and labels the result
**preview/debug-signed** — for testing only.

For an owner-signed release, add these repository Actions secrets:

- `ANDROID_KEYSTORE_BASE64` — base64-encoded owner keystore
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Optionally set the non-secret repository Actions variable `SHIA_DATA_BASE_URL` to
a mirror that serves the corpus files. Never commit a keystore or a credential.

### Downloading the APK on a phone

Every build on a pushed branch publishes a pre-release named
`app-v<version>` whose asset is `ShiaVerse-<version>.apk` — the file name
carries the version on purpose, so a phone never reuses a half-downloaded copy
of an older build. Two things happen after the upload:

1. the release notes are written with the file's exact size and SHA-256, so a
   download can be checked instead of guessed at;
2. a **Verify the hosted APK is the APK we built** step downloads the published
   asset again and fails the run if its digest differs from the APK the run
   produced — a truncated or stale asset stops the build, not the reader.

`cd app && flutter build apk --release` still works locally; that is the same
APK, just without the CI signature (see
[`app/android/ci-signing/README.md`](app/android/ci-signing/README.md)).

A newly generated APK is not automatically a Google Play update. Updating the
Play-installed app requires the original package identity, signing key, and any
required Play licensing/configuration; this project does not bypass those checks.
See [`docs/apk-analysis.md`](docs/apk-analysis.md).

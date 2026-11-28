# ShiaVerse 1.31.0 — eleven hadith books, a daily-study planner, and a copyright-free Azan

This release is version `1.31.0+10046` (Android versionCode 10046), above the
published `1.30.2+10045` release so Android can install it as an update.

## Requested changes

1. **قرآنِ کریم — Inzaal-ul-Quran edition.** `quran.db` is replaced by the
   Inzaal-ul-Quran database (11,702,272 bytes, SHA-256
   `37d2a411a8c51bbf6bd4a5443adfa5e8cbba04a8541ab46a048db1d1ed19c13d`): all
   6,236 verses and 114 surahs, now indexed under search-index version 12 so the
   old text is not quoted back to a reader.
2. **عیون اخبار الرضا (ع) joins the hadith shelf.** The eleventh hadith book
   ships as `uyun_akhbar_al_rida_urdu.db.gz` (2,442,777 bytes compressed,
   19,525,632 raw; SHA-256
   `5420397510ef550f7b7d8eb81f355635d2dfe1147ad401ea563361db55621984`):
   954 narrations in 70 chapter groups across the two volumes. Chapters,
   sections, passages, search, bookmarks, and daily-study portions all read it
   through the same code paths as the other books. The home tile now says
   **گیارہ مستند کتبِ احادیث**.
3. **Reader footer.** The redundant `تصدیق کے لیے اصل سرکاری صفحہ` heading is
   gone; the source link keeps its own row.
4. **Home background.** The light wallpaper photograph is removed. The home
   page paints a three-stop gradient (light: mint → cream → sand; dark:
   emerald → night → violet) from `DashboardPalette`, so the page matches the
   theme instantly and the APK is smaller.
5. **Location prompt and the mini prayer row.** A phone that still stores only
   an IP or fallback location is asked for the OS location permission once on
   startup (`location_install_prompt_v1`), so prayer times lock onto the exact
   town. The mini location row is now tappable end to end, and its beacon and
   action icon animate (beacon halo, spinning sync while locating) unless the
   system asks for reduced motion.
6. **روزانہ مطالعہ planner.** Twenty-one tracks are grouped by shelf
   (قرآن، دعائیں، نہج البلاغہ، احادیث، فتاویٰ، مضامین) with a search box; the
   duration chips run 7–365 days and any length from 1 to 3,650 days can be
   typed (Urdu or Latin digits). An active plan keeps its start day, length, and
   completed days while books are added or removed, `withTracks` deduplicates
   them, and any plan day can be opened — a grid of every day jumps straight to
   that day's portion in every book of the plan.
7. **تسبیح dial.** The `+` and reset buttons sit symmetrically on the 0.68 r
   ring around the bead; the progress ring eases to each new value, and a
   completed wird flashes a single gold ring outward from the bead (a finite
   animation, never a permanent loop).
8. **Copyright-free Short Azan.** The alert sound is now a 15.60 s vocal
   *Allahu Akbar* excerpt released under **CC0 1.0 Universal** (Wikimedia
   Commons `File:Beautiful_adhan.ogg` by Adam-synagda), shipped as
   `assets/audio/azan_short.wav` and
   `android/app/src/main/res/raw/shiaverse_short_azan.wav` (22,050 Hz, 16-bit
   mono, 688,004 bytes). **مختصر اذان** is the default mode in نماز کے اوقات,
   **نرم چائم** stays selectable, the choice is remembered, and a preview button
   plays it in-app. Six notification channels
   (`prayer_{silent|sound|short_azan}_{vibrate|quiet}`) are created up front, so
   switching sound or vibration takes effect on the next reminder instead of
   being frozen by Android's channel rules.

## Data delivery

The manifest now grounds **19** databases: ten bundled hadith books plus Uyun
Akhbar al-Rida, and the curated Quran, Mafatih, Sahifa Sajjadiyya, Sahifa
Alawiyya, Nahj al-Balagha, Sistani, Najafi, and encyclopaedia editions. The
retired Khamenei fatawa file (deleted upstream) is no longer listed, while its
catalog entry stays so old bookmarks still resolve. `scripts/prepare_databases.py`
regenerates both manifest copies, `verify_corpus.py` and `verify_client_sql.py`
pass on the new corpus, and the data-publish workflow uploads the set to
`databases-v2`.

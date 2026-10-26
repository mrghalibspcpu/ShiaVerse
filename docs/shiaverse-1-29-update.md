# ShiaVerse 1.29.0 — readers, Xplore, and refreshed data

This release is version `1.29.0+10042` (Android versionCode 10042), above the
published `1.28.0+10041` release so Android can install it as an update.

## Requested changes

- **دینی مسائل:** Ayatollah Khamenei is no longer offered in the marja picker.
  His catalog entry remains so existing links and saved references continue to
  resolve; Sistani and Najafi remain selectable.
- **Mafatih and Sahifa:** the two databases now match the files from Drive's
  **NEW ALTERNATIVE DATA** folder. The APK bundles hash-pinned copies; on first
  launch after updating, stale installed copies are replaced through a
  same-directory atomic swap before the readers open them. The search-index
  version is bumped so old indexed text is rebuilt.
  - Mafatih: 677 items, 5,378 lines; SHA-256
    `cc01c16db7652df6b00997c1ab7eebba354733c75334a2fc8d795702afc4c182`.
  - Sahifa: 2,103 text rows and 83 index entries; SHA-256
    `ad65542a5d430be203500464355d67148b774632cd12b8918808998724fc4f05`.
- **Xplore:** edge plates and controls are laid out within the system safe area;
  the five lens controls have equal diameters, the three triangular plates share
  one size, and their labels/buttons are enlarged.
- **روزانہ مطالعہ:** plans can include multiple library books, including Quran,
  both dua collections, Nahj divisions, hadith, fatawa, and the encyclopedia.
  Each book gets its own measured portion; generic reader navigation stays
  inside that day's assigned section run.
- **Home widget:** changing widget size reselects a compact or full layout. Short
  quotes use larger text, longer quotes use smaller text, and the widget refresh
  schedule is hourly (with the manual refresh button retained).
- **Quran:** the page-number jump control is removed; Surah/Ayah jump and page-run
  navigation remain.
- **اسلامی تقویم:** مناسبات now appear on swipeable, perspective-transformed
  monthly calendar pages with dual Gregorian/Hijri dates, event markers, and
  selected-day details rather than a vertical list.

## Data delivery

The manifest points to the pinned `databases-v2` release first, then falls back
to `databases-v1` and the repository assets if a file is unavailable. The
data-publish workflow creates or updates the v2 release from the verified
corpus. The two updated runtime databases are also
bundled in the APK to make the installed-app migration independent of a network
connection.

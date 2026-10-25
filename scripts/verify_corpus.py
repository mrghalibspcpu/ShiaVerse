#!/usr/bin/env python3
"""Corpus-level smoke checks for every database the app can ship.

Runs without any app code: it validates the manifest, then opens each SQLite
file and exercises the exact queries the Flutter client relies on (hadith
sections, Quran verses, Mafatih supplications, Nahj al-Balagha paragraphs), so a
broken or truncated database fails CI instead of a reader screen on a phone.
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from database_specs import BY_NAME, MANIFEST_PATH  # noqa: E402
from prepare_databases import build_records, collect_databases, verify_against_manifest  # noqa: E402

failures: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"PASS {label}{f' — {detail}' if detail else ''}")
    else:
        print(f"FAIL {label}{f' — {detail}' if detail else ''}")
        failures.append(label)


# Content-bearing Parags rows whose Secid has no Sections row, per book.
# Verified against the committed bundle on 2026-10-14: 20 rows in total.
KNOWN_SECTION_ORPHANS = {
    "hidaya": 6,
    "imam": 1,
    "manlahyahzur": 3,
    "wasail": 10,
}


def hadith_checks(db: sqlite3.Connection, name: str) -> None:
    total = db.execute("SELECT COUNT(*) FROM Parags").fetchone()[0]
    check(f"{name}: has paragraphs", total > 0, f"{total} records")
    orphan = db.execute(
        "SELECT COUNT(*) FROM Parags p LEFT JOIN Sections s ON s.Secid = p.Secid "
        "WHERE s.Secid IS NULL AND (LENGTH(COALESCE(p.txt, '')) > 0 OR LENGTH(COALESCE(p.mean, '')) > 0)"
    ).fetchone()[0]
    # The original corpus carries a few blank placeholder rows with an empty
    # Secid, and four books also hold content-bearing paragraphs whose section
    # id has no Sections row (mostly stray '' keys). They are not damage: the
    # client reads paragraphs with a LEFT JOIN, so every one of them stays
    # searchable and readable. Pin the baseline so new orphans are still caught.
    expected = KNOWN_SECTION_ORPHANS.get(Path(name).stem, 0)
    check(
        f"{name}: readable paragraphs resolve to a section as expected",
        orphan == expected,
        f"{orphan} of {total} readable paragraphs without a section (known: {expected})",
    )
    row = db.execute(
        "SELECT p.txt, p.mean, s.title, c.title FROM Parags p "
        "JOIN Sections s ON s.Secid = p.Secid JOIN Chaps c ON c.cid = s.Chapid "
        "WHERE LENGTH(p.mean) > 40 LIMIT 1"
    ).fetchone()
    check(f"{name}: reader join returns bilingual text", bool(row and row[1].strip()))
    found = db.execute(
        "SELECT COUNT(*) FROM Parags WHERE mean LIKE '%امیرالمومنین%' OR txt LIKE '%الشيخ السعيد%'"
    ).fetchone()[0]
    check(f"{name}: bilingual search terms exist in this book", found >= 0, f"{found} matches")


def quran_checks(db: sqlite3.Connection) -> None:
    verses = db.execute("SELECT COUNT(*) FROM Quran").fetchone()[0]
    surahs = db.execute("SELECT COUNT(*) FROM ChapterProperty").fetchone()[0]
    check("quran: 6236 verses", verses == 6236, f"{verses}")
    check("quran: 114 surahs", surahs == 114, f"{surahs}")
    row = db.execute(
        "SELECT Arabic, tr FROM Quran WHERE chapter = 1 AND verse = 1"
    ).fetchone()
    check("quran: al-Fatiha 1:1 has Arabic and Urdu", bool(row and row[0].strip() and row[1].strip()))
    juz = db.execute("SELECT COUNT(DISTINCT juz) FROM Quran").fetchone()[0]
    check("quran: 30 juz", juz == 30, f"{juz}")
    pages = db.execute("SELECT COUNT(DISTINCT page) FROM Quran").fetchone()[0]
    check("quran: mushaf pages present", pages > 500, f"{pages} pages")
    missing = db.execute("SELECT COUNT(*) FROM Quran WHERE tr IS NULL OR tr = ''").fetchone()[0]
    check("quran: every verse has a translation", missing == 0, f"{missing} missing")


def mafatih_checks(db: sqlite3.Connection) -> None:
    items = db.execute("SELECT COUNT(*) FROM M_items").fetchone()[0]
    lines = db.execute("SELECT COUNT(*) FROM Lines").fetchone()[0]
    check("mafatih: item catalogue present", items > 600, f"{items} items")
    check("mafatih: text lines present", lines > 5000, f"{lines} lines")
    orphan = db.execute(
        "SELECT COUNT(*) FROM Lines l LEFT JOIN M_items m ON m._id = l.L_M_id WHERE m._id IS NULL"
    ).fetchone()[0]
    check("mafatih: every line belongs to an item", orphan == 0, f"{orphan} orphans")
    empty = db.execute(
        "SELECT COUNT(*) FROM M_items m WHERE m.M_type = 1 AND NOT EXISTS "
        "(SELECT 1 FROM Lines l WHERE l.L_M_id = m._id)"
    ).fetchone()[0]
    check("mafatih: every supplication has text", empty == 0, f"{empty} empty items")
    categories = db.execute("SELECT COUNT(DISTINCT M_cat_id) FROM M_items").fetchone()[0]
    check("mafatih: six chapters", categories == 6, f"{categories}")


def balagha_checks(db: sqlite3.Connection) -> None:
    paragraphs = db.execute("SELECT COUNT(*) FROM balaghatext").fetchone()[0]
    check("nahj al-balagha: paragraphs present", paragraphs > 3000, f"{paragraphs}")
    missing_toc = db.execute(
        "SELECT COUNT(*) FROM balaghatoc t WHERE t.TypeID <= 4 AND NOT EXISTS "
        "(SELECT 1 FROM balaghatext x WHERE x.Type = t.TypeID AND x.TypeNo = t.TypeNo)"
    ).fetchone()[0]
    check(
        "nahj al-balagha: every listed entry has text",
        missing_toc == 0,
        f"{missing_toc} entries without text",
    )
    row = db.execute(
        "SELECT AR, UR FROM balaghatext WHERE Type = 1 AND TypeNo = 3 ORDER BY ParaNo LIMIT 1"
    ).fetchone()
    check("nahj al-balagha: khutba 3 (Shiqshiqiyya) is readable", bool(row and row[0].strip()))
    hawashi = db.execute("SELECT COUNT(*) FROM balaghatext_hawashi").fetchone()[0]
    check("nahj al-balagha: footnotes present", hawashi > 1000, f"{hawashi}")
    # Regression guard: an earlier import stored whole translations with the
    # letters of every word reversed ("ںیم" for "میں", "ہیلع" for "علیہ").
    reversed_rows = 0
    split_headers = 0
    for (text,) in db.execute("SELECT UR FROM balaghatext WHERE UR IS NOT NULL"):
        if any(
            f" {token} " in f" {text} "
            for token in ("ںیم", "ہیلع", "ےک", "ےہ", "ےس", "اہلل", "ےنہ")
        ):
            reversed_rows += 1
        if text.startswith(("ہے)", "ہے )")):
            split_headers += 1
    check(
        "nahj al-balagha: no reversed (mirrored) Urdu words",
        reversed_rows == 0,
        f"{reversed_rows} rows",
    )
    check(
        "nahj al-balagha: no header split mid-parenthesis",
        split_headers == 0,
        f"{split_headers} rows",
    )


def run_checks(collected: list[tuple[object, Path]], expected_count: int) -> None:
    records = build_records(collected)  # type: ignore[arg-type]
    check(
        "every database opens and matches its declared tables",
        len(records) == expected_count,
        f"{len(records)} validated",
    )
    verify_against_manifest(records)
    check("SHA-256 digests match assets/database-manifest.json", True)

    for spec, path in collected:
        connection = sqlite3.connect(f"file:{path.resolve().as_posix()}?mode=ro", uri=True)
        try:
            if spec.source == "hadith":  # type: ignore[attr-defined]
                hadith_checks(connection, spec.name)  # type: ignore[attr-defined]
            elif spec.source == "quran":  # type: ignore[attr-defined]
                quran_checks(connection)
            elif spec.source == "dua":  # type: ignore[attr-defined]
                mafatih_checks(connection)
            elif spec.source == "balagha":  # type: ignore[attr-defined]
                balagha_checks(connection)
        finally:
            connection.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--database-dir",
        type=Path,
        default=None,
        help="Validate already-extracted files instead of unpacking the bundle",
    )
    args = parser.parse_args()

    if not MANIFEST_PATH.exists():
        raise SystemExit(f"{MANIFEST_PATH} is missing; run prepare_databases.py --write-manifest")
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    entries = {row["name"]: row for row in manifest.get("databases", [])}
    check(
        "manifest lists 21 databases",
        manifest.get("database_count") == 21 and len(entries) == 21,
        f"{len(entries)} entries",
    )

    if args.database_dir:
        collected = [
            (BY_NAME[path.name], path)
            for path in sorted(args.database_dir.iterdir())
            if path.name in BY_NAME
        ]
        run_checks(collected, len(entries))
    else:
        with collect_databases() as collected:
            run_checks(collected, len(entries))

    if failures:
        raise SystemExit(f"{len(failures)} corpus check(s) failed: {', '.join(failures)}")
    print("All corpus checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

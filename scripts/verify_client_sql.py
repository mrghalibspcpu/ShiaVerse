#!/usr/bin/env python3
r"""Run the Flutter client's own SQL against the real databases.

The Dart repository builds every query by hand and CI images that only ship
Python have no Dart VM to compile it. This script closes that gap: it extracts
each statement verbatim from ``app/lib/library_repository.dart`` (so the check
fails as soon as the Dart and the schema drift apart) and executes it against the
shipped SQLite files. It then rebuilds a miniature copy of the on-device search
index — including the FTS5 mirror — and proves a bilingual query finds records.

    python3 scripts/verify_client_sql.py                    # unpack bundle + extras
    python3 scripts/verify_client_sql.py --database-dir assets/databases
"""
from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from database_specs import BY_NAME  # noqa: E402
from prepare_databases import collect_databases  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = ROOT / "app" / "lib" / "library_repository.dart"
TRIPLE = "'" * 3

failures: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    print(f"{'PASS' if condition else 'FAIL'} {label}{f' — {detail}' if detail else ''}")
    if not condition:
        failures.append(label)


def _string_literals(source: str):
    """Yield every string literal in a Dart file, in order.

    Triple-quoted SQL blocks contain single quotes (``COALESCE(x, '')``), so the
    scan has to consume a whole literal at a time instead of hunting for the
    nearest delimiter.
    """
    i = 0
    length = len(source)
    while i < length:
        char = source[i]
        if char == "/" and source.startswith("//", i):
            newline = source.find("\n", i)
            i = length if newline == -1 else newline + 1
            continue
        if char == "/" and source.startswith("/*", i):
            end = source.find("*/", i)
            i = length if end == -1 else end + 2
            continue
        if char in ("'", '"'):
            if source.startswith(char * 3, i):
                end = source.find(char * 3, i + 3)
                if end == -1:
                    return
                yield source[i + 3:end]
                i = end + 3
                continue
            cursor = i + 1
            closed = -1
            while cursor < length:
                if source[cursor] == "\\":
                    cursor += 2
                    continue
                if source[cursor] == char:
                    closed = cursor
                    break
                if source[cursor] == "\n":
                    break
                cursor += 1
            if closed == -1:
                i += 1
                continue
            yield source[i + 1:closed]
            i = closed + 1
            continue
        i += 1


def extract_query(fragment: str) -> str:
    """Return the Dart string literal that contains `fragment`, verbatim."""
    source = REPOSITORY.read_text(encoding="utf-8")
    for literal in _string_literals(source):
        if fragment in literal:
            return literal.strip()
    raise KeyError(f"statement not found in {REPOSITORY.name}: {fragment[:60]!r}")


def run(connection: sqlite3.Connection, fragment: str, params: tuple = ()) -> list:
    query = extract_query(fragment)
    try:
        return connection.execute(query, params).fetchall()
    except sqlite3.Error as exc:
        check(f"query near {fragment[:48]!r} executes", False, str(exc))
        return []


def hadith(connection: sqlite3.Connection) -> None:
    rows = run(
        connection,
        "WHERE LENGTH(COALESCE(p.txt, '')) > 0 OR LENGTH(COALESCE(p.mean, '')) > 0",
        (400, 0),
    )
    check("hadith: index query returns bilingual rows", len(rows) > 0, f"{len(rows)} rows in page 1")
    if not rows:
        return
    first = run(connection, "WHERE COALESCE(NULLIF(p.ID, ''), -p.rowid) = ?", (rows[0][0],))
    check("hadith: record lookup by ID", len(first) == 1)
    sections = run(connection, "WHERE p.Secid = ?", (rows[0][2],))
    check("hadith: section passages load", len(sections) > 0, f"{len(sections)} records")
    chapters = run(connection, "SELECT ID, cid, title FROM Chaps ORDER BY cid")
    check("hadith: chapter list", len(chapters) > 0, f"{len(chapters)} chapters")


def quran(connection: sqlite3.Connection) -> None:
    surahs = run(connection, "SELECT Id, Name, Nozol, Verse, revel FROM ChapterProperty ORDER BY Id")
    check("quran: surah list", len(surahs) == 114, f"{len(surahs)}")
    verses = run(connection, "WHERE q.chapter = ?", (2,))
    check("quran: al-Baqarah verses", len(verses) == 286, f"{len(verses)}")
    juz = run(connection, "WHERE q.juz = ?", (30,))
    check("quran: juz 30 verses", len(juz) > 500, f"{len(juz)}")
    page = run(connection, "WHERE q.page = ?", (1,))
    check("quran: mushaf page 1", len(page) == 7, f"{len(page)}")
    index = run(connection, "FROM (SELECT juz, MIN(ID) AS first_id FROM Quran GROUP BY juz) AS j")
    check("quran: juz index", len(index) == 30, f"{len(index)}")
    record = run(connection, "WHERE q.ID = ?", (1,))
    check("quran: verse lookup by ID", len(record) == 1 and bool(record[0][2]))
    # The reader used to show some verses as grey, unpainted blocks and the
    # complaint was "آیات لوڈ نہیں ہوئیں" — the data must never be the reason:
    # every verse carries Arabic text and a translation.
    empties = connection.execute(
        "SELECT COUNT(*) FROM Quran WHERE Arabic IS NULL OR trim(Arabic) = '' "
        "OR tr IS NULL OR trim(tr) = ''"
    ).fetchone()[0]
    check("quran: every verse has Arabic text and a translation", empties == 0, f"{empties} incomplete")
    mismatched = connection.execute(
        "SELECT COUNT(*) FROM ChapterProperty AS cp "
        "WHERE cp.Verse != (SELECT COUNT(*) FROM Quran AS q WHERE q.chapter = cp.Id)"
    ).fetchone()[0]
    check("quran: per-surah verse counts match the chapter table", mismatched == 0, f"{mismatched} differ")


def dua(connection: sqlite3.Connection) -> None:
    categories = run(connection, "FROM M_items GROUP BY M_cat_id ORDER BY M_cat_id")
    check("mafatih: six chapters", len(categories) == 6, f"{len(categories)}")
    items = run(connection, "WHERE m.M_cat_id = ?", (2,))
    check("mafatih: chapter items with line counts", len(items) > 0, f"{len(items)} items")
    featured = run(connection, "WHERE m.M_montakhab = 1 AND m.M_type = 1", (12,))
    check("mafatih: featured supplications", len(featured) > 0, f"{len(featured)}")
    leaf = next((row for row in items if row[3] == 1), None)
    check("mafatih: chapter contains readable items", leaf is not None)
    if leaf is None:
        return
    item = run(
        connection,
        "SELECT rowid AS row_id, _id, M_name, M_cat_id FROM M_items WHERE rowid = ?",
        (leaf[0],),
    )
    check("mafatih: item lookup by rowid", len(item) == 1)
    if not item:
        return
    lines = run(connection, "FROM Lines WHERE L_M_id = ?", (item[0][1],))
    check("mafatih: supplication lines", len(lines) > 0, f"{len(lines)} lines")
    # Line kinds drive the flowing dua layout: kind 1 must always carry the
    # Arabic dua text, kind 2 the Urdu instruction between segments. Exactly
    # one instruction row in the source is blank; the client drops it.
    no_arabic = connection.execute(
        "SELECT COUNT(*) FROM Lines WHERE L_type = 1 AND trim(L_text) = ''"
    ).fetchone()[0]
    check("mafatih: every dua line has Arabic text", no_arabic == 0, f"{no_arabic} blank")
    blank_guidance = connection.execute(
        "SELECT COUNT(*) FROM Lines WHERE L_type = 2 AND trim(L_text) = ''"
    ).fetchone()[0]
    check("mafatih: only the one known blank instruction row", blank_guidance == 1, f"{blank_guidance} blank")
    indexed = run(connection, "SELECT m.rowid AS record_id, m.M_name AS section_title", (400, 0))
    check(
        "mafatih: GROUP_CONCAT index query",
        len(indexed) > 0 and bool(indexed[0][4]),
        f"{len(indexed[0][4] or '')} characters of Arabic text for the first item",
    )


def balagha(connection: sqlite3.Connection) -> None:
    sections = run(connection, "FROM balaghatoc AS t\n      GROUP BY t.TypeID ORDER BY t.TypeID")
    check("balagha: five divisions", len(sections) == 5, f"{len(sections)}")
    entries = run(connection, "WHERE t.TypeID = ?", (1,))
    check("balagha: khutba entries", len(entries) == 238, f"{len(entries)}")
    # Introductions and footnotes are no longer loaded onto the matn page.
    # The type-5 prose query and the negative-id lookup were removed on purpose.
    source = REPOSITORY.read_text(encoding="utf-8")
    check(
        "balagha: matn page does not load type-5 prose",
        "FROM balaghatext_hawashi WHERE Type = 5 AND TypeNo = ?" not in source,
    )
    check(
        "balagha: a negative id is not a passage",
        "WHERE h.ID = ?" not in source and "if (recordId <= 0) return null;" in source,
    )
    main = run(connection, "WHERE x.Type = ? AND x.TypeNo = ?", (1, 3))
    check("balagha: khutba 3 paragraphs", len(main) > 10, f"{len(main)}")
    # The book's own typography comes from ParaFormat: 1 title, 2 text,
    # 3 sub-heading, 4 separator. The reader renders those roles and never
    # prints a "فقرا نمبر" label, so the roles have to be there.
    first = connection.execute(
        "SELECT ParaFormat FROM balaghatext WHERE Type = 1 AND TypeNo = 1 ORDER BY ParaNo LIMIT 1"
    ).fetchone()
    check("balagha: khutba 1 opens with a title row", first is not None and first[0] == 1)
    roles = dict(
        connection.execute(
            "SELECT ParaFormat, COUNT(*) FROM balaghatext WHERE Type = 1 AND TypeNo = 1 GROUP BY ParaFormat"
        ).fetchall()
    )
    check(
        "balagha: khutba 1 mixes text, sub-headings, separators",
        roles.get(2, 0) > 10 and roles.get(3, 0) > 0 and roles.get(4, 0) > 0,
        str(roles),
    )
    separators = connection.execute(
        "SELECT COUNT(*) FROM balaghatext WHERE ParaFormat = 4 AND trim(AR) LIKE '%٭%'"
    ).fetchone()[0]
    check("balagha: separator rows carry the ornament", separators > 100, f"{separators}")
    # Since 1.24 the reader loads an entry's notes in the book's own order and
    # never pairs them with a paragraph by number: `balaghatext_hawashi.ParaNo`
    # is the note's place in the footnote sequence (sermon 1 has 74 notes
    # numbered 1-75 above 30 paragraphs), so the same number on a paragraph is
    # a different thing entirely — that mismatch is what put a comment about
    # one passage under another.
    footnotes = run(
        connection,
        "FROM balaghatext_hawashi\n      WHERE Type = ? AND TypeNo = ? ORDER BY ID",
        (1, 3),
    )
    check("balagha: footnotes for khutba 3", len(footnotes) > 0, f"{len(footnotes)}")
    numbers = [
        row[0]
        for row in connection.execute(
            "SELECT ParaNo FROM balaghatext_hawashi WHERE Type = 1 AND TypeNo = 3 ORDER BY ID"
        )
    ]
    paragraphs = connection.execute(
        "SELECT COUNT(*) FROM balaghatext WHERE Type = 1 AND TypeNo = 3"
    ).fetchone()[0]
    check(
        "balagha: note numbers are a sequence, not paragraph ids",
        len(numbers) > 0
        and len(set(numbers)) == len(numbers)
        and numbers == sorted(numbers)
        and max(numbers) > paragraphs,
        f"{len(numbers)} notes numbered 1..{max(numbers)} over {paragraphs} paragraphs",
    )
    intro = run(connection, "FROM balaghatext_muqadamat WHERE Type = ?", (1,))
    check("balagha: section introduction", len(intro) > 10, f"{len(intro)}")
    lookup = run(connection, "WHERE x.ID = ?", (44,))
    check("balagha: paragraph lookup by ID", len(lookup) == 1)
    indexed = run(
        connection,
        "WHERE x.Type BETWEEN 1 AND 3\n          ORDER BY record_id",
        (20, 0),
    )
    check("balagha: search index is matn only", len(indexed) > 0 and all(1 <= row[4] <= 3 for row in indexed))
    # Negating a hawashi id can only be safe if both id spaces are positive.
    lowest = connection.execute(
        "SELECT (SELECT MIN(ID) FROM balaghatext), (SELECT MIN(ID) FROM balaghatext_hawashi)"
    ).fetchone()
    check(
        "balagha: paragraph and footnote id spaces are positive",
        lowest is not None and min(lowest[0], lowest[1]) > 0,
        f"min balaghatext.ID={lowest[0]}, min hawashi.ID={lowest[1]}",
    )


def sahifa(connection: sqlite3.Connection) -> None:
    """The reader shows the book's 83 supplications and nothing else."""
    query = extract_query("SELECT d.ID AS record_id, d.t_id * 10000")
    rows = connection.execute(
        f"SELECT section_id, section_title, container_type, container_id FROM ({query})"
    ).fetchall()
    check("sahifa: supplication rows load", len(rows) > 0, f"{len(rows)} rows")
    supplications = {row[0] for row in rows}
    # 54 duas of Sahifa Sajjadiyya + 7 "مزید دعائیں" + 7 weekday duas +
    # 15 Munajat Khamsa Ashar = 83. The rest of saheefa_data is site furniture
    # (biography, lecture videos, quizzes) that must never be listed as a dua.
    check(
        "sahifa: exactly the 83 supplications of the book",
        len(supplications) == 83,
        f"{len(supplications)} distinct supplications",
    )
    types = sorted({row[2] for row in rows})
    check(
        "sahifa: nothing from the site's extra sections",
        set(types) <= {1, 2, 3, 4},
        f"t_id values present: {types}",
    )
    unnamed = [row for row in rows if not row[1] or row[1].startswith("حصہ ")]
    check(
        "sahifa: every supplication has its title from the index",
        not unnamed,
        f"{len(unnamed)} rows fell back to a placeholder title",
    )


def fatwa(name: str):
    """Every ruling keeps the official page it was taken from."""

    def check_book(connection: sqlite3.Connection) -> None:
        query = extract_query("SELECT q.rowid AS record_id, q.category_id AS section_id")
        rows = connection.execute(
            f"SELECT source_url, source_ref, urdu FROM ({query})"
        ).fetchall()
        check(f"fatwa ({name}): answers load", len(rows) > 0, f"{len(rows)} answers")
        if not rows:
            return
        broken = [row for row in rows if not str(row[0] or "").startswith("https://")]
        check(
            f"fatwa ({name}): every answer links to its source page",
            not broken,
            f"{len(broken)} answers without an https source_url",
        )
        without_ref = [row for row in rows if not str(row[1] or "").strip()]
        check(
            f"fatwa ({name}): answers carry the publisher's reference",
            not without_ref,
            f"{len(without_ref)} answers without a source_ref",
        )
        empty = [row for row in rows if not str(row[2] or "").strip()]
        check(
            f"fatwa ({name}): every answer has question and answer text",
            not empty,
            f"{len(empty)} blank answers",
        )

    return check_book


def encyclopedia(connection: sqlite3.Connection) -> None:
    """The encyclopaedia reads exactly like the other books."""
    groups = connection.execute(
        "SELECT title_ur, sort_order, article_count FROM groups ORDER BY sort_order"
    ).fetchall()
    check("encyclopedia: ten curated chapters", len(groups) == 10, f"{len(groups)}")
    check(
        "encyclopedia: every chapter has articles",
        all((row[2] or 0) > 0 for row in groups),
        f"{[row[2] for row in groups]}",
    )
    check(
        "encyclopedia: chapters are in a deliberate reading order",
        [row[1] for row in groups] == sorted(row[1] for row in groups),
        str([row[1] for row in groups]),
    )
    # One article rendered as its ordered sections, which is what the reader
    # shows and every source chip is attached to.
    article = connection.execute(
        "SELECT a.id, a.title_ur FROM articles AS a ORDER BY a.character_count DESC LIMIT 1"
    ).fetchone()
    sections = connection.execute(
        f"SELECT record_id, section_id, urdu, locator, source_url, article_url, ordinal "
        f"FROM ({extract_query('s.heading_ur AS locator')})",
        (article[0],),
    ).fetchall()
    check("encyclopedia: an article opens as ordered sections", len(sections) >= 1, f"{len(sections)} sections")
    ordered = [row[6] for row in sections]
    check("encyclopedia: sections arrive in reading order", ordered == sorted(ordered), str(ordered[:8]))
    with_text = [row for row in sections if str(row[2] or "").strip()]
    check(
        "encyclopedia: every section carries Urdu text",
        len(with_text) == len(sections),
        f"{len(sections) - len(with_text)} blank",
    )
    # The reader falls back from the section URL to the article URL.
    sourced = [row for row in sections if str(row[4] or row[5] or "").startswith("https://")]
    check(
        "encyclopedia: every section can open its source",
        len(sourced) == len(sections),
        f"{len(sections) - len(sourced)} without a URL",
    )
    imams = run(connection, "FROM imams AS i JOIN articles AS a ON a.id = i.article_id\n        ORDER BY i.imam_number")
    check("encyclopedia: twelve Imam biographies", len(imams) == 12, f"{len(imams)}")
    topics = run(connection, "FROM topics AS t JOIN articles AS a ON a.id = t.article_id\n        ORDER BY t.id")
    check("encyclopedia: curated topics resolve to articles", len(topics) >= 5, f"{len(topics)}")
    # The small «ماخذ» chip must have a real page for every reference it shows.
    # Since 1.20 the encyclopaedia also carries the Wikishia topic notes, and
    # some of the pages those notes cite are only served over plain HTTP. Every
    # reference must still be a real page, so an http(s) URL is what is pinned.
    blank_refs = connection.execute(
        "SELECT COUNT(*) FROM source_references "
        "WHERE source_url NOT LIKE 'https://%' AND source_url NOT LIKE 'http://%'"
    ).fetchone()[0]
    check("encyclopedia: references keep their permanent URLs", blank_refs == 0, f"{blank_refs} without a URL")
    # Every article must give the reader at least one paragraph and one ماخذ.
    empty_articles = connection.execute(
        "SELECT COUNT(*) FROM articles a WHERE NOT EXISTS "
        "(SELECT 1 FROM sections s WHERE s.article_id = a.id AND LENGTH(TRIM(s.plain_text)) > 0)"
    ).fetchone()[0]
    check("encyclopedia: no article is an empty shell", empty_articles == 0, f"{empty_articles} empty articles")
    # «مزید پڑھیں» only ever points at an article that exists in this edition.
    dangling = connection.execute(
        "SELECT COUNT(*) FROM related_articles WHERE target_article_id IS NOT NULL "
        "AND target_article_id NOT IN (SELECT id FROM articles)"
    ).fetchone()[0]
    check("encyclopedia: related links resolve", dangling == 0, f"{dangling} dangling links")
    # The builder already strips wiki furniture; guard the reader against it.
    furniture = connection.execute(
        "SELECT COUNT(*) FROM sections WHERE plain_text LIKE '%{{%' "
        "OR plain_text LIKE '%[[%' OR plain_text LIKE '%]]' "
        "OR plain_text LIKE '%==%' OR plain_text LIKE '%|'"
    ).fetchone()[0]
    check("encyclopedia: no wiki markup reaches the reader", furniture == 0, f"{furniture} sections")


def build_index(paths: dict[str, Path]) -> sqlite3.Connection:
    """Recreate the on-device search index (search_docs + FTS5) in memory."""
    index = sqlite3.connect(":memory:")
    index.execute(
        extract_query("CREATE TABLE IF NOT EXISTS search_docs").replace(
            "CREATE TABLE IF NOT EXISTS", "CREATE TABLE"
        )
    )
    index.execute(
        "CREATE VIRTUAL TABLE search_fts USING fts5("
        "chapter_title, section_title, arabic, urdu, content='', "
        "tokenize='unicode61 remove_diacritics 0')"
    )
    fragments = {
        "alkafi": "WHERE LENGTH(COALESCE(p.txt, '')) > 0 OR LENGTH(COALESCE(p.mean, '')) > 0",
        "quran": "FROM Quran AS q\n          LEFT JOIN ChapterProperty AS cp ON cp.Id = q.chapter\n          ORDER BY q.ID",
        "mafatih": "SELECT m.rowid AS record_id, m.M_name AS section_title",
        "nahjul_balagha": "WHERE x.Type BETWEEN 1 AND 3\n          ORDER BY record_id",
        "sahifa": "SELECT d.ID AS record_id, d.t_id * 10000",
        "sistani": "SELECT q.rowid AS record_id, q.category_id AS section_id",
        "athna_ashari_encyclopedia": "FROM sections AS s JOIN articles AS a ON a.id = s.article_id\n          ORDER BY s.article_id, s.ordinal",
    }
    total = 0
    for source_key, fragment in fragments.items():
        query = extract_query(fragment)
        connection = sqlite3.connect(f"file:{paths[source_key]}?mode=ro", uri=True)
        try:
            if source_key in {"sahifa", "sistani"}:
                query = f"SELECT * FROM ({query}) ORDER BY record_id LIMIT ? OFFSET ?"
            cursor = connection.execute(query, (100000, 0))
            columns = [description[0] for description in cursor.description]
            rows = cursor.fetchall()
        finally:
            connection.close()
        for row in rows:
            total += 1
            record = dict(zip(columns, row))
            arabic = str(record.get("arabic") or "")
            urdu = str(record.get("urdu") or "")
            title = str(record.get("section_title") or record.get("surah_name") or "")
            index.execute(
                "INSERT INTO search_docs (id, book, record_id, chapter_title, section_title, "
                "container_type, container_id, norm_text) VALUES (?,?,?,?,?,?,?,?)",
                (
                    total,
                    source_key,
                    record.get("record_id"),
                    title,
                    title,
                    record.get("container_type"),
                    record.get("container_id"),
                    f"{arabic} {urdu}".lower(),
                ),
            )
            index.execute(
                "INSERT INTO search_fts(rowid, chapter_title, section_title, arabic, urdu) "
                "VALUES (?,?,?,?,?)",
                (total, title, title, arabic, urdu),
            )
    check("index: rows written from every source", total > 1000, f"{total} rows")
    return index


def search_probe(index: sqlite3.Connection) -> None:
    probes = (
        ('"الحسين"*', "Arabic hadith term"),
        ('"نماز"*', "Urdu term"),
    )
    for expression, label in probes:
        rows = index.execute(
            "SELECT d.book, d.record_id FROM search_fts "
            "JOIN search_docs AS d ON d.id = search_fts.rowid "
            "WHERE search_fts MATCH ? ORDER BY bm25(search_fts) LIMIT 5",
            (expression,),
        ).fetchall()
        check(f"search: FTS5 finds {label}", len(rows) > 0, f"{len(rows)} hits, first: {rows[:2]}")


def run_checks(paths: dict[str, Path]) -> None:
    needed = ("alkafi", "quran", "mafatih", "nahjul_balagha", "athna_ashari_encyclopedia")
    missing = [key for key in needed if key not in paths]
    if missing:
        raise SystemExit(f"Missing databases for client SQL check: {missing}")

    for key, checks in (
        ("alkafi", hadith),
        ("quran", quran),
        ("mafatih", dua),
        ("nahjul_balagha", balagha),
        ("sahifa", sahifa),
        ("sistani", fatwa("sistani")),
        ("athna_ashari_encyclopedia", encyclopedia),
    ):
        connection = sqlite3.connect(f"file:{paths[key]}?mode=ro", uri=True)
        try:
            checks(connection)
        finally:
            connection.close()

    index = build_index(paths)
    search_probe(index)
    index.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database-dir", type=Path, default=None)
    args = parser.parse_args()

    if not REPOSITORY.is_file():
        raise SystemExit(f"{REPOSITORY} not found")

    if args.database_dir:
        paths = {
            spec.key: args.database_dir / spec.name
            for spec in BY_NAME.values()
            if (args.database_dir / spec.name).is_file()
        }
        run_checks(paths)
    else:
        with collect_databases() as collected:
            run_checks({spec.key: path for spec, path in collected})

    if failures:
        raise SystemExit(f"{len(failures)} client SQL check(s) failed: {', '.join(failures)}")
    print("All client SQL checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

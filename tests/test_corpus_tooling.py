"""Unit tests for the corpus packaging tools (no Flutter or network needed)."""
from __future__ import annotations

import hashlib
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from database_specs import (  # noqa: E402
    DATABASES,
    EXTRA_DATABASES,
    MANIFEST_PATH,
    TARGET_PAGE_SIZE,
)
import prepare_databases  # noqa: E402


class DatabaseSpecTests(unittest.TestCase):
    def test_catalogue_covers_twenty_two_databases(self):
        self.assertEqual(len(DATABASES), 22)
        self.assertEqual(len([spec for spec in DATABASES if spec.source == "hadith"]), 14)
        # 8 curated standalones (Quran, Mafatih, Sahifa, the three marjas,
        # the encyclopaedia and Najafi) — 14 hadith books + 8 = 22.
        self.assertEqual(len(EXTRA_DATABASES), 8)

    def test_keys_and_file_names_are_unique(self):
        keys = [spec.key for spec in DATABASES]
        names = [spec.name for spec in DATABASES]
        self.assertEqual(len(set(keys)), len(keys))
        self.assertEqual(len(set(names)), len(names))

    def test_new_collections_declare_reader_indexes(self):
        for spec in EXTRA_DATABASES:
            with self.subTest(spec.name):
                self.assertTrue(spec.indexes, f"{spec.name} has no reader indexes")
                for statement in spec.indexes:
                    self.assertIn("shia_", statement)
                    self.assertIn("IF NOT EXISTS", statement)

    def test_page_size_matches_the_original_corpus(self):
        self.assertEqual(TARGET_PAGE_SIZE, 1024)


class HadithOrphanBaselineTests(unittest.TestCase):
    """Four books carry paragraphs whose section id has no Sections row.

    They are part of the original data, not damage: the client reads paragraphs
    with a LEFT JOIN, so all 20 stay searchable. ``scripts/verify_corpus.py``
    compares the live count against this baseline, so pin it here too.
    """

    def test_baseline_is_pinned_to_twenty_rows(self) -> None:
        from verify_corpus import KNOWN_SECTION_ORPHANS

        self.assertEqual(
            KNOWN_SECTION_ORPHANS,
            {"hidaya": 6, "imam": 1, "manlahyahzur": 3, "wasail": 10},
        )
        self.assertEqual(sum(KNOWN_SECTION_ORPHANS.values()), 20)

    def test_client_keeps_orphans_readable(self) -> None:
        """The indexed hadith query must be a LEFT JOIN, not an inner join."""
        repository = (ROOT / "app" / "lib" / "library_repository.dart").read_text(
            encoding="utf-8"
        )
        for statement in (
            "FROM Parags AS p\n          LEFT JOIN Sections AS s ON s.Secid = p.Secid",
            "chapter: chapter.isEmpty ? book.titleUrdu : chapter",
        ):
            self.assertIn(statement, repository)


class ManifestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))

    def test_manifest_is_version_two_and_complete(self):
        self.assertEqual(self.manifest["format_version"], 2)
        self.assertEqual(self.manifest["database_count"], 22)
        self.assertEqual(len(self.manifest["databases"]), 22)

    def test_every_entry_carries_a_digest_and_titles(self):
        for entry in self.manifest["databases"]:
            with self.subTest(entry["name"]):
                self.assertEqual(len(entry["sha256"]), 64)
                self.assertGreater(entry["size_bytes"], 0)
                self.assertTrue(entry["title_urdu"])
                self.assertTrue(entry["title_latin"])
                self.assertTrue(entry["records"])

    def test_totals_match_the_known_corpus(self):
        totals = self.manifest["totals"]
        self.assertEqual(totals["hadith_records"], 96513)
        self.assertEqual(totals["sections"], 17855)
        self.assertEqual(totals["chapters"], 845)
        self.assertEqual(totals["quran_verses"], 6236)
        self.assertEqual(totals["quran_surahs"], 114)
        self.assertEqual(totals["dua_items"], 677)
        self.assertEqual(totals["balagha_paragraphs"], 3742)
        self.assertEqual(totals["sahifa_rows"], 2103)

    def test_asset_names_match_what_the_app_requests(self):
        """`<name>` + `<extension>` must equal the file publish_databases.py writes."""
        from prepare_databases import DOWNLOAD_EXTENSION

        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        self.assertEqual(DOWNLOAD_EXTENSION, ".gz")
        self.assertEqual(manifest["download"]["extension"], DOWNLOAD_EXTENSION)
        for entry in manifest["databases"]:
            self.assertTrue(entry["name"].endswith((".db", ".sqlite", ".sqlite3")), entry["name"])
            # publish_databases.py writes f"{spec.name}.gz" into dist/.
            self.assertEqual(entry["name"] + DOWNLOAD_EXTENSION, f"{entry['name']}.gz")

    def test_download_settings_are_absolute_https_urls(self):
        download = self.manifest["download"]
        self.assertEqual(download["extension"], ".gz")
        self.assertIn("/databases-v2/", download["base_urls"][0])
        self.assertIn("/databases-v1/", download["base_urls"][1])
        for url in download["base_urls"]:
            with self.subTest(url):
                self.assertTrue(url.startswith("https://"))
                self.assertTrue(url.endswith("/"))

    def test_app_bundle_carries_the_same_manifest(self):
        bundled = ROOT / "app" / "assets" / "database-manifest.json"
        self.assertTrue(bundled.is_file(), "run prepare_databases.py --write-manifest")
        self.assertEqual(
            json.loads(bundled.read_text(encoding="utf-8")),
            self.manifest,
        )

    def test_replacement_books_are_bundled_with_manifest_hashes(self):
        app_assets = ROOT / "app" / "assets" / "databases"
        by_name = {entry["name"]: entry for entry in self.manifest["databases"]}
        for name in ("mafatihdb-v4.db", "Sahifa_Sajjadiyya_full_runtime.sqlite3"):
            with self.subTest(name):
                path = app_assets / name
                self.assertTrue(path.is_file(), f"{name} must be bundled for offline migration")
                digest = hashlib.sha256(path.read_bytes()).hexdigest()
                self.assertEqual(digest, by_name[name]["sha256"])


class ValidationTests(unittest.TestCase):
    """The three standalone collections are checked in, so validate them here."""

    def test_standalone_databases_open_and_match_their_spec(self):
        # collect_databases() expands the gzipped encyclopaedia edition into a
        # scratch copy, exactly as the release pipeline does.
        with prepare_databases.collect_databases(include_bundle=False) as collected:
            for spec, path in collected:
                with self.subTest(spec.name):
                    counts = prepare_databases.validate_database(path, spec)
                    self.assertEqual(set(counts), set(spec.tables))
                    for table, count in counts.items():
                        self.assertGreater(count, 0, f"{spec.name}.{table} is empty")

    def test_standalone_databases_use_the_shared_page_size(self):
        import sqlite3

        with prepare_databases.collect_databases(include_bundle=False) as collected:
            for spec, path in collected:
              with self.subTest(spec.name):
                connection = sqlite3.connect(f"file:{path.resolve().as_posix()}?mode=ro", uri=True)
                try:
                    self.assertEqual(
                        connection.execute("PRAGMA page_size").fetchone()[0],
                        # safiha/fatwa are the publisher's own files; the
                        # encyclopaedia edition is built from a 79 MB corpus
                        # whose pages are kept at 4 KiB (1 KiB pages would
                        # inflate it), like the other large collections.
                        4096 if spec.source in {"sahifa", "fatwa", "encyclopedia"} else TARGET_PAGE_SIZE
                    )
                    self.assertEqual(
                        str(connection.execute("PRAGMA encoding").fetchone()[0]).lower(), "utf-8"
                    )
                    self.assertEqual(connection.execute("PRAGMA quick_check").fetchone()[0], "ok")
                    indexes = {
                        row[0]
                        for row in connection.execute(
                            "SELECT name FROM sqlite_master WHERE type = 'index'"
                        )
                    }
                    # Uploaded databases stay byte-for-byte intact; their
                    # reader indexes are added to the app-storage copy at install.
                    for statement in (() if spec.source in {"sahifa", "fatwa"} else spec.indexes):
                        name = statement.split("shia_", 1)[1].split(" ")[0]
                        self.assertIn(f"shia_{name}", indexes)
                finally:
                    connection.close()

    def test_manifest_accepts_the_files_on_disk(self):
        with prepare_databases.collect_databases(include_bundle=False) as collected:
            records = prepare_databases.build_records(collected)
        self.assertEqual(len(records), len(EXTRA_DATABASES))
        prepare_databases.verify_against_manifest(records)

    def test_manifest_rejects_a_wrong_checksum(self):
        tampered = [
            {
                "name": "quran.db",
                "records": {"Quran": 6236},
                "sha256": "0" * 64,
            }
        ]
        with self.assertRaises(prepare_databases.DatabaseBundleError):
            prepare_databases.verify_against_manifest(tampered)

    def test_manifest_rejects_an_unknown_database(self):
        with self.assertRaises(prepare_databases.DatabaseBundleError):
            prepare_databases.verify_against_manifest(
                [{"name": "not-a-book.db", "records": {}, "sha256": "0" * 64}]
            )


class ReleaseManifestTests(unittest.TestCase):
    def test_release_manifest_is_pure_ascii_with_identical_content(self):
        """The published manifest must survive Latin-1 decoding unscathed.

        GitHub serves release assets without a charset, so clients may decode
        the bytes as Latin-1. The release copy therefore uses \\uXXXX escapes:
        single-byte decodings leave it untouched and JSON parsers restore the
        original Urdu text.
        """
        import tempfile

        import publish_databases

        source = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as tmp:
            destination = Path(tmp) / "database-manifest.json"
            publish_databases.write_release_manifest(MANIFEST_PATH, destination)
            raw = destination.read_bytes()
        raw.decode("ascii")  # raises unless every byte is ASCII
        self.assertEqual(json.loads(raw), source)
        # Exactly what a charset-less HTTP client would hand the JSON parser:
        self.assertEqual(json.loads(raw.decode("latin-1")), source)


if __name__ == "__main__":
    unittest.main()


class SelectedEncyclopediaTests(unittest.TestCase):
    """The reader edition is built from «اثنا عشری انسائکلوپیڈیا (منتخب).zip».

    1.21 dropped the Wikishia topic notes that 1.20 had merged in: the app must
    show the selected Urdu-Wikipedia corpus alone, and every «ماخذ» link must be
    a ur.wikipedia.org revision of that corpus.
    """

    @classmethod
    def setUpClass(cls):
        import gzip
        import sqlite3
        import tempfile

        cls._directory = tempfile.TemporaryDirectory(prefix="shiaverse-enc-")
        database = Path(cls._directory.name) / "encyclopedia.db"
        with gzip.open(ROOT / "assets" / "athna_ashari_encyclopedia.db.gz", "rb") as packed:
            database.write_bytes(packed.read())
        cls.db = sqlite3.connect(f"file:{database.as_posix()}?mode=ro", uri=True)
        cls.db.row_factory = sqlite3.Row

    @classmethod
    def tearDownClass(cls):
        cls.db.close()
        cls._directory.cleanup()

    def test_article_count_is_the_selected_corpus(self):
        articles = self.db.execute("SELECT COUNT(*) FROM articles").fetchone()[0]
        self.assertEqual(articles, 574)

    def test_every_section_keeps_a_wikipedia_revision_url(self):
        rows = self.db.execute(
            "SELECT COUNT(*) FROM sections WHERE source_url LIKE 'https://ur.wikipedia.org/%'"
        ).fetchone()[0]
        total = self.db.execute("SELECT COUNT(*) FROM sections").fetchone()[0]
        self.assertEqual(rows, total)
        blank = self.db.execute("SELECT COUNT(*) FROM sections WHERE source_url = ''").fetchone()[0]
        self.assertEqual(blank, 0)

    def test_no_wikishia_material_survives(self):
        sections = self.db.execute(
            "SELECT COUNT(*) FROM sections WHERE source_url LIKE '%wikishia%'"
        ).fetchone()[0]
        references = self.db.execute(
            "SELECT COUNT(*) FROM source_references WHERE source_url LIKE '%wikishia%'"
        ).fetchone()[0]
        self.assertEqual(sections + references, 0)
        # «مرجع تقلید» arrived only with the retired notes.
        row = self.db.execute(
            "SELECT COUNT(*) FROM articles WHERE title_ur = 'مرجع تقلید'"
        ).fetchone()[0]
        self.assertEqual(row, 0)

    def test_a_central_article_is_still_readable(self):
        article = self.db.execute(
            "SELECT id, group_id FROM articles WHERE title_ur = 'حسین بن علی'"
        ).fetchone()
        self.assertIsNotNone(article)
        sections = self.db.execute(
            "SELECT COUNT(*) FROM sections WHERE article_id = ?", (article["id"],)
        ).fetchone()[0]
        self.assertGreater(sections, 0)
        hosts = {
            row[0]
            for row in self.db.execute(
                "SELECT DISTINCT rtrim(substr(source_url, 1, instr(source_url, '/w/')), '/') "
                "FROM sections WHERE article_id = ?",
                (article["id"],),
            )
        }
        self.assertEqual(hosts, {"https://ur.wikipedia.org"})

    def test_related_links_never_dangle(self):
        dangling = self.db.execute(
            "SELECT COUNT(*) FROM related_articles WHERE target_article_id IS NOT NULL "
            "AND target_article_id NOT IN (SELECT id FROM articles)"
        ).fetchone()[0]
        self.assertEqual(dangling, 0)

    def test_group_counts_match_the_articles(self):
        for row in self.db.execute(
            "SELECT g.id, g.article_count, COUNT(a.id) AS actual FROM groups g "
            "LEFT JOIN articles a ON a.group_id = g.id GROUP BY g.id"
        ):
            self.assertEqual(row["article_count"], row["actual"])


class RevisedNahjTests(unittest.TestCase):
    """1.20 replaced the Nahj al-Balagha corpus with the newly uploaded one."""

    def test_uploaded_translation_is_in_place(self):
        import sqlite3

        connection = sqlite3.connect(
            f"file:{(ROOT / 'assets' / 'nahjul_balagha.db').as_posix()}?mode=ro", uri=True
        )
        try:
            urdu = connection.execute("SELECT UR FROM balaghatext WHERE ID = 2").fetchone()[0]
            # The uploaded file's translation of the second paragraph; the
            # previous corpus started the same sentence differently.
            self.assertIn("جس میں آپ نے", urdu)
            self.assertEqual(
                connection.execute("SELECT COUNT(*) FROM balaghatext").fetchone()[0], 3742
            )
            self.assertEqual(
                connection.execute("PRAGMA page_size").fetchone()[0], 1024
            )
        finally:
            connection.close()

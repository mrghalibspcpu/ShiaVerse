"""Replay every page of the actual Dart index queries against ALL 20 books."""
import sqlite3
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from prepare_databases import collect_databases
from verify_client_sql import extract_query


class FullSearchCoverageTests(unittest.TestCase):
    def test_every_book_is_indexed_to_its_last_record(self):
        fragments = {
            'hadith': "WHERE LENGTH(COALESCE(p.txt, '')) > 0 OR LENGTH(COALESCE(p.mean, '')) > 0",
            'quran': 'FROM Quran AS q\n          LEFT JOIN ChapterProperty AS cp ON cp.Id = q.chapter\n          ORDER BY q.ID',
            'dua': 'SELECT m.rowid AS record_id, m.M_name AS section_title',
            'balagha': 'WHERE x.Type BETWEEN 1 AND 3\n          ORDER BY record_id',
            'sahifa': 'SELECT d.ID AS record_id, d.t_id * 10000',
            'fatwa': 'SELECT q.rowid AS record_id, q.category_id AS section_id',
            'encyclopedia': 'FROM sections AS s JOIN articles AS a ON a.id = s.article_id\n          ORDER BY s.article_id, s.ordinal',
        }
        with collect_databases() as collected:
            self.assertEqual(len(collected), 21)
            for spec, path in collected:
                with self.subTest(book=spec.key), sqlite3.connect(path) as db:
                    query = extract_query(fragments[spec.source])
                    if spec.source in {'sahifa', 'fatwa'}:
                        query = f'SELECT * FROM ({query}) ORDER BY record_id LIMIT ? OFFSET ?'
                    expected = sum(db.execute(f'SELECT COUNT(*) FROM "{t}"').fetchone()[0]
                                   for t in ({'hadith': ['Parags'], 'quran': ['Quran'], 'dua': ['M_items'],
                                              'balagha': ['balaghatext'],
                                              'sahifa': ['saheefa_data'], 'fatwa': ['question_answers'],
                                              'encyclopedia': ['sections']}[spec.source]))
                    if spec.source == 'hadith':
                        expected = db.execute("SELECT COUNT(*) FROM Parags WHERE LENGTH(COALESCE(txt,''))>0 OR LENGTH(COALESCE(mean,''))>0").fetchone()[0]
                    elif spec.source == 'balagha':
                        expected = db.execute(
                            "SELECT COUNT(*) FROM balaghatext WHERE Type BETWEEN 1 AND 3"
                        ).fetchone()[0]
                    elif spec.source == 'sahifa':
                        # Only the book's 83 supplications are indexed; the
                        # remaining t_id values are site furniture.
                        expected = db.execute(
                            "SELECT COUNT(*) FROM saheefa_data WHERE t_id IN (1, 2, 3, 4)"
                        ).fetchone()[0]
                    seen = set()
                    for offset in range(0, expected, 400):
                        rows = db.execute(query, (400, offset)).fetchall()
                        self.assertEqual(len(rows), min(400, expected - offset))
                        for row in rows:
                            self.assertNotIn(row[0], seen, 'duplicate identity or unstable paging')
                            seen.add(row[0])
                    self.assertEqual(len(seen), expected)
                    self.assertEqual(db.execute(query, (400, expected)).fetchall(), [])
                    if spec.source == 'quran':
                        self.assertEqual(len(seen), 6236)
                        self.assertIn(db.execute('SELECT ID FROM Quran WHERE chapter=114 AND verse=6').fetchone()[0], seen)
                    elif spec.source == 'fatwa':
                        self.assertEqual(
                            len(seen),
                            {'sistani': 1619, 'najafi': 8104}[spec.key],
                        )
                    elif spec.source == 'sahifa':
                        # The 1.28 Drive edition (Sahifa_Sajjadiyya_83_duas)
                        # carries only the 83 supplications themselves:
                        # 2,103 Arabic/Urdu rows and nothing else.
                        self.assertEqual(len(seen), 2103)
                        self.assertEqual(
                            db.execute("SELECT COUNT(DISTINCT t_id * 10000 + t_no) FROM saheefa_data "
                                       "WHERE t_id IN (1, 2, 3, 4)").fetchone()[0],
                            83,
                        )
                        self.assertEqual(
                            {r[0] for r in db.execute(
                                'SELECT DISTINCT oe FROM saheefa_data WHERE t_id IN (1, 2, 3, 4)')},
                            {'a', 'u'},
                        )

    def test_all_6236_verses_and_last_juz_are_available_to_paginated_search(self):
        with sqlite3.connect(ROOT / 'assets/quran.db') as db:
            query = extract_query('FROM Quran AS q\n          LEFT JOIN ChapterProperty AS cp ON cp.Id = q.chapter\n          ORDER BY q.ID')
            db.row_factory = sqlite3.Row
            rows = db.execute(query, (10000, 0)).fetchall()
            db.execute('CREATE TEMP TABLE docs(id INTEGER PRIMARY KEY, body TEXT)')
            db.executemany('INSERT INTO docs VALUES (?,?)', [(r['record_id'], r['urdu']) for r in rows])
            total = db.execute("SELECT COUNT(*) FROM docs WHERE body LIKE '%اللہ%'").fetchone()[0]
            self.assertGreater(total, 40)
            seen = []
            for offset in range(0, total, 40):
                seen.extend(r[0] for r in db.execute("SELECT id FROM docs WHERE body LIKE '%اللہ%' ORDER BY id LIMIT ? OFFSET ?", (40, offset)))
            self.assertEqual(len(set(seen)), total)
            last_juz_matches = {r[0] for r in db.execute("SELECT ID FROM Quran WHERE juz=30 AND tr LIKE '%اللہ%'")}
            self.assertTrue(last_juz_matches)
            self.assertTrue(last_juz_matches.issubset(set(seen)))

    def test_reader_preserves_lazy_list_and_target_highlight(self):
        quran = (ROOT / 'app/lib/screens/quran_screen.dart').read_text()
        self.assertIn('ScrollablePositionedList.builder', quran)
        self.assertNotIn('SingleChildScrollView', quran)
        self.assertNotIn('_verseKeys', quran)
        self.assertIn('initialScrollIndex: _initialIndex', quran)
        self.assertIn('focusMatch: verse.recordId == widget.initialRecordId', quran)
        self.assertIn('parseReaderNumber(controller.text)', quran)

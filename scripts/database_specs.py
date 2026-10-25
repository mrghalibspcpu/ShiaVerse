#!/usr/bin/env python3
"""Single source of truth describing every SQLite database shipped with the app.

Both the 14 hadith books (delivered inside ``assets/shia-databases.zip``) and the
three standalone collections (Quran, Mafatih al-Jinan, Nahj al-Balagha) are
described here so that packaging, verification, and the Flutter catalog cannot
drift apart.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT / "assets" / "shia-databases.zip"
EXTRA_DIR = ROOT / "assets"
MANIFEST_PATH = ROOT / "assets" / "database-manifest.json"
# Copy bundled with the APK so the client can verify downloads offline.
APP_MANIFEST_PATH = ROOT / "app" / "assets" / "database-manifest.json"

# SQLite page size used by the original 14-book corpus. The three standalone
# collections are rebuilt with the same setting so every bundled file behaves
# identically on the device.
TARGET_PAGE_SIZE = 1024


@dataclass(frozen=True)
class DatabaseSpec:
    """Validation rules for one SQLite file."""

    name: str
    source: str
    key: str
    title_urdu: str
    title_latin: str
    origin: str  # "bundle" (inside the zip) or "assets" (checked in directly)
    tables: dict[str, set[str]] = field(default_factory=dict)
    indexes: tuple[str, ...] = ()
    record_label: str = "حدیث نمبر"

    @property
    def asset_path(self) -> Path:
        return EXTRA_DIR / self.name

    @property
    def packed_path(self) -> Path:
        """The gzipped copy committed for large files (the encyclopaedia edition)."""
        return EXTRA_DIR / f"{self.name}.gz"


HADITH_TABLES: dict[str, set[str]] = {
    "Parags": {"ID", "txt", "Secid", "paganum", "mean"},
    "Sections": {"ID", "title", "Chapid", "Secid"},
    "Chaps": {"ID", "cid", "title", "bookid"},
}

QURAN_INDEXES = (
    "CREATE INDEX IF NOT EXISTS shia_quran_record ON Quran(ID)",
    "CREATE INDEX IF NOT EXISTS shia_quran_chapter_verse ON Quran(chapter, verse)",
    "CREATE INDEX IF NOT EXISTS shia_quran_juz ON Quran(juz)",
    "CREATE INDEX IF NOT EXISTS shia_quran_page ON Quran(page)",
    "CREATE INDEX IF NOT EXISTS shia_quran_surah ON ChapterProperty(Id)",
)

MAFATIH_INDEXES = (
    "CREATE INDEX IF NOT EXISTS shia_mafatih_items_order ON M_items(M_cat_id, M_type, M_prio)",
    "CREATE INDEX IF NOT EXISTS shia_mafatih_lines_item ON Lines(L_M_id, L_prio)",
    "CREATE INDEX IF NOT EXISTS shia_mafatih_lines_record ON Lines(_id)",
)

BALAGHA_INDEXES = (
    "CREATE INDEX IF NOT EXISTS shia_balagha_text_locate ON balaghatext(Type, TypeNo, ParaNo)",
    "CREATE INDEX IF NOT EXISTS shia_balagha_toc_type ON balaghatoc(TypeID, TypeNo)",
    "CREATE INDEX IF NOT EXISTS shia_balagha_hawashi_locate ON balaghatext_hawashi(Type, TypeNo, ParaNo)",
    "CREATE INDEX IF NOT EXISTS shia_balagha_muqadamat_type ON balaghatext_muqadamat(Type, ParaFormat, ID)",
)

HADITH_BOOKS: tuple[tuple[str, str, str], ...] = (
    ("Tahzeeb.db", "تہذیب الاحکام", "Tahdhib al-Ahkam"),
    ("alkafi.db", "الکافی", "Al-Kafi"),
    ("alkhisal.db", "الخصال", "Al-Khisal"),
    ("hakam.db", "غرر الحکم", "Ghurar al-Hikam"),
    ("hidaya.db", "ہدایۃ العلم", "Hidayat al-Ilm"),
    ("hikmatprophet.db", "حکمت نامۂ رسول اکرم(ص)", "Hikmat-nama Rasul Akram (s)"),
    ("imam.db", "حکمت نامہ امام حسین(ع)", "Hikmat-nama Imam Husain (a)"),
    ("kamaledeen.db", "کمال الدین و تمام النعمة", "Kamal al-Din"),
    ("maniakbar.db", "معانی الاخبار", "Ma'ani al-Akhbar"),
    ("manlahyahzur.db", "من لا یحضره الفقیہ", "Man La Yahduruhu al-Faqih"),
    ("mezan.db", "میزان الحکمة", "Mizan al-Hikmah"),
    ("swab.db", "ثواب الاعمال", "Thawab al-A’mal"),
    ("towheed.db", "کتاب التوحید", "Kitab al-Tawhid"),
    ("wasail.db", "وسائل الشیعہ", "Wasa'il al-Shi'a"),
)

EXTRA_DATABASES: tuple[DatabaseSpec, ...] = (
    # The curated encyclopaedia. The checked-in file is the gzipped reader
    # edition built by scripts/build_encyclopedia_db.py from the Drive corpus;
    # the plain .db is materialised by collect_databases() (and is git-ignored,
    # like the other expanded database files).
    DatabaseSpec(
        name="athna_ashari_encyclopedia.db",
        source="encyclopedia",
        key="athna_ashari_encyclopedia",
        title_urdu="اثنا عشری انسائکلوپیڈیا",
        title_latin="Twelver Shia Encyclopedia",
        origin="assets",
        tables={
            "articles": {"id", "title_ur", "group_id", "source_url", "history_url",
                         "revision_id", "character_count", "excerpt", "license_id",
                         "attribution"},
            "groups": {"id", "slug", "title_ur", "sort_order", "article_count"},
            "sections": {"id", "article_id", "ordinal", "heading_ur",
                         "heading_level", "anchor", "source_url", "plain_text"},
            "source_references": {"id", "article_id", "reference_anchor",
                                  "reference_text", "source_url"},
            "imams": {"imam_number", "article_id"},
            "topics": {"id", "slug", "title_ur", "article_id", "article_count"},
            "related_articles": {"source_article_id", "target_article_id", "target_title"},
        },
        indexes=(
            "CREATE INDEX IF NOT EXISTS shia_encyclopedia_sections_article ON sections(article_id, ordinal)",
            "CREATE INDEX IF NOT EXISTS shia_encyclopedia_articles_title ON articles(title_ur)",
            "CREATE INDEX IF NOT EXISTS shia_encyclopedia_articles_group ON articles(group_id, title_ur)",
        ),
        record_label="مضمون",
    ),
    DatabaseSpec(name="Sahifa_Sajjadiyya_full_runtime.sqlite3", source="sahifa", key="sahifa",
        title_urdu="صحیفہ سجادیہ", title_latin="Sahifa Sajjadiyya", origin="assets",
        tables={"saheefa_data": {"ID", "oe", "t_id", "t_no", "p_no", "p_format", "p_text"},
                "saheefa_index": {"ID", "lnk_id", "lnk_text", "lnk_cat"}},
        indexes=("CREATE INDEX IF NOT EXISTS shia_sahifa_container ON saheefa_data(t_id, t_no, p_no, ID)",),
        record_label="دعا"),
    *(DatabaseSpec(name=f"{key}_urdu_fatawa.sqlite", source="fatwa", key=key,
        title_urdu=title, title_latin=latin, origin="assets",
        tables={"question_answers": {"entry_id", "category_id", "question_ur", "answer_ur", "source_url", "source_ref"},
                "categories": {"category_id", "category_title_ur"}},
        indexes=("CREATE INDEX IF NOT EXISTS shia_fatwa_category ON question_answers(category_id)",),
        record_label="مسئلہ") for key, title, latin in (
            # 1.28: the Khamenei Urdu fatawa edition was removed from the
            # corpus at the owner's request; the two marjas below remain.
            ("sistani", "فتاویٰ — آیت اللہ سیستانی", "Sistani Urdu Fatawa"),
            # 1.24: the marja's own 8,104 Urdu question/answer pairs, rebuilt
            # from the Drive archive by scripts/build_najafi_fatawa_db.py into
            # the same two-table shape as the other two marjas.
            ("najafi", "فتاویٰ — آیت اللہ حافظ بشیر حسین نجفی",
             "Hafiz Bashir Hussain Najafi Urdu Fatawa"))),
    DatabaseSpec(
        name="quran.db",
        source="quran",
        key="quran",
        title_urdu="قرآنِ کریم",
        title_latin="Al-Quran al-Karim",
        origin="assets",
        tables={
            "Quran": {"ID", "Arabic", "chapter", "verse", "juz", "page", "tr", "talighe", "search"},
            "ChapterProperty": {"Id", "Name", "Nozol", "Verse", "revel"},
        },
        indexes=QURAN_INDEXES,
        record_label="آیت",
    ),
    DatabaseSpec(
        name="mafatihdb-v4.db",
        source="dua",
        key="mafatih",
        title_urdu="مفاتیح الجنان",
        title_latin="Mafatih al-Jinan",
        origin="assets",
        tables={
            "M_items": {"_id", "M_name", "M_cat_id", "M_type", "M_prio"},
            "Lines": {"_id", "L_M_id", "L_text", "L_Translate", "L_prio", "L_type"},
        },
        indexes=MAFATIH_INDEXES,
        record_label="دعا",
    ),
    DatabaseSpec(
        name="nahjul_balagha.db",
        source="balagha",
        key="nahjul_balagha",
        title_urdu="نہج البلاغہ",
        title_latin="Nahj al-Balagha",
        origin="assets",
        tables={
            "balaghatext": {"ID", "Type", "TypeNo", "ParaNo", "AR", "UR", "ARSIMPLE"},
            "balaghatoc": {"ID", "TypeID", "TypeNo", "Description", "ShortDesc"},
            "balaghatext_hawashi": {"ID", "Type", "TypeNo", "ParaNo", "hawashi"},
            "balaghatext_muqadamat": {"ID", "Type", "ParaNo", "ParaFormat", "mqar", "mqur"},
        },
        indexes=BALAGHA_INDEXES,
        record_label="فقرا",
    ),
)

DATABASES: tuple[DatabaseSpec, ...] = tuple(
    DatabaseSpec(
        name=name,
        source="hadith",
        key=name[:-3].lower(),
        title_urdu=title_urdu,
        title_latin=title_latin,
        origin="bundle",
        tables=HADITH_TABLES,
        record_label="حدیث نمبر",
    )
    for name, title_urdu, title_latin in HADITH_BOOKS
) + EXTRA_DATABASES

BY_NAME: dict[str, DatabaseSpec] = {spec.name: spec for spec in DATABASES}
BY_KEY: dict[str, DatabaseSpec] = {spec.key: spec for spec in DATABASES}

BUNDLED_NAMES = frozenset(spec.name for spec in DATABASES if spec.origin == "bundle")
EXTRA_NAMES = frozenset(spec.name for spec in DATABASES if spec.origin == "assets")

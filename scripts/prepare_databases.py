#!/usr/bin/env python3
"""Safely unpack, validate, and (optionally) re-manifest the Shia library corpus.

The corpus reaches the app in two shapes:

* ``assets/shia-databases.zip`` — the 14 original hadith books (~190 MiB
  expanded). Keeping them compressed avoids committing a second expanded copy.
* ``assets/quran.db``, ``assets/mafatihdb-v4.db``, ``assets/nahjul_balagha.db``
  — three standalone collections checked in directly.

Builds and CI materialise every file into one directory (``assets/databases`` by
default, or ``app/assets/databases`` for a bundled APK) after validating SQLite
integrity, required tables/columns, row counts, and SHA-256 digests.
``--write-manifest`` regenerates ``assets/database-manifest.json`` from the files
that are actually present.
"""
from __future__ import annotations

import argparse
import contextlib
import gzip
import hashlib
import json
import shutil
import sqlite3
import sys
import tempfile
import zipfile
from collections.abc import Iterator
from pathlib import Path, PurePosixPath

sys.path.insert(0, str(Path(__file__).resolve().parent))

from database_specs import (  # noqa: E402
    APP_MANIFEST_PATH,
    BUNDLE,
    BY_NAME,
    DATABASES,
    EXTRA_DATABASES,
    MANIFEST_PATH,
    TARGET_PAGE_SIZE,
    DatabaseSpec,
)

# Pinned to the data release tag on purpose. `releases/latest/download/` would
# follow whichever release was published most recently, so the day an app/APK
# release lands, every database download in every installed copy breaks with a
# 404. Keeping the tag fixed means the data release can be republished forever
# (assets are replaced with --clobber) without apps noticing.
DOWNLOAD_BASE_URLS = (
    # The v2 release contains the refreshed Mafatih/Sahifa databases and a
    # complete manifest; unchanged books continue to fall back to v1.
    "https://github.com/mrghalibspcpu/Shia-Ai/releases/download/databases-v2/",
    "https://github.com/mrghalibspcpu/Shia-Ai/releases/download/databases-v1/",
    "https://raw.githubusercontent.com/mrghalibspcpu/Shia-Ai/main/assets/",
)
DOWNLOAD_EXTENSION = ".gz"
MAX_ENTRY_BYTES = 100 * 1024 * 1024


class DatabaseBundleError(RuntimeError):
    """Raised when a bundle is incomplete, unsafe, or contains invalid SQLite."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_database(path: Path, spec: DatabaseSpec) -> dict[str, int]:
    """Check SQLite integrity and return the row count of every required table."""
    uri = f"file:{path.resolve().as_posix()}?mode=ro"
    try:
        with sqlite3.connect(uri, uri=True) as connection:
            check = connection.execute("PRAGMA quick_check").fetchone()
            if not check or check[0] != "ok":
                raise DatabaseBundleError(f"SQLite quick_check failed for {spec.name}: {check}")
            tables = {
                row[0]
                for row in connection.execute("SELECT name FROM sqlite_master WHERE type = 'table'")
            }
            counts: dict[str, int] = {}
            for table, expected_columns in spec.tables.items():
                if table not in tables:
                    raise DatabaseBundleError(f"{spec.name} is missing table {table!r}")
                actual_columns = {
                    row[1] for row in connection.execute(f'PRAGMA table_info("{table}")')
                }
                missing = expected_columns - actual_columns
                if missing:
                    raise DatabaseBundleError(
                        f"{spec.name}.{table} is missing columns: {sorted(missing)}"
                    )
                counts[table] = int(
                    connection.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0]
                )
            return counts
    except sqlite3.DatabaseError as exc:
        raise DatabaseBundleError(f"Could not open {spec.name} as SQLite: {exc}") from exc


@contextlib.contextmanager
def collect_databases(
    bundle: Path = BUNDLE, *, include_bundle: bool = True
) -> Iterator[list[tuple[DatabaseSpec, Path]]]:
    """Yield every database available on disk, staged in one scratch directory."""
    staging = Path(tempfile.mkdtemp(prefix=".shia-databases-"))
    try:
        collected: list[tuple[DatabaseSpec, Path]] = []
        if include_bundle:
            collected.extend(_read_bundle(bundle, staging))
        for spec in EXTRA_DATABASES:
            target = staging / spec.name
            if spec.asset_path.is_file():
                shutil.copyfile(spec.asset_path, target)
            elif spec.packed_path.is_file():
                # Large collections are committed gzipped (the app downloads
                # them gzipped too); expand into the scratch directory.
                with gzip.open(spec.packed_path, "rb") as packed, target.open("wb") as handle:
                    shutil.copyfileobj(packed, handle, length=1024 * 1024)
            else:
                raise DatabaseBundleError(
                    f"{spec.name} is missing from {spec.asset_path.parent}. Add "
                    f"{spec.name} or {spec.packed_path.name}, or remove it from "
                    "scripts/database_specs.py."
                )
            collected.append((spec, target))
        yield collected
    finally:
        shutil.rmtree(staging, ignore_errors=True)


def _read_bundle(bundle: Path, staging: Path) -> list[tuple[DatabaseSpec, Path]]:
    """Extract the compressed hadith books into the staging directory."""
    if not bundle.is_file():
        raise DatabaseBundleError(f"Database bundle not found: {bundle}")
    try:
        archive = zipfile.ZipFile(bundle)
    except (OSError, zipfile.BadZipFile) as exc:
        raise DatabaseBundleError(f"Invalid database ZIP bundle: {exc}") from exc

    expected = {spec.name for spec in DATABASES if spec.origin == "bundle"}
    with archive:
        infos = [info for info in archive.infolist() if not info.is_dir()]
        names = {PurePosixPath(info.filename).name for info in infos}
        if names != expected:
            raise DatabaseBundleError(
                "Bundle contents do not match the verified database set. "
                f"Expected {sorted(expected)}, found {sorted(names)}"
            )
        staged: list[tuple[DatabaseSpec, Path]] = []
        for info in infos:
            name = PurePosixPath(info.filename).name
            # Require flat, known names; do not trust archive paths.
            if PurePosixPath(info.filename).name != info.filename or name not in BY_NAME:
                raise DatabaseBundleError(f"Unsafe or unexpected archive path: {info.filename!r}")
            if info.file_size > MAX_ENTRY_BYTES:
                raise DatabaseBundleError(f"Unexpectedly large database entry: {name}")
            target = staging / name
            with archive.open(info, "r") as source, target.open("wb") as handle:
                shutil.copyfileobj(source, handle, length=1024 * 1024)
            staged.append((BY_NAME[name], target))
        return staged


def build_records(collected: list[tuple[DatabaseSpec, Path]]) -> list[dict]:
    records: list[dict] = []
    for spec, path in collected:
        counts = validate_database(path, spec)
        records.append(
            {
                "name": spec.name,
                "key": spec.key,
                "source": spec.source,
                "title_urdu": spec.title_urdu,
                "title_latin": spec.title_latin,
                "record_label": spec.record_label,
                "size_bytes": path.stat().st_size,
                "sha256": sha256_file(path),
                "records": counts,
            }
        )
    return sorted(
        records, key=lambda row: (row["source"] != "hadith", str(row["name"]).lower())
    )


def verify_against_manifest(records: list[dict]) -> None:
    """Reject any file whose digest or row counts differ from the manifest."""
    if not MANIFEST_PATH.exists():
        return
    expected = {
        row["name"]: row
        for row in json.loads(MANIFEST_PATH.read_text(encoding="utf-8")).get("databases", [])
    }
    for record in records:
        entry = expected.get(record["name"])
        if not entry:
            raise DatabaseBundleError(
                f"{record['name']} is not listed in {MANIFEST_PATH.name}. "
                "Run `python3 scripts/prepare_databases.py --write-manifest`."
            )
        if record["sha256"] != entry.get("sha256"):
            raise DatabaseBundleError(f"Checksum mismatch for {record['name']}")
        expected_counts = entry.get("records") or {
            table: entry.get(table) for table in record["records"]
        }
        for table, count in record["records"].items():
            if expected_counts.get(table) not in (None, count):
                raise DatabaseBundleError(
                    f"Unexpected {table} row count in {record['name']}: "
                    f"{count} != {expected_counts.get(table)}"
                )


def write_manifest(records: list[dict]) -> None:
    totals = {
        "hadith_records": sum(r["records"].get("Parags", 0) for r in records),
        "sections": sum(r["records"].get("Sections", 0) for r in records),
        "chapters": sum(r["records"].get("Chaps", 0) for r in records),
        "quran_verses": sum(r["records"].get("Quran", 0) for r in records),
        "quran_surahs": sum(r["records"].get("ChapterProperty", 0) for r in records),
        "dua_items": sum(r["records"].get("M_items", 0) for r in records),
        "dua_lines": sum(r["records"].get("Lines", 0) for r in records),
        "balagha_paragraphs": sum(r["records"].get("balaghatext", 0) for r in records),
        "sahifa_rows": sum(r["records"].get("saheefa_data", 0) for r in records),
        "fatwa_answers": sum(r["records"].get("question_answers", 0) for r in records),
        "balagha_sections": sum(r["records"].get("balaghatoc", 0) for r in records),
    }
    payload = {
        "format_version": 2,
        "source_app": (
            "Ahadith al Shia Urdu 1.0.1 corpus plus the Quran, Mafatih al-Jinan, "
            "and Nahj al-Balagha collections"
        ),
        "sqlite_page_size": TARGET_PAGE_SIZE,
        "database_count": len(records),
        "totals": {key: value for key, value in totals.items() if value},
        "download": {"extension": DOWNLOAD_EXTENSION, "base_urls": list(DOWNLOAD_BASE_URLS)},
        "databases": records,
    }
    text = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    MANIFEST_PATH.write_text(text, encoding="utf-8")
    # The Flutter bundle ships its own copy so the app can verify downloads
    # offline; writing both here keeps the two from drifting apart.
    APP_MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    APP_MANIFEST_PATH.write_text(text, encoding="utf-8")


def install(collected: list[tuple[DatabaseSpec, Path]], output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    for spec, path in collected:
        destination = output_dir / spec.name
        if destination.exists() and sha256_file(destination) == sha256_file(path):
            continue
        shutil.move(str(path), str(destination))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, default=BUNDLE)
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Where to materialise the databases (default: validate only)",
    )
    parser.add_argument(
        "--skip-bundle",
        action="store_true",
        help="Validate only the standalone Quran/Mafatih/Nahj al-Balagha files",
    )
    parser.add_argument(
        "--write-manifest",
        action="store_true",
        help="Regenerate assets/database-manifest.json from the files on disk",
    )
    args = parser.parse_args()

    try:
        with collect_databases(args.bundle, include_bundle=not args.skip_bundle) as collected:
            records = build_records(collected)
            if args.write_manifest:
                write_manifest(records)
            else:
                verify_against_manifest(records)
            if args.output:
                install(collected, args.output)
    except DatabaseBundleError as exc:
        parser.error(str(exc))

    for record in records:
        counts = ", ".join(f"{table}={count}" for table, count in record["records"].items())
        print(
            f"{record['name']}: {counts} "
            f"({record['size_bytes']:,} bytes; SHA-256 {record['sha256'][:12]}…)"
        )
    if args.output:
        print(f"Validated {len(records)} SQLite databases in {args.output.resolve()}")
    else:
        print(f"Validated {len(records)} SQLite databases")
    if args.write_manifest:
        print(f"Wrote {MANIFEST_PATH} and {APP_MANIFEST_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

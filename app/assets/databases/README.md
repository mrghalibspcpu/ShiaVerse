Bundled SQLite books are unpacked here before a Flutter build:

```sh
python3 scripts/prepare_databases.py --output app/assets/databases
```

The expanded release corpus remains gitignored except for the two replacement
books bundled in ShiaVerse 1.29 (`mafatihdb-v4.db` and
`Sahifa_Sajjadiyya_full_runtime.sqlite3`). The bundled copies are hash-pinned and
atomically replace older installed copies before readers open them. The
compressed hadith source remains `assets/shia-databases.zip`.

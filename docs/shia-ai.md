# ShiaAi — source-grounded question/answer over the installed library

ShiaAi is the ShiaVerse equivalent of an "Aalim 360"-style assistant: the user
asks a question in Urdu, Arabic or Roman Urdu, the app finds the most relevant
passages in the books already installed on the device, and — when online
synthesis is explicitly enabled — a model writes an Urdu answer grounded **only**
in those passages. Every answer carries tappable citations that open the exact
record in the app's existing readers.

## 1. Architecture

```
┌────────────────────────────── Phone (ShiaVerse app) ──────────────────────────────┐
│                                                                                    │
│  question                                                                          │
│     │                                                                              │
│     ▼                                                                              │
│  ShiaAiRetriever          existing SQLite books + shia-search.sqlite FTS/LIKE      │
│   • normalizeArabicUrdu / searchTokens / expandSearchQueries (text_utils.dart)     │
│   • Roman-Urdu → Arabic-script hints (kShiaAiRomanHints)                           │
│   • fans out query variants through LibraryRepository.searchMany                   │
│   • re-ranks by term coverage/title weight, per-book diversity cap                 │
│   • keeps the true (bookKey, recordId) of every passage                            │
│     │                                                                              │
│     ▼                                                                              │
│  ShiaAiEngine            evidence gate + citation validation (all on device)       │
│   • no/weak evidence → abstain, never call the network                             │
│   • offline/unconfigured → local sources only, nothing leaves the device           │
│   • otherwise posts ≤ 8 short excerpts to the gateway                              │
│   • every returned citation id is re-checked against the retrieved set             │
│     │                                                                              │
│     ▼                                                                              │
│  ShiaAiChatScreen         Urdu chat, privacy banner, verified citation chips       │
│   • tap citation → pushReaderFor(...) → exact ayah/hadith/fatwa/dua                │
│   • Back pops the reader; the chat route stays mounted (state + scroll kept)       │
│   • conversation persisted in SharedPreferences (ShiaAiConversationStore)           │
└───────────────────────────────────┬────────────────────────────────────────────────┘
                                     │ HTTPS POST {question, passages[≤8, clipped]}
                                     ▼
┌────────────────────────── backend/shia-ai-gateway (Cloudflare Worker) ─────────────┐
│  GEMINI_API_KEY = server-side secret (wrangler secret), never in the app/git/logs  │
│  strict grounding prompt (Urdu answer; passages only; abstain if insufficient)     │
│  Gemini generateContent → {sufficient, answer, used_citation_ids}                  │
│  re-validates citation ids, maps 401/403/429/5xx to clear error codes              │
└────────────────────────────────────────────────────────────────────────────────────┘
```

### New client code (all under `app/lib/shia_ai/` and `app/lib/screens/`)

| file | role |
| --- | --- |
| `shia_ai/shia_ai_models.dart` | `ShiaAiEvidence`, `ShiaAiCitation`, `ShiaAiMessage`, `ShiaAiReply`, delivery states. Citations can only be built from verified evidence. |
| `shia_ai/shia_ai_retriever.dart` | Query expansion (incl. Roman-Urdu hints), fan-out over `LibraryRepository.searchMany`, coverage re-ranking, diversity cap, evidence threshold. |
| `shia_ai/shia_ai_gateway.dart` | HTTPS client (package:http, injectable). Maps offline/quota/key/malformed failures to typed states. Holds **no key**. |
| `shia_ai/shia_ai_engine.dart` | Orchestration, evidence gate, abstention wording, app-side citation validation, `cleanModelAnswer`. |
| `shia_ai/shia_ai_settings.dart` | Gateway URL + explicit consent flag in SharedPreferences (default off). |
| `shia_ai/shia_ai_store.dart` | On-device conversation persistence. |
| `screens/shia_ai_screen.dart` | `ShiaAiChatScreen`, citation tiles, privacy dialog, `ShiaAiSettingsSheet`. |

Nothing in the existing readers, search code, database schemas, or corpus text
was changed. The retriever only *reads* through the existing
`LibraryRepository` API (`searchMany`, which uses the same FTS/LIKE machinery as
the unified search screen).

**Entry points.** The radial Xplore plate only renders its six curated
features, so ShiaAi is opened from **Xplore → Xplore Xtra → "ShiaAi — ذہین
سوال و جواب"** (first card) and from **Settings → "ShiaAi — ذہین سوال و
جواب"**. Both routes push the same `ShiaAiChatScreen`; its app-bar gear opens
the gateway/consent settings sheet.

## 2. Retrieval and multilingual handling

* **Arabic / Urdu:** the existing `normalizeArabicUrdu` already removes harakat
  and tatweel, unifies Alef/Yeh/Kaf/Heh variants (`ك→ک`, `ي→ی`, `ة/ہ→ه`,
  `آ/أ/إ→ا`), strips punctuation and keeps Arabic-Indic digits. FTS and the
  normalized-LIKE fallback operate on the same normalized text the readers
  display.
* **Roman Urdu:** the index contains no Latin text, so Roman questions are
  expanded into Arabic-script query terms before searching. The existing
  `kTopicExpansions` cover the large fiqh clusters (namaz, wuzu, roza, khums,
  mutah, ghadir, karbala…); `kShiaAiRomanHints` adds everyday terms
  (ghusl, tayammum, zakat, nikah, talaq, hajj, janaza, qasr, taqleed, hijab…).
* **Ranking:** variants are merged and de-duplicated by `book:recordId`, scored
  by distinct-term coverage (title matches weighted heavily, intact-phrase
  bonus, coverage-squared reward), then capped at three passages per book and
  eight in total so different collections stay represented.
* **Identity preservation:** evidence carries the actual `bookKey` and
  `recordId` from the indexed row through every layer. There is no semantic
  vector store and no separate cloud index, so IDs can never drift.

## 3. Grounding, abstention and citation integrity

1. **No evidence** → the model is never called; the user gets the plain
   "no matching passage in the installed books" message.
2. **Weak evidence** (no strong passage and fewer than two term-matching
   passages) → abstention plus the retrieved passages to inspect manually.
3. **Offline / unconfigured** → local sources are listed; nothing is
   transmitted.
4. The gateway prompt instructs the model to answer only from the supplied
   passages, in Urdu, and to return `sufficient:false` rather than invent
   anything.
5. The app **re-validates**: a `used_citation_id` not present in the retrieved
   set is dropped (both in the worker and again in the engine). Citations are
   constructed in app code from the real records — never parsed from model
   prose — and rejected if the book key is unknown or the record id ≤ 0.
6. The app never asks the model for page/reference numbers; displayed locators
   come from the corpus rows themselves.

This makes hallucinated hadith, rulings, references or page numbers impossible
to render as a citation, though — as with any retrieval system — relevance of
the top passages is not guaranteed to be perfect; the UI never claims 100%
accuracy and always exposes the source text for verification.

## 4. Navigation and the Back trip

`defaultShiaAiOpener` calls the existing `pushReaderFor(context, library, book,
recordId, sectionId, title)`, which routes to the correct reader (Quran surah
reader, hadith/fatwa ReaderScreen, Mafatih dua reader, Nahj al-Balagha reader,
etc.). The reader is pushed **on top of** the chat route, so the chat's State,
messages and `ScrollController` stay alive; Back returns to the same
conversation at the same scroll offset. A widget test covers the full round
trip, including offset equality.

## 5. Secrets, privacy and dataset rights

* The Gemini key exists only in the gateway's secret store
  (`wrangler secret put GEMINI_API_KEY`). It is not in the APK, git, GitHub
  Actions logs, or any client source. The app stores only a gateway **URL**,
  which authorizes nothing by itself.
* The full book databases are never uploaded. A request contains the question
  and at most 8 excerpts clipped to 1,200 characters each; the worker clips
  again (1,500) and stores nothing.
* Online synthesis is **off by default** and requires an explicit consent
  toggle. The chat screen shows a persistent mode banner and a privacy dialog;
  Settings → ماخذ اور حقوق explains the data flow in Urdu.
* `docs/store/dataset-rights-audit.md` records that redistribution rights for
  the Urdu corpus are not cleared. Sending even short excerpts to a third-party
  model should be treated under the same caution: keep the consent gate, do not
  enable the feature by default in a public release without the rights review,
  and consider rate limiting at the gateway.

## 6. Failure handling

| situation | user-visible behaviour |
| --- | --- |
| no network | local retrieval still works; synthesis shows the offline/network message with local citations; regular browsing/search untouched |
| gateway URL missing or consent off | "local mode" — passages only, zero network traffic |
| missing/rejected server key (401/403 → 502) | key-unavailable message with the local sources |
| quota exhausted / model 503 (429) | quota message with the local sources |
| model 404 / 5xx / malformed JSON / empty answer | service-error message with the local sources |
| no matching passage | plain abstention, no citations, no network call |

## 7. Backend and secret setup

See `backend/shia-ai-gateway/README.md` for the full guide. Short version:

```bash
cd backend/shia-ai-gateway
npm install
npx wrangler deploy
npx wrangler secret put GEMINI_API_KEY   # stored only at Cloudflare
# then in the app: Xplore → Xplore Xtra → ShiaAi → ترتیبات (gear) →
# enable online mode, paste the gateway URL
# (Settings → "ShiaAi — ذہین سوال و جواب" opens the same chat)
```

The same worker logic ports to any HTTPS host (Cloud Function, Lambda, small
Node service) provided the key stays in the platform secret manager and the
JSON contract is preserved.

## 8. Tests

* Dart/Flutter: `app/test/shia_ai_test.dart` — normalization and Roman-Urdu
  expansion, retrieval ranking/diversity/id preservation, valid/invalid
  citations, abstention when evidence is missing, gateway error mapping,
  preference validation, persistence, and widget tests for citation → reader
  navigation and the Back round trip including scroll offset.
* Backend: `backend/shia-ai-gateway/test/worker.test.mjs` (`node --test`) —
  input caps, prompt construction, JSON normalization, id re-validation and all
  upstream error mappings with a mocked Gemini call.
* The offline guard `scripts/check_dart.py` (tree-sitter) runs on every change;
  GitHub Actions additionally runs `flutter analyze`, the full `flutter test`
  suite and the corpus verification scripts.

## 9. Known limitations

* Retrieval is lexical (normalized FTS/LIKE plus curated term expansions), not
  embedding-based: paraphrases with no shared roots depend on the hint/topic
  tables, which can be extended without any schema change.
* Synthesis quality depends on the configured Gemini model and the retrieved
  passages; the system errs toward abstention, so some answerable questions may
  return sources without a synthesized answer.
* The gateway has no authentication/rate limiting in the reference
  implementation; add WAF/rate limiting (or a shared-secret header) before
  broad rollout.
* Only one conversation is retained on the device (capped at 60 messages).
* The app does not claim 100% accuracy; readers should verify rulings against
  the cited source and their marja.

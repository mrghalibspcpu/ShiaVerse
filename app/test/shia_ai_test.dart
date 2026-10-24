import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiaverse/library_repository.dart';
import 'package:shiaverse/models.dart';
import 'package:shiaverse/screens/shia_ai_screen.dart';
import 'package:shiaverse/screens/xplore_xtra_screen.dart';
import 'package:shiaverse/shia_ai/shia_ai_engine.dart';
import 'package:shiaverse/shia_ai/shia_ai_gateway.dart';
import 'package:shiaverse/shia_ai/shia_ai_models.dart';
import 'package:shiaverse/shia_ai/shia_ai_retriever.dart';
import 'package:shiaverse/shia_ai/shia_ai_settings.dart';
import 'package:shiaverse/shia_ai/shia_ai_store.dart';

SearchHit _hit(
  String bookKey,
  int recordId, {
  String urdu = '',
  String arabic = '',
  String section = '',
  String chapter = '',
  String locator = '',
  String sourceUrl = '',
}) {
  final book = BookDefinition.byKey(bookKey)!;
  return SearchHit(
    book: book,
    citation: '',
    passage: Passage(
      recordId: recordId,
      arabic: arabic,
      urdu: urdu,
      sectionTitle: section,
      chapterTitle: chapter,
      locator: locator,
      sourceUrl: sourceUrl,
    ),
  );
}

ShiaAiEvidence _evidence(
  String bookKey,
  int recordId, {
  int score = 20,
  int matched = 2,
  String urdu = 'وضو کا طریقہ',
  String sourceUrl = '',
}) =>
    ShiaAiEvidence.fromHit(
      _hit(bookKey, recordId, urdu: urdu, sourceUrl: sourceUrl),
      score: score,
      matchedTokens: matched,
    );

/// Repository fake: only [searchMany] is used by the retriever.
class _FakeLibrary extends LibraryRepository {
  _FakeLibrary([this.hits = const <SearchHit>[]]);
  final List<SearchHit> hits;

  @override
  Future<List<SearchHit>> searchMany(
    List<String> queries, {
    int limit = 12,
    String? bookKey,
    String language = 'all',
    CorpusSource? source,
  }) async =>
      hits.take(limit).toList();
}

class _FakeRetriever extends ShiaAiRetriever {
  _FakeRetriever(this.result) : super(library: _FakeLibrary());
  final ShiaAiRetrieval result;

  @override
  Future<ShiaAiRetrieval> retrieve(String question) async => result;
}

class _FakeGateway extends ShiaAiGateway {
  _FakeGateway({this.reply, this.error})
      : super(client: MockClient((request) async => http.Response('{}', 500)));
  final ShiaAiGatewayResponse? reply;
  final ShiaAiGatewayException? error;
  int calls = 0;
  List<ShiaAiEvidence> lastEvidence = const <ShiaAiEvidence>[];

  @override
  Future<ShiaAiGatewayResponse> synthesize({
    required Uri endpoint,
    required String question,
    required List<ShiaAiEvidence> evidence,
  }) async {
    calls++;
    lastEvidence = evidence;
    if (error != null) throw error!;
    return reply!;
  }
}

/// Builds an in-memory HTTP client that records request bodies and either
/// returns a canned response or throws (transport/timeout failures).
MockClient _recordingClient({
  http.Response? response,
  Object? throwable,
  required List<String> bodies,
}) {
  return MockClient((request) async {
    bodies.add(request.body);
    if (throwable != null) throw throwable;
    return response!;
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('Arabic/Urdu/Roman Urdu normalization', () {
    test('letter variants and diacritics collapse to one form', () {
      expect(normalizeArabicUrdu('الْوُضُوءُ'), contains('الوضوء'));
      expect(normalizeArabicUrdu('كافر'), normalizeArabicUrdu('کافر'));
      expect(normalizeArabicUrdu('على'), normalizeArabicUrdu('علی'));
      // taa marbuta and Urdu heh goal both collapse to plain heh.
      expect(normalizeArabicUrdu('صلاة'), normalizeArabicUrdu('صلاه'));
      expect(normalizeArabicUrdu('جمعہ'), normalizeArabicUrdu('جمعه'));
      expect(normalizeArabicUrdu('آپ'), normalizeArabicUrdu('اپ'));
      // Arabic-Indic digits survive normalization rather than turning Latin.
      final digits = normalizeArabicUrdu('آیت ۱۲۳');
      expect(digits, contains('۱۲۳'));
      expect(digits, isNot(contains('123')));
    });

    test('Roman Urdu questions expand into the Arabic-script index terms', () {
      final retriever = ShiaAiRetriever(library: _FakeLibrary());
      final wuzu = retriever.buildQueries('wudu kaise karein');
      expect(wuzu, contains('وضو'));
      expect(wuzu, contains('الوضوء'));

      final ghusl = retriever.buildQueries('ghusl e janabat ka tareeqa');
      expect(ghusl, contains('غسل'));
      expect(ghusl, contains('غسل جنابت'));

      final namaz = retriever.buildQueries('how to combine namaz');
      expect(namaz.any((q) => q.contains('نماز')), isTrue);
    });

    test('scripted questions keep the original and topic expansions', () {
      final retriever = ShiaAiRetriever(library: _FakeLibrary());
      final queries = retriever.buildQueries('وضو کی کیفیت');
      expect(queries.first, 'وضو کی کیفیت');
      expect(queries, contains('وضو'));
    });

    test('unknown Latin wording still yields a query (never crashes)', () {
      final retriever = ShiaAiRetriever(library: _FakeLibrary());
      final queries = retriever.buildQueries('xyzzy floop');
      expect(queries, contains('xyzzy floop'));
    });

    test('empty questions retrieve nothing', () async {
      final retriever = ShiaAiRetriever(library: _FakeLibrary());
      final result = await retriever.retrieve('   ');
      expect(result.evidence, isEmpty);
      expect(result.hasAny, isFalse);
      expect(result.hasEnough, isFalse);
    });
  });

  group('local retrieval ranking and identity', () {
    test('ranks by coverage, drops unrelated hits, and keeps true ids', () async {
      final library = _FakeLibrary([
        _hit('quran', 5, urdu: 'وضو کا طریقہ'),
        _hit('alkafi', 11, urdu: 'وضو کا بیان'),
        _hit('alkafi', 12, urdu: 'بالکل غیر متعلقہ متن'),
      ]);
      final retriever = ShiaAiRetriever(library: library);
      final result = await retriever.retrieve('وضو کا طریقہ');
      expect(result.evidence.length, 2);
      // The passage covering BOTH terms (and the intact phrase) outranks the
      // passage that only mentions one of them.
      expect(result.evidence.first.bookKey, 'quran');
      expect(result.evidence.first.recordId, 5);
      expect(result.evidence.first.matchedTokens, 2);
      // Identities are the real storage keys.
      expect(result.evidence.map((e) => e.citationId), ['quran:5', 'alkafi:11']);
      expect(result.hasEnough, isTrue);
    });

    test('caps any single book at three passages for source diversity', () async {
      final library = _FakeLibrary([
        for (var i = 1; i <= 4; i++) _hit('alkafi', 100 + i, urdu: 'وضو کا طریقہ'),
        _hit('quran', 7, urdu: 'وضو کا طریقہ'),
        _hit('sistani', 9, urdu: 'وضو کا طریقہ'),
      ]);
      final retriever = ShiaAiRetriever(library: library);
      final result = await retriever.retrieve('وضو کا طریقہ');
      final alkafiCount = result.evidence.where((e) => e.bookKey == 'alkafi').length;
      expect(alkafiCount, ShiaAiRetriever.perBookCap);
      expect(result.evidence.length, lessThanOrEqualTo(8));
      final ids = result.evidence.map((e) => e.citationId).toSet();
      expect(ids.length, result.evidence.length); // no duplicated records
    });

    test('pure scoring weights titles above body text', () {
      final terms = <String>{'وضو'};
      final bodyHit = _hit('alkafi', 1, urdu: 'یہاں وضو کا ذکر ہے');
      final titleHit = _hit('alkafi', 2, urdu: 'کچھ اور', section: 'وضو کا بیان');
      final body = ShiaAiRetriever.scoreHit(bodyHit, terms, 'وضو');
      final title = ShiaAiRetriever.scoreHit(titleHit, terms, 'وضو');
      expect(title.score, greaterThan(body.score));
      expect(ShiaAiRetriever.scoreHit(_hit('alkafi', 3, urdu: 'غیر'), terms, 'وضو').matched, 0);
    });
  });

  group('citation validation', () {
    test('citations are built only from openable evidence', () {
      final evidence = [_evidence('alkafi', 11), _evidence('quran', 5)];
      final citations = ShiaAiEngine.citationsFor(
        evidence,
        {'alkafi:11', 'quran:5'},
      );
      expect(citations.map((c) => c.citationId), ['alkafi:11', 'quran:5']);
      expect(citations.every((c) => c.isValid), isTrue);
    });

    test('unknown book keys and non-positive ids are rejected', () {
      final fake = ShiaAiEvidence(
        bookKey: 'not-a-book',
        recordId: 3,
        bookTitle: 'جعلی کتاب',
        score: 20,
        matchedTokens: 1,
      );
      expect(fake.isOpenable, isFalse);
      expect(ShiaAiCitation.fromEvidence(fake).isValid, isFalse);
      final zero = ShiaAiCitation.fromEvidence(
        ShiaAiEvidence(
          bookKey: 'alkafi',
          recordId: 0,
          bookTitle: 'الکافی',
          score: 20,
          matchedTokens: 1,
        ),
      );
      expect(zero.isValid, isFalse);
    });

    test('model-returned ids that were never retrieved are dropped', () {
      final evidence = [_evidence('alkafi', 11), _evidence('quran', 5)];
      final citations = ShiaAiEngine.citationsFor(
        evidence,
        {'alkafi:11', 'hallucinated:999'},
      );
      expect(citations.map((c) => c.citationId), ['alkafi:11']);
    });

    test('citation JSON round-trips and stale invalid rows are filtered', () async {
      const store = ShiaAiConversationStore();
      final message = ShiaAiMessage.assistant(
        'جواب',
        id: 'a1',
        delivery: ShiaAiDelivery.answered,
        citations: [ShiaAiCitation.fromEvidence(_evidence('alkafi', 11))],
        evidenceIds: const ['alkafi:11'],
      );
      await store.saveMessages([message]);
      final loaded = await store.loadMessages();
      expect(loaded.single.citations.single.citationId, 'alkafi:11');
      await store.clear();
      expect(await store.loadMessages(), isEmpty);
    });
  });

  group('engine abstinence and grounding', () {
    ShiaAiRetrieval emptyRetrieval() => const ShiaAiRetrieval(
          question: 'سوال',
          queries: ['سوال'],
          terms: {'سوال'},
          evidence: <ShiaAiEvidence>[],
        );

    test('no evidence: abstains without ever calling the gateway', () async {
      final gateway = _FakeGateway(reply: null);
      final engine = ShiaAiEngine(
        retriever: _FakeRetriever(emptyRetrieval()),
        gateway: gateway,
        preferences: () async => const ShiaAiPreferences(
          gatewayUrl: 'https://gw.example',
          onlineEnabled: true,
        ),
      );
      final reply = await engine.ask('ایسا سوال جس کا کچھ نہ ملے');
      expect(reply.delivery, ShiaAiDelivery.noEvidence);
      expect(reply.answer, ShiaAiWording.noEvidence);
      expect(gateway.calls, 0);
    });

    test('weak evidence: abstains and shows the passages without synthesis', () async {
      final weak = [
        ShiaAiEvidence.fromHit(_hit('alkafi', 1, urdu: 'وضو'),
            score: 4, matchedTokens: 1),
      ];
      final retrieval = ShiaAiRetrieval(
        question: 'وضو',
        queries: const ['وضو'],
        terms: const {'وضو'},
        evidence: weak,
      );
      final gateway = _FakeGateway(reply: null);
      final engine = ShiaAiEngine(
        retriever: _FakeRetriever(retrieval),
        gateway: gateway,
        preferences: () async => const ShiaAiPreferences(
          gatewayUrl: 'https://gw.example',
          onlineEnabled: true,
        ),
      );
      final reply = await engine.ask('وضو');
      expect(reply.delivery, ShiaAiDelivery.abstained);
      expect(reply.citations.single.citationId, 'alkafi:1');
      expect(gateway.calls, 0);
    });

    test('unconfigured client stays offline and sends nothing', () async {
      final gateway = _FakeGateway(reply: null);
      final retrieval = ShiaAiRetrieval(
        question: 'وضو',
        queries: const ['وضو'],
        terms: const {'وضو'},
        evidence: [_evidence('alkafi', 1)],
      );
      final engine = ShiaAiEngine(
        retriever: _FakeRetriever(retrieval),
        gateway: gateway,
        preferences: () async => const ShiaAiPreferences(),
      );
      final reply = await engine.ask('وضو');
      expect(reply.delivery, ShiaAiDelivery.offlineSources);
      expect(gateway.calls, 0);
      expect(reply.citations, isNotEmpty);
    });

    test('model saying evidence is insufficient becomes an abstention', () async {
      final retrieval = ShiaAiRetrieval(
        question: 'وضو',
        queries: const ['وضو'],
        terms: const {'وضو'},
        evidence: [_evidence('alkafi', 1)],
      );
      final gateway = _FakeGateway(
        reply: const ShiaAiGatewayResponse(
          answer: 'کچھ نہیں ملا',
          sufficient: false,
          usedIds: ['alkafi:1'],
        ),
      );
      final engine = ShiaAiEngine(
        retriever: _FakeRetriever(retrieval),
        gateway: gateway,
        preferences: () async => const ShiaAiPreferences(
          gatewayUrl: 'https://gw.example',
          onlineEnabled: true,
        ),
      );
      final reply = await engine.ask('وضو');
      expect(reply.delivery, ShiaAiDelivery.abstained);
      expect(reply.answer, ShiaAiWording.modelAbstained);
    });

    test('happy path answers with re-validated citations only', () async {
      final retrieval = ShiaAiRetrieval(
        question: 'وضو',
        queries: const ['وضو'],
        terms: const {'وضو'},
        evidence: [_evidence('alkafi', 1), _evidence('quran', 5)],
      );
      final gateway = _FakeGateway(
        reply: const ShiaAiGatewayResponse(
          answer: '**وضو** کا طریقہ یہ ہے',
          sufficient: true,
          usedIds: ['alkafi:1', 'ghost:999'],
        ),
      );
      final engine = ShiaAiEngine(
        retriever: _FakeRetriever(retrieval),
        gateway: gateway,
        preferences: () async => const ShiaAiPreferences(
          gatewayUrl: 'https://gw.example',
          onlineEnabled: true,
        ),
      );
      final reply = await engine.ask('وضو');
      expect(reply.delivery, ShiaAiDelivery.answered);
      expect(reply.answer, 'وضو کا طریقہ یہ ہے'); // markdown removed
      expect(reply.citations.map((c) => c.citationId), ['alkafi:1']);
      expect(gateway.lastEvidence.length, 2);
    });

    test('gateway failures degrade to local sources, never general knowledge', () async {
      final retrieval = ShiaAiRetrieval(
        question: 'وضو',
        queries: const ['وضو'],
        terms: const {'وضو'},
        evidence: [_evidence('alkafi', 1)],
      );
      final engine = ShiaAiEngine(
        retriever: _FakeRetriever(retrieval),
        gateway: _FakeGateway(
          error: const ShiaAiGatewayException(
            ShiaAiDelivery.networkError,
            'offline',
          ),
        ),
        preferences: () async => const ShiaAiPreferences(
          gatewayUrl: 'https://gw.example',
          onlineEnabled: true,
        ),
      );
      final reply = await engine.ask('وضو');
      expect(reply.delivery, ShiaAiDelivery.networkError);
      expect(reply.answer, ShiaAiWording.networkError);
      expect(reply.citations.single.citationId, 'alkafi:1');
    });
  });

  group('gateway HTTP client', () {
    ShiaAiGateway gatewayWith(http.Client client) =>
        ShiaAiGateway(client: client);

    final evidence = [_evidence('alkafi', 1), _evidence('quran', 5)];

    test('parses a successful model response', () async {
      final bodies = <String>[];
      final client = _recordingClient(
        bodies: bodies,
        response: http.Response(
          jsonEncode({
            'sufficient': true,
            'answer': 'جواب',
            'used_citation_ids': ['alkafi:1'],
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      final reply = await gatewayWith(client).synthesize(
        endpoint: Uri.parse('https://gw.example/'),
        question: 'وضو',
        evidence: evidence,
      );
      expect(reply.answer, 'جواب');
      expect(reply.usedIds, ['alkafi:1']);
      final sent = jsonDecode(bodies.single) as Map<String, Object?>;
      expect((sent['passages'] as List<Object?>).length, 2);
      expect(sent['question'], 'وضو');
    });

    test('never sends more than eight excerpts', () async {
      final many = List.generate(10, (i) => _evidence('alkafi', i + 1));
      final bodies = <String>[];
      final client = _recordingClient(
        bodies: bodies,
        response: http.Response(
          jsonEncode({'sufficient': true, 'answer': 'x', 'used_citation_ids': <String>[]}),
          200,
        ),
      );
      await gatewayWith(client).synthesize(
        endpoint: Uri.parse('https://gw.example/'),
        question: 'q',
        evidence: many,
      );
      final sent = jsonDecode(bodies.single) as Map<String, Object?>;
      expect((sent['passages'] as List<Object?>).length, 8);
    });

    test('maps transport, quota, key and malformed failures', () async {
      final cases = <(Object?, ShiaAiDelivery)>[
        (http.ClientException('no route'), ShiaAiDelivery.networkError),
        (TimeoutException('slow'), ShiaAiDelivery.networkError),
      ];
      for (final (throwable, delivery) in cases) {
        final gateway = gatewayWith(
          _recordingClient(bodies: <String>[], throwable: throwable),
        );
        await expectLater(
          gateway.synthesize(
            endpoint: Uri.parse('https://gw.example/'),
            question: 'q',
            evidence: evidence,
          ),
          throwsA(isA<ShiaAiGatewayException>()
              .having((e) => e.delivery, 'delivery', delivery)),
        );
      }
      for (final (status, delivery) in <(int, ShiaAiDelivery)>[
        (429, ShiaAiDelivery.quotaExhausted),
        (503, ShiaAiDelivery.quotaExhausted),
        (401, ShiaAiDelivery.keyUnavailable),
        (403, ShiaAiDelivery.keyUnavailable),
        (404, ShiaAiDelivery.serviceError),
        (500, ShiaAiDelivery.serviceError),
      ]) {
        final gateway = gatewayWith(
          _recordingClient(
            bodies: <String>[],
            response: http.Response('{}', status),
          ),
        );
        await expectLater(
          gateway.synthesize(
            endpoint: Uri.parse('https://gw.example/'),
            question: 'q',
            evidence: evidence,
          ),
          throwsA(isA<ShiaAiGatewayException>()
              .having((e) => e.delivery, 'delivery', delivery)),
        );
      }
      final malformed = gatewayWith(
        _recordingClient(
          bodies: <String>[],
          response: http.Response('not json', 200),
        ),
      );
      await expectLater(
        malformed.synthesize(
          endpoint: Uri.parse('https://gw.example/'),
          question: 'q',
          evidence: evidence,
        ),
        throwsA(isA<ShiaAiGatewayException>()),
      );
    });
  });

  group('preferences', () {
    test('only valid HTTPS endpoints with consent count as configured', () async {
      final prefs = ShiaAiPreferences(
        gatewayUrl: 'https://gw.example.workers.dev',
        onlineEnabled: true,
      );
      expect(prefs.isConfigured, isTrue);
      expect(prefs.copyWith(onlineEnabled: false).isConfigured, isFalse);
      expect(
        ShiaAiPreferences(gatewayUrl: 'http://plain.example', onlineEnabled: true)
            .isConfigured,
        isFalse,
      );
      expect(
        ShiaAiPreferences(gatewayUrl: 'http://localhost:8787', onlineEnabled: true)
            .isConfigured,
        isTrue,
      );
    });

    test('persists and reloads the URL and consent flag', () async {
      await const ShiaAiPreferences(
        gatewayUrl: 'https://gw.example',
        onlineEnabled: true,
      ).save();
      final loaded = await ShiaAiPreferences.load();
      expect(loaded.gatewayUrl, 'https://gw.example');
      expect(loaded.onlineEnabled, isTrue);
    });
  });

  group('chat screen, citations and the return trip', () {
    Widget host({
      required ShiaAiEngine engine,
      required ShiaAiReaderOpener opener,
      ShiaAiPreferences preferences = const ShiaAiPreferences(),
    }) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ShiaAiChatScreen(
          library: _FakeLibrary(),
          engine: engine,
          opener: opener,
          preferencesLoader: () async => preferences,
        ),
      );
    }

    ShiaAiEngine engineWith(
      _FakeGateway gateway, {
      List<ShiaAiEvidence>? evidence,
    }) {
      final retrieval = ShiaAiRetrieval(
        question: 'وضو',
        queries: const ['وضو'],
        terms: const {'وضو'},
        evidence: evidence ?? [_evidence('alkafi', 11), _evidence('quran', 5)],
      );
      return ShiaAiEngine(
        retriever: _FakeRetriever(retrieval),
        gateway: gateway,
        preferences: () async => const ShiaAiPreferences(
          gatewayUrl: 'https://gw.example',
          onlineEnabled: true,
        ),
      );
    }

    testWidgets('shows local-mode banner until online synthesis is enabled',
        (tester) async {
      final gateway = _FakeGateway(reply: null);
      await tester.pumpWidget(host(
        engine: ShiaAiEngine(retriever: _FakeRetriever(const ShiaAiRetrieval(
          question: '',
          queries: [],
          terms: {},
          evidence: [],
        ))),
        opener: (_, __, ___) async {},
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('مقامی موڈ'), findsOneWidget);
      expect(gateway.calls, 0);
    });

    testWidgets('answers with verified citations and opens the exact reader record',
        (tester) async {
      final gateway = _FakeGateway(
        reply: const ShiaAiGatewayResponse(
          answer: 'وضو کا طریقہ یہ ہے…',
          sufficient: true,
          usedIds: ['alkafi:11', 'ghost:999'],
        ),
      );
      final opened = <ShiaAiCitation>[];
      await tester.pumpWidget(host(
        engine: engineWith(gateway),
        opener: (context, library, citation) async {
          opened.add(citation);
          await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Reader')),
              body: const Center(
                  child: Text('READER DUMMY', textDirection: TextDirection.ltr)),
            ),
          ));
        },
        preferences: const ShiaAiPreferences(
          gatewayUrl: 'https://gw.example',
          onlineEnabled: true,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'وضو کیسے کریں؟');
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // The answer and exactly one verified citation are shown.
      expect(find.text('وضو کا طریقہ یہ ہے…'), findsOneWidget);
      expect(find.textContaining('الکافی'), findsWidgets);
      expect(find.textContaining('ghost'), findsNothing);
      expect(gateway.calls, 1);

      // Open the citation: the reader route lands on the cited record.
      await tester.tap(find.byIcon(Icons.menu_book).first);
      await tester.pumpAndSettle();
      expect(find.text('READER DUMMY'), findsOneWidget);
      expect(opened.single.citationId, 'alkafi:11');
      expect(opened.single.recordId, 11);

      // Back restores the same conversation, still mounted with its state.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('وضو کیسے کریں؟'), findsOneWidget);
      expect(find.text('وضو کا طریقہ یہ ہے…'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('shia-ai-message-list')),
          findsOneWidget);
    });

    testWidgets('scroll position is preserved across the reader round trip',
        (tester) async {
      tester.view.physicalSize = const Size(360, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final many = List.generate(6, (i) => _evidence('alkafi', 100 + i));
      final gateway = _FakeGateway(
        reply: const ShiaAiGatewayResponse(
          answer: 'لمبا جواب',
          sufficient: true,
          usedIds: [],
        ),
      );
      await tester.pumpWidget(host(
        engine: engineWith(gateway, evidence: many),
        opener: (context, library, citation) async {
          await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Reader')),
              body: const Center(
                  child: Text('READER DUMMY', textDirection: TextDirection.ltr)),
            ),
          ));
        },
        preferences: const ShiaAiPreferences(
          gatewayUrl: 'https://gw.example',
          onlineEnabled: true,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'پہلا سوال');
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'دوسرا سوال');
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final listFinder = find.byKey(const ValueKey<String>('shia-ai-message-list'));
      final scrollableFinder = find.descendant(
        of: listFinder,
        matching: find.byType(Scrollable),
      );
      await tester.drag(listFinder, const Offset(0, -220));
      await tester.pumpAndSettle();
      // The list is scrolled to its end, so target the last (visible) tile.
      final citationIcon = find.byIcon(Icons.menu_book).last;
      await tester.ensureVisible(citationIcon);
      await tester.pumpAndSettle();
      final before =
          tester.state<ScrollableState>(scrollableFinder).position.pixels;
      expect(before, greaterThan(0));

      await tester.tap(citationIcon);
      await tester.pumpAndSettle();
      expect(find.text('READER DUMMY'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      final after =
          tester.state<ScrollableState>(scrollableFinder).position.pixels;
      expect(after, before);
      // Both turns survived the round trip. The 175px list lazily unmounts
      // off-screen bubbles, so verify the conversation through its store
      // (the same persistence that restores chats after an app restart).
      final stored =
          await const ShiaAiConversationStore().loadMessages();
      final texts = stored.map((message) => message.text).toList();
      expect(texts, contains('پہلا سوال'));
      expect(texts, contains('دوسرا سوال'));
    });

    testWidgets('no-evidence turns show the plain abstention message',
        (tester) async {
      final gateway = _FakeGateway(reply: null);
      final engine = ShiaAiEngine(
        retriever: _FakeRetriever(const ShiaAiRetrieval(
          question: 'اجنبی سوال',
          queries: ['اجنبی سوال'],
          terms: {'اجنبی'},
          evidence: [],
        )),
        gateway: gateway,
        preferences: () async => const ShiaAiPreferences(
          gatewayUrl: 'https://gw.example',
          onlineEnabled: true,
        ),
      );
      await tester.pumpWidget(host(engine: engine, opener: (_, __, ___) async {}));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'اجنبی سوال');
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('کوئی عبارت نہیں ملی'), findsOneWidget);
      expect(gateway.calls, 0);
    });

    testWidgets('Xplore Xtra exposes a ShiaAi card that opens the chat',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: XploreXtraScreen(library: _FakeLibrary()),
      ));
      await tester.pumpAndSettle();

      final card = find.text('ShiaAi — ذہین سوال و جواب');
      expect(card, findsOneWidget);
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pumpAndSettle();

      expect(find.byType(ShiaAiChatScreen), findsOneWidget);
    });
  });
}

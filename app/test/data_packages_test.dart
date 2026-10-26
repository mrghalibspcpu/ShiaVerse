import 'package:flutter_test/flutter_test.dart';
import 'package:shiaverse/data_packages.dart';

const String _manifest = '''
{
  "format_version": 2,
  "database_count": 2,
  "download": {
    "extension": ".gz",
    "base_urls": [
      "https://github.com/mrghalibspcpu/Shia-Ai/releases/download/databases-v2/",
      "https://github.com/mrghalibspcpu/Shia-Ai/releases/download/databases-v1/",
      "https://raw.githubusercontent.com/mrghalibspcpu/Shia-Ai/main/assets"
    ]
  },
  "databases": [
    {
      "name": "quran.db",
      "key": "quran",
      "source": "quran",
      "title_urdu": "قرآنِ کریم",
      "title_latin": "Al-Quran al-Karim",
      "size_bytes": 16943104,
      "sha256": "c09009ac4f3d0000000000000000000000000000000000000000000000000000",
      "records": {"Quran": 6236}
    },
    {
      "name": "alkafi.db",
      "key": "alkafi",
      "source": "hadith",
      "title_urdu": "الکافی",
      "size_bytes": 27953152,
      "sha256": "23c030d6ffd6244edf0503b7eabc8f42addfbef3aad8c67a80a20583998821b8"
    }
  ]
}
''';

void main() {
  group('manifest parsing', () {
    test('reads packages, sizes, and download settings', () {
      final catalog = DataCatalog.parse(_manifest);
      expect(catalog.packages, hasLength(2));
      expect(catalog.extension, '.gz');
      expect(catalog.totalBytes, 16943104 + 27953152);
      expect(catalog.byKey('quran')?.fileName, 'quran.db');
      expect(catalog.byKey('alkafi')?.source, 'hadith');
      expect(catalog.byKey('missing'), isNull);
    });

    test('normalises base URLs to end with a slash', () {
      final catalog = DataCatalog.parse(_manifest);
      expect(catalog.baseUrls.last, endsWith('/assets/'));
    });

    test('rejects malformed payloads instead of throwing', () {
      expect(DataCatalog.parse('[]').isEmpty, isTrue);
      expect(DataCatalog.parse('not json').isEmpty, isTrue);
    });

    test('marks an entry without a digest as not downloadable', () {
      const package = DataPackage(
        key: 'x',
        fileName: 'x.db',
        titleUrdu: '',
        titleLatin: '',
        source: 'hadith',
        sizeBytes: 10,
        sha256: 'short',
      );
      expect(package.isDownloadable, isFalse);
    });
  });

  group('download URLs', () {
    const package = DataPackage(
      key: 'quran',
      fileName: 'quran.db',
      titleUrdu: 'قرآن',
      titleLatin: 'Quran',
      source: 'quran',
      sizeBytes: 100,
      sha256: 'c09009ac4f3d0000000000000000000000000000000000000000000000000000',
    );

    test('prefers the compiled mirror, then releases, then the repository', () {
      final urls = downloadUrlsFor(
        package: package,
        baseUrls: const ['https://releases.example/', 'https://repo.example/'],
        extension: '.gz',
        overrideBaseUrl: 'https://mirror.example',
      );
      expect(urls.first, 'https://mirror.example/quran.db.gz');
      expect(urls[1], 'https://releases.example/quran.db.gz');
      expect(urls[2], 'https://repo.example/quran.db.gz');
      expect(urls.last, 'https://repo.example/quran.db', reason: 'uncompressed fallback');
    });

    test('formats sizes for the Urdu UI', () {
      expect(formatBytes(0), '0 MB');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2.0 KB');
      expect(formatBytes(16943104), '16 MB');
      expect(formatBytes(241000000), '230 MB');
    });
  });
}

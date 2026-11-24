import 'package:flutter_test/flutter_test.dart';
import 'package:galley/galley.dart';

void main() {
  test('DrmProtectedException expõe algoritmos e mensagem', () {
    final e = DrmProtectedException(['urn:x']);
    expect(e, isA<GalleyException>());
    expect(e.algorithms, ['urn:x']);
    expect(e.toString(), startsWith('DrmProtectedException: '));
    expect(e.message, contains('urn:x'));
  });

  test('toString usa o nome da classe e a mensagem', () {
    expect(NotAnEpubException('ruim').toString(), 'NotAnEpubException: ruim');
    expect(
      CorruptArchiveException('zip').toString(),
      'CorruptArchiveException: zip',
    );
    expect(
      ArchiveLimitExceededException('grande').toString(),
      'ArchiveLimitExceededException: grande',
    );
    expect(
      MissingPackageDocumentException('opf').toString(),
      'MissingPackageDocumentException: opf',
    );
  });

  test('ResourceNotFoundException expõe o caminho', () {
    final e = ResourceNotFoundException('OEBPS/a.xhtml');
    expect(e.path, 'OEBPS/a.xhtml');
    expect(e.message, contains('OEBPS/a.xhtml'));
    expect(e.toString(), startsWith('ResourceNotFoundException: '));
  });

  test('BookClosedException tem mensagem fixa', () {
    expect(BookClosedException().message, isNotEmpty);
    expect(BookClosedException(), isA<GalleyException>());
  });
}

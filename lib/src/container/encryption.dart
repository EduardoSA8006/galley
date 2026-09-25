/// `META-INF/encryption.xml`, `rights.xml` e detecção de DRM (spec do
/// contêiner §6).
library;

import 'package:xml/xml.dart';

import '../diagnostics/diagnostic.dart';
import '../diagnostics/exceptions.dart';
import 'container.dart';
import 'zip/central_directory.dart';

const String idpfObfuscationAlgorithm = 'http://www.idpf.org/2008/embedding';
const String adobeObfuscationAlgorithm = 'http://ns.adobe.com/pdf/enc#RC';
const String lcpContentKeyType =
    'http://readium.org/2014/01/lcp#EncryptedContentKey';
const String adeptNamespace = 'http://ns.adobe.com/adept';

const Set<String> _fontExtensions = {
  '.ttf',
  '.otf',
  '.ttc',
  '.otc',
  '.woff',
  '.woff2',
};

/// Extensão de fonte, sem diferenciar maiúsculas.
bool isFontPath(String path) {
  final lower = path.toLowerCase();
  final dot = lower.lastIndexOf('.');
  return dot >= 0 && _fontExtensions.contains(lower.substring(dot));
}

/// `CipherReference URI`: `%xx` decodificado (texto cru se inválido) e a
/// normalização de nome do central directory.
String normalizeCipherReference(String uri) {
  String decoded;
  try {
    decoded = Uri.decodeComponent(uri);
  } on ArgumentError {
    decoded = uri;
  }
  return normalizeEntryName(decoded);
}

/// Um `EncryptedData` com `CipherReference`.
final class EncryptedItem {
  const EncryptedItem({
    required this.algorithm,
    required this.uri,
    required this.lcpKey,
    required this.adeptKey,
  });

  /// `EncryptionMethod@Algorithm`; `''` se ausente.
  final String algorithm;

  /// `CipherReference@URI`, já normalizado.
  final String uri;

  /// `KeyInfo/RetrievalMethod` com o `Type` do LCP.
  final bool lcpKey;

  /// `KeyInfo` com elemento no namespace do ADEPT.
  final bool adeptKey;
}

/// Itens de `encryption.xml`, em ordem de documento. Lê por nome local, em
/// qualquer prefixo ou namespace. `EncryptedData` sem `CipherReference` é
/// ignorado. [XmlException] se o XML for inválido.
List<EncryptedItem> parseEncryptionXml(String text) {
  final doc = XmlDocument.parse(text);
  final items = <EncryptedItem>[];
  for (final data in doc.findAllElements('EncryptedData', namespaceUri: '*')) {
    final reference = data
        .findAllElements('CipherReference', namespaceUri: '*')
        .firstOrNull
        ?.getAttribute('URI');
    if (reference == null) continue;
    final method = data
        .findElements('EncryptionMethod', namespaceUri: '*')
        .firstOrNull;
    final keyInfos = data.findAllElements('KeyInfo', namespaceUri: '*');
    items.add(
      EncryptedItem(
        algorithm: method?.getAttribute('Algorithm') ?? '',
        uri: normalizeCipherReference(reference),
        lcpKey: keyInfos.any(
          (k) => k
              .findAllElements('RetrievalMethod', namespaceUri: '*')
              .any((r) => r.getAttribute('Type') == lcpContentKeyType),
        ),
        adeptKey: keyInfos.any(
          (k) =>
              k.namespaceUri == adeptNamespace ||
              k.descendantElements.any((e) => e.namespaceUri == adeptNamespace),
        ),
      ),
    );
  }
  return items;
}

/// Esquema de `rights.xml`: `adobe-adept` com o namespace do ADEPT, senão
/// `unknown:rights.xml` (inclusive XML inválido).
String rightsScheme(String text) {
  try {
    final doc = XmlDocument.parse(text);
    final adept = doc.descendantElements.any(
      (e) => e.namespaceUri == adeptNamespace,
    );
    return adept ? 'adobe-adept' : 'unknown:rights.xml';
  } on XmlException {
    return 'unknown:rights.xml';
  }
}

/// Aplica a tabela de §6 aos [items]. Com [drmIsFatal] (ZIP), LCP, ADEPT e
/// qualquer cifra sobre caminho que não é fonte lançam
/// [EpubEncryptedException]; sem ele (provider), só as fontes contam.
///
/// [resolve] leva o URI normalizado ao nome da entrada (mesmo índice de
/// `fetch`). Devolve a ofuscação por nome resolvido e emite
/// `fontObfuscationUnknown` para algoritmo desconhecido sobre fonte.
Map<String, FontObfuscation> resolveEncryption(
  List<EncryptedItem> items, {
  required String Function(String uri) resolve,
  required DiagnosticSink sink,
  required bool drmIsFatal,
}) {
  if (drmIsFatal) {
    if (items.any((i) => i.lcpKey)) {
      throw EpubEncryptedException(
        'conteúdo cifrado com Readium LCP (KeyInfo em encryption.xml): '
        'esquema lcp',
        scheme: 'lcp',
      );
    }
    if (items.any((i) => i.adeptKey)) {
      throw EpubEncryptedException(
        'conteúdo cifrado com Adobe ADEPT (KeyInfo em encryption.xml): '
        'esquema adobe-adept',
        scheme: 'adobe-adept',
      );
    }
    for (final item in items) {
      final path = resolve(item.uri);
      if (!isFontPath(path)) {
        throw EpubEncryptedException(
          'recurso cifrado com algoritmo "${item.algorithm}": '
          'esquema unknown:${item.algorithm}',
          scheme: 'unknown:${item.algorithm}',
          href: path,
        );
      }
    }
  }
  final result = <String, FontObfuscation>{};
  for (final item in items) {
    final path = resolve(item.uri);
    if (!isFontPath(path)) continue;
    final kind = switch (item.algorithm) {
      idpfObfuscationAlgorithm => FontObfuscation.idpf,
      adobeObfuscationAlgorithm => FontObfuscation.adobe,
      _ => FontObfuscation.unknown,
    };
    result[path] = kind;
    if (kind == FontObfuscation.unknown) {
      sink.emit(
        EpubDiagnosticCode.fontObfuscationUnknown,
        href: path,
        message: 'fonte com ofuscação não reconhecida: "${item.algorithm}"',
        details: {'algorithm': item.algorithm},
      );
    }
  }
  return result;
}

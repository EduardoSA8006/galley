/// OPF: leitura por nome local, metadados, manifest, spine e guide (spec da
/// Publicação §6). Pura: os `href` saem crus e quem resolve é o orquestrador.
///
/// Linear no tamanho do OPF: um parse do `package:xml`, uma passada
/// iterativa pelos descendentes de `metadata` (o texto de cada elemento vem
/// só dos filhos diretos, nunca de `innerText`, que repercorreria a
/// subárvore em metadado aninhado), uma pelos filhos de `manifest`, `spine`
/// e `guide`, e refinamentos por mapa de `id`. O `package:xml` não obriga
/// `id` único: com `id` repetido (hostil), só o primeiro elemento com cada
/// `id` (o "dono") consulta os seus refinamentos; os demais recebem lista
/// vazia em O(1), senão N elementos com o mesmo `id` e N refinamentos
/// seriam O(N²).
library;

import 'package:xml/xml.dart';

import '../diagnostics/diagnostic.dart';
import '../diagnostics/exceptions.dart';
import 'metadata.dart';
import 'model.dart';

const String dcNamespace = 'http://purl.org/dc/elements/1.1/';

/// `<item>` do manifest, cru.
final class OpfItem {
  const OpfItem({
    required this.id,
    required this.href,
    required this.mediaType,
    required this.properties,
    this.fallback,
  });

  final String id;

  /// Cru, como no OPF.
  final String href;

  /// Cru, como no OPF (`''` se ausente).
  final String mediaType;
  final Set<String> properties;
  final String? fallback;
}

/// `<itemref>` do spine com `idref` resolvido e não repetido.
final class OpfItemRef {
  const OpfItemRef({required this.idref, required this.linear});

  final String idref;
  final bool linear;
}

/// `<reference>` do `guide` (EPUB2).
final class OpfReference {
  const OpfReference({
    required this.type,
    required this.title,
    required this.href,
  });

  final String type;
  final String title;

  /// Cru, relativo ao OPF.
  final String href;
}

/// O que o orquestrador precisa do OPF.
final class OpfDocument {
  OpfDocument({
    required this.opfPath,
    required this.version,
    required this.metadata,
    required List<String> identifiers,
    required List<String> uniqueIdentifiers,
    required List<OpfItem> items,
    required List<OpfItemRef> itemrefs,
    required this.spineToc,
    required this.direction,
    required this.layout,
    required List<OpfReference> guide,
    required this.coverId,
  }) : identifiers = List.unmodifiable(identifiers),
       uniqueIdentifiers = List.unmodifiable(uniqueIdentifiers),
       items = List.unmodifiable(items),
       itemrefs = List.unmodifiable(itemrefs),
       guide = List.unmodifiable(guide);

  /// Caminho do OPF no contêiner (o `opfPath` de [parseOpf]); usado para
  /// resolver `href` relativos a ele, como o do `<meta name="cover">` com
  /// `href` no lugar do id (spec §8.2).
  final String opfPath;

  /// Atributo `version` do `<package>`, cru (`''` se ausente).
  final String version;
  final EpubMetadata metadata;

  /// Todos os `dc:identifier` não vazios, em ordem, com `trim`.
  final List<String> identifiers;

  /// O `dc:identifier` do `unique-identifier`; sem casamento,
  /// `[identifiers.first]` (se houver).
  final List<String> uniqueIdentifiers;

  /// Itens com `id` e `href`, na ordem do OPF; `id` repetido: o primeiro.
  final List<OpfItem> items;

  /// `itemref` com item, sem `idref` repetido, em ordem.
  final List<OpfItemRef> itemrefs;

  /// Atributo `toc` do `<spine>` (id do NCX).
  final String? spineToc;
  final EpubReadingDirection direction;
  final EpubLayoutMode layout;
  final List<OpfReference> guide;

  /// `content` do `<meta name="cover">`.
  final String? coverId;
}

/// Lê o OPF. [EpubPackageException] (`href: opfPath`) com XML inválido,
/// raiz que não é `package`, sem `manifest` ou sem `spine`. Emite
/// `resourceMissing` (item sem `id`/`href`), `spineItemUnresolved` e
/// `spineItemDuplicate`; em `strict`, os warnings lançam
/// [EpubPackageException].
OpfDocument parseOpf(
  String text, {
  required String opfPath,
  required DiagnosticSink sink,
}) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(text);
  } on XmlException catch (e) {
    throw EpubPackageException(
      'OPF não é XML válido: ${e.message}',
      href: opfPath,
      cause: e,
    );
  }
  final root = document.rootElement;
  if (root.name.local != 'package') {
    throw EpubPackageException(
      'raiz do OPF é <${root.name.qualified}>, não <package>',
      href: opfPath,
    );
  }
  final manifest = _child(root, 'manifest');
  if (manifest == null) {
    throw EpubPackageException('OPF sem <manifest>', href: opfPath);
  }
  final spine = _child(root, 'spine');
  if (spine == null) {
    throw EpubPackageException('OPF sem <spine>', href: opfPath);
  }
  EpubPackageException strictError(String m) =>
      EpubPackageException(m, href: opfPath);

  final items = <OpfItem>[];
  final ids = <String>{};
  for (final e in manifest.childElements) {
    if (e.name.local != 'item') continue;
    final id = _attr(e, 'id');
    final href = e.getAttribute('href', namespaceUri: '*');
    if (id == null || id.isEmpty || href == null) {
      sink.emit(
        EpubDiagnosticCode.resourceMissing,
        message: id == null || id.isEmpty
            ? 'item do manifest sem id descartado'
            : 'item do manifest "$id" sem href descartado',
        details: {
          'reason': id == null || id.isEmpty ? 'no-id' : 'no-href',
          if (id != null && id.isNotEmpty) 'id': id,
        },
        onStrict: strictError,
      );
      continue;
    }
    if (!ids.add(id)) continue;
    items.add(
      OpfItem(
        id: id,
        href: href,
        mediaType: _attr(e, 'media-type') ?? '',
        properties: _tokens(_attr(e, 'properties')),
        fallback: _attr(e, 'fallback'),
      ),
    );
  }

  final itemrefs = <OpfItemRef>[];
  final seen = <String>{};
  for (final e in spine.childElements) {
    if (e.name.local != 'itemref') continue;
    final idref = _attr(e, 'idref') ?? '';
    if (!ids.contains(idref)) {
      sink.emit(
        EpubDiagnosticCode.spineItemUnresolved,
        href: opfPath,
        message: 'itemref "$idref" sem item no manifest; ignorado',
        details: {'idref': idref},
        onStrict: strictError,
      );
      continue;
    }
    if (!seen.add(idref)) {
      sink.emit(
        EpubDiagnosticCode.spineItemDuplicate,
        href: opfPath,
        message: 'itemref "$idref" repetido; vale o primeiro',
        details: {'idref': idref},
        onStrict: strictError,
      );
      continue;
    }
    itemrefs.add(
      OpfItemRef(
        idref: idref,
        linear: _attr(e, 'linear')?.toLowerCase() != 'no',
      ),
    );
  }

  final guide = <OpfReference>[];
  final guideElement = _child(root, 'guide');
  if (guideElement != null) {
    for (final e in guideElement.childElements) {
      if (e.name.local != 'reference') continue;
      final href = e.getAttribute('href', namespaceUri: '*');
      if (href == null) continue;
      guide.add(
        OpfReference(
          type: _attr(e, 'type') ?? '',
          title: _attr(e, 'title') ?? '',
          href: href,
        ),
      );
    }
  }

  final meta = _Metadata(
    _child(root, 'metadata'),
    uniqueIdentifierId: _attr(root, 'unique-identifier'),
  );
  return OpfDocument(
    opfPath: opfPath,
    version: root.getAttribute('version', namespaceUri: '*') ?? '',
    metadata: meta.metadata,
    identifiers: meta.identifiers,
    uniqueIdentifiers: meta.uniqueIdentifiers,
    items: items,
    itemrefs: itemrefs,
    spineToc: _attr(spine, 'toc'),
    direction: switch (_attr(
      spine,
      'page-progression-direction',
    )?.toLowerCase()) {
      'ltr' => EpubReadingDirection.ltr,
      'rtl' => EpubReadingDirection.rtl,
      _ => EpubReadingDirection.auto,
    },
    layout: meta.layout,
    guide: guide,
    coverId: meta.coverId,
  );
}

XmlElement? _child(XmlElement parent, String local) {
  for (final e in parent.childElements) {
    if (e.name.local == local) return e;
  }
  return null;
}

/// Atributo por nome local (`opf:role` = `role`), com `trim`.
String? _attr(XmlElement e, String local) =>
    e.getAttribute(local, namespaceUri: '*')?.trim();

Set<String> _tokens(String? value) => value == null
    ? const {}
    : value.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();

/// Texto dos filhos diretos (texto e CDATA), com `trim`.
String _ownText(XmlElement e) {
  final buffer = StringBuffer();
  for (final node in e.children) {
    if (node is XmlText) {
      buffer.write(node.value);
    } else if (node is XmlCDATA) {
      buffer.write(node.value);
    }
  }
  return buffer.toString().trim();
}

/// Um `dc:*` ou `meta` de `metadata`, em ordem de documento.
final class _Element {
  _Element.dc(XmlElement e)
    : isDc = true,
      name = e.name.local.toLowerCase(),
      text = _ownText(e),
      id = _attr(e, 'id'),
      role = _attr(e, 'role')?.toLowerCase(),
      event = _attr(e, 'event')?.toLowerCase(),
      metaName = null,
      content = null,
      property = null,
      refines = null;

  _Element.meta(XmlElement e)
    : isDc = false,
      name = 'meta',
      text = _ownText(e),
      id = _attr(e, 'id'),
      role = null,
      event = null,
      metaName = _attr(e, 'name'),
      content = _attr(e, 'content'),
      property = _attr(e, 'property'),
      refines = _refinedId(_attr(e, 'refines'));

  final bool isDc;

  /// Nome local em minúsculas do `dc:*` (`title`, `creator`…), ou `meta`.
  final String name;
  final String text;
  final String? id;
  final String? role;
  final String? event;
  final String? metaName;
  final String? content;
  final String? property;
  final String? refines;

  static String? _refinedId(String? refines) {
    if (refines == null || refines.isEmpty) return null;
    return refines.startsWith('#') ? refines.substring(1) : refines;
  }
}

bool _isDc(XmlElement e) =>
    e.namespaceUri == dcNamespace || e.name.prefix == 'dc';

/// Montagem dos metadados (spec §6.2) e dos identificadores (§6.3).
final class _Metadata {
  _Metadata(XmlElement? element, {required String? uniqueIdentifierId}) {
    if (element != null) {
      for (final e in element.descendantElements) {
        if (_isDc(e)) {
          _all.add(_Element.dc(e));
        } else if (e.name.local == 'meta') {
          _all.add(_Element.meta(e));
        }
      }
    }
    for (final e in _all) {
      final id = e.id;
      if (id != null && id.isNotEmpty) {
        _owner.putIfAbsent(id, () => e);
      }
      final refined = e.refines;
      if (!e.isDc && refined != null) {
        (_refinements[refined] ??= []).add(e);
      }
    }
    _identifiers(uniqueIdentifierId);
    _build();
  }

  final List<_Element> _all = [];
  final Map<String, List<_Element>> _refinements = {};

  /// Primeiro elemento com cada `id` em `metadata`: só o dono consulta os
  /// seus refinamentos (senão, `id` repetido faz cada um copiar a lista
  /// inteira de refinamentos do outro, o(N²) num OPF hostil).
  final Map<String, _Element> _owner = {};
  final Set<_Element> _used = Set.identity();

  final List<String> identifiers = [];
  final List<String> uniqueIdentifiers = [];
  late final EpubMetadata metadata;
  EpubLayoutMode layout = EpubLayoutMode.reflowable;
  String? coverId;

  Iterable<_Element> _dc(String name) =>
      _all.where((e) => e.isDc && e.name == name && e.text.isNotEmpty);

  Iterable<_Element> _meta({String? property, String? name}) => _all.where(
    (e) =>
        !e.isDc &&
        e.refines == null &&
        (property == null || e.property == property) &&
        (name == null || e.metaName == name),
  );

  /// `meta` que refinam [e] com [property] e texto não vazio. Vazio quando
  /// [e] não é o dono do seu `id` (`id` repetido: só o primeiro consulta;
  /// os outros não pagam o custo de repercorrer a lista de refinamentos).
  List<_Element> _refinedBy(_Element e, String property) {
    final id = e.id;
    if (id == null || !identical(_owner[id], e)) return const [];
    return [
      for (final r in _refinements[id] ?? const <_Element>[])
        if (r.property == property && r.text.isNotEmpty) r,
    ];
  }

  /// Primeiro refinamento de [e] com [property] e texto não vazio, sem
  /// marcar nada como usado (quem chama decide se ele vira campo).
  _Element? _firstRefinement(_Element e, String property) {
    final id = e.id;
    if (id == null || !identical(_owner[id], e)) return null;
    for (final r in _refinements[id] ?? const <_Element>[]) {
      if (r.property == property && r.text.isNotEmpty) return r;
    }
    return null;
  }

  /// Valores dos refinamentos de [e] com [property], marcados como usados.
  List<String> _refinedValues(_Element e, String property) {
    final refs = _refinedBy(e, property);
    _used.addAll(refs);
    return [for (final r in refs) r.text];
  }

  String? _first(String name) {
    final e = _dc(name).firstOrNull;
    if (e == null) return null;
    _used.add(e);
    return e.text;
  }

  void _identifiers(String? uniqueIdentifierId) {
    _Element? unique;
    for (final e in _dc('identifier')) {
      identifiers.add(e.text);
      if (unique == null && e.id != null && e.id == uniqueIdentifierId) {
        unique = e;
      }
    }
    unique ??= _dc('identifier').firstOrNull;
    if (unique != null) {
      uniqueIdentifiers.add(unique.text);
      _used.add(unique);
    }
  }

  void _build() {
    // Títulos.
    final titles = _dc('title').toList();
    String? typeOf(_Element t) {
      final r = _firstRefinement(t, 'title-type');
      if (r != null) _used.add(r);
      return r?.text.toLowerCase();
    }

    final types = {for (final t in titles) t: typeOf(t)};
    final title =
        titles.where((t) => types[t] == 'main').firstOrNull ??
        titles
            .where((t) => types[t] != 'subtitle' && types[t] != 'expanded')
            .firstOrNull ??
        titles.firstOrNull;
    final subtitle = titles
        .where((t) => !identical(t, title) && types[t] == 'subtitle')
        .firstOrNull;
    if (title != null) _used.add(title);
    if (subtitle != null) _used.add(subtitle);

    // Autores e colaboradores.
    final authors = <String>[];
    final contributors = <String>[];
    for (final e in _all) {
      if (!e.isDc || e.text.isEmpty) continue;
      if (e.name != 'creator' && e.name != 'contributor') continue;
      final roles = [
        ?e.role,
        for (final r in _refinedValues(e, 'role')) r.toLowerCase(),
      ];
      final isAuthor =
          e.name == 'creator' && (roles.isEmpty || roles.contains('aut'));
      (isAuthor ? authors : contributors).add(e.text);
      _used.add(e);
    }

    // Série.
    String? series;
    double? seriesIndex;
    for (final c in _meta(property: 'belongs-to-collection')) {
      if (c.text.isEmpty) continue;
      final kinds = [
        for (final k in _refinedBy(c, 'collection-type')) k.text.toLowerCase(),
      ];
      // Coleção que não é série (`set`) fica em raw, com os refinamentos.
      if (kinds.isNotEmpty && !kinds.contains('series')) continue;
      series = c.text;
      _used
        ..add(c)
        ..addAll(_refinedBy(c, 'collection-type'));
      final position = _firstRefinement(c, 'group-position');
      if (position != null) {
        final value = double.tryParse(position.text);
        if (value != null && value.isFinite) {
          seriesIndex = value;
          _used.add(position);
        }
      }
      break;
    }
    if (series == null) {
      final calibre = _meta(name: 'calibre:series')
          .where((e) => (e.content ?? '').isNotEmpty)
          .firstOrNull;
      if (calibre != null) {
        series = calibre.content;
        _used.add(calibre);
        final index = _meta(name: 'calibre:series_index').firstOrNull;
        if (index != null) {
          final value = double.tryParse(index.content ?? '');
          if (value != null && value.isFinite) {
            seriesIndex = value;
            _used.add(index);
          }
        }
      }
    }

    // Datas.
    final dates = _dc('date').toList();
    final publication =
        dates.where((d) => d.event == 'publication').firstOrNull ??
        dates.where((d) => d.event != 'modification').firstOrNull;
    final published = _date(publication);
    final modifiedMeta = _meta(property: 'dcterms:modified')
        .where((e) => e.text.isNotEmpty)
        .firstOrNull;
    final modified = _date(
      modifiedMeta ?? dates.where((d) => d.event == 'modification').firstOrNull,
    );

    // Layout e capa (campos do OpfDocument, não de raw).
    final layoutMeta = _meta(property: 'rendition:layout').firstOrNull;
    if (layoutMeta != null) {
      _used.add(layoutMeta);
      if (layoutMeta.text == 'pre-paginated') {
        layout = EpubLayoutMode.prePaginated;
      }
    }
    final cover = _meta(name: 'cover')
        .where((e) => (e.content ?? '').isNotEmpty)
        .firstOrNull;
    if (cover != null) {
      coverId = cover.content;
      _used.add(cover);
    }

    final language = _first('language');
    final publisher = _first('publisher');
    final description = _first('description');
    final rights = _first('rights');
    final subjects = [for (final s in _dc('subject')) s.text];
    _used.addAll(_dc('subject'));

    metadata = EpubMetadata(
      title: title?.text,
      subtitle: subtitle?.text,
      authors: authors,
      contributors: contributors,
      language: language,
      publisher: publisher,
      identifier: uniqueIdentifiers.firstOrNull,
      description: description,
      published: published,
      modified: modified,
      subjects: subjects,
      rights: rights,
      series: series,
      seriesIndex: seriesIndex,
      raw: _raw(),
    );
  }

  /// Data do elemento, marcado como usado só se parseia.
  DateTime? _date(_Element? e) {
    if (e == null) return null;
    final value = parseEpubDate(e.text);
    if (value != null) _used.add(e);
    return value;
  }

  Map<String, List<String>> _raw() {
    final raw = <String, List<String>>{};
    for (final e in _all) {
      if (_used.contains(e)) continue;
      if (e.isDc) {
        if (e.text.isNotEmpty) (raw[e.name] ??= []).add(e.text);
      } else if (e.property != null && e.property!.isNotEmpty) {
        // `content` vazio conta como ausente; sem texto, `content` supre.
        final content = e.content;
        final value = e.text.isNotEmpty
            ? e.text
            : (content != null && content.isNotEmpty ? content : null);
        if (value != null) (raw[e.property!] ??= []).add(value);
      } else if (e.metaName != null && e.metaName!.isNotEmpty) {
        final content = e.content;
        if (content != null && content.isNotEmpty) {
          (raw[e.metaName!] ??= []).add(content);
        }
      }
    }
    return raw;
  }
}

/// Gramática do EPUB para datas (um subconjunto validado de ISO 8601, spec
/// da Publicação §6.2, decisão 11): `YYYY`, `YYYY-MM`, `YYYY-MM-DD`, ou
/// `YYYY-MM-DDThh:mm(:ss(.fração)?)?` com `Z` ou `±hh:mm` opcional. Nada de
/// ano expandido (`+`/`-` na frente), nada de hora sem minuto.
final RegExp _epubDate = RegExp(
  r'^(?<year>\d{4})'
  r'(-(?<month>\d{2})'
  r'(-(?<day>\d{2})'
  r'(T(?<hour>\d{2}):(?<minute>\d{2})'
  r'(:(?<second>\d{2})(?:\.(?<fraction>\d+))?)?'
  r'(?<offset>Z|[+-]\d{2}:\d{2})?'
  r')?'
  r')?'
  r')?'
  r'$',
);

const List<int> _daysInMonthTable = [
  31,
  28,
  31,
  30,
  31,
  30,
  31,
  31,
  30,
  31,
  30,
  31,
];

bool _isLeapYear(int year) =>
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

int _daysInMonth(int year, int month) =>
    month == 2 && _isLeapYear(year) ? 29 : _daysInMonthTable[month - 1];

/// `YYYY` → 1º de janeiro; `YYYY-MM` → dia 1; `YYYY-MM-DD`; e com hora,
/// `YYYY-MM-DDThh:mm(:ss(.fração)?)?`, com `Z`/`±hh:mm` (até `+14:00`) ou,
/// sem offset, interpretada como UTC. Sempre `isUtc`. Calendário inválido
/// (mês fora de 1–12, dia fora do mês — inclusive 29/02 fora de bissexto,
/// hora/minuto/segundo fora do intervalo, offset acima de 14:00) ou texto
/// que não casa com a gramática (inclusive acima de 64 caracteres, ou ano
/// expandido com sinal) é `null` (spec da Publicação §6.2, decisão 11: nada
/// de `DateTime.parse` normalizando data inválida).
DateTime? parseEpubDate(String text) {
  final s = text.trim();
  if (s.isEmpty || s.length > 64) return null;
  final m = _epubDate.firstMatch(s);
  if (m == null) return null;

  final year = int.parse(m.namedGroup('year')!);
  final monthText = m.namedGroup('month');
  final month = monthText == null ? 1 : int.parse(monthText);
  if (month < 1 || month > 12) return null;
  final dayText = m.namedGroup('day');
  final day = dayText == null ? 1 : int.parse(dayText);
  if (day < 1 || day > _daysInMonth(year, month)) return null;

  final hourText = m.namedGroup('hour');
  if (hourText == null) {
    return DateTime.utc(year, month, day);
  }
  final hour = int.parse(hourText);
  final minute = int.parse(m.namedGroup('minute')!);
  final secondText = m.namedGroup('second');
  final second = secondText == null ? 0 : int.parse(secondText);
  if (hour > 23 || minute > 59 || second > 59) return null;
  final fractionText = m.namedGroup('fraction');
  final milliseconds = fractionText == null
      ? 0
      : int.parse('${fractionText}000'.substring(0, 3));

  var utcHour = hour;
  var utcMinute = minute;
  final offset = m.namedGroup('offset');
  if (offset != null && offset != 'Z') {
    final sign = offset.startsWith('-') ? -1 : 1;
    final offsetHour = int.parse(offset.substring(1, 3));
    final offsetMinute = int.parse(offset.substring(4, 6));
    if (offsetHour > 14 ||
        offsetMinute > 59 ||
        (offsetHour == 14 && offsetMinute > 0)) {
      return null;
    }
    utcHour -= sign * offsetHour;
    utcMinute -= sign * offsetMinute;
  }
  return DateTime.utc(
    year,
    month,
    day,
    utcHour,
    utcMinute,
    second,
    milliseconds,
  );
}

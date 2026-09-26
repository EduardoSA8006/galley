// reconcileToc: órfãos do spine no TOC (spec da Publicação §7.6).
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/publication/model.dart';
import 'package:galley/src/publication/reconcile.dart';

List<SpineItem> _spine(List<String> names, {Set<String> nonLinear = const {}}) {
  return [
    for (final n in names)
      () {
        final item = ManifestItem(
          id: n,
          path: 'OEBPS/$n.xhtml',
          mediaType: 'application/xhtml+xml',
        );
        return SpineItem(
          idref: n,
          item: item,
          content: item,
          linear: !nonLinear.contains(n),
        );
      }(),
  ];
}

NavPoint _entry(String name, {List<NavPoint> children = const []}) => NavPoint(
  title: name.toUpperCase(),
  target: NavTarget('OEBPS/$name.xhtml', 'f'),
  children: children,
);

List<String> _titles(List<NavPoint> toc) => [
  for (final e in toc) e.synthesized ? '+${e.title}' : e.title,
];

void main() {
  test('sem órfão: o mesmo TOC e nenhum diagnóstico', () {
    final sink = DiagnosticSink();
    final toc = [_entry('a'), _entry('b')];
    expect(reconcileToc(toc, _spine(['a', 'b']), sink: sink), same(toc));
    expect(sink.diagnostics, isEmpty);
  });

  test('órfãos no começo, no meio, no fim e consecutivos', () {
    final sink = DiagnosticSink();
    final out = reconcileToc(
      [_entry('c'), _entry('f')],
      _spine(['a', 'b', 'c', 'd', 'e', 'f', 'g']),
      sink: sink,
    );
    expect(_titles(out), ['+a', '+b', 'C', '+d', '+e', 'F', '+g']);
    final synthesized = out.first;
    expect(synthesized.target, const NavTarget('OEBPS/a.xhtml'));
    expect(synthesized.children, isEmpty);
    final d = sink.diagnostics.single;
    expect(d.code, EpubDiagnosticCode.tocReconciled);
    expect(d.severity, EpubSeverity.info);
    expect(d.href, isNull);
    expect(d.details, {'orphans': 5, 'count': 1});
  });

  test('coberto em qualquer nível não é órfão; posição pelo descendente', () {
    final out = reconcileToc(
      [
        NavPoint(title: 'Parte', children: [_entry('b')]),
        _entry('d'),
      ],
      _spine(['a', 'b', 'c', 'd']),
      sink: DiagnosticSink(),
    );
    expect(_titles(out), ['+a', 'Parte', '+c', 'D']);
  });

  test('ordem do TOC manda: raiz fora de ordem não se move', () {
    final out = reconcileToc(
      [_entry('d'), _entry('b')],
      _spine(['a', 'b', 'c', 'd', 'e']),
      sink: DiagnosticSink(),
    );
    // c (índice 2): última raiz com primeira < 2 é "b" (posição 1).
    // e (índice 4): a última raiz, na ordem do TOC, com primeira < 4 é "b".
    expect(_titles(out), ['+a', 'D', 'B', '+c', '+e']);
  });

  test('linear="no" nunca é órfão, e a entrada para ele é mantida', () {
    final sink = DiagnosticSink();
    final withEntry = reconcileToc(
      [_entry('a'), _entry('notas')],
      _spine(['a', 'notas'], nonLinear: {'notas'}),
      sink: sink,
    );
    expect(_titles(withEntry), ['A', 'NOTAS']);
    final without = reconcileToc(
      [_entry('a')],
      _spine(['a', 'notas'], nonLinear: {'notas'}),
      sink: sink,
    );
    expect(_titles(without), ['A']);
    expect(sink.diagnostics, isEmpty);
  });

  test('alvo fora do spine e entrada sem alvo são mantidos', () {
    final out = reconcileToc(
      [
        NavPoint(title: 'Externo'),
        NavPoint(title: 'Fora', target: const NavTarget('OEBPS/x.xhtml')),
        _entry('b'),
      ],
      _spine(['a', 'b', 'c']),
      sink: DiagnosticSink(),
    );
    expect(_titles(out), ['+a', 'Externo', 'Fora', 'B', '+c']);
  });

  test('sem TOC: tudo sintetizado, na ordem do spine', () {
    final sink = DiagnosticSink();
    final out = reconcileToc(const [], _spine(['a', 'b']), sink: sink);
    expect(_titles(out), ['+a', '+b']);
    expect(sink.diagnostics.single.details['orphans'], 2);
  });

  test('custo linear: 20 000 raízes e 20 000 órfãos', () {
    final names = [for (var i = 0; i < 40000; i++) 'c$i'];
    final toc = [for (var i = 1; i < 40000; i += 2) _entry('c$i')];
    final sw = Stopwatch()..start();
    final out = reconcileToc(toc, _spine(names), sink: DiagnosticSink());
    sw.stop();
    expect(out, hasLength(40000));
    expect(out.first.synthesized, isTrue);
    expect(out[1].synthesized, isFalse);
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('spine com caminho repetido: só o primeiro índice conta', () {
    // Duas entradas do spine apontando para o mesmo arquivo (o `idref`
    // difere, mas o `item.path` é igual); a guarda `spineIndex[...] == i`
    // evita órfão duplicado para a mesma posição.
    final dup = ManifestItem(
      id: 'dup',
      path: 'OEBPS/dup.xhtml',
      mediaType: 'application/xhtml+xml',
    );
    final other = ManifestItem(
      id: 'other',
      path: 'OEBPS/other.xhtml',
      mediaType: 'application/xhtml+xml',
    );
    final spine = [
      SpineItem(idref: 'dup1', item: dup, content: dup, linear: true),
      SpineItem(idref: 'dup2', item: dup, content: dup, linear: true),
      SpineItem(idref: 'other', item: other, content: other, linear: true),
    ];
    final out = reconcileToc(const [], spine, sink: DiagnosticSink());
    expect(out, hasLength(2));
    expect(out.map((e) => e.target!.path), [
      'OEBPS/dup.xhtml',
      'OEBPS/other.xhtml',
    ]);
  });

  test(
    'órfão dentro de uma parte aninhada vai para a raiz, depois da parte',
    () {
      final out = reconcileToc(
        [
          NavPoint(title: 'P1', children: [_entry('a'), _entry('c')]),
        ],
        _spine(['a', 'b', 'c']),
        sink: DiagnosticSink(),
      );
      expect(_titles(out), ['P1', '+b']);
    },
  );

  test('item missing ou remote nunca vira órfão, qualquer que seja o path', () {
    // O path de um item missing/remote é o href cru (spec §5.3): nunca pode
    // virar NavTarget.path.
    final hostile = <(String, bool)>[
      ('../../../etc/passwd', false),
      ('http://evil.example/a.xhtml', true),
      (r'C:\Windows\win.ini', false),
      ('x\u0000y.xhtml', false),
      ('OEBPS/nao-existe.xhtml', false),
    ];
    final ok = ManifestItem(
      id: 'ok',
      path: 'OEBPS/ok.xhtml',
      mediaType: 'application/xhtml+xml',
    );
    final spine = [
      for (final (i, (path, remote)) in hostile.indexed)
        () {
          final item = ManifestItem(
            id: 'h$i',
            path: path,
            mediaType: 'application/xhtml+xml',
            missing: !remote,
            remote: remote,
          );
          return SpineItem(
            idref: 'h$i',
            item: item,
            content: item,
            linear: true,
          );
        }(),
      SpineItem(idref: 'ok', item: ok, content: ok, linear: true),
    ];
    final sink = DiagnosticSink();
    final out = reconcileToc(const [], spine, sink: sink);
    expect(out.map((e) => e.target!.path), ['OEBPS/ok.xhtml']);
    expect(sink.diagnostics.single.details['orphans'], 1);
  });

  test('entrada que aponta para o content do fallback cobre o item', () {
    final a = ManifestItem(
      id: 'a',
      path: 'OEBPS/a.foo',
      mediaType: 'application/x-foo',
      fallback: 'b',
    );
    final b = ManifestItem(
      id: 'b',
      path: 'OEBPS/b.xhtml',
      mediaType: 'application/xhtml+xml',
    );
    final c = ManifestItem(
      id: 'c',
      path: 'OEBPS/c.xhtml',
      mediaType: 'application/xhtml+xml',
    );
    final spine = [
      SpineItem(idref: 'c', item: c, content: c, linear: true),
      SpineItem(idref: 'a', item: a, content: b, linear: true),
    ];
    final toc = [
      NavPoint(title: 'B', target: const NavTarget('OEBPS/b.xhtml')),
    ];
    final sink = DiagnosticSink();
    final out = reconcileToc(toc, spine, sink: sink);
    // "a" é coberto por "B"; "c" (índice 0) entra antes de "B" (índice 1).
    expect(_titles(out), ['+c', 'B']);
    expect(sink.diagnostics.single.details['orphans'], 1);
  });
}

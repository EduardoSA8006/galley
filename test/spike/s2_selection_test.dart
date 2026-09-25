// Spike S2 — seleção sobre `RenderBox` próprio (doc/05 §3, doc/13 §1.1).
//
// Pergunta: seleção de texto sobre um `RenderBox` que pinta vários
// `ui.Paragraph` clipados e transladados funciona de ponta a ponta, inclusive
// atravessando blocos, atravessando "páginas" e com texto exibido diferente do
// canônico? Roda em flutter_tester com a fonte FlutterTest (1 glifo = fontSize
// = 10 px; linha de 10 px). Resultado em spike/RESULTADO-S2.md.

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/s2_display_map.dart';
import 'support/s2_page_render_box.dart';

const _shy = 0x00AD;

const _prose = [
  'O leitor abre o livro e a página aparece sem demora nenhuma na tela.',
  'Cada bloco é um parágrafo shapeado uma vez só e pintado com translate.',
  'A seleção é um par de offsets canônicos da seção, não de posições.',
  'Quando o parágrafo não cabe, o mesmo Paragraph continua na página '
      'seguinte, com outro clip e outro translate, sem novo shaping.',
  'Fim da seção de teste.',
];

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(alignment: Alignment.topLeft, child: child),
);

Future<S2PageRenderBox> _pump(
  WidgetTester tester,
  S2Page page,
  S2SelectionController controller,
) async {
  await tester.pumpWidget(
    _host(S2SelectablePage(page: page, controller: controller)),
  );
  return tester.renderObject<S2PageRenderBox>(find.byType(S2PageView));
}

Offset _global(WidgetTester tester, Offset local, [int index = 0]) =>
    tester.getTopLeft(find.byType(S2PageView).at(index)) + local;

/// Centro do primeiro retângulo do range canônico.
Offset _centerOf(S2PageRenderBox box, int start, int end) =>
    box.rectsFor(start, end).first.center;

bool _within(Rect inner, Rect outer) =>
    inner.left >= outer.left - 1e-6 &&
    inner.top >= outer.top - 1e-6 &&
    inner.right <= outer.right + 1e-6 &&
    inner.bottom <= outer.bottom + 1e-6;

void main() {
  group('DisplayMap (doc/04 §1.1)', () {
    test('identidade não copia a string nem aloca mapa', () {
      const s = 'sem transformação';
      final t = buildDisplayText(s);
      expect(identical(t.display, s), isTrue);
      expect(identical(t.map, DisplayMap.identity), isTrue);
      // Uppercase sem mudança de comprimento também cai na identidade.
      expect(
        identical(
          buildDisplayText('abc', uppercase: true).map,
          DisplayMap.identity,
        ),
        isTrue,
      );
    });

    test('achado: toUpperCase da VM não expande ß (SpecialCasing é nosso)', () {
      print(
        'S2 achado: "straße".toUpperCase() na VM = '
        '"${'straße'.toUpperCase()}"; buildDisplayText = '
        '"${buildDisplayText('straße', uppercase: true).display}"',
      );
      expect('ß'.toUpperCase(), 'ß');
      expect(buildDisplayText('straße', uppercase: true).display, 'STRASSE');
    });

    test(
      'monotônico e toCanonical(toDisplay(c)) == c (Random(7), 300 casos)',
      () {
        final rnd = Random(7);
        const alphabet = 'abcß ﬁxyz';
        for (var k = 0; k < 300; k++) {
          final n = 1 + rnd.nextInt(40);
          final canonical = String.fromCharCodes(
            List.generate(
              n,
              (_) => alphabet.codeUnitAt(rnd.nextInt(alphabet.length)),
            ),
          );
          final shy = <int>[
            for (var i = 1; i < n; i++)
              if (rnd.nextDouble() < 0.15) i,
          ];
          final t = buildDisplayText(
            canonical,
            uppercase: rnd.nextBool(),
            softHyphensBefore: shy,
          );
          var prev = 0;
          for (var d = 0; d <= t.display.length; d++) {
            final c = t.map.toCanonical(d);
            expect(c, greaterThanOrEqualTo(prev));
            expect(c, lessThanOrEqualTo(canonical.length));
            prev = c;
          }
          expect(t.map.toCanonical(t.display.length), canonical.length);
          for (var c = 0; c <= canonical.length; c++) {
            expect(
              t.map.toCanonical(t.map.toDisplay(c)),
              c,
              reason: '"$canonical" shy=$shy c=$c display="${t.display}"',
            );
          }
        }
      },
    );
  });

  testWidgets(
    '1. toque → offset canônico → retângulo contém o ponto (50 pontos, '
    'Random(2))',
    (tester) async {
      final section = S2Section.layout([
        for (final p in _prose) S2BlockSpec(p),
        const S2BlockSpec(
          'a rua straße fica longe daqui e o passo é lento',
          uppercase: true,
        ),
        const S2BlockSpec(
          'paralelepípedo encantamento inconstitucional',
          softHyphensBefore: [4, 8, 14, 18, 25, 32],
        ),
        for (final p in _prose.reversed) S2BlockSpec(p),
      ], columnWidth: 200);
      addTearDown(section.dispose);
      final pages = section.paginate(pageHeight: 200);
      // Página 1 (a segunda): começa com um fragmento continuado, então o
      // translate não é trivial.
      final page = pages[1];
      expect(page.fragments.first.firstLine, greaterThan(0));
      final controller = S2SelectionController();
      final box = await _pump(tester, page, controller);

      final rnd = Random(2);
      var checked = 0, mapped = 0;
      while (checked < 50) {
        final f = page.fragments[rnd.nextInt(page.fragments.length)];
        final line = f.firstLine + rnd.nextInt(f.lastLine - f.firstLine + 1);
        final width = f.block.lineRights[line];
        final top = f.block.lineTops[line], bottom = f.block.lineTops[line + 1];
        final local =
            f.translation +
            Offset(
              rnd.nextDouble() * width,
              top + 0.5 + rnd.nextDouble() * (bottom - top - 1),
            );
        final hit = box.hitAt(local)!;
        expect(hit.insideFragment, isTrue);
        // O "caractere" canônico pode ser `ß` (2 glifos exibidos): o range
        // canônico de 1 unidade cobre os dois.
        final rects = box.rectsFor(hit.char, hit.char + 1);
        expect(
          rects.any((r) => r.contains(local)),
          isTrue,
          reason:
              'ponto $local → char ${hit.char} '
              '("${section.canonicalText[hit.char]}") → $rects',
        );
        expect(hit.caret, anyOf(hit.char, hit.char + 1));
        if (!f.displayMap.isIdentity) mapped++;
        checked++;
      }
      print(
        'S2.1 ida e volta: 50/50 pontos; $mapped em blocos com DisplayMap '
        'não identidade; fragmentos na página: ${page.fragments.length}',
      );
    },
  );

  testWidgets('2. long press seleciona a palavra de canonicalText', (
    tester,
  ) async {
    final section = S2Section.layout([
      const S2BlockSpec('O gato dorme na janela ao sol da tarde.'),
      const S2BlockSpec('a rua straße fica longe daqui', uppercase: true),
    ], columnWidth: 200);
    addTearDown(section.dispose);
    final page = section.paginate(pageHeight: 300).single;
    final controller = S2SelectionController();
    final box = await _pump(tester, page, controller);

    final janela = section.canonicalText.indexOf('janela');
    await tester.longPressAt(
      _global(tester, _centerOf(box, janela, janela + 6)),
    );
    await tester.pump();
    expect(controller.value, S2Selection(janela, janela + 6));
    expect(controller.textIn(section), 'janela');

    final strasse = section.canonicalText.indexOf('straße');
    // Toque no último E de "STRASSE".
    final eRect = box.rectsFor(strasse + 5, strasse + 6).single;
    await tester.longPressAt(_global(tester, eRect.center));
    await tester.pump();
    final text = controller.textIn(section);
    final block = section.blocks[1];
    final s = controller.value!;
    final shown = block.text.display.substring(
      block.map.toDisplay(s.start - block.textStart),
      block.map.toDisplay(s.end - block.textStart),
    );
    print('S2.2 long press: "$text" (canônico), exibido "$shown"');
    expect(text, 'straße');
    expect(shown, 'STRASSE');
    final (a, b) = box.handleAnchors(s);
    expect(a, isNotNull);
    expect(b, isNotNull);
  });

  testWidgets('3. arraste atravessa blocos; alças estendem e invertem', (
    tester,
  ) async {
    final section = S2Section.layout([
      const S2BlockSpec('O gato dorme na janela ao sol da tarde quente.'),
      const S2BlockSpec('Depois acorda, espreguiça e vai até a cozinha.'),
      const S2BlockSpec('Lá encontra a tigela vazia e reclama bem alto.'),
    ], columnWidth: 200);
    addTearDown(section.dispose);
    final page = section.paginate(pageHeight: 300).single;
    expect(page.fragments, hasLength(3));
    final controller = S2SelectionController();
    final box = await _pump(tester, page, controller);
    final f0 = page.fragments[0], f1 = page.fragments[1];
    final f2 = page.fragments[2];

    // Long press em "gato" e arraste até a 2ª linha do bloco 1.
    final gato = section.canonicalText.indexOf('gato');
    final g = await tester.startGesture(
      _global(tester, _centerOf(box, gato, gato + 4)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(controller.value, S2Selection(gato, gato + 4));
    final target =
        f1.translation +
        Offset(55, (f1.block.lineTops[1] + f1.block.lineTops[2]) / 2);
    await g.moveTo(_global(tester, target));
    await tester.pump();
    await g.up();
    await tester.pump();

    var s = controller.value!;
    expect(s.start, gato);
    expect(s.end, box.canonicalOffsetAt(target));
    expect(s.end, greaterThan(f1.block.textStart));
    expect(controller.textIn(section), contains('\n'));
    final rects = box.rectsFor(s.start, s.end);
    expect(rects.where((r) => _within(r, f0.rect)), isNotEmpty);
    expect(rects.where((r) => _within(r, f1.rect)), isNotEmpty);
    for (final r in rects) {
      expect(
        page.fragments.any((f) => _within(r, f.rect)),
        isTrue,
        reason: 'retângulo $r fora de todos os fragmentos',
      );
    }
    print(
      'S2.3 arraste bloco 0 → 1: ${s.start}..${s.end}, '
      '${rects.length} retângulos, texto '
      '"${controller.textIn(section).replaceAll('\n', r'\n')}"',
    );

    // Arraste da alça final até o bloco 2.
    var (_, endAnchor) = box.handleAnchors(s);
    final endTarget =
        f2.translation +
        Offset(125, (f2.block.lineTops[0] + f2.block.lineTops[1]) / 2);
    final grab = S2PageRenderBox.handleCenter(endAnchor!);
    final h = await tester.startGesture(_global(tester, grab));
    // O ponto de texto acompanha o dedo a partir da ancoragem (−1 px).
    final move = endTarget - (endAnchor - const Offset(0, 1));
    for (var i = 1; i <= 4; i++) {
      await h.moveTo(_global(tester, grab + move * (i / 4)));
      await tester.pump();
    }
    await h.up();
    await tester.pump();
    s = controller.value!;
    expect(s.start, gato);
    expect(s.end, box.canonicalOffsetAt(endTarget));
    expect(s.end, greaterThan(f2.block.textStart));
    final threeBlocks = box.rectsFor(s.start, s.end);
    for (final f in page.fragments) {
      expect(threeBlocks.where((r) => _within(r, f.rect)), isNotEmpty);
    }

    // Alça inicial arrastada para depois da final: a seleção inverte e
    // continua coerente (base = antiga extremidade final).
    final oldEnd = s.end;
    final (startAnchor, _) = box.handleAnchors(s);
    final startGrab = S2PageRenderBox.handleCenter(startAnchor!);
    final pastEnd =
        f2.translation +
        Offset(155, (f2.block.lineTops[1] + f2.block.lineTops[2]) / 2);
    final moveStart = pastEnd - (startAnchor - const Offset(0, 1));
    final hs = await tester.startGesture(_global(tester, startGrab));
    for (var i = 1; i <= 6; i++) {
      await hs.moveTo(_global(tester, startGrab + moveStart * (i / 6)));
      await tester.pump();
    }
    await hs.up();
    await tester.pump();
    s = controller.value!;
    expect(s.base, oldEnd);
    expect(s.start, oldEnd);
    expect(s.end, box.canonicalOffsetAt(pastEnd));
    (_, endAnchor) = box.handleAnchors(s);
    expect(endAnchor, isNotNull);
  });

  testWidgets('4. bloco dividido entre duas páginas: clip e cobertura', (
    tester,
  ) async {
    final section = S2Section.layout([
      S2BlockSpec(_prose[0]),
      S2BlockSpec('${_prose[3]} ${_prose[1]} ${_prose[2]}'),
      S2BlockSpec(_prose[4]),
    ], columnWidth: 200);
    addTearDown(section.dispose);
    final pages = section.paginate(pageHeight: 100);
    expect(pages.length, greaterThanOrEqualTo(2));
    final a = pages[0].fragments.last, b = pages[1].fragments.first;
    expect(
      identical(a.paragraph, b.paragraph),
      isTrue,
      reason: 'o mesmo Paragraph nas duas páginas',
    );
    expect(b.firstLine, a.lastLine + 1);
    final block = a.block;
    // Começa na 2ª linha visível do bloco na página 1 e termina na 3ª linha
    // visível na página 2.
    final start = block.textStart + block.lineStarts[a.firstLine + 1] + 3;
    final end = block.textStart + block.lineStarts[b.firstLine + 2] + 5;

    final controller = S2SelectionController()..value = S2Selection(start, end);
    await tester.pumpWidget(
      _host(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            S2SelectablePage(page: pages[0], controller: controller),
            S2SelectablePage(page: pages[1], controller: controller),
          ],
        ),
      ),
    );
    final boxes = tester
        .renderObjectList<S2PageRenderBox>(find.byType(S2PageView))
        .toList();
    final r1 = boxes[0].rectsFor(start, end);
    final r2 = boxes[1].rectsFor(start, end);

    // Só a parte visível de cada página.
    expect(r1, isNotEmpty);
    expect(r2, isNotEmpty);
    for (final r in r1) {
      expect(_within(r, a.rect), isTrue, reason: 'página 1: $r fora de $a');
    }
    for (final r in r2) {
      expect(_within(r, b.rect), isTrue, reason: 'página 2: $r fora de $b');
    }
    // Sem clip, getBoxesForRange do range todo daria caixas fora do fragmento
    // da página 1 (as linhas que estão na página 2).
    final raw = block.paragraph.getBoxesForRange(
      start - block.textStart,
      end - block.textStart,
    );
    final unclipped = raw.map((x) => x.toRect().shift(a.translation)).toList();
    final outside = unclipped.where((r) => !_within(r, a.rect)).length;
    expect(outside, greaterThan(0));
    expect(
      r1.length + r2.length,
      raw.length,
      reason: 'cada caixa de linha aparece em exatamente uma página',
    );

    // União dos ranges cobertos == range pedido, sem lacuna nem sobreposição.
    final covered = [
      ...boxes[0].coveredRanges(start, end),
      ...boxes[1].coveredRanges(start, end),
    ];
    expect(covered.first.$1, start);
    for (var i = 1; i < covered.length; i++) {
      expect(covered[i].$1, covered[i - 1].$2);
    }
    expect(covered.last.$2, end);
    // Cada caractere do range tem retângulo em exatamente uma página. Exceção:
    // o espaço final de uma linha cheia, cuja caixa fica toda fora da coluna.
    var overflowSpaces = 0;
    for (var c = start; c < end; c++) {
      final on1 = boxes[0].rectsFor(c, c + 1).isNotEmpty;
      final on2 = boxes[1].rectsFor(c, c + 1).isNotEmpty;
      if (!on1 && !on2) {
        final d = c - block.textStart;
        final line = block.paragraph.getLineNumberAt(d)!;
        expect(section.canonicalText[c], ' ');
        expect(d, block.lineStarts[line + 1] - 1, reason: 'não é fim de linha');
        overflowSpaces++;
        continue;
      }
      expect(on1 != on2, isTrue, reason: 'caractere $c em 1=$on1 2=$on2');
    }
    // Alça inicial só na página 1, final só na página 2.
    final sel = controller.value!;
    final (a1, b1) = boxes[0].handleAnchors(sel);
    final (a2, b2) = boxes[1].handleAnchors(sel);
    expect(a1, isNotNull);
    expect(b1, isNull);
    expect(a2, isNull);
    expect(b2, isNotNull);
    // Cada página pinta exatamente os seus retângulos, em ordem.
    for (final (box, rects) in [(boxes[0], r1), (boxes[1], r2)]) {
      final pattern = paints;
      for (final r in rects) {
        pattern.rect(rect: r, color: S2PageRenderBox.selectionColor);
      }
      expect(box, pattern);
      expect(box, paintsExactlyCountTimes(#drawRect, rects.length));
    }
    print(
      'S2.4 bloco dividido (linhas ${a.firstLine}–${a.lastLine} | '
      '${b.firstLine}–${b.lastLine}): range $start..$end → '
      '${r1.length} + ${r2.length} retângulos; sem clip, $outside de '
      '${raw.length} caixas cairiam fora do fragmento da página 1; '
      '$overflowSpaces espaço(s) final(is) além da coluna',
    );
  });

  testWidgets('5. text-transform: uppercase com ß', (tester) async {
    final section = S2Section.layout([
      const S2BlockSpec('antes'),
      const S2BlockSpec('a rua straße fica longe daqui', uppercase: true),
    ], columnWidth: 200);
    addTearDown(section.dispose);
    final page = section.paginate(pageHeight: 300).single;
    final box = await _pump(tester, page, S2SelectionController());
    final f = page.fragments[1];
    final block = f.block;
    expect(block.text.display, 'A RUA STRASSE FICA LONGE DAQUI');
    expect((block.map as ChangePointMap).changeCount, 1);
    final eszett = block.canonical.indexOf('ß'); // 10
    final ss = block.text.display.indexOf('SS'); // 10 e 11
    final c = block.textStart + eszett;

    final firstS = block.paragraph.getBoxesForRange(ss, ss + 1).single.toRect();
    final secondS = block.paragraph
        .getBoxesForRange(ss + 1, ss + 2)
        .single
        .toRect();
    final onSecond = f.translation + secondS.center;
    final hit = box.hitAt(onSecond)!;
    expect(hit.char, c);
    expect(section.canonicalText[hit.char], 'ß');
    // Caret na metade esquerda do segundo S: ainda o offset do ß.
    expect(
      box.canonicalOffsetAt(
        f.translation + Offset(secondS.left + 2, secondS.center.dy),
      ),
      c,
    );
    // Metade direita do segundo S: caret depois do ß.
    expect(
      box.canonicalOffsetAt(
        f.translation + Offset(secondS.right - 2, secondS.center.dy),
      ),
      c + 1,
    );

    final rects = box.rectsFor(c, c + 1);
    expect(rects, hasLength(1));
    expect(rects.single.left, firstS.shift(f.translation).left);
    expect(rects.single.right, secondS.shift(f.translation).right);
    expect(rects.single.width, 20);
    // O caractere seguinte (E) não é engolido pelo ß.
    final after = box.rectsFor(c + 1, c + 2).single;
    expect(after.left, rects.single.right);
    print(
      'S2.5 ß: toque no 2º S → canônico $c ("ß"); rectsFor(ß) = '
      '${rects.single} (largura ${rects.single.width} = 2 glifos)',
    );
  });

  testWidgets('6. U+00AD inserido: offsets contíguos, toque no hífen', (
    tester,
  ) async {
    // Coluna de 85 px: "Par­alele" (8 glifos visíveis = 80 px) cabe; a linha
    // quebra no segundo U+00AD, antes de "pipedo".
    final section = S2Section.layout([
      const S2BlockSpec('Paralelepipedo e mais', softHyphensBefore: [3, 8]),
    ], columnWidth: 85);
    addTearDown(section.dispose);
    final page = section.paginate(pageHeight: 100).single;
    final box = await _pump(tester, page, S2SelectionController());
    final f = page.fragments.single;
    final block = f.block;
    final map = block.map;
    final ts = block.textStart;
    expect(block.text.display.codeUnitAt(3), _shy);
    expect(block.text.display.codeUnitAt(9), _shy);
    expect(block.endsWithSoftHyphen(0), isTrue);
    expect(block.lineRights[0], 80);

    // Caret antes e depois de cada U+00AD mapeia para o mesmo offset
    // canônico; caracteres vizinhos são contíguos.
    expect(map.toCanonical(3), 3);
    expect(map.toCanonical(4), 3);
    expect(map.toCanonical(9), 8);
    expect(map.toCanonical(10), 8);
    final ep = box.rectsFor(ts + 7, ts + 9);
    expect(ep, hasLength(2), reason: '"e" no fim da linha 0, "p" na linha 1');
    expect(ep[0].top, lessThan(ep[1].top));
    expect(section.canonicalText.substring(ts + 7, ts + 9), 'ep');

    // Hífen pendurado pintado em (lineRight, top) da linha 0.
    expect(
      box,
      paints
        ..paragraph(paragraph: block.paragraph)
        ..paragraph(
          paragraph: section.hyphen,
          offset: f.translation + const Offset(80, 0),
        ),
    );

    // Toque sobre o hífen (dentro da coluna e já na margem) → offset seguinte.
    final y = f.translation.dy + 5;
    for (final x in [83.0, 88.0]) {
      final p = Offset(f.translation.dx + x, y);
      final hit = box.hitAt(p)!;
      expect(hit.caret, ts + 8, reason: 'caret em x=$x');
      expect(hit.char, ts + 8, reason: 'char em x=$x');
      expect(section.canonicalText[hit.char], 'p');
    }
    // U+00AD no meio da linha (largura zero, entre "r" e "a"): os dois lados
    // dão o mesmo caret.
    final left = box.hitAt(Offset(f.translation.dx + 29, y))!;
    final right = box.hitAt(Offset(f.translation.dx + 31, y))!;
    expect(left.caret, ts + 3);
    expect(right.caret, ts + 3);
    expect(left.char, ts + 2);
    expect(right.char, ts + 3);
    // Selecionar "ra" passa por cima do U+00AD sem retângulo de largura zero.
    final ra = box.rectsFor(ts + 2, ts + 4);
    expect(ra.every((r) => r.width > 0), isTrue);
    expect(ra.fold<double>(0, (w, r) => w + r.width), 20);
    print(
      'S2.6 U+00AD: caret (3,4)→${map.toCanonical(3)},'
      '${map.toCanonical(4)}; (9,10)→${map.toCanonical(9)},'
      '${map.toCanonical(10)}; toque no hífen → ${ts + 8} ("p")',
    );
  });

  testWidgets('7. toque fora de fragmento nunca é morto', (tester) async {
    final section = S2Section.layout([
      S2BlockSpec(_prose[0]),
      S2BlockSpec(_prose[1]),
      S2BlockSpec(_prose[2]),
    ], columnWidth: 200);
    addTearDown(section.dispose);
    final page = section.paginate(pageHeight: 300).single;
    final box = await _pump(tester, page, S2SelectionController());
    final f0 = page.fragments[0], f1 = page.fragments[1];
    final b0 = f0.block;
    final line1Y = f0.translation.dy + 15;

    int canon(S2Fragment f, int display) =>
        f.textStart + f.displayMap.toCanonical(display);

    // Margem esquerda → início da linha; margem direita → fim da linha.
    expect(
      box.canonicalOffsetAt(Offset(5, line1Y)),
      canon(f0, b0.lineStarts[1]),
    );
    expect(
      box.canonicalOffsetAt(Offset(page.size.width - 5, line1Y)),
      canon(f0, b0.lineStarts[2]),
    );
    // Espaço entre blocos: fragmento mais próximo verticalmente.
    final gapNearTop = box.hitAt(Offset(100, f0.rect.bottom + 2))!;
    expect(gapNearTop.fragmentIndex, 0);
    expect(gapNearTop.insideFragment, isFalse);
    expect(
      gapNearTop.caret,
      inInclusiveRange(canon(f0, b0.lineStarts[f0.lastLine]), f0.canonicalEnd),
    );
    final gapNearBottom = box.hitAt(Offset(100, f1.rect.top - 2))!;
    expect(gapNearBottom.fragmentIndex, 1);
    expect(
      gapNearBottom.caret,
      inInclusiveRange(f1.canonicalStart, canon(f1, f1.block.lineStarts[1])),
    );
    // Cantos da página → início e fim da página.
    expect(box.canonicalOffsetAt(const Offset(2, 2)), page.canonicalStart);
    expect(
      box.canonicalOffsetAt(Offset(page.size.width - 2, page.size.height - 2)),
      page.canonicalEnd,
    );
    // Varredura: nenhum ponto da página devolve null ou sai do range dela.
    final rnd = Random(3);
    for (var i = 0; i < 500; i++) {
      final p = Offset(
        rnd.nextDouble() * page.size.width,
        rnd.nextDouble() * page.size.height,
      );
      final c = box.canonicalOffsetAt(p);
      expect(c, isNotNull);
      expect(c, inInclusiveRange(page.canonicalStart, page.canonicalEnd));
    }
  });

  testWidgets('U+FFFC (imagem inline): a seleção cobre a imagem', (
    tester,
  ) async {
    final section = S2Section.layout([
      const S2BlockSpec('veja a figura \uFFFC ao lado dela e siga'),
    ], columnWidth: 200);
    addTearDown(section.dispose);
    final page = section.paginate(pageHeight: 300).single;
    final box = await _pump(tester, page, S2SelectionController());
    final f = page.fragments.single;
    final block = f.block;
    final image = section.canonicalText.indexOf('\uFFFC');
    final placeholder = block.paragraph
        .getBoxesForPlaceholders()
        .single
        .toRect()
        .shift(f.translation);
    expect(placeholder.size, const Size(30, 20));
    // A linha da imagem cresce para caber o placeholder.
    expect(block.lineTops[1] - block.lineTops[0], greaterThanOrEqualTo(20));
    // Seleção "figura ￼ ao": algum retângulo cobre a imagem inteira.
    final rects = box.rectsFor(image - 7, image + 4);
    expect(
      rects.any((r) => _within(placeholder, r)),
      isTrue,
      reason: 'imagem $placeholder não coberta por $rects',
    );
    // Toque sobre a imagem → o offset do U+FFFC.
    expect(box.hitAt(placeholder.center)!.char, image);
    print('S2.FFFC placeholder $placeholder; retângulos da seleção $rects');
  });

  testWidgets('pintura: seleção antes do texto, alças por cima (doc/05 §1)', (
    tester,
  ) async {
    final section = S2Section.layout([
      S2BlockSpec(_prose[0]),
      S2BlockSpec(_prose[1]),
    ], columnWidth: 200);
    addTearDown(section.dispose);
    final page = section.paginate(pageHeight: 300).single;
    final controller = S2SelectionController()
      ..value = S2Selection(3, section.blocks[1].textStart + 10);
    final box = await _pump(tester, page, controller);
    expect(
      box,
      paints
        ..rect(color: S2PageRenderBox.selectionColor)
        ..clipRect(rect: page.fragments[0].clipRect)
        ..paragraph(paragraph: section.blocks[0].paragraph)
        ..clipRect(rect: page.fragments[1].clipRect)
        ..paragraph(paragraph: section.blocks[1].paragraph)
        ..circle(color: S2PageRenderBox.handleColor)
        ..circle(color: S2PageRenderBox.handleColor),
    );
    // Trocar a seleção é repaint, não relayout (doc/05 §1.1).
    box.selection = const S2Selection(0, 5);
    expect(box.debugNeedsPaint, isTrue);
    expect(box.debugNeedsLayout, isFalse);
  });

  test('8. custo: canonicalOffsetAt e rectsFor, página de 12 fragmentos', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final specs = <S2BlockSpec>[
      for (var i = 0; i < 12; i++)
        switch (i % 4) {
          1 => const S2BlockSpec(
            'a rua straße fica longe daqui e o passo é lento demais',
            uppercase: true,
          ),
          3 => const S2BlockSpec(
            'paralelepípedo encantamento inconstitucional sim',
            softHyphensBefore: [4, 8, 14, 18, 25, 32, 40],
          ),
          _ => S2BlockSpec(_prose[(i ~/ 2) % 4].substring(0, 55)),
        },
    ];
    final section = S2Section.layout(specs, columnWidth: 200);
    addTearDown(section.dispose);
    // Altura exata para os 12 blocos caberem numa página.
    final height =
        section.blocks.fold<double>(0, (h, b) => h + b.lineTops[b.lineCount]) +
        11 * 10;
    final page = section.paginate(pageHeight: height).single;
    expect(page.fragments, hasLength(12));
    final box = S2PageRenderBox(page: page);
    final rnd = Random(8);
    final points = List.generate(
      1000,
      (_) => Offset(
        rnd.nextDouble() * page.size.width,
        rnd.nextDouble() * page.size.height,
      ),
    );
    final span = page.canonicalEnd - page.canonicalStart;
    final ranges = List.generate(1000, (_) {
      final s = page.canonicalStart + rnd.nextInt(span);
      return (s, min(page.canonicalEnd, s + 1 + rnd.nextInt(span ~/ 2)));
    });

    double timeUs(void Function(int i) body) {
      for (var i = 0; i < 300; i++) {
        body(i); // aquecimento do JIT
      }
      final samples = <double>[];
      for (var round = 0; round < 5; round++) {
        final sw = Stopwatch()..start();
        for (var i = 0; i < 1000; i++) {
          body(i);
        }
        sw.stop();
        samples.add(sw.elapsedMicroseconds / 1000);
      }
      samples.sort();
      return samples[2];
    }

    var sink = 0;
    final hitUs = timeUs((i) => sink += box.canonicalOffsetAt(points[i])!);
    final rectsUs = timeUs(
      (i) => sink += box.rectsFor(ranges[i].$1, ranges[i].$2).length,
    );
    final fullUs = timeUs(
      (i) =>
          sink += box.rectsFor(page.canonicalStart, page.canonicalEnd).length,
    );
    final wordUs = timeUs((i) => sink += box.wordAt(ranges[i].$1).$1);
    final lines = page.fragments.fold<int>(
      0,
      (n, f) => n + f.lastLine - f.firstLine + 1,
    );
    print(
      'S2.8 página: ${page.fragments.length} fragmentos, $lines linhas, '
      '$span caracteres canônicos (sink $sink)',
    );
    print(
      'S2.8 µs médio por chamada (mediana de 5 × 1000): '
      'canonicalOffsetAt ${hitUs.toStringAsFixed(2)}; '
      'rectsFor aleatório ${rectsUs.toStringAsFixed(2)}; '
      'rectsFor página inteira ${fullUs.toStringAsFixed(2)}; '
      'wordAt ${wordUs.toStringAsFixed(2)}',
    );
    // Sanidade do orçamento: arraste chama os dois por frame; 16 ms é o teto.
    expect(hitUs + fullUs, lessThan(1000));
  });

  test('sanidade: a fonte FlutterTest dá 10 px por glifo', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final p =
        (ui.ParagraphBuilder(
                ui.ParagraphStyle(fontSize: 10, fontFamily: 'FlutterTest'),
              )
              ..pushStyle(ui.TextStyle(fontSize: 10, fontFamily: 'FlutterTest'))
              ..addText('ßãç'))
            .build()
          ..layout(const ui.ParagraphConstraints(width: 500));
    expect(p.longestLine, 30);
    p.dispose();
  });
}

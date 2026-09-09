import '../corpus_case.dart';
import 'common.dart';

const _group = 'faixa-b';

List<CorpusCase> faixaBCases() => [
      CorpusCase(
        group: _group,
        slug: 'float-com-contorno',
        readme: 'Imagem e capitular com `float: left` e texto contornando: degradado para o fluxo normal com diagnóstico.',
        diagnostics: ['unsupportedLayout'],
        build: () {
          final prose = proseFor('float-com-contorno');
          final body = '<h1>Float</h1><p><span class="capitular">A</span>${prose.paragraph().substring(1)}</p>'
              '<div class="caixa">Caixa flutuante à direita com texto curto.</div>${prose.paragraphs(4)}';
          const css = '.capitular{float:left;font-size:3em;line-height:1;padding-right:.1em} .caixa{float:right;width:40%;border:1px solid #999;padding:.5em;margin:0 0 .5em .5em}';
          return singleChapterBook('float-com-contorno', body, title: 'Float', css: css).build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'columns',
        readme: '`column-count: 2` no corpo e `columns: 3` numa div: conteúdo emitido em coluna única com diagnóstico.',
        diagnostics: ['unsupportedLayout'],
        build: () {
          final prose = proseFor('columns');
          final body = '<h1>Colunas</h1><div class="duas">${prose.paragraphs(4)}</div><div class="tres">${prose.paragraphs(3)}</div>';
          const css = '.duas{column-count:2;column-gap:1.5em} .tres{columns:3}';
          return singleChapterBook('columns', body, title: 'Colunas', css: css).build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'writing-mode-vertical',
        readme: '`writing-mode: vertical-rl` em japonês com `page-progression-direction="rtl"`: renderizado horizontal com diagnóstico.',
        diagnostics: ['unsupportedLayout'],
        build: () {
          const body = '<h1>縦書き</h1><p>吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。</p>'
              '<p>何でも薄暗いじめじめした所でニャーニャー泣いていた事だけは記憶している。</p>';
          const css = 'html{writing-mode:vertical-rl;-epub-writing-mode:vertical-rl;text-orientation:mixed}';
          final b = singleChapterBook('writing-mode-vertical', body, title: '縦書き', lang: 'ja', css: css);
          b.direction = 'rtl';
          return b.build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'ruby',
        readme: '`<ruby>` com `<rt>` e `<rp>` (furigana): anotação achatada no fluxo com diagnóstico.',
        diagnostics: ['rubyFlattened'],
        build: () {
          const body = '<h1>ルビ</h1><p><ruby>漢<rp>(</rp><rt>かん</rt><rp>)</rp></ruby><ruby>字<rp>(</rp><rt>じ</rt><rp>)</rp></ruby>の<ruby>勉強<rt>べんきょう</rt></ruby>をする。</p>'
              '<p>Ruby em texto latino: <ruby>Tōkyō<rt>東京</rt></ruby>.</p>';
          return singleChapterBook('ruby', body, title: 'ルビ', lang: 'ja').build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'mathml',
        readme: 'MathML em bloco e inline com `alttext` e `annotation` textual: renderizado o fallback com diagnóstico.',
        diagnostics: ['unsupportedMath'],
        build: () {
          const body = '<h1>Matemática</h1><p>A fórmula de Bhaskara:</p>'
              '<math xmlns="http://www.w3.org/1998/Math/MathML" display="block" alttext="x = (-b ± sqrt(b^2 - 4ac)) / 2a">'
              '<semantics><mrow><mi>x</mi><mo>=</mo><mfrac><mrow><mo>−</mo><mi>b</mi><mo>±</mo><msqrt><msup><mi>b</mi><mn>2</mn></msup><mo>−</mo><mn>4</mn><mi>a</mi><mi>c</mi></msqrt></mrow><mrow><mn>2</mn><mi>a</mi></mrow></mfrac></mrow>'
              '<annotation encoding="application/x-tex">x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}</annotation></semantics></math>'
              '<p>E inline: <math xmlns="http://www.w3.org/1998/Math/MathML" alttext="E = mc^2"><mrow><mi>E</mi><mo>=</mo><mi>m</mi><msup><mi>c</mi><mn>2</mn></msup></mrow></math> no meio da frase.</p>';
          final b = singleChapterBook('mathml', body, title: 'Matemática');
          b.resources[0] = b.resources[0].copyWithProperties(const ['mathml']);
          return b.build();
        },
      ),
    ];

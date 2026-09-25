// Spike S9 — gerador determinístico de XHTML para o worker cooperativo.
//
// Produz uma seção de prosa parecida com a de uma light novel: parágrafos
// curtos (muito diálogo), alguns longos, headings, uma citação em
// `blockquote > p`, uma lista e uma tabela a cada tanto, e marcação inline
// (`em`, `strong`, `a`, `span`) com entidades. O conteúdo depende só de
// `seed` e `targetBytes`, para que VM e Chrome parseiem exatamente a mesma
// string.

const _words = [
  'a',
  'o',
  'de',
  'que',
  'e',
  'do',
  'da',
  'em',
  'um',
  'para',
  'com',
  'não',
  'uma',
  'os',
  'no',
  'se',
  'na',
  'por',
  'mais',
  'as',
  'dos',
  'como',
  'mas',
  'ao',
  'ele',
  'das',
  'seu',
  'sua',
  'ou',
  'quando',
  'muito',
  'nos',
  'já',
  'eu',
  'também',
  'só',
  'pelo',
  'pela',
  'até',
  'isso',
  'ela',
  'entre',
  'depois',
  'sem',
  'mesmo',
  'aos',
  'seus',
  'quem',
  'nas',
  'me',
  'esse',
  'eles',
  'você',
  'essa',
  'num',
  'nem',
  'suas',
  'meu',
  'às',
  'minha',
  'numa',
  'pelos',
  'elas',
  'qual',
  'nós',
  'lhe',
  'deles',
  'essas',
  'esses',
  'pelas',
  'este',
  'dele',
  'tu',
  'te',
  'vocês',
  'vos',
  'lhes',
  'meus',
  'minhas',
  'teu',
  'tua',
  'nosso',
  'nossa',
  'dela',
  'delas',
  'esta',
  'estes',
  'estas',
  'aquele',
  'aquela',
  'aqueles',
  'aquelas',
  'isto',
  'aquilo',
  'castelo',
  'espada',
  'magia',
  'demônio',
  'rei',
  'masmorra',
  'nível',
  'invocação',
  'coração',
  'olhos',
  'porta',
  'noite',
  'caminho',
  'silêncio',
  'sorriso',
  'mão',
  'janela',
  'vento',
  'chuva',
  'fogo',
  'guerreira',
  'elfa',
  'aventureiro',
  'guilda',
  'taverna',
  'moeda',
  'pergaminho',
  'feitiço',
  'lâmina',
  'escudo',
  'floresta',
  'montanha',
  'cidade',
  'mercado',
  'muralha',
  'estrela',
  'lua',
  'sombra',
  'luz',
];

/// Park–Miller (multiplicador 48271, módulo 2³¹ − 1). O produto cabe em 47
/// bits, então o resultado é idêntico em VM, dart2js e dart2wasm (no JS os
/// inteiros são doubles e só são exatos até 2⁵³).
class _Lcg {
  _Lcg(int seed) : _state = 1 + seed % 2147483646;

  int _state;

  int next(int max) {
    _state = (_state * 48271) % 2147483647;
    return _state % max;
  }
}

String _sentence(_Lcg rng, int minWords, int maxWords) {
  final n = minWords + rng.next(maxWords - minWords + 1);
  final sb = StringBuffer();
  for (var i = 0; i < n; i++) {
    var w = _words[rng.next(_words.length)];
    if (i == 0) w = w[0].toUpperCase() + w.substring(1);
    if (i > 0) sb.write(' ');
    // Marcação inline em ~6% das palavras.
    switch (rng.next(50)) {
      case 0:
        sb.write('<em>$w</em>');
      case 1:
        sb.write('<strong>$w</strong>');
      case 2:
        sb.write('<span class="ruby">$w</span>');
      default:
        sb.write(w);
    }
  }
  sb.write(const ['.', '.', '.', '!', '?', '…'][rng.next(6)]);
  return sb.toString();
}

String _paragraphBody(_Lcg rng) {
  final kind = rng.next(10);
  if (kind < 5) {
    // Diálogo curto, com travessão e às vezes quebra de linha no fonte.
    return '&#8212; ${_sentence(rng, 3, 10)}';
  }
  if (kind < 9) {
    // Prosa média: 1 a 2 frases, whitespace irregular a colapsar.
    final sb = StringBuffer(_sentence(rng, 6, 14));
    if (rng.next(2) == 0) sb.write('\n      ${_sentence(rng, 4, 10)}');
    return sb.toString();
  }
  // Parágrafo longo, com link e entidade.
  final sb = StringBuffer();
  for (var i = 0; i < 3 + rng.next(3); i++) {
    if (i > 0) sb.write('  ');
    sb.write(_sentence(rng, 8, 18));
  }
  sb.write(' <a href="#n${rng.next(999)}">[nota]</a> &amp; fim.');
  return sb.toString();
}

const _head =
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!DOCTYPE html>\n'
    '<html xmlns="http://www.w3.org/1999/xhtml" '
    'xmlns:epub="http://www.idpf.org/2007/ops" lang="pt-BR" xml:lang="pt-BR">\n'
    '<head><meta charset="utf-8"/><title>Capítulo</title>'
    '<link rel="stylesheet" type="text/css" href="../css/estilo.css"/></head>\n'
    '<body>\n<section epub:type="chapter" id="cap">\n';

const _tail = '</section>\n</body>\n</html>\n';

/// Seção de prosa com cerca de [targetBytes] unidades de código UTF-16
/// (≈ bytes: o texto é quase todo ASCII). Com 500 000, sai com ~4 mil
/// parágrafos.
String sampleSectionXhtml({required int targetBytes, int seed = 9}) {
  final rng = _Lcg(seed);
  final sb = StringBuffer(_head);
  var n = 0;
  while (sb.length < targetBytes - _tail.length) {
    n++;
    if (n % 400 == 1) {
      sb.write('<h2 id="h$n">${_sentence(rng, 2, 5)}</h2>\n');
    } else if (n % 250 == 0) {
      sb.write(
        '<blockquote><p>${_sentence(rng, 8, 16)}</p>'
        '<p>${_sentence(rng, 4, 8)}</p></blockquote>\n',
      );
    } else if (n % 300 == 0) {
      sb.write('<ul>\n');
      for (var i = 0; i < 4; i++) {
        sb.write('  <li>${_sentence(rng, 2, 6)}</li>\n');
      }
      sb.write('</ul>\n');
    } else if (n % 700 == 0) {
      sb.write('<table><tbody>\n');
      for (var r = 0; r < 3; r++) {
        sb.write(
          '<tr><td>${_sentence(rng, 1, 3)}</td>'
          '<td>${_sentence(rng, 1, 3)}</td></tr>\n',
        );
      }
      sb.write('</tbody></table>\n');
    } else if (n % 90 == 0) {
      sb.write('<hr class="cena"/>\n');
    } else {
      sb.write('<p>${_paragraphBody(rng)}</p>\n');
    }
  }
  sb.write(_tail);
  return sb.toString();
}

/// Seção com um bloco gigante de ~[blockBytes] no meio de 200 parágrafos: o
/// caso em que um único passo do gerador é grande (doc/08 §2 tolera a fatia
/// até 8 ms). [tag] é `pre` (texto preservado, passo barato) ou `p` (o mesmo
/// texto passa pelo colapso de whitespace com regex, passo caro).
String sampleGiantBlockXhtml({
  String tag = 'pre',
  int blockBytes = 1000000,
  int seed = 11,
}) {
  final rng = _Lcg(seed);
  final sb = StringBuffer(_head);
  for (var i = 0; i < 100; i++) {
    sb.write('<p>${_paragraphBody(rng)}</p>\n');
  }
  sb.write('<$tag id="gigante">');
  final start = sb.length;
  var line = 0;
  while (sb.length - start < blockBytes) {
    line++;
    // Linhas de "código" com indentação que um `pre` precisa preservar.
    sb.write(
      '${line.toString().padLeft(6)}    '
      '${_words[rng.next(_words.length)]} = '
      '${_words[rng.next(_words.length)]}(${rng.next(1000)});\n',
    );
  }
  sb.write('</$tag>\n');
  for (var i = 0; i < 100; i++) {
    sb.write('<p>${_paragraphBody(rng)}</p>\n');
  }
  sb.write(_tail);
  return sb.toString();
}

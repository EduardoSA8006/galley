import 'dart:math';

/// Gerador determinístico de prosa. Não é lorem ipsum: são frases reais em
/// português e inglês, para que quebra de linha, hifenização e busca tenham
/// material plausível.
class Prose {
  Prose({this.lang = 'pt', int seed = 1}) : _rng = Random(seed);

  final String lang;
  final Random _rng;

  static const _pt = [
    'A porta estava aberta desde o princípio, e ninguém tinha reparado.',
    'O rio descia devagar entre as pedras, carregando folhas e memórias.',
    'Ela guardou a carta na gaveta e fingiu que o dia seguia normal.',
    'Havia um silêncio antigo naquela casa, do tipo que se herda.',
    'Ninguém sabia dizer quando o relógio da sala tinha parado.',
    'O menino contou as estrelas até perder a conta e o sono.',
    'As palavras compridas do português testam a paciência da coluna estreita.',
    'Extraordinariamente, o inconstitucionalíssimo decreto foi revogado.',
    'Choveu a noite inteira e a manhã chegou limpa, quase transparente.',
    'Do outro lado da rua, um homem varria calçada que já estava limpa.',
    'Pensou em voltar, mas a estrada atrás dele já não existia.',
    'Era um livro pequeno, de capa gasta, que cabia no bolso do casaco.',
    'O café esfriou enquanto ela lia a mesma frase pela quinta vez.',
    'Todo mapa mente um pouco; este mentia com elegância.',
    'A cidade acordava aos poucos, uma janela acesa por vez.',
    'Prometeu escrever, e escreveu, embora nunca tenha enviado.',
  ];

  static const _en = [
    'The door had been open from the start, and nobody had noticed.',
    'The river came down slowly between the stones, carrying leaves.',
    'She put the letter in the drawer and pretended the day was ordinary.',
    'There was an old silence in that house, the kind one inherits.',
    'Nobody could say when the clock in the parlour had stopped.',
    'The boy counted the stars until he lost count and fell asleep.',
    'Long words test the patience of a narrow column.',
    'It rained all night and the morning arrived clean, almost transparent.',
    'Across the street a man swept a pavement that was already clean.',
    'He thought of turning back, but the road behind him was gone.',
    'It was a small book with a worn cover that fit in a coat pocket.',
    'The coffee went cold while she read the same sentence a fifth time.',
    'Every map lies a little; this one lied gracefully.',
    'The town woke slowly, one lit window at a time.',
  ];

  List<String> get _pool => lang == 'en' ? _en : _pt;

  String sentence() => _pool[_rng.nextInt(_pool.length)];

  String paragraph({int minSentences = 3, int maxSentences = 7}) {
    final n = minSentences + _rng.nextInt(maxSentences - minSentences + 1);
    return List.generate(n, (_) => sentence()).join(' ');
  }

  /// Parágrafos XHTML `<p>` até atingir aproximadamente [words] palavras.
  String paragraphsForWords(int words) {
    final buf = StringBuffer();
    var count = 0;
    while (count < words) {
      final p = paragraph();
      count += p.split(' ').length;
      buf.writeln('<p>$p</p>');
    }
    return buf.toString();
  }

  String paragraphs(int n) =>
      List.generate(n, (_) => '<p>${paragraph()}</p>').join('\n');
}

import 'dart:typed_data';

import 'css_tokenizer.dart';

/// Profundidade máxima de parênteses em condições de `@media` e
/// `@supports`; mais fundo, a condição (a consulta inteira) é falsa.
const int kMaxConditionDepth = 32;

/// Para cada token que abre um bloco (`(`, `[`, `{` ou função), o índice
/// do fechamento correspondente; `tokens.length` se o bloco não fecha (no
/// CSS ele fecha no fim da entrada). `-1` nos demais tokens.
///
/// Como em `_skipBlock` do parser: só o fechamento do bloco mais interno
/// conta; um fechamento de outro tipo é token comum. Linear e sem recursão.
Int32List matchCssBlocks(List<CssToken> tokens) {
  final match = Int32List(tokens.length)..fillRange(0, tokens.length, -1);
  final openers = <int>[];
  final closers = <CssTokenType>[];
  for (var i = 0; i < tokens.length; i++) {
    final type = tokens[i].type;
    if (closers.isNotEmpty && type == closers.last) {
      match[openers.removeLast()] = i;
      closers.removeLast();
      continue;
    }
    final closer = switch (type) {
      CssTokenType.leftParen ||
      CssTokenType.function => CssTokenType.rightParen,
      CssTokenType.leftSquare => CssTokenType.rightSquare,
      CssTokenType.leftBrace => CssTokenType.rightBrace,
      _ => null,
    };
    if (closer != null) {
      openers.add(i);
      closers.add(closer);
    }
  }
  for (final o in openers) {
    match[o] = tokens.length;
  }
  return match;
}

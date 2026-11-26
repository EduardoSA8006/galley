import 'package:meta/meta.dart';

import '../../../core/diagnostics/diagnostic.dart';
import '../../../core/diagnostics/diagnostic_codes.dart';
import '../../../core/diagnostics/diagnostic_sink.dart';
import 'css_tokenizer.dart';

/// Nível máximo de at-rules aninhadas (`@media` dentro de `@media`...); o
/// bloco além dele é descartado.
const int _maxAtRuleDepth = 32;

/// At-rules cujo bloco é uma lista de regras.
const Set<String> _ruleContainers = {'media', 'supports', 'document'};

/// At-rules cujo bloco é uma lista de declarações.
const Set<String> _declarationContainers = {'font-face', 'page'};

/// Uma regra de CSS (CSS Syntax §5), sem aninhamento de CSS.
@immutable
sealed class CssRule {
  const CssRule(this.offset);

  /// Início da regra no texto pré-processado.
  final int offset;
}

/// Regra com prelúdio e bloco de declarações (`p, q { ... }`). O prelúdio
/// fica cru: o seletor é lido (e eventualmente rejeitado) depois.
final class QualifiedRule extends CssRule {
  /// Cria uma regra qualificada.
  const QualifiedRule(
    super.offset, {
    required this.prelude,
    required this.declarations,
  });

  /// Tokens do prelúdio, sem espaço nas pontas.
  final List<CssToken> prelude;

  /// Declarações do bloco.
  final List<RawDeclaration> declarations;
}

/// At-rule (`@media`, `@font-face`, `@import`...).
final class AtRule extends CssRule {
  /// Cria uma at-rule.
  const AtRule(
    super.offset, {
    required this.name,
    required this.prelude,
    this.rules,
    this.declarations,
  });

  /// Nome em minúsculas, sem o `@`.
  final String name;

  /// Tokens do prelúdio, sem espaço nas pontas.
  final List<CssToken> prelude;

  /// Regras internas; só em `media`, `supports` e `document` com bloco.
  final List<CssRule>? rules;

  /// Declarações; só em `font-face` e `page` com bloco.
  final List<RawDeclaration>? declarations;
}

/// Declaração ainda não interpretada (`nome: valor [!important]`).
@immutable
final class RawDeclaration {
  /// Cria uma declaração crua.
  const RawDeclaration({
    required this.name,
    required this.value,
    required this.important,
    required this.offset,
    required this.valueStart,
    required this.valueEnd,
  });

  /// Nome em minúsculas ASCII; propriedades personalizadas (`--*`) mantêm a
  /// caixa.
  final String name;

  /// Tokens do valor, aparados e sem o `!important`.
  final List<CssToken> value;

  /// Se terminava em `!important`.
  final bool important;

  /// Início da declaração (do nome).
  final int offset;

  /// Início do texto cru do valor, no texto pré-processado.
  final int valueStart;

  /// Fim (exclusivo) do texto cru do valor, no texto pré-processado.
  final int valueEnd;
}

/// Resultado de [parseCss].
final class ParsedCss {
  /// Cria o resultado; [source] é o texto já pré-processado.
  ParsedCss(this.rules, this.source) : _lines = _LineIndex(source);

  /// Regras do topo, em ordem.
  final List<CssRule> rules;

  /// Texto pré-processado ([preprocessCss]); todos os deslocamentos
  /// ([CssRule.offset], [RawDeclaration.valueStart] e os dos tokens) valem
  /// nele.
  final String source;

  final _LineIndex _lines;

  /// Linha (a partir de 1) de [offset] em [source].
  int lineOf(int offset) => _lines.lineOf(offset);
}

/// Lê a folha [source] (CSS Syntax Level 3, §5, sem aninhamento de CSS).
///
/// Erros de sintaxe viram `css.parseError` em [sink], com `location` =
/// `'<location>:<linha>'`; o trecho inválido é descartado. O limite de
/// relatos é do chamador (embrulhe [sink] num `LimitedDiagnosticSink`). Linear no
/// tamanho da entrada e sem recursão: blocos usam pilha explícita e
/// at-rules aninhadas além de 32 níveis têm o bloco descartado.
ParsedCss parseCss(
  String source, {
  required String location,
  required DiagnosticSink sink,
}) {
  final text = preprocessCss(source);
  final parser = _Parser(tokenizeCss(text), text, location, sink);
  return ParsedCss(parser.parseStylesheet(), text);
}

/// Lê uma lista de declarações (o valor de um atributo `style=`).
///
/// Os deslocamentos valem em `preprocessCss(source)` (que devolve a própria
/// [source] quando nada muda). Erros como em [parseCss].
List<RawDeclaration> parseCssDeclarations(
  String source, {
  required String location,
  required DiagnosticSink sink,
}) {
  final text = preprocessCss(source);
  final tokens = tokenizeCss(text);
  return _Parser(
    tokens,
    text,
    location,
    sink,
  ).parseDeclarations(0, tokens.length);
}

/// Índice de inícios de linha, para `lineOf` em O(log n).
final class _LineIndex {
  _LineIndex(this._source);

  final String _source;
  List<int>? _starts;

  int lineOf(int offset) {
    final starts = _starts ??= _build();
    var lo = 0;
    var hi = starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (starts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo + 1;
  }

  List<int> _build() {
    final starts = <int>[0];
    for (var i = 0; i < _source.length; i++) {
      if (_source.codeUnitAt(i) == 0x0A) starts.add(i + 1);
    }
    return starts;
  }
}

/// Fim de um bloco: [contentEnd] é onde o conteúdo termina (o fechamento ou
/// o limite), [next] o primeiro token depois do bloco.
typedef _Block = ({int contentEnd, int next, bool closed});

/// Quadro de uma lista de regras em curso (topo ou bloco de at-rule).
final class _Frame {
  _Frame({
    required this.pos,
    required this.end,
    required this.next,
    this.owner,
    this.ownerPrelude,
    this.ownerOffset = 0,
  });

  int pos;
  final int end;

  /// Onde o quadro pai continua quando este termina.
  final int next;
  final String? owner;
  final List<CssToken>? ownerPrelude;
  final int ownerOffset;
  final List<CssRule> rules = [];
}

final class _Parser {
  _Parser(this._t, this._source, this._location, this._sink)
    : _lines = _LineIndex(_source);

  final List<CssToken> _t;
  final String _source;
  final String _location;
  final DiagnosticSink _sink;
  final _LineIndex _lines;

  void _error(int offset, String message) {
    _sink.report(
      Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: DiagnosticCodes.cssParseError,
        message: message,
        location: '$_location:${_lines.lineOf(offset)}',
      ),
    );
  }

  int _offsetAt(int i) => i < _t.length ? _t[i].start : _source.length;

  static CssTokenType? _closerOf(CssTokenType type) => switch (type) {
    CssTokenType.leftParen || CssTokenType.function => CssTokenType.rightParen,
    CssTokenType.leftSquare => CssTokenType.rightSquare,
    CssTokenType.leftBrace => CssTokenType.rightBrace,
    _ => null,
  };

  /// Consome o bloco aberto em [i] (um `(`, `[`, `{` ou função) até o
  /// fechamento correspondente, com pilha explícita; só o fechamento do topo
  /// da pilha conta, os demais são tokens comuns.
  _Block _skipBlock(int i, int limit) {
    final stack = <CssTokenType>[_closerOf(_t[i].type)!];
    for (var j = i + 1; j < limit; j++) {
      final type = _t[j].type;
      if (type == stack.last) {
        stack.removeLast();
        if (stack.isEmpty) return (contentEnd: j, next: j + 1, closed: true);
      } else {
        final closer = _closerOf(type);
        if (closer != null) stack.add(closer);
      }
    }
    return (contentEnd: limit, next: limit, closed: false);
  }

  /// Avança de [i] até um `;` (se [stopAtSemicolon]) ou `{` fora de
  /// qualquer outro bloco, ou até [limit]. Devolve o índice de parada.
  int _scanPrelude(int i, int limit, {required bool stopAtSemicolon}) {
    while (i < limit) {
      final type = _t[i].type;
      if (type == CssTokenType.leftBrace) return i;
      if (stopAtSemicolon && type == CssTokenType.semicolon) return i;
      if (_closerOf(type) != null) {
        i = _skipBlock(i, limit).next;
      } else {
        i++;
      }
    }
    return limit;
  }

  List<CssToken> _trimmed(int from, int to) {
    while (from < to && _t[from].type == CssTokenType.whitespace) {
      from++;
    }
    while (to > from && _t[to - 1].type == CssTokenType.whitespace) {
      to--;
    }
    return _t.sublist(from, to);
  }

  List<CssRule> parseStylesheet() {
    final stack = <_Frame>[_Frame(pos: 0, end: _t.length, next: _t.length)];
    while (true) {
      final frame = stack.last;
      if (frame.pos >= frame.end) {
        stack.removeLast();
        if (stack.isEmpty) return frame.rules;
        final parent = stack.last;
        parent.pos = frame.next;
        parent.rules.add(
          AtRule(
            frame.ownerOffset,
            name: frame.owner!,
            prelude: frame.ownerPrelude!,
            rules: frame.rules,
          ),
        );
        continue;
      }
      final token = _t[frame.pos];
      final isTop = stack.length == 1;
      switch (token.type) {
        case CssTokenType.whitespace:
          frame.pos++;
        case CssTokenType.cdo || CssTokenType.cdc when isTop:
          frame.pos++;
        case CssTokenType.atKeyword:
          _atRule(stack, frame, token);
        default:
          _qualifiedRule(frame, token);
      }
    }
  }

  void _atRule(List<_Frame> stack, _Frame frame, CssToken keyword) {
    final name = _asciiLower(keyword.value);
    final start = frame.pos;
    final stop = _scanPrelude(start + 1, frame.end, stopAtSemicolon: true);
    final prelude = _trimmed(start + 1, stop);
    if (stop >= frame.end || _t[stop].type == CssTokenType.semicolon) {
      // Sem bloco (`@import ...;` ou fim do texto).
      frame.pos = stop < frame.end ? stop + 1 : frame.end;
      frame.rules.add(AtRule(keyword.start, name: name, prelude: prelude));
      return;
    }
    final block = _skipBlock(stop, frame.end);
    if (!block.closed) {
      _error(_offsetAt(block.contentEnd), 'bloco de @$name sem fechamento');
    }
    if (_ruleContainers.contains(name)) {
      if (stack.length - 1 >= _maxAtRuleDepth) {
        _error(
          keyword.start,
          '@$name aninhada além de $_maxAtRuleDepth níveis; bloco descartado',
        );
        frame.pos = block.next;
        frame.rules.add(AtRule(keyword.start, name: name, prelude: prelude));
        return;
      }
      stack.add(
        _Frame(
          pos: stop + 1,
          end: block.contentEnd,
          next: block.next,
          owner: name,
          ownerPrelude: prelude,
          ownerOffset: keyword.start,
        ),
      );
      return;
    }
    frame.pos = block.next;
    frame.rules.add(
      AtRule(
        keyword.start,
        name: name,
        prelude: prelude,
        declarations: _declarationContainers.contains(name)
            ? parseDeclarations(stop + 1, block.contentEnd)
            : null,
      ),
    );
  }

  void _qualifiedRule(_Frame frame, CssToken first) {
    final start = frame.pos;
    final stop = _scanPrelude(start, frame.end, stopAtSemicolon: false);
    if (stop >= frame.end) {
      _error(first.start, 'regra sem bloco; descartada');
      frame.pos = frame.end;
      return;
    }
    final block = _skipBlock(stop, frame.end);
    if (!block.closed) {
      _error(_offsetAt(block.contentEnd), 'bloco de regra sem fechamento');
    }
    frame.pos = block.next;
    frame.rules.add(
      QualifiedRule(
        first.start,
        prelude: _trimmed(start, stop),
        declarations: parseDeclarations(stop + 1, block.contentEnd),
      ),
    );
  }

  /// Lê as declarações nos tokens `[from, to)`.
  List<RawDeclaration> parseDeclarations(int from, int to) {
    final out = <RawDeclaration>[];
    var i = from;
    while (i < to) {
      final token = _t[i];
      switch (token.type) {
        case CssTokenType.whitespace || CssTokenType.semicolon:
          i++;
        case CssTokenType.atKeyword:
          _error(
            token.start,
            '@${token.value} dentro de declarações; descartada',
          );
          final stop = _scanPrelude(i + 1, to, stopAtSemicolon: true);
          if (stop < to && _t[stop].type == CssTokenType.leftBrace) {
            i = _skipBlock(stop, to).next;
          } else {
            i = stop < to ? stop + 1 : to;
          }
        default:
          final end = _scanDeclarationEnd(i, to);
          final declaration = token.type == CssTokenType.ident
              ? _declaration(i, end)
              : null;
          if (declaration != null) {
            out.add(declaration);
          } else {
            _error(token.start, 'declaração inválida; descartada');
          }
          i = end < to ? end + 1 : to;
      }
    }
    return out;
  }

  /// Índice do `;` que termina a declaração iniciada em [i] (ou [to]).
  int _scanDeclarationEnd(int i, int to) {
    while (i < to) {
      final type = _t[i].type;
      if (type == CssTokenType.semicolon) return i;
      if (_closerOf(type) != null) {
        i = _skipBlock(i, to).next;
      } else {
        i++;
      }
    }
    return to;
  }

  /// Declaração nos tokens `[from, end)` (o primeiro é um ident), ou `null`
  /// se faltar o `:`.
  RawDeclaration? _declaration(int from, int end) {
    final nameToken = _t[from];
    var i = from + 1;
    while (i < end && _t[i].type == CssTokenType.whitespace) {
      i++;
    }
    if (i >= end || _t[i].type != CssTokenType.colon) return null;
    final colon = _t[i];
    var vFrom = i + 1;
    var vTo = end;
    while (vFrom < vTo && _t[vFrom].type == CssTokenType.whitespace) {
      vFrom++;
    }
    while (vTo > vFrom && _t[vTo - 1].type == CssTokenType.whitespace) {
      vTo--;
    }
    var important = false;
    // `!` + ident `important`, nos dois últimos tokens não-espaço.
    if (vTo - 1 >= vFrom) {
      final last = _t[vTo - 1];
      if (last.type == CssTokenType.ident &&
          last.value.toLowerCase() == 'important') {
        var b = vTo - 2;
        while (b >= vFrom && _t[b].type == CssTokenType.whitespace) {
          b--;
        }
        if (b >= vFrom &&
            _t[b].type == CssTokenType.delim &&
            _t[b].value == '!') {
          important = true;
          vTo = b;
          while (vTo > vFrom && _t[vTo - 1].type == CssTokenType.whitespace) {
            vTo--;
          }
        }
      }
    }
    final value = _t.sublist(vFrom, vTo);
    final name = nameToken.value.startsWith('--')
        ? nameToken.value
        : _asciiLower(nameToken.value);
    return RawDeclaration(
      name: name,
      value: value,
      important: important,
      offset: nameToken.start,
      valueStart: value.isEmpty ? colon.end : value.first.start,
      valueEnd: value.isEmpty ? colon.end : value.last.end,
    );
  }
}

String _asciiLower(String s) {
  var needs = false;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0x41 && c <= 0x5A) {
      needs = true;
      break;
    }
  }
  if (!needs) return s;
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    out.writeCharCode(c >= 0x41 && c <= 0x5A ? c + 32 : c);
  }
  return out.toString();
}

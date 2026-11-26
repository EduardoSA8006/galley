import 'package:meta/meta.dart';

import 'css_value.dart' show asciiLower;

/// Pseudo-elementos suportados (nível 3), sempre no fim do seletor.
enum PseudoElement {
  /// `::before`.
  before,

  /// `::after`.
  after,

  /// `::first-letter`.
  firstLetter,

  /// `::first-line`.
  firstLine,
}

/// Prefixos de namespace declarados com `@namespace` numa folha.
@immutable
final class NamespaceMap {
  /// Cria o mapa.
  const NamespaceMap({this.defaultUri, this.prefixes = const {}});

  /// Mapa sem nenhuma declaração.
  static const NamespaceMap empty = NamespaceMap();

  /// URI do namespace padrão (`@namespace url(...)`), ou `null`.
  final String? defaultUri;

  /// URI de cada prefixo (com caixa).
  final Map<String, String> prefixes;
}

/// Combinador entre dois compostos.
enum Combinator {
  /// Espaço: descendente.
  descendant,

  /// `>`: filho.
  child,

  /// `+`: irmão imediatamente anterior.
  nextSibling,

  /// `~`: algum irmão anterior.
  laterSibling,
}

/// Restrição de namespace de um seletor de tipo ou de atributo.
@immutable
final class NamespaceConstraint {
  const NamespaceConstraint._(this.uri);

  /// Qualquer namespace (`*|`, ou tipo sem prefixo e sem namespace padrão).
  static const NamespaceConstraint any = NamespaceConstraint._(null);

  /// Sem namespace (`|tipo`, ou atributo sem prefixo).
  static const NamespaceConstraint none = NamespaceConstraint._('');

  /// Namespace com a [uri] dada (não vazia).
  factory NamespaceConstraint.uri(String uri) =>
      uri.isEmpty ? none : NamespaceConstraint._(uri);

  /// URI exigida; `null` = qualquer; vazia = sem namespace.
  final String? uri;
}

/// Seletor simples (parte de um composto).
@immutable
sealed class SimpleSelector {
  const SimpleSelector();
}

/// Seletor de tipo (`p`, `svg|rect`) ou universal (`*`, `ns|*`).
final class TypeSelector extends SimpleSelector {
  /// Cria o seletor; [localName] `null` é o universal.
  TypeSelector(this.localName, this.namespace)
    : lowerName = localName == null ? null : asciiLower(localName);

  /// Nome como escrito; `null` no universal.
  final String? localName;

  /// [localName] em minúsculas ASCII (comparado com elementos XHTML).
  final String? lowerName;

  /// Namespace exigido.
  final NamespaceConstraint namespace;
}

/// `#id` (com caixa).
final class IdSelector extends SimpleSelector {
  /// Cria o seletor.
  const IdSelector(this.id);

  /// O id.
  final String id;
}

/// `.classe` (com caixa).
final class ClassSelector extends SimpleSelector {
  /// Cria o seletor.
  const ClassSelector(this.name);

  /// A classe.
  final String name;
}

/// Operador de um seletor de atributo.
enum AttributeOperator {
  /// `[a]`.
  exists,

  /// `[a=v]`.
  equals,

  /// `[a~=v]`.
  includes,

  /// `[a|=v]`.
  dashMatch,

  /// `[a^=v]`.
  prefix,

  /// `[a$=v]`.
  suffix,

  /// `[a*=v]`.
  substring,
}

/// Seletor de atributo.
final class AttributeSelector extends SimpleSelector {
  /// Cria o seletor.
  AttributeSelector(
    this.localName,
    this.namespace,
    this.operator,
    this.value, {
    required this.caseInsensitive,
  }) : lowerName = asciiLower(localName);

  /// Nome local como escrito.
  final String localName;

  /// [localName] em minúsculas ASCII (comparado em elementos XHTML).
  final String lowerName;

  /// Namespace do atributo.
  final NamespaceConstraint namespace;

  /// Operador.
  final AttributeOperator operator;

  /// Valor comparado (vazio em [AttributeOperator.exists]).
  final String value;

  /// Flag `i`: valor comparado sem caixa ASCII.
  final bool caseInsensitive;
}

/// Tipos de pseudo-classe suportados.
enum PseudoClassKind {
  /// `:root`.
  root,

  /// `:nth-child(an+b)` (e `:first-child`).
  nthChild,

  /// `:nth-last-child(an+b)` (e `:last-child`).
  nthLastChild,

  /// `:nth-of-type(an+b)` (e `:first-of-type`).
  nthOfType,

  /// `:nth-last-of-type(an+b)` (e `:last-of-type`).
  nthLastOfType,

  /// `:only-child`.
  onlyChild,

  /// `:only-of-type`.
  onlyOfType,

  /// `:empty`.
  empty,

  /// `:lang(x)`.
  lang,

  /// `:link`.
  link,

  /// `:hover`, `:active`, `:focus`, `:visited`, `:target`, `:enabled`,
  /// `:disabled`, `:checked`, `:indeterminate`: válidos, nunca casam.
  never,
}

/// Pseudo-classe.
final class PseudoClassSelector extends SimpleSelector {
  /// Cria a pseudo-classe.
  const PseudoClassSelector(this.kind, {this.a = 0, this.b = 0, this.lang});

  /// Tipo.
  final PseudoClassKind kind;

  /// Coeficiente `a` de `an+b` (`:nth-*`).
  final int a;

  /// Termo `b` de `an+b` (`:nth-*`).
  final int b;

  /// Faixa de `:lang()`, em minúsculas ASCII.
  final String? lang;
}

/// `:not(simples)`.
final class NotSelector extends SimpleSelector {
  /// Cria a negação.
  const NotSelector(this.argument);

  /// O argumento (nunca outro [NotSelector]).
  final SimpleSelector argument;
}

/// Sequência de seletores simples sem combinador (`p.x[title]`).
@immutable
final class CompoundSelector {
  /// Cria o composto.
  const CompoundSelector(this.simples);

  /// Os seletores simples, na ordem escrita.
  final List<SimpleSelector> simples;
}

/// Um seletor complexo (um item de uma lista de seletores).
///
/// Os compostos ficam da direita para a esquerda: [compounds] `[0]` é o
/// sujeito, e [combinators] `[i]` liga `compounds[i]` a `compounds[i + 1]`
/// (à sua esquerda).
@immutable
final class Selector {
  /// Cria o seletor; use `parseSelectorList`.
  Selector({
    required this.compounds,
    required this.combinators,
    required this.specificity,
    this.pseudoElement,
  }) : assert(compounds.isNotEmpty, 'seletor sem composto'),
       assert(
         combinators.length == compounds.length - 1,
         'combinadores não batem com os compostos',
       ),
       ancestorHashes = _ancestorHashes(compounds, combinators);

  /// Compostos, da direita (sujeito) para a esquerda.
  final List<CompoundSelector> compounds;

  /// Combinadores; `combinators[i]` fica à esquerda de `compounds[i]`.
  final List<Combinator> combinators;

  /// Especificidade empacotada `a << 20 | b << 10 | c` (cada parte até 1023).
  final int specificity;

  /// Pseudo-elemento no fim do seletor, se houver.
  final PseudoElement? pseudoElement;

  /// Hashes ([SelectorHashes]) dos ids, classes e nomes de tipo dos
  /// compostos à esquerda de combinadores descendente/filho: todo elemento
  /// que casa precisa ter ancestrais com esses hashes (filtro de ancestrais).
  final List<int> ancestorHashes;

  /// Primeiro id do sujeito (fora de `:not`), ou `null`.
  String? get rightmostId {
    for (final s in compounds.first.simples) {
      if (s is IdSelector) return s.id;
    }
    return null;
  }

  /// Primeira classe do sujeito (fora de `:not`), ou `null`.
  String? get rightmostClass {
    for (final s in compounds.first.simples) {
      if (s is ClassSelector) return s.name;
    }
    return null;
  }

  /// Nome de tipo do sujeito, como escrito; `null` se universal ou ausente.
  /// Elementos XHTML o comparam sem caixa ASCII, os demais com caixa.
  String? get rightmostType {
    for (final s in compounds.first.simples) {
      if (s is TypeSelector) return s.localName;
    }
    return null;
  }

  static List<int> _ancestorHashes(
    List<CompoundSelector> compounds,
    List<Combinator> combinators,
  ) {
    final out = <int>[];
    for (var i = 1; i < compounds.length; i++) {
      final c = combinators[i - 1];
      if (c != Combinator.descendant && c != Combinator.child) continue;
      for (final s in compounds[i].simples) {
        switch (s) {
          case IdSelector(:final id):
            out.add(SelectorHashes.ofId(id));
          case ClassSelector(:final name):
            out.add(SelectorHashes.ofClass(name));
          case TypeSelector(:final localName?):
            out.add(SelectorHashes.ofType(localName));
          default:
        }
      }
    }
    return List.unmodifiable(out);
  }
}

/// Hashes de nomes para o filtro de ancestrais (FNV-1a de 32 bits sobre as
/// unidades UTF-16, com base diferente por tipo).
///
/// É a **única** função de hash de nome: tanto [Selector.ancestorHashes]
/// quanto o filtro que percorre a árvore usam estas funções. O nome de tipo
/// é sempre reduzido a minúsculas ASCII antes do hash: elementos XHTML casam
/// o tipo sem caixa e os demais com caixa (Ruling F4), então o hash sem caixa
/// é conservador para ambos (o casamento exato decide depois).
abstract final class SelectorHashes {
  static const int _prime = 0x01000193;
  static const int _typeBasis = 0x811C9DC5;
  static const int _classBasis = 0x050C5D1F;
  static const int _idBasis = 0x2F5A3C6B;

  /// Hash do nome local de tipo [localName] (sem caixa ASCII).
  static int ofType(String localName) {
    var h = _typeBasis;
    for (var i = 0; i < localName.length; i++) {
      var c = localName.codeUnitAt(i);
      if (c >= 0x41 && c <= 0x5A) c += 32;
      h = ((h ^ c) * _prime) & 0xFFFFFFFF;
    }
    return h;
  }

  /// Hash da classe [name] (com caixa).
  static int ofClass(String name) => _hash(_classBasis, name);

  /// Hash do id [id] (com caixa).
  static int ofId(String id) => _hash(_idBasis, id);

  static int _hash(int basis, String s) {
    var h = basis;
    for (var i = 0; i < s.length; i++) {
      h = ((h ^ s.codeUnitAt(i)) * _prime) & 0xFFFFFFFF;
    }
    return h;
  }
}

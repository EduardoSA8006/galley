import 'package:meta/meta.dart';

/// Entrada de navegação (sumário, lista de páginas ou marcos).
@immutable
final class NavPoint {
  /// Cria uma entrada; [children] vira uma lista não modificável.
  NavPoint({
    required this.label,
    this.path,
    this.fragment,
    this.type,
    List<NavPoint> children = const [],
  }) : children = List.unmodifiable(children);

  /// Rótulo exibido (pode ser vazio quando o EPUB não fornece texto).
  final String label;

  /// Caminho resolvido no zip; `null` para entradas sem link ou externas.
  final String? path;

  /// Fragmento (sem `#`) do destino, se houver.
  final String? fragment;

  /// Valor de `epub:type` (marcos de `landmarks`).
  final String? type;

  /// Entradas filhas.
  final List<NavPoint> children;

  @override
  String toString() => 'NavPoint($label, $path#$fragment)';
}

/// Navegação do livro: sumário, lista de páginas e marcos.
@immutable
final class EpubNavigation {
  /// Cria a navegação; as listas viram não modificáveis.
  EpubNavigation({
    List<NavPoint> toc = const [],
    List<NavPoint> pageList = const [],
    List<NavPoint> landmarks = const [],
  }) : toc = List.unmodifiable(toc),
       pageList = List.unmodifiable(pageList),
       landmarks = List.unmodifiable(landmarks);

  const EpubNavigation._empty()
    : toc = const [],
      pageList = const [],
      landmarks = const [];

  /// Navegação vazia.
  static const EpubNavigation empty = EpubNavigation._empty();

  /// Sumário.
  final List<NavPoint> toc;

  /// Lista de páginas.
  final List<NavPoint> pageList;

  /// Marcos (`landmarks`).
  final List<NavPoint> landmarks;
}

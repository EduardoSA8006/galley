import 'package:galley/src/features/document/domain/document_tree.dart';

/// Percurso determinístico de [tree] para comparar árvores: uma linha por
/// nó, com tipo, namespace, nome local, atributos ordenados, texto e a
/// marca `virtual`.
List<String> dumpTree(DocumentTree tree) {
  final lines = <String>[];
  void walk(int n, int depth) {
    final pad = '  ' * depth;
    final virtual = tree.isVirtual(n) ? ' virtual' : '';
    switch (tree.kindOf(n)) {
      case NodeKind.document:
        lines.add('${pad}document');
      case NodeKind.element:
        final attributes = [
          for (final a in tree.attributesOf(n))
            '${tree.names.namespaceOf(a.name)}:'
                '${tree.names.localNameOf(a.name)}=${a.value}',
        ]..sort();
        lines.add(
          '$pad<${tree.namespaceOf(n)}:${tree.localNameOf(n)}'
          '$virtual [${attributes.join(', ')}]>',
        );
      case NodeKind.text:
        lines.add('$pad#text$virtual "${tree.textOf(n)}"');
    }
    for (final c in tree.childrenOf(n)) {
      walk(c, depth + 1);
    }
  }

  walk(tree.documentNode, 0);
  return lines;
}

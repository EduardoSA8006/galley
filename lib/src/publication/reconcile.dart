/// Reconciliação do TOC com o spine (spec da Publicação §7.6; doc/03 §3.1).
///
/// Linear em entradas + spine: uma caminhada iterativa pelo TOC para os
/// caminhos cobertos e o menor índice do spine de cada raiz, um vetor de
/// "última raiz antes do índice i" por prefixo máximo e uma montagem única.
library;

import '../diagnostics/diagnostic.dart';
import '../diagnostics/exceptions.dart';
import 'href.dart';
import 'model.dart';

/// [toc] com os órfãos do spine inseridos como entradas raiz
/// `synthesized`. Órfão: item com `linear` verdadeiro cujo `content` final é
/// local e presente (nem `missing` nem `remote`; o item em si pode ser
/// `missing` com `fallback` local), cujo `item.path` e cujo `content.path`
/// nenhuma entrada, em qualquer nível, tem como `target.path`. O alvo e o
/// título do órfão vêm do `content.path`, nunca do `path` do item (o de um
/// item `missing`/`remote` é o `href` cru); dois itens com o mesmo `content`
/// dão um órfão só. O órfão de índice `i` entra logo depois da
/// última raiz, na ordem do TOC, cujo menor índice do spine (dela e dos
/// descendentes, casando por `item.path` ou `content.path`) é menor que `i`;
/// sem nenhuma, no início. Emite `tocReconciled` uma vez, se houver órfão.
///
/// Sem órfão, devolve a mesma instância de [toc] recebida (`identical`);
/// com órfão, devolve uma lista nova.
List<NavPoint> reconcileToc(
  List<NavPoint> toc,
  List<SpineItem> spine, {
  required DiagnosticSink sink,
}) {
  final spineIndex = <String, int>{};
  for (var i = 0; i < spine.length; i++) {
    spineIndex.putIfAbsent(spine[i].item.path, () => i);
  }
  // O `content` do fallback também identifica a seção: uma entrada para
  // `b.xhtml` cobre o item `a.foo` do spine cujo `content` é `b.xhtml`.
  for (var i = 0; i < spine.length; i++) {
    spineIndex.putIfAbsent(spine[i].content.path, () => i);
  }
  final covered = <String>{};
  // Menor índice do spine por raiz (spine.length = sem alvo no spine).
  final first = List<int>.filled(toc.length, spine.length);
  for (var r = 0; r < toc.length; r++) {
    final stack = <NavPoint>[toc[r]];
    while (stack.isNotEmpty) {
      final point = stack.removeLast();
      final path = point.target?.path;
      if (path != null) {
        covered.add(path);
        final index = spineIndex[path];
        if (index != null && index < first[r]) first[r] = index;
      }
      stack.addAll(point.children);
    }
  }
  // Um órfão por `content.path` (dois itens com o mesmo `content`, um só).
  final targets = <String>{};
  final orphans = <int>[];
  for (var i = 0; i < spine.length; i++) {
    final s = spine[i];
    if (!s.linear || !_hasLocalContent(s)) continue;
    if (covered.contains(s.item.path) || covered.contains(s.content.path)) {
      continue;
    }
    if (spineIndex[s.item.path] != i) continue;
    if (targets.add(s.content.path)) orphans.add(i);
  }
  if (orphans.isEmpty) return toc;

  // lastBefore[i] = maior r com first[r] < i, ou -1.
  final lastAt = List<int>.filled(spine.length + 1, -1);
  for (var r = 0; r < toc.length; r++) {
    if (first[r] < spine.length && r > lastAt[first[r]]) lastAt[first[r]] = r;
  }
  final lastBefore = List<int>.filled(spine.length + 1, -1);
  for (var i = 1; i <= spine.length; i++) {
    final candidate = lastAt[i - 1];
    lastBefore[i] = candidate > lastBefore[i - 1]
        ? candidate
        : lastBefore[i - 1];
  }

  // Órfãos por posição de inserção (antes da raiz `slot`), na ordem do spine.
  final bySlot = <int, List<NavPoint>>{};
  for (final i in orphans) {
    final path = spine[i].content.path;
    (bySlot[lastBefore[i] + 1] ??= []).add(
      NavPoint(
        title: basenameWithoutExtension(path),
        target: NavTarget(path),
        synthesized: true,
      ),
    );
  }
  final out = <NavPoint>[];
  for (var slot = 0; slot <= toc.length; slot++) {
    out.addAll(bySlot[slot] ?? const []);
    if (slot < toc.length) out.add(toc[slot]);
  }
  sink.emit(
    EpubDiagnosticCode.tocReconciled,
    message: '${orphans.length} itens do spine fora do TOC inseridos',
    details: {'orphans': orphans.length},
    onStrict: EpubPackageException.new,
  );
  return out;
}

/// `content` local e presente: só então o `content.path` é um caminho
/// normalizado que pode virar `NavTarget.path`.
bool _hasLocalContent(SpineItem s) => !s.content.missing && !s.content.remote;

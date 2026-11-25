<p align="center">
  <img src="https://raw.githubusercontent.com/EduardoSA8006/galley/main/doc/logo/galley-logo.svg" alt="Galley" width="200">
</p>

<h1 align="center">Galley</h1>

<p align="center">
  Renderizador de EPUB nativo para Flutter: Dart puro, sem WebView.
</p>

---

O Galley abre e renderiza livros EPUB 2 e 3 com um motor próprio de estilo e layout que pinta direto no `Canvas` do Flutter. O objetivo é ser mais rápido, mais leve e mais compatível que os leitores baseados em WebView, e dar ao app uma camada simples para aplicar as preferências do leitor (fonte, tamanho, cores, alinhamento, margens).

**Plataformas:** Android, iOS, Linux, macOS e Windows.

## Estado

> Em desenvolvimento inicial. Ainda não publicado no pub.dev.

| Subprojeto | Estado |
|---|---|
| 1. Fundação + Container (zip próprio, OPF, spine, navegação, fontes ofuscadas, DRM) | ✅ concluído |
| 2. Benchmark e corpus | ✅ concluído |
| 3. Documento (XHTML → árvore própria) | ✅ concluído |
| 4. Estilo (motor CSS + preferências do leitor) | planejado |
| 5. Layout e paginação | planejado |
| 6. Render e API pública (widget, controller) | planejado |
| 7. Recursos de leitura (seleção, CFI, busca, TTS) | planejado |
| 8. Casos difíceis (layout fixo, texto vertical) | planejado |

A arquitetura e as decisões estão em [`docs/superpowers/specs/`](docs/superpowers/specs/).

## Uso (API atual)

```dart
import 'package:galley/galley.dart';

final book = await EpubBook.open('/caminho/livro.epub');
print(book.metadata.title);
for (final item in book.spine.items) {
  final xhtml = await book.resourceText(item.item.path);
  // ...
}
for (final d in book.diagnostics) {
  print('${d.severity.name} ${d.code}: ${d.message}');
}
await book.close();
```

Livros malformados abrem sempre que possível; problemas recuperáveis aparecem em `diagnostics`. Só falhas que impedem a abertura lançam uma `GalleyException` (por exemplo `NotAnEpubException`, `DrmProtectedException`).

## Benchmarks

Gates de desempenho no CI (instruções e tempo, contra a `main`), comparação com
outros parsers de EPUB, teto de 2 MiB de tamanho no APK Android e registro
local: veja [`benchmark/README.md`](benchmark/README.md).

## Licença

BSD-3-Clause. Veja [LICENSE](LICENSE).

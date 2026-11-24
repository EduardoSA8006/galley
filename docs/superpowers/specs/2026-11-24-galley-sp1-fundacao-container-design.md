# Galley — Subprojeto 1: Fundação + Container

- **Data:** 2026-11-24
- **Status:** aprovado pelo usuário
- **Documento pai:** `2026-11-24-galley-arquitetura-design.md` (§7 etapa 1, §8 item 1)

## Intenção

Criar a base do pacote (estrutura, erros/diagnósticos, CI) e a etapa 1 do pipeline: abrir um arquivo EPUB 2/3 e expor pacote, metadados, spine, navegação e recursos — rápido, com memória mínima e tolerante a livros malformados. Inclui a sonda de risco de medição de texto em isolate, que sustenta a arquitetura inteira.

## Abordagens (leitura do zip)

| Abordagem | Trade-off | Decisão |
|---|---|---|
| Pacote `archive` | padrão do ecossistema; o uso comum descompacta tudo ao abrir; dependência extra | descartada |
| **Leitor de zip próprio** | lê só o diretório central e descompacta cada entrada sob demanda via zlib nativa do `dart:io` (`ZLibDecoder(raw: true)`); memória de abertura em KB; sem dependência; custo: código próprio com testes de fuzz | **escolhida pelo usuário** |

## Desenho

**Pacote:** Flutter package `galley`; Flutter ≥ 3.47 / Dart ≥ 3.13 (mínimo); BSD-3-Clause; dependências: `xml`, `meta`. Única API pública: `lib/galley.dart`.

**Estrutura:**
- `lib/src/core/` — `GalleyException` (hierarquia tipada para falhas fatais), `Diagnostic` (severidade, código estável, mensagem, local) e `DiagnosticSink` (coletor observável pelo app).
- `lib/src/features/container/` — camadas `data` (zip, leitura de arquivo/bytes, parsers XML) e `domain` (modelos imutáveis e caso de uso de abertura).

**Zip:**
- Fontes: arquivo (leitura aleatória sob demanda, `RandomAccessFile`) ou bytes em memória.
- Lê EOCD (com busca do comentário), suporta ZIP64, métodos *stored* e *deflate*; valida CRC-32; nomes UTF-8 e CP437.
- Limites de segurança: tamanho descompactado declarado vs real, proteção contra zip bomb e caminhos com `..`.
- Entradas criptografadas por zip → exceção tipada.

**Container:**
- `mimetype` (ausente/errado → diagnóstico, não fatal), `META-INF/container.xml` (primeiro rootfile OPF; múltiplas renditions → diagnóstico).
- OPF EPUB 2 e 3: metadados (título, autores, idioma, identificadores, editora, datas, descrição, `refines`/`meta` EPUB 3 e `opf:` EPUB 2), manifest (id, href, media-type, properties, fallback), spine (itemref, `linear`, `page-progression-direction`), detecção de capa (EPUB 3 `cover-image`, EPUB 2 `meta name="cover"`, guide), propriedades de rendition (`rendition:layout`, `orientation`, `spread`) lidas para o futuro layout fixo.
- Navegação: `nav.xhtml` (toc, page-list, landmarks) ou NCX (navMap, pageList), num modelo único de árvore.
- Recursos: acesso assíncrono por href resolvido (relativo ao OPF, percent-encoding, fragmentos removidos), com media-type.
- Fontes ofuscadas: desofuscação IDPF (SHA-1 do identificador único) e Adobe (UUID), a partir de `META-INF/encryption.xml`. Outros algoritmos de `encryption.xml` → DRM → exceção tipada clara.
- Tolerância: erros recuperáveis viram diagnósticos; só é fatal o que impede abrir (não é zip, sem OPF localizável, DRM).

**API (forma; nomes finais no plano):** `EpubBook.open(path)` / `EpubBook.fromBytes(bytes)` → livro com `metadata`, `spine`, `navigation`, `cover`, `resource(href)`, `diagnostics`, `close()`.

**Sonda de risco:** teste de integração que mede texto com `dart:ui` (`ParagraphBuilder` → `layout` → métricas) dentro de um isolate de fundo e compara com a medição na thread principal. Roda no CI em Linux, macOS, Windows, emulador Android e simulador iOS. Resultado registrado no documento pai; se falhar, aciona o plano B (§7 do pai).

**CI base (GitHub Actions):** `dart format --set-exit-if-changed`, `flutter analyze` sem avisos, `flutter test`, matriz da sonda. Benchmarks ficam no subprojeto 2.

**Testes:** EPUBs sintéticos montados no próprio teste (um por comportamento), fixtures malformadas de propósito, fuzz do leitor de zip (entradas truncadas/corrompidas nunca causam exceção não tipada nem travamento).

## Fora deste subprojeto

Parsing de XHTML de conteúdo (subprojeto 3), benchmarks (2), qualquer widget (6).

## Chamadas minhas

Nomes finais da API, códigos de diagnóstico, limites numéricos de segurança do zip.

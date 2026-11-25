# Pendências

Itens que ficaram de fora de propósito: não valiam o custo no momento, dependem de
outro subprojeto ou esperam algo externo. Cada um diz de onde veio e quando
retomar. Ao resolver um item, apague-o deste arquivo no mesmo commit.

## Dependem de upstream

- **Remover `LinearHtml5EntityMapping`** (`lib/src/features/document/data/event_adapter.dart`)
  quando uma versão oficial do `package:xml` trouxer a decodificação linear de
  entidades (issue renggli/dart-xml#221, PR #222). Manter os testes de
  equivalência e de tempo. Exige migrar `xml` 6.6.1 → 7.x.
- **Remover a normalização de CRLF** do mesmo arquivo quando a correção do
  upstream (dart-xml#220, ainda não lançada) sair numa versão. Mesma migração.
- **`&#10;`/`&#9;` em atributos viram espaço** (limitação do `package:xml`,
  documentada no adaptador e no `docdiff`). Rever junto com a migração acima.
- **Velocidade do `package:xml`:** o perfil (2026-11-25) mostra ~25 % do tempo
  em `substring`. Patches upstream (parser de nome com tabela ASCII, cache de
  nomes, bitmap no petitparser) dão +10–39 %, com teto ~1,5×. Um tokenizador
  próprio que guarde posições em vez de strings curtas chegaria a 5–10× o
  `parseEvents`. Retomar se a leitura do documento virar gargalo medido.
- **Layout fora do isolate raiz:** quando flutter/flutter#30604 for resolvida
  (o teste-canário em `example/integration_test` avisa), reescrever a etapa de
  layout para rodar em isolate (hoje: plano B, layout fatiado no raiz).

## Benchmark

- **Expandir o benchmark a cada subprojeto** (pendência permanente): estilo,
  layout, render e recursos de leitura devem acrescentar suas métricas e
  comparações (leitores com renderização a partir do SP6).
- **Abertura de livros pequenos:** concorrentes ~0,8 ms, Galley ~1,3 ms.
  Otimizar antes da 1.0.
- **wide-refresh via rsync** em vez de baixar o corpus amplo de novo.
- **Chave de cache com `run_attempt`** nos workflows.
- **Cache duplicado** entre os jobs `compare` e `docdiff` do noturno (só custo
  de cache; as chaves já não colidem).
- **Linhas `compare` dos livros `hm/*`** são ruído (documentos minúsculos);
  informativas, sem gate.
- **Teto de memória do documento** só mede `retainedBytes`; a memória real
  (RSS) entra no SP6.
- **Linhas > 80 colunas** em `benchmark/bin/bench_runner.dart:30` e
  `benchmark/tool/bench.dart:307` (string que o formatador não quebra).

## SP3 — Documento

Desempenho e API:
- `epubTypesOf` aloca uma lista a cada chamada. Devolver ids quando o SP4
  consultar em laço.
- Detectar `\r` e caracteres proibidos já no `decodeText` (bytes) para economizar
  ~2,5 ms por 2 MB. Só otimização; o resultado é o mesmo.

Modo tolerante e cabeçalho:
- `<title>` sem `<head>` em `text/html` vai para o body (texto visível e título
  não extraído). Tratar no SP5; `text/html` no spine é raro.
- `text/html` com conteúdo antes de `<html>` não gera diagnóstico.
- A linha informada no diagnóstico `document.recovered` pode vir de um
  diagnóstico não relacionado.
- Segunda raiz depois de `</svg>` entra dentro do svg.
- Lista de elementos que fecham `<p>` incompleta em relação ao HTML (`address`,
  `details`, `dl`, `fieldset`, `figcaption`, `form`, `hgroup`, `main`, `menu`,
  `summary`…). Só afeta o modo tolerante.
- `<link>` sem `href` é ignorado sem diagnóstico (nada se perde).
- `viewport` é lido mesmo fora do `<head>` (o SP8 decide).
- `<title>` vazio vira `""` em vez de `null`.

Organização e testes:
- Dividir `event_adapter.dart` e `recovery.dart` (~760 linhas cada) quando
  forem mexidos de novo.
- `_isBlank` duplicado e pilha paralela na política de recuperação.
- Fuzz só com ASCII/UTF-8 e sem seed SVG; ampliar.
- `dumpTree` (helper de teste) ordena atributos e imprime namespace como número.

## Antes da primeira publicação no pub.dev

- Forma da API pública: sealed, códigos de diagnóstico,
  `DrmProtectedException.algorithms`, nome `diagnostics`.
- Idioma do README (adiado).
- Atualizar o Flutter local (3.47.5) e conferir a versão mínima no `pubspec`.

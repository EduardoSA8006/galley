# Galley — Design geral (arquitetura e subprojetos)

- **Data:** 2026-11-24
- **Status:** rascunho para aprovação
- **Escopo deste documento:** visão geral, decisões transversais e decomposição em subprojetos. Cada subprojeto terá o seu próprio documento de design detalhado antes de ser planejado.

## 1. Intenção e o porquê

Todas as bibliotecas Flutter de EPUB maduras hoje renderizam por meio de WebView (epub.js) ou convertem HTML em árvores de widgets genéricas. A primeira abordagem é pesada (um navegador inteiro por leitor, comunicação por ponte JS, memória alta, integração ruim com o app). A segunda não escala (milhares de widgets por capítulo, paginação precária, CSS limitado).

O **Galley** é um pacote Flutter open source, publicado no pub.dev, que renderiza EPUB **nativamente**, com um motor próprio de estilo e layout em Dart, pintando direto no `Canvas`. O objetivo é ser **mais rápido, mais leve e mais compatível** que os concorrentes existentes, e oferecer ao desenvolvedor de um app de leitura uma camada de abstração simples para aplicar as preferências do leitor.

## 2. Metas

1. Renderizar o maior número possível de EPUBs reais, incluindo, ao longo do roadmap, os difíceis: layout fixo, tabelas, texto vertical (CJK), notas de rodapé, CSS de editora pesado.
2. Superar **todos** os concorrentes em cada eixo medido: tempo de abertura, tempo de paginação, memória de pico, fluidez (FPS ao virar página), tamanho adicionado ao app e compatibilidade de renderização.
3. API pública simples para o desenvolvedor do app: preferências do leitor (família e tamanho de fonte, cores de fundo e texto, alinhamento, espaçamentos, margens, modo paginado/rolagem etc.) aplicadas por uma camada de abstração, sem que ele precise entender o motor.
4. Fornecer o **mecanismo** dos recursos de leitura: seleção de texto, marcações/destaques com âncoras estáveis (EPUB CFI), busca, navegação por índice, posição de leitura que sobrevive a mudanças de preferência, exposição do texto em ordem de leitura com destaque de trecho para TTS, notas de rodapé.
5. Qualidade alta e verificável: CI estruturado rodando testes, análise estática e benchmarks a cada PR.

## 3. Não-metas

- **Interface de usuário pronta.** O pacote não entrega menus, barras de busca, painéis de configuração nem menus de seleção. Ele roda a lógica e desenha as páginas; o app constrói a interface. (Decisão do usuário.)
- **Plataforma web.** Suportadas: Android, iOS, Linux, macOS e Windows. Web fica fora.
- **DRM** (Adobe, LCP etc.) — fora do escopo; o pacote recebe bytes/arquivos de EPUB já abertos. *(Chamada minha; ver §9.)*
- **Edição/criação de EPUB.**
- **Ser um navegador.** Não buscamos suporte a toda propriedade CSS; buscamos renderizar corretamente os livros (ver métrica de compatibilidade em §6).
- **Persistência.** O pacote produz âncoras e estados serializáveis; onde e como salvar é do app.

## 4. Anti-metas (o que faria o projeto fracassar mesmo "funcionando")

- Ficar abaixo de **qualquer** concorrente em **qualquer** eixo do benchmark. Isso reprova o projeto, com as ressalvas da §6 (gate a partir da 1.0; tamanho do app tem teto próprio; eixos comprovadamente inalcançáveis são documentados, não perseguidos à custa de qualidade).
- Sacrificar qualidade ou recursos só para vencer um número de benchmark.
- Exigir toolchain nativa (Rust, C++, CMake) de quem instala o pacote.
- Travar a UI: parsing, cascata e paginação pesados rodando na thread de interface.
- Forçar um gerenciador de estado ou uma interface específica no app consumidor.
- Regressões silenciosas de desempenho ou de renderização (todo PR é medido).

## 5. Restrições

- **Flutter/Dart:** estável atual é Flutter 3.50.1 / Dart 3.14.0 (20/11/2026); a máquina local está em 3.47.5 / 3.13.4 e deve ser atualizada. O SDK mínimo exato é decidido no primeiro subprojeto.
- **Dart puro na 1.0.** Sem FFI/Rust. Decisão consciente: o trabalho mais caro (medir e quebrar texto) tem de acontecer em `dart:ui` para que medição e pintura sejam idênticas; o restante roda bem em Dart AOT e em isolates; a ponte FFI custa serialização; binários nativos pioram a distribuição. **Rust só entra com evidência de benchmark** — uma etapa provada gargalo, com protótipo que vença com folga, trocada por trás da mesma interface.
- **Dependências mínimas** e bem mantidas; cada nova dependência é justificada no design do subprojeto.
- **Licença open source** permissiva. *(Chamada minha: BSD-3-Clause, padrão do ecossistema Flutter; ver §9.)*
- **Arquitetura do código:** feature-first + `core` + `shared`, com separação em camadas (padrão do usuário), adaptada a uma biblioteca:
  - `lib/galley.dart` — única API pública exportada.
  - `lib/src/core/` — primitivas compartilhadas (erros, diagnósticos, geometria, utilidades de texto).
  - `lib/src/features/<etapa>/` — uma pasta por etapa do pipeline (ver §7), cada uma com camadas `data` / `domain` / `presentation` quando fizer sentido.
  - `lib/src/shared/` — modelos trocados entre etapas.
  - A camada de widget segue MVVM: um controller (view model) expõe estado observável; o widget só renderiza.
  - **Sem Riverpod dentro do pacote** — uma biblioteca não deve impor gerenciador de estado. O controller usa `ChangeNotifier`/`ValueListenable`, que funcionam com qualquer solução. O **app de exemplo** usa Riverpod 3 + go_router. *(Chamada minha; ver §9.)*

## 6. Benchmarks e CI (parte do projeto desde o dia 1)

**Corpus de teste, em dois níveis:**

*Público (no repositório open source, reproduzível por qualquer pessoa):*
- casos sintéticos mínimos por recurso (um EPUB por comportamento);
- EPUBs escritos à mão com formatações variadas (tipografia, CSS de editora típico, tabelas, notas, imagens, idiomas e escritas diferentes), criados para o projeto;
- a suíte oficial `w3c/epub-tests` (EPUB 3.3; W3C Software and Document License), que também traz relatórios de resultado por leitor para comparação;
- livros reais variados de domínio público ou licença livre (romances, técnicos, com tabelas, ilustrados, layout fixo, CJK vertical).

*Privado (fora do repositório; só na máquina do mantenedor):* livros com direitos autorais que o mantenedor possui, indicados por `GALLEY_PRIVATE_CORPUS` e medidos pelo modo `local`, para cobrir CSS de editora real e casos difíceis. Só agregados ou identificadores anônimos (hash do conteúdo) saem da máquina; os arquivos e seus nomes, nunca.

**Referência de compatibilidade:** Chromium headless renderizando o mesmo capítulo, paginado por CSS columns no mesmo tamanho de página (modo paginado) e em rolagem contínua (modo rolagem); a comparação é visual, capítulo a capítulo, com tolerância definida no subprojeto de benchmark. *(Chamada minha.)*

**Métricas, todas numéricas e com limite de reprovação no CI:**
| Eixo | Métrica |
|---|---|
| Abertura | tempo até a primeira página visível |
| Paginação | tempo para paginar o livro inteiro; tempo para repaginar após mudar fonte |
| Memória | memória de pico e em regime ao ler |
| Fluidez | FPS / jank ao virar página e rolar |
| Tamanho | bytes adicionados ao app |
| Compatibilidade | fração de páginas do corpus que coincidem visualmente com uma referência renderizada por navegador, dentro de tolerância |

**Comparação com concorrentes:** um harness reproduzível roda os concorrentes no mesmo corpus e nas mesmas máquinas, e o resultado é comparado ao nosso. Lista inicial (levantada em 24/11/2026; mantida no subprojeto de benchmark):

| Concorrente | Técnica | Plataformas |
|---|---|---|
| `flutter_epub_viewer` 2.2.1 | epub.js em WebView | Android, iOS, macOS |
| `epub_view` 3.3.0 | parser epubx + HTML→widgets | Android, iOS, desktop |
| `cosmos_epub` 1.0.1 | widgets nativos, sem WebView | a verificar |
| `flutter_readium` 0.10.1 / `flureadium` 0.19.6 | plugin sobre Readium (WebView nativo) | Android, iOS (+macOS) |
| Readium Kotlin 3.4 / Swift 3.11 | WebView; referência de qualidade fora do Flutter | Android, iOS |

Cada concorrente é comparado nas plataformas que suporta. Pacotes abandonados (`vocsy_epub_viewer`, `epub_viewer`) ficam fora. Nenhum concorrente encontrado usa motor de layout próprio em Dart puro.

**Regras de reprovação (decisão do usuário):**
- **Quando vale:** o gate "abaixo de um concorrente reprova" trava **releases a partir da 1.0**. Antes disso, todos os números são medidos e publicados em cada PR, sem bloquear por comparação com concorrentes (regressões contra o nosso próprio baseline bloqueiam desde o início).
- **Tamanho do app:** não é comparado com leitores WebView (que reaproveitam o navegador do sistema). Tem um **teto absoluto** de bytes adicionados ao app; ultrapassar o teto reprova. Valor inicial proposto: 2 MB em release Android arm64, revisado no subprojeto de benchmark. *(Valor: chamada minha.)*
- **CSS exótico:** o que um navegador suporta e nós não é **documentado** (lista pública de suporte de CSS), não perseguido a qualquer custo.
- **Eixo inalcançável:** se um eixo se provar inalcançável sem perder qualidade, ele é documentado como tal; não se tira qualidade do projeto para vencer benchmark.

**Infraestrutura (decisão do usuário; detalhada no SP2, `2026-11-24-galley-sp2-benchmark-design.md`):**
- **A cada PR**, nos runners hospedados do GitHub: `dart format`, `flutter analyze` sem avisos, testes unitários e de golden, compatibilidade visual no corpus público e os gates de benchmark. Como esses runners oscilam, o gate não compara tempo cru com o histórico:
  - **Instruções (gate principal):** a `main` (merge-base) e o PR são compilados e medidos no mesmo job, com o mesmo toolchain, contando instruções de CPU (Valgrind no CI, `perf` no local). Reprova se algum benchmark ficar mais de 0,5% acima da `main`.
  - **A/B estatístico de tempo:** as duas versões em AOT no mesmo job, execuções intercaladas; reprova só com regressão de pelo menos 5% e IC de 95% (bootstrap da razão das medianas) inteiramente acima de 1,05.
  - Os jobs `instructions` e `ab` são status obrigatórios da `main`. Os gates funcionam sem o Bencher.
- **Bencher** guarda o histórico, os gráficos e a regressão gradual (reprova só o job noturno, com 10% de acúmulo sobre um baseline fixo atualizado pelo mantenedor) e comenta nos PRs. O envio é pulado sem `BENCHER_API_TOKEN`.
- **Toda noite** (e em push na `main`), também nos runners hospedados: instruções, comparação com concorrentes, tamanho do APK e um A/B mais longo, para formar o histórico. A medição em dispositivos físicos (FPS/jank, memória real) fica para o SP6.
- **Execução local no lugar do runner privado:** o modo `local`, na máquina do mantenedor, mede tempo absoluto, memória de pico, `perf` nativo, livros grandes e o corpus privado, e envia ao Bencher como `local-dev`.
- **Máquina dedicada (adição futura):** uma VM com núcleos fixos ou um servidor de entrada entrará como testbed novo e assumirá o modo `local` de forma agendada, com o corpus privado. Não faz parte do SP2.
- **Expansão permanente:** cada subprojeto acrescenta ao benchmark as métricas e comparações das etapas que criar (SP3: parsing de XHTML; SP4: cascata e seletores; SP5: paginação, repaginação e medição fatiada; SP6: FPS/jank, memória real, compatibilidade visual e leitores que renderizam; SP7: busca e CFI). O checklist vive em `benchmark/README.md`.

## 7. Arquitetura

Pipeline de etapas puras (dados entram, dados saem), cada uma testável e medida isoladamente:

```
bytes/arquivo .epub
  └─► 1. Container   zip, META-INF/container.xml, OPF (manifest, spine, metadata),
                     nav/NCX, EPUB 2 e 3, recursos (fontes, imagens, CSS)
        └─► 2. Document   XHTML/HTML → árvore de documento própria (IR), tolerante a erro
              └─► 3. Style   parser CSS, seletores, cascata, herança, valores computados;
                             preferências do leitor entram como camada da cascata
                    └─► 4. Layout   caixas (bloco, inline, float, tabela, imagem),
                                    texto via dart:ui Paragraph, hifenização própria,
                                    fragmentação em páginas (ou faixas de rolagem)
                          └─► 5. Render & API   RenderObject próprio pintando no Canvas,
                                                widget leitor, controller, preferências,
                                                navegação, seleção, CFI, busca, TTS hooks
```

- Etapas 1–4 não dependem de widgets. As etapas 1–3 rodam em **isolate**; a 4 usa `dart:ui` para medir texto e roda no isolate raiz (ver resultado da sonda e decisão abaixo).
- **Resultado da sonda (2026-11-24, Flutter 3.47.5, Linux):** `dart:ui` **não** funciona fora do isolate raiz — `ParagraphBuilder` falha com `UI actions are only available on root isolate.` em `Isolate.run`, `compute`, `Isolate.spawn` e com `BackgroundIsolateBinaryMessenger` (restrição do engine, vale para todas as plataformas). No isolate raiz, ~0,34 ms por parágrafo de 300 px após aquecimento.
- **Decisão (usuário, 2026-11-24): plano B + estimativa.** Etapas 1–3 (container, documento, estilo) em isolate. Etapa 4 (layout) no isolate raiz, fatiada por orçamento de quadro (~4 ms), sempre só à frente da página visível; o livro inteiro é paginado aos poucos em quadros ociosos; medições em cache por (texto, estilo, largura). Uma **estimativa** em isolate (larguras por caractere calibradas com medições reais do raiz) dá total de páginas e progresso imediatos, corrigidos conforme o layout exato avança.
- **Pendência:** issue upstream flutter/flutter#30604 (medição de texto em isolates; alternativa: API para desenhar glifos pré-moldados). Comentário com o caso de uso publicado em 2026-11-24; o projeto se oferece para contribuir se o time aceitar uma direção. **Quando corrigirem, reescrever a etapa 4 para rodar em isolate.** Um teste-canário no CI (`example/integration_test/`) falha quando o Flutter passar a permitir `dart:ui` em isolates, sinalizando a hora da reescrita. Como toda a arquitetura se apoia nisso, a viabilidade de medir texto com `dart:ui` em isolate de fundo é verificada por **sonda já no subprojeto 1**, em todas as plataformas-alvo. **Plano B** se falhar: etapas 1–3 continuam em isolate; o layout (4) roda na thread de UI em fatias com orçamento por quadro, sempre só à frente da página visível, com as mesmas interfaces de dados. *(Chamada minha.)*
- **Escritas na 1.0:** latino, cirílico, grego; CJK horizontal; RTL e bidi (árabe, hebraico) — o modelo de linhas, posição e seleção é bidi-ciente desde o início. **Depois da 1.0:** texto vertical. **Hifenização na 1.0:** pt, en, es, fr, de, com padrões TeX de licença livre; outros idiomas por padrões adicionais. *(Recomendação aceita pelo usuário.)*
- Erros nunca derrubam o leitor: cada etapa é tolerante e reporta **diagnósticos** (avisos estruturados) a um coletor que o app pode observar.
- A posição de leitura é expressa em termos do documento (CFI / caminho na árvore + deslocamento), nunca em número de página, para sobreviver à repaginação.
- **Preferências do leitor × CSS da editora:** as preferências são uma camada explícita na cascata, com política configurável por propriedade (ex.: forçar fonte e cor, respeitar alinhamento da editora). A política padrão é decidida no design do subprojeto de estilo.

## 8. Subprojetos e ordem

Cada um passa por brainstorming → design → plano → implementação por subagentes → revisão, um de cada vez:

1. **Fundação + Container** — scaffolding do pacote, CI base, núcleo de erros/diagnósticos, leitura completa do pacote EPUB 2/3.
2. **Benchmark & corpus** — corpus, harness de métricas, harness de concorrentes, integração ao CI. (Vem cedo para que tudo depois seja medido.)
3. **Document (IR)** — parser XHTML/HTML tolerante e árvore de documento.
4. **Style** — motor CSS e camada de preferências.
5. **Layout & paginação** — layout de caixas, texto, hifenização, fragmentação.
6. **Render & API pública** — widget, controller, preferências, navegação, posição de leitura. *(Ao fim deste, existe um leitor utilizável de texto corrido.)*
7. **Recursos de leitura** — seleção, CFI/marcações, busca, TTS hooks, notas de rodapé.
8. **Casos difíceis** — layout fixo, texto vertical, tabelas complexas, demais lacunas de CSS apontadas pelo benchmark.

**1.0** = subprojetos 1–7 com os benchmarks verdes para livros de texto corrido. Layout fixo e texto vertical ficam para versão seguinte, mas a arquitetura (modelo de páginas, eixo de escrita no layout) os prevê desde o início.

## 9. Abordagens consideradas

| Abordagem | Ganho | Custo | Decisão |
|---|---|---|---|
| A) XHTML/CSS → widgets Flutter | começo rápido | milhares de widgets por capítulo, paginação difícil, floats/tabelas/vertical como remendo; é o teto dos concorrentes | descartada |
| **B) Motor próprio em Dart puro, pintando no Canvas** | controle total, melhor desempenho possível, paginação nativa no layout, mesma arquitetura para os casos difíceis, instalação trivial | maior esforço: motor de CSS e layout próprios | **escolhida pelo usuário** |
| C) Motor HTML/CSS nativo via FFI (litehtml, Stylo/Taffy) | herda parte da compatibilidade CSS | toolchain nativa em 5 plataformas, binário maior, medição de texto dividida, dependência das lacunas da lib | descartada |
| B + Rust via ponte para processamento bruto | possível ganho em etapas específicas | ver §5 | adiada: só com evidência de benchmark |

## 10. Decisões do usuário (registradas)

- Cobertura máxima de EPUBs, incluindo os difíceis (no roadmap).
- Pacote open source no pub.dev.
- Personalização do leitor via camada de abstração simples.
- Benchmarks contínuos contra concorrentes; ficar abaixo de qualquer um reprova.
- CI estruturado rodando a cada PR.
- Plataformas: Android, iOS, desktop (Linux, macOS, Windows); sem web.
- O pacote fornece só a lógica/renderização; toda UI de controle é do app.
- Abordagem B; Dart puro na 1.0; Rust apenas com evidência de benchmark.
- Gate contra concorrentes a partir da 1.0; tamanho do app com teto próprio; CSS exótico e eixos inalcançáveis documentados, sem sacrificar qualidade.
- Toda a bateria em cada PR nos runners do GitHub; serviço alugado para medições precisas noturnas.
- Corpus público (livre + EPUBs escritos à mão) no repositório; corpus privado só na máquina do mantenedor (modo `local`).
- Escritas na 1.0: latino/cirílico/grego, CJK horizontal, RTL/bidi; vertical depois; hifenização pt/en/es/fr/de.

## 11. Chamadas minhas (para revisão)

- Nome do pacote `galley` (disponibilidade no pub.dev a confirmar).
- Licença BSD-3-Clause.
- DRM fora do escopo.
- Sem Riverpod dentro do pacote; app de exemplo com Riverpod 3 + go_router.
- Benchmark contra concorrentes completo em agenda noturna; benchmark por etapa em cada PR.
- Ordem dos subprojetos, com benchmark como segundo.
- Definição de 1.0 (subprojetos 1–7, texto corrido).
- Teto inicial de tamanho: 2 MB (release Android arm64).
- Sonda de `dart:ui` em isolate antecipada para o subprojeto 1, com plano B de layout fatiado na UI.
- Referência de compatibilidade: Chromium headless com CSS columns, capítulo a capítulo.
- Reprovação de desempenho por PR baseada em métricas estáveis e margem estatística.
- Cada plano de implementação cobre um subprojeto; este documento é o roteiro.

## 12. O que fica para o construtor

Detalhes de cada etapa são decididos no design de cada subprojeto: estruturas de dados da IR, algoritmo de cascata, algoritmo de quebra de linha e padrões de hifenização, formato de diagnósticos, formato e limites exatos dos benchmarks, tolerância da comparação visual, API exata do controller.

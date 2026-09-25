# Spikes da Fase 0

Código descartável. Nada daqui vira produção; o que aprendemos vai para `doc/`
(em especial `doc/13-riscos-spikes-fases.md`).

## Onde cada coisa fica

| Caminho | Conteúdo |
|---|---|
| `test/spike/s*_test.dart` | Spikes que rodam em `flutter_tester` (fonte `FlutterTest`, sem engine real) |
| `test/spike/support/` | Protótipos de lógica pura usados pelos testes acima |
| `example/integration_test/spike_*_test.dart` | Spikes que exigem engine real (isolate, fontes do sistema, pixels) |
| `spike/RESULTADO-S*.md` | Um por spike: o que foi medido, o número, e "sustenta / contradiz doc/XX §Y" |

## Como rodar

```sh
flutter test test/spike                              # flutter_tester
cd example && flutter test integration_test/spike_s1_isolate_paragraph_test.dart -d linux
```

Na engine real, rode **um arquivo por invocação**: `flutter test integration_test
-d linux` com mais de um arquivo falha no segundo com `Unable to start the app on
the device` (Flutter 3.44.1).

O S9 roda também no Chrome. `--platform chrome` compila com DDC e `--wasm` com
dart2wasm `-O0`, então os números servem para comparar alvos, não como
desempenho de release (ver `RESULTADO-S9.md`):

```sh
CHROME_EXECUTABLE=/usr/bin/chromium flutter test --platform chrome test/spike/s9_cooperative_worker_test.dart
CHROME_EXECUTABLE=/usr/bin/chromium flutter test --platform chrome --wasm test/spike/s9_cooperative_worker_test.dart
```

S1 e S5–S8 rodaram em Flutter 3.44.1; S2, S4 e S9, em 3.47.5. O mínimo do
`pubspec.yaml` continua 3.44.

| Spike | Pergunta | Onde |
|---|---|---|
| S1 | `ui.Paragraph` funciona em isolate de background? | `example/integration_test/` |
| S2 | Seleção sobre `RenderBox` próprio: toque ↔ offset canônico, retângulos, palavra, arraste e alças através de blocos e páginas, `DisplayMap`? | `test/spike/` |
| S4 | O algoritmo de tabela da Emenda 12 produz layouts corretos, e a que custo? | `test/spike/` |
| S5 | `ui.Paragraph` quebra e pinta soft hyphen? `justify` tem controle de espaçamento? | `test/spike/` + `example/integration_test/` |
| S6 | Desofuscação IDPF e Adobe; custo do SHA-1 próprio | `test/spike/` |
| S7 | `addPlaceholder` inline; `instantiateImageCodec` com tamanho-alvo | `test/spike/` |
| S8 | Paginação ancorada cobre a seção e difere em ≤ 1 página? | `test/spike/` |
| S9 | A Camada A como `sync*` fatiado a 4 ms é viável no web? Quanto perde para o isolate? | `test/spike/` (VM e Chrome) |

Regras: nenhum arquivo de depuração versionado; nenhuma edição em `doc/` a
partir de spike (o resultado vai no `RESULTADO-*.md` e a documentação é
atualizada em revisão separada).

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
cd example && flutter test integration_test -d linux # engine real (Linux desktop)
```

| Spike | Pergunta | Onde |
|---|---|---|
| S1 | `ui.Paragraph` funciona em isolate de background? | `example/integration_test/` |
| S5 | `ui.Paragraph` quebra e pinta soft hyphen? `justify` tem controle de espaçamento? | `test/spike/` + `example/integration_test/` |
| S6 | Desofuscação IDPF e Adobe; custo do SHA-1 próprio | `test/spike/` |
| S7 | `addPlaceholder` inline; `instantiateImageCodec` com tamanho-alvo | `test/spike/` |
| S8 | Paginação ancorada cobre a seção e difere em ≤ 1 página? | `test/spike/` |

Regras: nenhum arquivo de depuração versionado; nenhuma edição em `doc/` a
partir de spike (o resultado vai no `RESULTADO-*.md` e a documentação é
atualizada em revisão separada).

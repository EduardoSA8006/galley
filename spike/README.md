# Spikes da Fase 0

Código descartável. Nada daqui vira produção; o que aprendemos vai para `doc/`
(em especial `doc/13-riscos-spikes-fases.md`, coluna "Resultado").

| Spike | Onde roda | Como rodar |
|---|---|---|
| S1 `ui.Paragraph` em isolate | Engine real (Linux desktop) | `cd spike/app && flutter test integration_test -d linux` |
| S5 soft hyphen e justificação | `flutter_tester` | `flutter test test/spike/s5_*` |
| S7 placeholder inline e decode com tamanho-alvo | `flutter_tester` | `flutter test test/spike/s7_*` |
| S8 paginação ancorada | `flutter_tester` (lógica pura) | `flutter test test/spike/s8_*` |

Cada spike termina com um `RESULTADO.md` na sua pasta ou um comentário de
cabeçalho no teste dizendo: o que foi medido, o número, e a decisão que isso
sustenta.

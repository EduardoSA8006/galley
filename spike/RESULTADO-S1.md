# S1 — `ui.Paragraph` em isolate de background

**Data:** 2026-09-09. **Flutter:** 3.44.1 stable (Dart 3.12.1), engine real,
Linux desktop (`example/integration_test/spike_s1_isolate_paragraph_test.dart`).

## Resultado: negativo, definitivo

| Onde | `ParagraphBuilder` + `layout` + `computeLineMetrics` |
|---|---|
| Isolate raiz | ok, 2 linhas |
| `Isolate.run` | lança `String`: `UI actions are only available on root isolate.` |
| `Isolate.spawn` + `SendPort` | idem, mesma mensagem |

O erro é lançado na **construção** do `ParagraphBuilder`, antes de qualquer
layout. As duas APIs de isolate se comportam igual, então não há caminho via
grupo de isolates compartilhando heap.

## Efeito na documentação

- **Sustenta** doc/08 §2 (paginação em background por orçamento por frame no
  isolate principal) e P4 em doc/01.
- **Sustenta** doc/13 S1 como "presume-se negativo". Pode ser marcado como
  fechado, com a mensagem literal acima.
- Nada a mudar.

## Nota operacional

`flutter test integration_test -d linux` com **mais de um arquivo** falha no
segundo com `Error waiting for a debug connection: The log reader stopped
unexpectedly, or never started` / `Unable to start the app on the device`
(limitação do harness de integração no desktop ao relançar o app). Rodar um
arquivo por invocação: `flutter test integration_test/<arquivo> -d linux`.
Sugestão: registrar isso em `spike/README.md`.

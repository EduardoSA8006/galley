# S6 — Desofuscação de fontes e SHA-1 próprio

**Data:** 2026-09-09. **Ambiente:** Flutter 3.44.1 stable, `flutter_tester`
(Dart JIT; os tempos absolutos são piores que em AOT no dispositivo). **Código:**
`test/spike/support/sha1.dart`, `test/spike/support/s6_font_obfuscation.dart`,
`test/spike/s6_font_deobfuscation_test.dart`.

## Perguntas

1. Um SHA-1 próprio (~100 linhas, sem dependência) está correto e é rápido o
   bastante para a chave do cache de seção (doc/08 §4.1) e para a chave IDPF?
2. Desofuscar fontes IDPF e Adobe (doc/09 §4) é o XOR trivial descrito, e a
   fonte resultante carrega no motor de texto?

## Resultados

### SHA-1

- Vetores: `"abc"`, string vazia, `"The quick brown fox…"`, e as fronteiras de
  padding com 55, 56 e 64 bytes de `'a'` — **todos corretos** (conferidos contra
  `sha1sum`).
- Tempo (mediana de 5, `flutter_tester`):

| Entrada | Mediana | Min | Max |
|---|---|---|---|
| 100 KB | **1 608–2 994 µs** (duas execuções, a segunda com outros testes rodando em paralelo) | 1 598 µs | 34 201 µs (1ª medição, JIT aquecendo) |
| 1 024 KB | **15 845–16 245 µs** | 15 774 µs | 16 538 µs |

Cerca de **16 µs por KB** em JIT. Linear.

### Ofuscação de fonte

- Fonte real: `/usr/share/fonts/noto/NotoSerif-Regular.ttf` (712 444 bytes).
- IDPF: XOR dos primeiros **1040** bytes com SHA-1 (20 bytes) dos identifiers
  concatenados sem espaço/CR/LF/TAB; bytes além de 1040 intactos; ida e volta
  devolve bytes idênticos; chave errada não devolve a fonte.
- Adobe: XOR dos primeiros **1024** bytes com os 16 bytes do UUID; idem.
- A fonte desofuscada carregada via `FontLoader('SpikeS6')` faz layout de um
  `ui.Paragraph` sem erro: 1 linha, 224.2 px para "Fonte desofuscada em layout."

## Sustenta / contradiz

| Doc | Seção | Veredito |
|---|---|---|
| 09 | §4 ofuscação de fonte "desofuscar é trivial" | **Sustenta.** São ~40 linhas além do SHA-1 |
| 09 | §4 chave IDPF "SHA-1 do identifier normalizado" | **Sustenta**, precisando: SHA-1 da **concatenação de todos os `unique-identifier`** com espaço, CR, LF e TAB removidos, como a especificação IDPF exige. O texto atual fala em "identifier" no singular |
| 11 | §1 hash próprio "~150 linhas" | **Sustenta.** O SHA-1 ficou em ~95 linhas |
| 08 | §4.1 "O SHA-1 da seção (10 a 500 KB) custa menos de um milissegundo" | **Contradiz** em JIT: 100 KB custam 1,6 ms e 500 KB custariam ~8 ms. Em AOT no dispositivo espera-se 2 a 4× melhor, ainda assim 500 KB ficam na casa de 2 a 4 ms. Como o hash roda no `EpubWorker` e fora do caminho crítico da primeira página (a chave é calculada para consultar o cache, então **está** no caminho da abertura com cache quente), o número precisa ser corrigido para "da ordem de 1 a 2 ms por 100 KB" e a decisão de manter SHA-1 deve ser reavaliada: um hash não criptográfico de 64 bits (FNV-1a 64 ou xxHash64, ~10× mais rápido) basta para chave de cache local, onde não há adversário. Recomendação: **SHA-1 só para a chave IDPF (obrigatório pela especificação); FNV-1a 64 para a chave do cache**, e medir em AOT na Fase 1 antes de fechar |

## Limites do spike

- Tempo medido em JIT no `flutter_tester`; a decisão final sobre o hash do cache
  deve ser tomada com medição em `--profile` no dispositivo de referência.
- Não testa `encryption.xml` real (o parse do XML é da Fase 1); o corpus tem
  casos IDPF e Adobe para isso.

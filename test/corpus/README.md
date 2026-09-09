# Corpus

Cada subpasta é um caso: um `book.epub`, um `README.md` de **uma linha** dizendo
o que ele testa e de onde veio, e, quando aplicável, exatamente um destes:

- `diagnostics.expected` — códigos de `EpubDiagnostic` (doc/09 §3) esperados,
  um por linha, em ordem alfabética. Só diagnósticos determinados pelo parse;
  os que dependem de viewport (`tableOverflow`, `indivisibleBlock`) não entram.
- `exception.expected` — nome da exceção fatal (doc/09 §2) que `open` deve
  lançar.

Grupos (doc/10 §1.1): `regressoes/`, `estrutura/`, `conteudo/`, `faixa-b/`,
`escrita/`, `patologia/` são sintéticos; `reais/` são EPUBs de domínio público
baixados, cada um com URL e licença no README.

Os sintéticos são gerados por `dart run tool/corpus/generate.dart` e **também**
versionados, para que o teste não dependa do gerador. Regenerar um grupo apaga
e recria a pasta inteira; `--only <grupo|slug>` regenera só uma parte.

`corpus_test.dart` verifica a convenção acima e a forma do ZIP; não parseia
EPUB (isso é a Fase 1).

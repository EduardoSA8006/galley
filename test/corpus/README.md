# Corpus

Cada subpasta é um caso: um `.epub`, um `README.md` de uma linha dizendo o que
ele testa e de onde veio, e, quando aplicável, `diagnostics.expected` com a
lista exata de códigos de diagnóstico esperados.

Grupos (doc/10 §1.1): `regressoes/`, `estrutura/`, `conteudo/`, `faixa-b/`,
`escrita/`, `patologia/`.

Arquivos sintéticos são gerados por `dart run tool/corpus/generate.dart` e
**também** versionados, para que o teste não dependa do gerador.

## Não lançado

- Fase 1, sub-projeto 1 (contêiner): leitor de ZIP próprio com leitura por
  faixas, ZIP64, prefixo e limites contra arquivo hostil; inflate chunked com
  CRC-32 sempre verificado; detecção de DRM (LCP, ADEPT, criptografia do ZIP);
  desofuscação de fontes IDPF e Adobe; `FileEpubByteSource`,
  `MemoryEpubByteSource`, `EpubResourceProvider`, `EpubException` e
  `EpubDiagnostic` públicos.

- Fase 0 concluída, exceto S3: spikes S1, S2 e S4–S9, documentação v0.5,
  corpus de 65 EPUBs, harness de desempenho com baseline por modelo de CPU,
  CI no GitHub Actions e Flutter mínimo 3.47.0.

## 0.0.1

- Fase 0: documentação de arquitetura v0.3, esqueleto do pacote, spikes e corpus.

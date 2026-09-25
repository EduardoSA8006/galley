# Segurança

O galley lê arquivos EPUB de origem arbitrária: ZIP, XML, XHTML, CSS, fontes e
imagens. Falhas de parse que travam, estouram memória ou leem fora do contêiner
são problemas de segurança, não só bugs.

## Como reportar

Use o **reporte privado de vulnerabilidade** do GitHub, em
[Security → Report a vulnerability](https://github.com/EduardoSA8006/galley/security/advisories/new).
Não abra issue pública para vulnerabilidade.

Inclua, se puder, o EPUB (ou um trecho reduzido) que dispara o problema, a
versão do galley e do Flutter e a plataforma.

## Versões suportadas

O pacote ainda não foi publicado (Fase 0). Até a 1.0, só a `main` recebe
correções.

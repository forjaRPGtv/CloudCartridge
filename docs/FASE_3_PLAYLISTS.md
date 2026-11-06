# Fase 3 — Playlists, thumbnails e catálogo

## Auditoria da origem local

Os scripts históricos foram encontrados em `RetroArch-Tools/scripts`. Eles contêm conhecimento útil de extensões, nomes e cores, mas alguns movem ROMs, removem diretórios e reescrevem playlists com `-Force`. Por isso não foram executados nem integrados diretamente.

## Primeiro lote seguro

- Descoberta recursiva de candidatos sem mover ou renomear ROMs.
- Merge incremental de playlists RetroArch 1.5.
- Deduplicação de caminhos sem diferenciar maiúsculas/minúsculas.
- Entradas e campos customizados existentes são preservados integralmente.
- Apenas jogos ausentes são adicionados; itens temporariamente offline não são removidos.
- Prévia por padrão e gravação JSON atômica somente com aplicação explícita.
- Duas varreduras sucessivas geram hash idêntico.
- `.m3u` substitui apenas os discos que referencia e que realmente existem; discos avulsos permanecem visíveis.
- Índice persistente reaproveita metadados de arquivos cujo tamanho e `mtime` não mudaram.
- Reparo de thumbnails só cria arquivos ausentes por troca final; arte existente nunca é aberta para escrita.
- CLI: `library index`, `playlist sync` e `thumbnails plan`, com prévia por padrão.

## Evidência

A suíte completa está em **32 testes aprovados, 0 falhas**. Além da idempotência por SHA-256, os testes cobrem `.m3u`, atualização incremental do índice e preservação byte a byte de thumbnail personalizada.

## Próximos pontos

- Medição de desempenho com biblioteca equivalente a 20 mil títulos.
- Downloader oficial de thumbnails com validação de conteúdo e retomada.
- Relatório agregado de inventário/compatibilidade por sistema.

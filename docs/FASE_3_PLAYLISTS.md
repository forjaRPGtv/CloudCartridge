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
- Inventário agregado por sistema, extensão, quantidade e bytes via `library inventory`.
- Downloader aceita apenas HTTPS em `thumbnails.libretro.com`, valida assinatura PNG e tamanho antes da promoção atômica.

## Evidência

A suíte completa está em **34 testes aprovados, 0 falhas**. Além da idempotência por SHA-256, os testes cobrem `.m3u`, atualização incremental, inventário por sistema, preservação byte a byte de arte personalizada e rejeição de host/arquivo inválido.

O índice também foi exercitado com **20.000 arquivos reais em fixture temporária** e concluiu dentro do gate de 60 segundos.

## Próximos pontos

- Retomada por bloco para downloads grandes de thumbnails (não necessária para PNGs pequenos no fluxo atual).
- Cruzar o inventário com compatibilidade efetiva de cores/emuladores.

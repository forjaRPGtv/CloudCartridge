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

## Evidência

A suíte completa está em **29 testes aprovados, 0 falhas**. O teste de playlist preserva rótulo, core e propriedades customizadas, adiciona somente um jogo ausente e comprova idempotência por SHA-256.

## Próximos pontos

- Tratamento seguro de `.m3u` sem esconder discos que não pertencem ao manifesto.
- Índice persistente para bibliotecas grandes.
- Reparo de thumbnails exclusivamente ausentes, sem sobrescrever arte personalizada.
- CLI e relatório de inventário por sistema.

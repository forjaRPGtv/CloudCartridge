# Changelog

As mudanças relevantes do CloudCartridge são registradas neste arquivo. O projeto ainda não adotou versionamento semântico público; os marcos usam data e evidência de validação.

## Não publicado

- Nenhuma mudança funcional pendente.

## Marco de produção local — 2026-11-18

### Adicionado

- CLI unificada para diagnóstico, detecção, cache, downloads, saves, biblioteca, Host e MiSTer.
- Save Guardian com manifesto de três vias, conflitos, locks, fila offline e versões restauráveis.
- Catálogo incremental, playlists idempotentes, multidisco e reparo conservador de thumbnails.
- Host privado autenticado para até cinco convidados, convites de uso único e isolamento de saves.
- Adaptador MiSTer isolado com compatibilidade explícita e verificação SHA-256.
- Instalador com prévia, confirmação e backup; empacotamento sanitizado com manifesto.

### Corrigido

- Mapeamento de Wii U preservado como Cemu standalone em vez de core RetroArch inexistente.
- Conflito falso com sincronização nativa do RetroArch.
- Sucesso falso de desidratação quando o provedor não altera o estado do arquivo.
- Resíduos temporários no empacotamento e ação incompatível no menu de contexto.
- Caminhos de saves e savestates do RetroArch para o diretório autorizado no disco de dados.

### Validado

- 45 testes automatizados aprovados em fixtures isoladas.
- `doctor --json` com 45/45 cores e seis mapeamentos standalone detectados no ambiente de referência.
- DPAPI e round-trip versionado de save sintético no Windows.
- Cache oficial do Google Drive para Desktop migrado para o disco de dados e unidade virtual remontada.

### Limites conhecidos

- A expulsão física exatamente após três dias depende de uma interface suportada do provedor, não disponível no volume virtual observado.
- Host/Client entre dois PCs e transferência/save em MiSTer físico ainda exigem homologação com o equipamento correspondente.

# Continuidade — CloudCartridge vNext

## Objetivo e fonte

Finalizar e depurar o projeto conforme `CloudCartridge_vNext_PLANO_MESTRE_CODEX.md`, preservando ROMs, playlists, saves e configurações reais. Branch `main`; baseline inicial da retomada: `8b7cfa7`.

## Estado implementado

- Fase 1: configuração, caminhos seguros, cache, retenção/pin, fila deduplicada, retomada e SHA-256.
- Fase 2: Save Guardian três-vias, locks, detecção de caminhos/cores, fila offline, identidade e restauração versionada.
- Fase 3: playlists idempotentes, `.m3u`, catálogo incremental de 20 mil títulos e thumbnails ausentes sem sobrescrever arte customizada.
- Fase 4: Host privado para cinco convidados, convites de uso único, confirmação/recovery, credenciais, isolamento, API autenticada, anti-replay/rate-limit e listener privado.
- Fase 5: adaptador MiSTer isolado, operação PC tolerante a MiSTer offline, compatibilidade por core/formato e transferência fixture com SHA-256.
- Fase 6: instalador com prévia, confirmação e backup; monitor TUI; pacote sanitizado; manuais; privacidade/recuperação; Agent Skill local.

## Evidência atual

- `Testar_CloudCartridge.cmd`: **45 aprovados, 0 falhas**.
- Benchmark de catálogo com 20 mil títulos dentro do limite de segurança.
- Listener HTTP loopback real testado; porta efêmera escolhida pelo Windows para evitar colisão no teste.
- Instalador testado em cópia temporária: prévia não grava; aplicação cria configuração; segunda aplicação cria backup.
- Pacote fixture: README e manifesto SHA-256 presentes; zero config, banco Host, backup, log, cache, credencial ou ZIP aninhado.
- Skill validada por regressão estrutural local. O `quick_validate.py` oficial não executou porque PyYAML não está instalado; nenhuma dependência foi instalada sem autorização.

## Gate real de 2026-11-17

- Configuração local aplicada; `doctor --json` em `status: ok`, 45/45 cores e 6/6 mapeamentos standalone.
- Caminhos de saves e savestates do RetroArch corrigidos para `Z:\_ISOS_ROMS_\_RA_SAVES`, com backup e SHA-256 anterior.
- DPAPI real aprovado no perfil Windows interativo; arquivo e credenciais aleatórias do teste removidos.
- Save Guardian real aprovado em upload, hash, estado sincronizado, atualização versionada e preservação de versão; artefatos sintéticos locais/remotos removidos.
- Wii U removido da lista de cores RetroArch incompletos e preservado como Cemu standalone.
- Menu de contexto atualizado para a telemetria atual; ação legada de `attrib` removida.

## Limites ainda externos ou do provedor

Não declarar como validados sem ambiente apropriado:

- fluxo LAN/VPN entre dois PCs físicos;
- transferência, estrutura PSX/CHD e save em MiSTer físico.

O Google Drive streaming observado é um volume virtual, não um placeholder NTFS/CFAPI. A leitura e a integridade foram validadas, mas a liberação física exata após três dias permanece sob o gerenciador automático de cache do Google Drive para Desktop. `attrib` com código zero sem mudança de estado não é mais aceito como sucesso.

Medição de produção de 2026-11-18: o diretório oficial do cache foi alterado pela interface do Google Drive para `Z:\_GOOGLE_DRIVE_CACHE`. O Drive reiniciou, migrou cerca de 9,5 GiB para o novo local e remontou a unidade virtual `G:`. O `doctor --json` permaneceu em `status: ok` após a migração.

O Host e o MiSTer estão implementados e cobertos por fixtures, mas esses quatro gates físicos continuam pendentes. Não testar com saves reais sem autorização explícita e backup.

## Retomada

```cmd
Testar_CloudCartridge.cmd
```

Depois, executar os gates externos um por vez, registrando evidência e sem alterar automaticamente a biblioteca do usuário.

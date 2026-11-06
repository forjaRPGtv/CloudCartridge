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

- `Testar_CloudCartridge.cmd`: **43 aprovados, 0 falhas**.
- Benchmark de catálogo com 20 mil títulos dentro do limite de segurança.
- Listener HTTP loopback real testado; porta efêmera escolhida pelo Windows para evitar colisão no teste.
- Instalador testado em cópia temporária: prévia não grava; aplicação cria configuração; segunda aplicação cria backup.
- Pacote fixture: README e manifesto SHA-256 presentes; zero config, banco Host, backup, log, cache, credencial ou ZIP aninhado.
- Skill validada por regressão estrutural local. O `quick_validate.py` oficial não executou porque PyYAML não está instalado; nenhuma dependência foi instalada sem autorização.

## Limites ainda externos

Não declarar como validados sem ambiente apropriado:

- hidratação/desidratação CFAPI real do Google Drive;
- DPAPI no perfil Windows interativo do usuário;
- fluxo LAN/VPN entre dois PCs físicos;
- transferência, estrutura PSX/CHD e save em MiSTer físico.

O Host e o MiSTer estão implementados e cobertos por fixtures, mas esses quatro gates físicos continuam pendentes. Não testar com saves reais sem autorização explícita e backup.

## Retomada

```cmd
Testar_CloudCartridge.cmd
```

Depois, executar os gates externos um por vez, registrando evidência e sem alterar automaticamente a biblioteca do usuário.

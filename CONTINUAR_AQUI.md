# Continuidade — CloudCartridge vNext

## Objetivo

Finalizar e depurar o projeto conforme `CloudCartridge_vNext_PLANO_MESTRE_CODEX.md`, sem recomeçar do zero e sem arriscar ROMs, playlists ou saves reais.

## Fonte e estado

- Branch: `main`, baseline inicial `8b7cfa7`.
- Fase 0 concluída: código, dependências e riscos auditados.
- Fase 1 em andamento: primeiro lote de estabilização integrado e coberto por testes.
- Backup anterior à Fase 1: `..\backups\CloudCartridge-phase1-20261106\` (bundle Git completo e snapshot de configuração do RetroArch).

## Alterações deste marco

- `CloudCartridge.Core.psm1`: configuração central, limites de caminho, JSON por troca final e versões de saves.
- Launcher/telemetria/watcher usam configuração compartilhada e caminhos relativos ao projeto.
- Limpeza só atua dentro da raiz gerenciada e só muda estado após sucesso.
- Cloud Save respeita flag e preserva a versão anterior em divergência.
- Prefetch usa modo dedicado e respeita flag.
- `CloudCartridge.cmd`: CLI local de diagnóstico e inventário.
- `Testar_CloudCartridge.cmd`: regressão isolada.
- Force-push automático removido.

## Evidência atual

- `Testar_CloudCartridge.cmd`: 12 aprovados, 0 falhas.
- Smoke real em PowerShell 5.1 do Launcher e Telemetria com fixture temporária.
- `doctor --json`: RetroArch detectado, 45/46 mapeamentos de core detectados, 6/6 mapeamentos standalone (5 executáveis únicos).
- Alertas atuais: `config.json` local ausente, destino de Cloud Save não configurado e Wii U ainda com mapeamento `DETECT`.

## Limites e riscos preservados

- Não executar testes contra saves reais sem autorização explícita e backup.
- Seleção histórica de saves por nome/janela de 60 minutos ainda será substituída pelo Save Guardian.
- Não integrar scripts antigos de playlists diretamente: contêm caminhos fixos e operações destrutivas.
- Métrica atual é de leitura/hidratação, não bytes reais de rede.
- Host multiusuário, autenticação, MiSTer e Agent Skill ainda estão pendentes.

## Próxima ação

Fechar o restante da Fase 1: configuração local segura, detecção dinâmica, política de cache configurável, fila de download/prefetch e testes dos cenários locais T01–T14/T27/T37/T38/T39. Depois iniciar Save Guardian da Fase 2 com fixtures e merge de três vias.

Comando de retomada:

```cmd
Testar_CloudCartridge.cmd
```

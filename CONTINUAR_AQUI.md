# Continuidade — CloudCartridge vNext

## Objetivo

Finalizar e depurar o projeto conforme `CloudCartridge_vNext_PLANO_MESTRE_CODEX.md`, sem recomeçar do zero e sem arriscar ROMs, playlists ou saves reais.

## Fonte e estado

- Branch: `main`, baseline inicial `8b7cfa7`.
- Fase 0 concluída: código, dependências e riscos auditados.
- Fase 1 em andamento: dois lotes de estabilização integrados e cobertos por testes.
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
- Política/pin/limpeza do cache são prévia por padrão e só aplicam com `--yes`.
- Journal de downloads deduplica solicitações, prioriza o jogo atual e limita concorrência.
- Launcher e CLI compartilham o mesmo executor de limpeza segura.

## Evidência atual

- `Testar_CloudCartridge.cmd`: 19 aprovados, 0 falhas.
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

Fechar T05/T06/T27 com checksum e retomada segura da hidratação e ampliar T39 para comparar configuração efetiva de saves/cores. Depois iniciar o Save Guardian da Fase 2 com fixtures, manifesto e merge de três vias.

Comando de retomada:

```cmd
Testar_CloudCartridge.cmd
```

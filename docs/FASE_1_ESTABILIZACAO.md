# Fase 1 — Estabilização do cliente Windows

## Escopo deste marco

Primeiro lote seguro da Fase 1, sem executar jogos e sem acessar saves reais.

## Integrado

- Backup Git completo e snapshot separado das configurações do RetroArch antes das alterações.
- Módulo compartilhado para configuração, caminhos gerenciados, JSON atômico e versionamento de saves.
- Watcher independente do caminho antigo do workspace.
- Flags de limpeza, Cloud Save Sync e multidisco respeitadas nos fluxos correspondentes.
- Limpeza rejeita arquivos fora da raiz gerenciada e só marca `cloud_only` após sucesso do `attrib`.
- Prefetch multidisco não depende mais de `LaunchAfter` e usa modo dedicado sem iniciar emulador.
- Publicação não executa mais `git push --force` automaticamente.
- Runner de testes isolados e `Testar_CloudCartridge.cmd` na raiz.
- CLI local com `status`, `doctor`, `detect`, `emulators list`, `cores list` e `cache status`, incluindo saída JSON versionada.

## Validação

O runner cobre sintaxe UTF-8, JSON, defaults e rejeição de configuração inválida, traversal/prefix collision, escrita JSON sem resíduos, criação/deduplicação/versionamento de saves, ausência de force-push, resolução do watcher e flags de recursos.

Resultado do marco: **12 testes aprovados, 0 falhas**, incluindo smoke real do Launcher e da Telemetria em Windows PowerShell 5.1 com fixture temporária.

O `doctor --json` detectou o RetroArch, 45 dos 46 mapeamentos de core e os seis mapeamentos standalone (cinco executáveis únicos). Permanecem avisos para configuração local ausente, destino de Cloud Save não configurado e entrada Wii U ainda marcada como `DETECT`.

## Limites ainda abertos

- O Save Guardian completo ainda precisa de manifesto, gerações, merge de três vias, locks e recuperação de caminhos antigos.
- A seleção de saves ainda herda o casamento aproximado e a janela histórica de 60 minutos; agora há versionamento antes da troca, mas a autoridade do arquivo ainda será redesenhada.
- Downloads multidisco continuam sequenciais; fila concorrente e prioridades ainda serão implementadas.
- Métrica da telemetria ainda mede leitura/hidratação, não tráfego real de rede.
- CLI `cloudcartridge`, detecção dinâmica completa e Host privado ainda não foram implementados.
- Nenhuma configuração, playlist, ROM ou save real foi alterado ou usado nos testes.

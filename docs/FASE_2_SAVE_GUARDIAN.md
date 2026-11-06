# Fase 2 — Save Guardian

## Estado deste marco

Primeiro lote integrado, exclusivamente validado com saves fictícios em diretórios temporários.

## Integrado

- Manifesto por chave estável de save, com hash-base, geração, caminhos local/remoto e confirmação UTC.
- Decisão de sincronização em três vias por SHA-256; timestamps servem apenas para auditoria.
- Upload e download versionados, com cópia anterior preservada antes de promover conteúdo novo.
- Conflito bilateral preserva os dois lados e não promove nenhum automaticamente.
- Histórico configurável, com cinco versões por padrão.
- Ausência inesperada após sincronização vira revisão manual, nunca criação/sobrescrita automática.
- Leitura em camadas das opções efetivas de save do RetroArch.
- `save doctor` procura candidatos em diretórios atuais e antigos e reporta `found_legacy_save`/`path_changed`.
- `save reconcile` é prévia por padrão e só aplica com `--yes`.
- Lock exclusivo por chave de save, com token de proprietário e recuperação automática quando o PID morreu.
- Detecção de Cloud Sync nativo do RetroArch; a reconciliação é bloqueada quando os dois motores de save estão ativos.
- Fila offline própria para saves, persistente e deduplicada, que mantém jobs pendentes quando o remoto está indisponível.
- CLI `save queue`, `save jobs` e `save sync`; processamento permanece em prévia até `--yes`.

## Evidência

- Relógios local/remoto deliberadamente invertidos não alteram a decisão baseada em hash.
- Duas edições independentes geram conflito e duas cópias preservadas; os arquivos originais permanecem intactos.
- Mudança simulada de `savefile_directory` encontra o save no caminho antigo sem declará-lo perdido.
- A suíte completa está em **25 testes aprovados, 0 falhas**.
- Tentativa de dupla sincronização foi bloqueada antes de qualquer gravação; o fluxo permitido liberou o lock ao terminar.
- Um save modificado offline permaneceu na fila e foi sincronizado corretamente quando o destino voltou, sem duplicar o job.

## Limites ainda abertos

- Resolver overrides por core, diretório e jogo a partir da árvore completa do RetroArch.
- Detectar mudança de nome/versão de core, região/serial e incompatibilidade de formato por adaptador.
- Adicionar restauração explícita por versão.
- Nenhum save real foi lido, copiado ou modificado.

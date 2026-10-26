# Orientações para agentes de código — CloudCartridge

## Fonte principal da evolução
Leia integralmente `CloudCartridge_vNext_PLANO_MESTRE_CODEX.md` antes de planejar ou modificar o projeto. Esse arquivo documenta os requisitos aprovados para a evolução vNext; as funcionalidades propostas **não devem ser presumidas implementadas**.

## Sequência obrigatória
1. Inspecione o código atual, as configurações e o histórico do repositório; confronte a implementação com o plano.
2. Informe o que já funciona, o que é parcial e o que ainda falta. Identifique riscos e dependências externas antes de iniciar alterações.
3. Trabalhe em fases pequenas, com testes reproduzíveis, commits claros e relatório de progresso.
4. Faça dry-run e backup antes de alterar configurações de emuladores, playlists, arquivos de cache e **qualquer save**.
5. Nunca acesse ou modifique saves reais sem autorização explícita. Preserve os arquivos existentes e detecte mudanças de caminho/nome/formato após atualização do RetroArch.
6. Integre o organizador de playlists existente somente após localizar e examinar o código-fonte original, sem presumir sua localização.
7. Quando serviços, dispositivos ou credenciais não estiverem disponíveis, use mocks ou testes locais e registre o que ficou sem validação real.

## Restrições de produto
- **Sem interface gráfica, launcher próprio ou dashboard web.** Operação autônoma e silenciosa; status e configuração somente pelo terminal.
- Preserve a arquitetura já funcional de download sob demanda e cache; os 3 dias de retenção são valor padrão **configurável**, para otimização de espaço, não DRM.
- Detecte emuladores instalados, núcleos e configurações de forma conservadora. Emuladores ausentes devem ser instalados manualmente pelo usuário; novas instalações são integradas por varredura posterior.
- No modo privado, o Host mantém exclusivamente as credenciais do Google Drive. O Client não deve receber credenciais ou links permanentes, e os até cinco convidados autorizados têm saves independentes.
- Proteja saves com autenticação, identificação estável, detecção de conflitos, backups e históricos; um código curto de perfil não é segredo de autenticação.
- Downloads de ROMs, ISOs e CHDs apenas quando a distribuição e utilização forem autorizadas.
- Não faça push com `--force` como mecanismo automático de correção; não inclua segredos em repositório, logs ou exemplos.
- Preserve escolhas locais de núcleos, shaders, áudio, controles, overlays, perfis e thumbnails personalizadas.

## Quando receber um pedido para iniciar a atualização
Comece por uma auditoria e apresente um plano incremental de implementação com testes de regressão. Não prometa que a implementação completa está concluída apenas por existir o documento de planejamento.

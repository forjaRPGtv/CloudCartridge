# Fase 4 — Host privado

## Primeiro lote: domínio de segurança

- Máximo de cinco convidados ativos; perfis revogados liberam vaga sem apagar saves.
- `profile_code` público com oito caracteres, UUID imutável e nome apenas de apresentação.
- Recovery key aleatória de 256 bits, persistida somente como PBKDF2-SHA256 com salt e 200 mil iterações.
- Token de dispositivo aleatório de 256 bits, persistido somente como SHA-256.
- Recuperação exige `profile_code + recovery_key`; o código curto sozinho nunca autentica.
- Cada perfil recebe árvore privada por UUID para RetroArch, standalone, MiSTer e versões.
- Resolução de caminhos exige credencial válida e rejeita traversal para outro perfil.
- Revogação invalida dispositivos e preserva integralmente a pasta de saves.
- Convites individuais expiram, reservam uma das cinco vagas, armazenam somente hash do token e são de uso único.
- Credenciais do cliente usam DPAPI `CurrentUser`; se o perfil criptográfico não estiver carregado, a gravação aborta sem fallback em texto puro.
- Onboarding por convite mantém o dispositivo inativo até a recovery key ser repetida corretamente.
- API exige perfil + bearer válido, timestamp recente e nonce não reutilizado; aplica rate limit por endereço.
- Audit log registra rota/status sem token, recovery key ou nonce.
- Listener TCP/HTTP usa loopback por padrão; LAN/Tailscale exige `-AllowLan`, enquanto wildcard e IP público são recusados.
- `Iniciar_Host.cmd` oferece inicialização em um clique após existir banco configurado.
- CLI administrativo: `host monitor`, `host users list|invite|revoke`; convite/revogação são prévia até `--yes`.

## Evidência

A suíte completa está em **38 testes aprovados, 0 falhas**. Além do isolamento, os testes comprovam confirmação obrigatória da recovery key, 401 sem credencial, bloqueio de replay, rate limit, token A recusado para B, log redigido e resposta real do listener loopback.

O runner automatizado não possui perfil DPAPI interativo carregado; nesse contexto a implementação foi confirmada como *fail-closed*, sem criar arquivo parcial. O roundtrip do contrato de proteção foi validado com provedor injetado de fixture. A validação DPAPI real permanece pendente em sessão Windows interativa.

## Próximos pontos

- Smoke DPAPI real em sessão Windows interativa.
- TLS de aplicação ou VPN obrigatória documentada para tráfego fora de loopback; bearer em HTTP puro não deve cruzar rede não confiável.
- Teste físico entre dois PCs na LAN e documentação opcional para Tailscale/WireGuard.
- Monitor TUI contínuo de eventos/downloads, além do snapshot atual do CLI.

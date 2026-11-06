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

## Evidência

A suíte completa está em **35 testes aprovados, 0 falhas**. O teste do Host comprova: convidado 6 negado, segredos ausentes do banco em texto puro, token A recusado no perfil B, traversal bloqueado, recovery incorreto negado, novo dispositivo recuperado e saves preservados após revogação.

## Próximos pontos

- Convites com expiração/uso único e confirmação explícita da recovery key.
- Armazenamento local do cliente via DPAPI/Credential Manager.
- Gateway LAN autenticado, sem bind público por padrão.
- Rate limiting, anti-replay, auditoria redigida e monitor TUI.
- Teste de rede LAN e documentação opcional para Tailscale/WireGuard.

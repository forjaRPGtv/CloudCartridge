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

## Evidência

A suíte completa está em **36 testes aprovados, 0 falhas**. Além do isolamento, os testes comprovam convite sem token negado, uso único, token ausente do banco em texto puro e limite de cinco convites pendentes.

O runner automatizado não possui perfil DPAPI interativo carregado; nesse contexto a implementação foi confirmada como *fail-closed*, sem criar arquivo parcial. O roundtrip do contrato de proteção foi validado com provedor injetado de fixture. A validação DPAPI real permanece pendente em sessão Windows interativa.

## Próximos pontos

- Confirmação interativa obrigatória da recovery key no onboarding.
- Smoke DPAPI real em sessão Windows interativa.
- Gateway LAN autenticado, sem bind público por padrão.
- Rate limiting, anti-replay, auditoria redigida e monitor TUI.
- Teste de rede LAN e documentação opcional para Tailscale/WireGuard.

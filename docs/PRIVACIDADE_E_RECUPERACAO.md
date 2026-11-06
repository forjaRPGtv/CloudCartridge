# Privacidade, credenciais e recuperação

## Dados tratados

O cliente mantém configuração de caminhos, catálogo/cache e metadados de sincronização. O Host mantém nome exibido, código de perfil, identificadores, hashes de tokens, verificador de recuperação, convites e auditoria redigida. Saves ficam em arquivos isolados por perfil, não dentro do banco administrativo.

O jogo atual só deve ser enviado como telemetria opcional e conhecida pelo convidado. Sem consentimento, o painel deve mostrar apenas o estado necessário à operação, nunca inferir aplicativos em execução.

## Segredos

- Device token e recovery key são segredos; não entram em logs, prints, prompts, ZIPs ou Git.
- O servidor armazena hashes/verificadores, não o segredo recuperável.
- A credencial local usa proteção do perfil Windows quando disponível; a validação automatizada usa provider injetado e não prova DPAPI interativo.
- Clientes não recebem credenciais nem localizadores privados do Google Drive.

## Recuperação

A recovery key deve ser confirmada no cadastro e guardada fora do PC. Com código + recovery key válida, o Host pode emitir credencial para novo dispositivo. Apenas o código de oito caracteres não concede acesso. Sem recovery key e sem outro dispositivo autenticado, não há recuperação prometida.

Conflitos de saves nunca são resolvidos pelo relógio local. Hash, geração e ancestralidade determinam o estado; duas alterações offline são preservadas até decisão explícita. Uma restauração deve ser feita primeiro para caminho separado.

## Revogação e retenção

Revogar um perfil bloqueia novos acessos e não apaga saves automaticamente. Exclusão de dados exige ação administrativa separada e backup apropriado. Logs devem ser mínimos, redigidos e mantidos somente pelo período operacional necessário.


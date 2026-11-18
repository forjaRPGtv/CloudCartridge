# Política de segurança

## Versões suportadas

O branch `main` recebe correções de segurança. Como ainda não existem releases semânticos públicos, snapshots e forks antigos podem não conter as proteções atuais.

## Relatar uma vulnerabilidade

Use **Security > Report a vulnerability** no repositório do GitHub para enviar um relato privado. Não publique tokens, recovery keys, saves, caminhos privados ou detalhes exploráveis em uma issue pública.

Inclua, quando possível:

- componente e commit afetados;
- impacto e pré-condições;
- passos mínimos de reprodução usando dados sintéticos;
- correção ou mitigação sugerida.

## Escopo prioritário

- acesso indevido a saves de outro perfil;
- vazamento de credenciais, tokens ou recovery keys;
- traversal ou acesso fora das raízes gerenciadas;
- execução de comandos não autorizados;
- sobrescrita ou exclusão silenciosa de saves;
- exposição pública involuntária do Host.

Não envie ROMs, BIOS, firmwares, saves reais ou credenciais como prova. O mantenedor confirmará o recebimento e coordenará a correção antes da divulgação.

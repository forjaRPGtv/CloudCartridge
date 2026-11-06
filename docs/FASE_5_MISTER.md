# Fase 5 — MiSTer FPGA

## Integrado

- `MisterAdapter` separado do cliente PC e do Host.
- Somente hosts explicitamente autorizados podem ser consultados.
- Estado offline é normal e nunca bloqueia cache, jogos ou saves do PC.
- Compatibilidade depende simultaneamente da regra de sistema, formato e core realmente informado como instalado.
- Plataformas PC-only (GameCube, Wii, Wii U, PS2 e PS3) são recusadas explicitamente.
- PSX aceita CHD/BIN+CUE/M3U apenas com core PSX e planeja pasta individual por jogo.
- Transferência é prévia por padrão e exige ação de transporte explícita para aplicar.
- CLI: `mister compatibility` e `mister plan`.

## Evidência

A suíte completa está em **39 testes aprovados, 0 falhas**. A fixture comprova autorização de host, estado offline isolado, recusa de Wii U, aceitação condicionada de PSX/CHD, pasta individual e igualdade SHA-256 após transferência simulada.

## Limites reais

- Nenhum MiSTer físico estava disponível; descoberta de cores, espaço e transporte SFTP/SMB ainda não têm validação em hardware.
- Saves/cartões de PSX não foram declarados intercambiáveis com RetroArch sem adaptador e teste real.
- A matriz é conservadora e deve ser ampliada somente após observar os cores instalados no dispositivo do usuário.

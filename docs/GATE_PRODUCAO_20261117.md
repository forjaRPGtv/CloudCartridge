# Gate de produção — 2026-11-17

## Aprovado

- Configuração real criada com Google Drive streaming, biblioteca em `Z:` e RetroArch detectado.
- `doctor --json`: `status: ok`, 45/45 cores e 6/6 mapeamentos standalone.
- RetroArch fechado durante a intervenção; savefiles e savestates apontam para `Z:\_ISOS_ROMS_\_RA_SAVES`.
- DPAPI `CurrentUser`: round-trip aprovado e segredos ausentes do texto persistido.
- Save Guardian real: `upload_new`, `in_sync`, `upload_versioned`, hashes iguais e uma versão anterior preservada.
- Artefatos sintéticos de DPAPI e save removidos após o gate.
- Menu do Explorer aponta para a telemetria atual do CloudCartridge; comando legado de liberação incompatível removido.
- Regressão integral: 45 aprovados, 0 falhas.

## Backup e reversão

- Backup externo da configuração do RetroArch em `RetroArch-Tools/backups/CloudCartridge-production-20261117-195445/`.
- Backup ao lado do executável: `retroarch.cfg.before-cloudcartridge-20261117-195445.bak`.
- Backups dos verbos antigos do Explorer na subpasta `context-menu` do backup externo.

## Limite comprovado do Google Drive streaming

O volume `G:` observado é virtual e o arquivo testado não apresentou atributos de placeholder NTFS/CFAPI. `attrib +u -p` retornou zero, mas não mudou o estado do arquivo. O CloudCartridge agora exige confirmação do estado Files On-Demand antes de marcar `cloud_only` e removeu do Explorer a ação que prometia liberação sem prova.

O Google Drive para Desktop administra automaticamente o cache de arquivos em streaming. Uma retenção física exata de três dias não pode ser afirmada por esta integração enquanto o Google não fornecer uma interface suportada de expulsão de cache no Windows.

Na máquina de produção, o log do Drive para Desktop informou aproximadamente 8.958 MiB usados no cache sob o perfil do usuário no SSD `C:` e capacidade dinâmica de aproximadamente 105.938 MiB. A pasta `Z:\_GOOGLE_DRIVE_CACHE` foi criada com mais de 1,3 TiB livre para receber o cache. Falta confirmar a mudança na interface oficial: **Preferências > Configurações avançadas > Diretório local dos arquivos em cache**. A tentativa de abrir essa janela por automação expirou sem alterar a configuração.

Referências oficiais:

- [Google Drive para Desktop — cache de conteúdo em streaming](https://support.google.com/drive/answer/13470231)
- [Microsoft — estados Files On-Demand e atributos pin/unpin](https://learn.microsoft.com/en-us/onedrive/files-on-demand-windows)

## Gates que exigem equipamento externo

- Host/Client em dois PCs por LAN ou VPN privada.
- Transferência, estrutura PSX/CHD e save em MiSTer físico.

Esses dois gates não bloqueiam o uso local do CloudCartridge e permanecem desativados/não homologados até que o equipamento esteja disponível.

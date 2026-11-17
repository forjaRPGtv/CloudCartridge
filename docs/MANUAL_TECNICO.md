# Manual técnico

## Componentes

- `CloudCartridge.Core.psm1`: configuração, cache, fila e escrita JSON atômica.
- `CloudCartridge.SaveGuardian.psm1`: identidade de save, manifesto três-vias, versões, conflitos, locks e fila offline.
- `CloudCartridge.Playlists.psm1`: inventário, catálogo, `.lpl`, `.m3u` e thumbnails.
- `CloudCartridge.Host.psm1` e `CloudCartridge.HostApi.psm1`: perfis, credenciais, recuperação, autorização e auditoria.
- `CloudCartridge.HostServer.ps1`: gateway HTTP privado; loopback é o padrão.
- `CloudCartridge.Mister.psm1`: compatibilidade e planos isolados de transferência.

## Operação

Comece por `CloudCartridge.cmd doctor --json` e `detect --refresh --json`. Comandos mutáveis oferecem prévia; `--yes` ou `-Apply` deve ser explícito. Feche o RetroArch antes de alterar `.lpl`, configuração ou diretórios de ROMs.

O Host deve permanecer em loopback durante diagnóstico. `-AllowLan` só aceita IP privado explícito; wildcard/endereço público é negado. Use VPN privada para redes distintas e não exponha a porta na Internet.

## Configuração e atualização

`Setup_CloudROM.ps1` mescla apenas chaves conhecidas, valida o resultado e grava atomicamente. Se `config.json` existir, cria backup em `backups/config` antes de aplicar. O empacotador nunca distribui esse arquivo.

## Qualidade

Execute `Testar_CloudCartridge.cmd`. A suíte cobre fixtures de cache/download, saves, playlists/catálogo, Host/gateway e MiSTer. Sucesso de fixture não substitui DPAPI interativo, armazenamento real, dois PCs ou hardware MiSTer. Google Drive streaming no Windows pode usar volume virtual e cache próprio; não interprete `attrib` com saída zero como liberação sem confirmar atributos Files On-Demand/CFAPI.

Para empacotar:

```powershell
.\Criar_Pacote.ps1
.\Criar_Pacote.ps1 -Apply
```

O primeiro comando é somente prévia. O segundo cria ZIP e `MANIFEST-SHA256.txt` sem dados locais.


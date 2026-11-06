# CloudCartridge

Cliente PowerShell para organizar uma biblioteca de emulação mantida pelo Google Drive para Desktop, com cache local controlado, playlists do RetroArch, proteção de saves, Host privado para até cinco convidados e planejamento isolado de transferências para MiSTer.

O projeto funciona sem IA. A Agent Skill incluída serve apenas para manutenção assistida do repositório.

## Estado atual

Implementado e testado com fixtures isolados:

- CLI para diagnóstico, detecção conservadora, cache e fila de downloads com SHA-256;
- retenção configurável (`3`, `7`, `14`, `30` dias ou desativada), pin e proteção de cópias manuais;
- Save Guardian com manifesto de três vias, versões, conflitos, locks e fila offline;
- playlists incrementais/idempotentes, `.m3u`, catálogo persistente e thumbnails ausentes;
- Host privado autenticado, cinco vagas, convites de uso único, recuperação e isolamento de saves;
- listener loopback por padrão, proteção contra replay/rate limit e logs redigidos;
- adaptador MiSTer isolado com matriz de compatibilidade e verificação por hash;
- testes automatizados que não usam ROMs, saves ou credenciais pessoais.

Ainda exigem validação no ambiente real: hidratação/desidratação CFAPI do Google Drive, DPAPI no perfil Windows interativo, rede privada entre dois PCs e transferência/save em um MiSTer físico. O suporte a emuladores depende do executável/core realmente detectado; o CloudCartridge não os instala automaticamente.

## Requisitos

- Windows 10 ou 11;
- Windows PowerShell 5.1 ou PowerShell 7+;
- Google Drive para Desktop em modo de streaming, quando a biblioteca em nuvem for usada;
- RetroArch e/ou emuladores standalone instalados manualmente.

## Instalação segura

1. Feche o RetroArch.
2. Execute `Instalar_Configurar.cmd`.
3. Informe os caminhos solicitados.
4. Revise a prévia. Nada é gravado até digitar exatamente `APLICAR`.

O instalador cria backup de uma configuração existente antes de migrá-la, preserva destinos já existentes e só cria junções quando solicitado. Para orientação detalhada, consulte [Manual do iniciante](docs/MANUAL_INICIANTE.md).

## Uso rápido

```cmd
CloudCartridge.cmd status --json
CloudCartridge.cmd doctor --json
CloudCartridge.cmd detect --refresh --json
CloudCartridge.cmd host monitor --json
CloudCartridge.cmd host monitor --watch
Testar_CloudCartridge.cmd
```

Atalhos legados permanecem disponíveis para o launcher e a telemetria:

- `Jogar.cmd`
- `Abrir_RetroArch_com_Telemetria.cmd`
- `Ver_Telemetria_e_Downloads.cmd`
- `Monitorar_Host.cmd`

## Segurança e privacidade

O cliente usa caminhos locais fornecidos pelo usuário e não recebe credenciais do Google Drive. O Host possui credenciais próprias de dispositivo e recuperação, mas armazena somente hashes/verificadores; tokens e recovery keys não devem entrar em configuração, log ou Git. A recuperação sem a chave e sem outro dispositivo válido não é prometida.

O Host escuta apenas em loopback por padrão. Exposição em LAN é opt-in, aceita somente endereço privado e continua exigindo autenticação. Nunca publique o listener diretamente na Internet.

Leia [Privacidade e recuperação](docs/PRIVACIDADE_E_RECUPERACAO.md) e o [Manual técnico](docs/MANUAL_TECNICO.md).

## Empacotamento

`Criar_Pacote.ps1` mostra uma prévia por padrão. Use `-Apply` para gerar um ZIP sanitizado com manifesto SHA-256; `config.json`, bancos do Host, logs, backups, caches e segredos não são incluídos.

## Licença

Distribuído sob a licença [MIT](LICENSE). Desenvolvido por Arthur Reis.

# CloudCartridge

[![Testes](https://github.com/forjaRPGtv/CloudCartridge/actions/workflows/tests.yml/badge.svg)](https://github.com/forjaRPGtv/CloudCartridge/actions/workflows/tests.yml)
[![Documentação](https://img.shields.io/badge/docs-GitHub%20Pages-0969da)](https://forjarpgtv.github.io/CloudCartridge/)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?logo=windows&logoColor=white)](https://www.microsoft.com/windows/)
[![Licença MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-green.svg)](LICENSE)

**Automação cloud-first para bibliotecas de emulação no Windows.** O CloudCartridge integra Google Drive para Desktop, RetroArch e emuladores standalone, mantendo downloads sob demanda, cache controlado, playlists e saves protegidos — sem substituir o emulador e sem exigir IA para funcionar.

> [Documentação completa](https://forjarpgtv.github.io/CloudCartridge/) · [Manual do iniciante](docs/MANUAL_INICIANTE.md) · [Manual técnico](docs/MANUAL_TECNICO.md) · [Privacidade e recuperação](docs/PRIVACIDADE_E_RECUPERACAO.md)

## O que o projeto resolve

| Área | Entrega |
|---|---|
| Biblioteca em nuvem | Integra arquivos transmitidos pelo Google Drive para Desktop sem baixar a coleção inteira antecipadamente. |
| Cache local | Retenção configurável, jogos fixados e limpeza restrita ao cache gerenciado. |
| Saves | Save Guardian com hashes de três vias, versões, conflitos, locks, fila offline e restauração segura. |
| RetroArch | Detecção conservadora de cores, playlists idempotentes, multidisco e thumbnails ausentes. |
| Emuladores standalone | Mapeamentos detectados sem instalação automática ou alteração silenciosa. |
| Host privado | Até cinco convidados, convites de uso único, autenticação e saves isolados por perfil. |
| MiSTer | Adaptador isolado, matriz de compatibilidade e transferência explícita com SHA-256. |
| Automação | CLI com JSON, dry-run, diagnóstico e testes que usam somente fixtures temporárias. |

## Estado atual

O fluxo local de produção está operacional e a regressão automatizada possui **45 testes aprovados**. Foram validados no ambiente Windows real:

- Google Drive para Desktop em modo de streaming e cache no disco de dados;
- RetroArch com 45/45 cores detectados e seis mapeamentos standalone;
- DPAPI no perfil interativo do Windows;
- round-trip de save sintético, versionamento e preservação de conflito;
- pacote de distribuição sanitizado, sem configuração, credenciais, logs, backups ou cache.

Os seguintes gates exigem equipamento externo e não são apresentados como homologados: comunicação Host/Client entre dois PCs físicos e transferência/save em um MiSTer físico.

### Limite conhecido do Google Drive

O Drive para Desktop usa um volume virtual e administra o cache físico dos arquivos transmitidos. No ambiente validado, ele não expõe estado Windows Files On-Demand/CFAPI suficiente para o CloudCartridge garantir uma expulsão física exatamente após três dias. O projeto só marca uma liberação como concluída quando existe evidência verificável do provedor.

## Requisitos

- Windows 10 ou 11;
- Windows PowerShell 5.1 ou PowerShell 7+;
- Google Drive para Desktop em modo de streaming, quando houver biblioteca em nuvem;
- RetroArch e/ou emuladores standalone instalados manualmente;
- conteúdo próprio ou cuja utilização e distribuição sejam autorizadas.

O repositório **não inclui ROMs, BIOS, firmwares, credenciais ou saves**.

## Instalação segura

1. Baixe o código pelo botão **Code > Download ZIP** ou clone o repositório:

   ```powershell
   git clone https://github.com/forjaRPGtv/CloudCartridge.git
   cd CloudCartridge
   ```

2. Feche o RetroArch.
3. Execute `Instalar_Configurar.cmd`.
4. Informe os caminhos solicitados e revise a prévia.
5. Digite exatamente `APLICAR` somente quando a prévia estiver correta.
6. Valide a instalação:

   ```cmd
   CloudCartridge.cmd doctor --json
   Testar_CloudCartridge.cmd
   ```

O instalador cria backup antes de migrar uma configuração existente e preserva destinos já encontrados. Consulte o [manual do iniciante](docs/MANUAL_INICIANTE.md) antes da primeira configuração.

## Uso rápido

```cmd
CloudCartridge.cmd status --json
CloudCartridge.cmd doctor --json
CloudCartridge.cmd detect --refresh --json
CloudCartridge.cmd host monitor --json
CloudCartridge.cmd host monitor --watch
Testar_CloudCartridge.cmd
```

Atalhos de compatibilidade:

- `Jogar.cmd` — busca e inicia jogos pelo fluxo legado;
- `Abrir_RetroArch_com_Telemetria.cmd` — abre o RetroArch com telemetria;
- `Ver_Telemetria_e_Downloads.cmd` — acompanha cache e transferências;
- `Monitorar_Host.cmd` — abre o monitor do Host privado.

## Segurança por padrão

- o Host escuta somente em loopback por padrão;
- exposição em LAN é opt-in e continua exigindo autenticação;
- recovery keys e tokens nunca devem entrar em configuração, log ou Git;
- saves divergentes não são sobrescritos automaticamente;
- limpeza não pode tocar saves, fontes na nuvem, jogos ativos ou cópias manuais;
- o projeto não instala emuladores, cores, BIOS ou jogos automaticamente;
- o listener não deve ser publicado diretamente na Internet.

Leia a política de [privacidade e recuperação](docs/PRIVACIDADE_E_RECUPERACAO.md) e, para relatar uma vulnerabilidade, siga [SECURITY.md](SECURITY.md).

## Documentação

| Documento | Conteúdo |
|---|---|
| [Portal de documentação](docs/index.md) | Visão geral e rotas de leitura. |
| [Manual do iniciante](docs/MANUAL_INICIANTE.md) | Instalação, primeiros comandos e recuperação. |
| [Manual técnico](docs/MANUAL_TECNICO.md) | Arquitetura, módulos, operação e diagnóstico. |
| [Privacidade e recuperação](docs/PRIVACIDADE_E_RECUPERACAO.md) | Credenciais, isolamento e Save Guardian. |
| [Gate de produção](docs/GATE_PRODUCAO_20261117.md) | Evidências reais e limites conhecidos. |
| [Plano mestre](CloudCartridge_vNext_PLANO_MESTRE_CODEX.md) | Especificação original e critérios de aceitação. |
| [Changelog](CHANGELOG.md) | Evolução publicada do projeto. |

## Desenvolvimento

Execute a suíte completa em Windows:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

Os testes criam fixtures em diretório temporário e não devem usar ROMs, saves ou credenciais reais. Pull requests precisam manter a suíte verde, preservar os guardrails e seguir o [guia de contribuição](CONTRIBUTING.md).

## Empacotamento

`Criar_Pacote.ps1` opera em prévia por padrão. Para gerar um ZIP sanitizado com manifesto SHA-256:

```powershell
.\Criar_Pacote.ps1 -Apply
```

Dados de runtime, configurações pessoais, bancos do Host, backups, logs, caches, credenciais e ZIPs aninhados são excluídos.

## Licença

Distribuído sob a [licença MIT](LICENSE). Desenvolvido por Arthur Reis.

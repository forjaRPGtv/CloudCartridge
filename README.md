# 🎮 CloudCartridge: Emulação Inteligente na Nuvem via Google Drive

[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-blue.svg)](https://microsoft.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![RetroArch](https://img.shields.io/badge/RetroArch-Compatible-brightgreen.svg)](https://www.retroarch.com)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-blue.svg)](https://microsoft.com/powershell)

> **Jogue centenas de gigabytes de jogos retrô diretamente da nuvem sem lotar o seu SSD local.**  
> O **CloudCartridge** utiliza o streaming nativo do Google Drive para Desktop e Junções NTFS no Windows com download sob demanda, painel de telemetria em tempo real, retenção inteligente de 3 dias no PC, pré-carregamento multi-disco e sincronização automática de saves na nuvem (*Cloud Save Sync*).

---

## ✨ Principais Funcionalidades

- ☁️ **0 Bytes Físicos no SSD:** Todos os seus jogos ficam guardados na sua conta do Google Drive e aparecem nas pastas do Windows como arquivos virtuais transparentes.
- ⚡ **Download Sob Demanda com Telemetria Visual:** Ao iniciar um jogo que ainda não foi baixado, uma janela de telemetria abre com barra de progresso em tempo real, velocidade instantânea em **MB/s** e tempo estimado (**ETA**).
- 🕒 **Política Inteligente de Retenção de 3 Dias:** O jogo baixado fica no seu PC por **3 dias** para você jogar sem gastar internet. Passado esse período, o espaço no SSD é liberado automaticamente (`attrib +u -p`), mantendo o jogo seguro na nuvem e visível na pasta.
- ⭐ **Modo Campanha (*Pin / Never Purge*):** Fixe seus jogos favoritos ou em campanha ativa para que nunca sejam apagados do PC até você desmarcar.
- 💾 **Cloud Save Sync:** Ao fechar a partida, seus saves e savestates são enviados automaticamente para a nuvem no Google Drive.
- 💿 **Multi-Disc Pre-fetch:** Ao baixar o Disco 1 de um jogo longo (PS1, PS2, GameCube), o sistema detecta e pré-baixa os discos adicionais em segundo plano.
- 🖱️ **Menu de Contexto no Windows Explorer:** Clique com o botão direito em qualquer ROM para jogar diretamente ou liberar espaço em 1 clique.
- 🕹️ **Compatibilidade Multi-Emulador:** Suporte completo para **RetroArch** (46 plataformas) e emuladores standalone de alta performance (**PCSX2**, **Dolphin**, **Cemu**, **Citra**, **RPCS3**, **DuckStation**).

---

## 📋 Requisitos do Sistema

1. **Windows 10 ou Windows 11** (x64).
2. **[Google Drive para Desktop](https://www.google.com/drive/download/)** instalado e conectado à sua conta Google em modo **"Fazer streaming de arquivos"** (*Stream files*).
3. **[RetroArch](https://www.retroarch.com/)** ou qualquer emulador standalone instalado.

---

## 🚀 Como Instalar e Usar (3 Passos Simples)

### Passo 1: Baixar o Repositório
Baixe o arquivo ZIP deste repositório ou clone usando o Git:
```bash
git clone https://github.com/forjaRPGtv/CloudCartridge.git
```

### Passo 2: Executar o Assistente de Configuração
Dê dois cliques no arquivo:
```cmd
Instalar_Configurar.cmd
```
O assistente interativo guiará você:
1. Informe onde fica sua pasta de jogos no Google Drive (exemplo: `G:\Meu Drive\_ISOS_ROMS_`).
2. Escolha onde suas pastas virtuais serão criadas no PC (exemplo: `Z:\_ISOS_ROMS_` ou `C:\Games\ROMs`).
3. O script criará automaticamente as **Junções NTFS** de todos os consoles com **zero bytes de consumo de disco**.
4. (Opcional) Escolha se deseja registrar os atalhos no botão direito do mouse.

### Passo 3: Jogar!
Escolha como prefere iniciar seus jogos:
- **Pelo Launcher Interativo:** Dê dois cliques em `Jogar.cmd` (permite busca global por nome em todos os consoles ao mesmo tempo).
- **Pelo RetroArch com Telemetria Ativa:** Dê dois cliques em `Abrir_RetroArch_com_Telemetria.cmd`.
- **Direto pelo Windows Explorer:** Clique com o botão direito em qualquer ROM e escolha **"Jogar com CloudCartridge Telemetria"**.

---

## 📊 Terminal de Telemetria e Dashboard de Prazos

Dê dois cliques em `Ver_Telemetria_e_Downloads.cmd` para abrir a qualquer hora o painel de status do seu PC:

```text
==========================================================================================
                    TELEMETRIA CLOUDCARTRIDGE - DOWNLOAD EM TEMPO REAL                    
==========================================================================================
 [PAINEL 1] ARQUIVO EM TRANSFERÊNCIA
 -----------------------------------------------------------------------------------------
 Plataforma : Sony - PlayStation
 Arquivo    : Crash Bash (USA).chd
 Tamanho    : 58.3 MB
 Origem     : Google Drive (Nuvem)
 -----------------------------------------------------------------------------------------
 Progresso  : [██████████████████████░░░░░░░░░░░░░░] 61.4%
 Baixado    : 35.8 MB de 58.3 MB
 Velocidade : 22.4 MB/s
 Tempo      : 1.6s decorridos | ETA restante: 1s

==========================================================================================
 [PAINEL 2] JOGOS INSTALADOS NO PC & CONTAGEM REGRESSIVA (RETENÇÃO: 3 DIAS)             
==========================================================================================
 • [Sony - PlayStation] Legend of Legaia (USA) (420.0 MB)
   -> Jogado em: 25/10 18:10 | Falta para sair: 2 dia(s), 23 h e 48 min
 • [Nintendo - Game Boy] Zuigao Jimi (0.02 MB)
   -> Jogado em: 25/10 17:58 | Falta para sair: 2 dia(s), 23 h e 36 min
------------------------------------------------------------------------------------------
 Total em disco: 420.02 MB em 2 jogo(s) instalados.
 *Ao zerar o tempo, o espaço é liberado sem apagar nada da nuvem nem perder seus saves.
==========================================================================================
```

---

## 🛠️ Estrutura de Arquivos

| Arquivo / Script | Função |
| :--- | :--- |
| `Instalar_Configurar.cmd` | Assistente inicial One-Click para configurar caminhos e junções. |
| `Jogar.cmd` | Launcher principal com pesquisa rápida e seleção de consoles. |
| `Abrir_RetroArch_com_Telemetria.cmd` | Executa o RetroArch com o Guardião de background ativo. |
| `Ver_Telemetria_e_Downloads.cmd` | Abre o dashboard com jogos instalados e contadores de tempo. |
| `Instalar_Menu_Contexto.cmd` | Adiciona as opções de botão direito no Windows Explorer. |
| `CloudROM_Launcher.ps1` | Motor principal de navegação, purga de 3 dias e execução. |
| `CloudROM_Telemetry.ps1` | Painel gráfico em terminal com medição de MB/s e ETA. |
| `CloudROM_Watcher.ps1` | Monitor de I/O de background para capturar aberturas pelo RetroArch. |
| `core_mapping.json` | Mapeamento automático de Cores do RetroArch para 46 sistemas. |
| `standalone_emulators.template.json` | Configuração de emuladores dedicados (Dolphin, PCSX2, etc.). |

---

## 🔒 Segurança e Privacidade

- **Zero Credenciais:** O CloudCartridge **não** possui, não solicita e não armazena nenhuma senha ou token de autenticação.
- **Isolamento de Nuvem:** Toda a comunicação segura é realizada pelo aplicativo oficial do Google Drive para Desktop com criptografia TLS 1.3.
- **Proteção dos seus Jogos:** A liberação de espaço nunca deleta arquivos da nuvem; ela apenas descarta o cache temporário do Windows.

---

## 📄 Licença

Distribuído sob a licença **MIT**. Consulte o arquivo [LICENSE](LICENSE) para obter mais informações.

Desenvolvido por **Arthur Reis**.

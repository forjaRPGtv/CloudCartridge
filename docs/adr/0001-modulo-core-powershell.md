# ADR 0001 — Núcleo compartilhado em PowerShell

- Status: aceito
- Data: 2026-11-06
- Contexto: Fase 1 da evolução vNext

## Contexto

Launcher, telemetria e watcher duplicavam leitura de configuração, escrita do registro e sincronização de saves. As cópias divergiam e continham caminhos absolutos. Uma reescrita de stack agora aumentaria o risco sobre cache e saves sem baseline de testes.

## Decisão

Manter os conectores PowerShell compatíveis e extrair invariantes para `CloudCartridge.Core.psm1`:

- configuração centralizada e validada;
- validação de caminhos dentro de raízes gerenciadas;
- escrita JSON por arquivo temporário e troca final;
- cópia de saves com SHA-256 e preservação da versão anterior.

O módulo não acessa ROMs ou saves por conta própria. Chamadores fornecem caminhos explícitos. Testes usam somente diretórios temporários.

## Consequências

- Corrige divergências sem recomeçar o projeto.
- Permite caracterização e evolução incremental da CLI.
- PowerShell 5.1 continua sendo a baseline nesta fase.
- Save Guardian completo, merge de três vias e Host autenticado continuam em fases posteriores.

## Alternativas rejeitadas agora

- Reescrever imediatamente em outra linguagem: sem benchmark ou testes suficientes.
- Manter funções duplicadas: perpetua correções inconsistentes.
- Sincronizar saves por `Copy-Item -Force`: pode destruir uma versão divergente.

# CloudCartridge vNext — Plano mestre para execução pelo Codex

> **Data do planejamento:** 26/10/2026  
> **Status:** especificação de engenharia para atualizar o projeto existente; **não é documentação de funcionalidades já implementadas**.  
> **Repositório-base:** https://github.com/forjaRPGtv/CloudCartridge  
> **Branch-base consultada:** `main`, commit `9da1e329ae810be323c091e7edec536e1ddd246f` (verificar HEAD novamente antes de trabalhar).  
> **Escopo imediato:** versão pessoal/privada, **1 administrador + até 5 convidados**, com Google Drive do administrador como origem dos arquivos e destino dos saves autorizados.  
> **Diretriz de produto:** aplicação **sem GUI, sem launcher próprio e sem dashboard web**; motor automático silencioso e painel **exclusivamente no terminal**, aberto apenas sob demanda.  
> **Pedido ao agente:** auditar o código atual, produzir plano de migração curto, implementar por fases verificáveis, testar regressões e preservar tudo que já funciona. Não executar mudanças irreversíveis sem backup e aprovação.

---

## 0. Resumo executivo para o Codex

O CloudCartridge **não é um emulador e não é um frontend**. É uma camada leve de automação que:

1. Detecta e integra emuladores/cores já instalados; nunca instala emuladores por conta própria.
2. Indexa a biblioteca de ROMs/imagens de disco hospedada na nuvem **sem baixá-la integralmente**.
3. Ao abrir um jogo, garante o download/hidratação do arquivo necessário, executa/entrega ao emulador e reutiliza o cache.
4. Controla até **3 downloads simultâneos por cliente** inicialmente, com prioridade para o jogo que o usuário quer executar; sem cota arbitrária diária de GB no uso normal.
5. Libera espaço de jogos temporários após **3 dias desde o último uso efetivo** (padrão), com opção por perfil de configurar mais dias, fixar jogos ou desativar a limpeza temporal.
6. Organiza playlists RetroArch, cores, configurações, thumbnails **somente ausentes** e integra um organizador local de RetroArch já desenvolvido pelo proprietário, após localizar e auditar seu código.
7. Protege rigorosamente saves e savestates, incluindo o caso histórico em que mudanças na configuração de reconhecimento/nomeação/localização do RetroArch tornaram saves existentes aparentemente ausentes.
8. Permite que **até 5 convidados autorizados** tenham perfis privados de saves no Google Drive do administrador, sem nunca receber acesso direto ou credenciais do Drive.
9. Exibe, no terminal do administrador, usuários, conexões, downloads, status dos jogos (quando o convidado optar por compartilhar essa telemetria), saves, cache e emuladores instalados/validados por PC.
10. Permite futura integração ao MiSTer FPGA (catálogo comum, CHD quando suportado, distribuição via rede); não presumir compatibilidade com núcleos de PC não existentes no MiSTer.
11. Publica uma **Agent Skill** para Codex e agentes compatíveis, sem que o CloudCartridge dependa de IA para funcionar.

**Princípio de bom senso:** permitir testar muitos jogos e conservar cópias que a pessoa voluntariamente faça. A retenção de 3 dias **é otimização do SSD, não DRM, não mecanismo antirroubo**. Proteger Google Drive/contas e saves é diferente de tentar impedir o usuário de copiar um jogo já recebido. Compartilhar exclusivamente conteúdo cuja distribuição seja autorizada.

---

## 1. Estado real do repositório existente

### Arquivos encontrados na baseline pública

- `CloudROM_Launcher.ps1`: busca, navegação, execução, registro, limpeza/retention, sync de saves;
- `CloudROM_Telemetry.ps1`: hidratação por leitura, terminal, registro do cache, monitoramento da sessão, rotina multidisco;
- `CloudROM_Watcher.ps1`: observa histórico do RetroArch e processos standalone;
- `Setup_CloudROM.ps1`: configura pastas, RetroArch e junções NTFS;
- `core_mapping.json`: **46 entradas** de sistema → core/caminho para a instalação de referência;
- `standalone_emulators.template.json`: modelos de execução para PCSX2, Dolphin, Cemu, RPCS3 e Citra;
- `config.template.json`, `setup_context_menu.ps1` e arquivos `.cmd` para inicialização;
- `README.md`, `.gitignore`, `LICENSE`.

### Funcionalidades existentes a preservar

- Google Drive para Desktop em modo streaming e junções NTFS;
- download/hidratação por uso no Windows;
- retenção inicial de 3 dias com registro e opção de fixar jogos;
- telemetria em terminal;
- integração com RetroArch e associações de sistemas;
- tentativa de sincronização dos saves e identificação multidisco;
- menu de contexto e atalhos de terminal (reconsiderar após introdução da CLI, mas preservar compatibilidade enquanto necessário).

### Riscos técnicos constatados — corrigir antes de ampliar

1. `CloudROM_Watcher.ps1` contém **caminhos absolutos**, como caminhos do RetroArch, ROMs e script de telemetria. Migrar para descoberta e configuração por instalação, com validação.
2. A telemetria calcula velocidade lendo o arquivo por completo; isso pode medir **cache local**, não necessariamente bytes realmente transferidos da internet. Separar métricas de hidratação/leitura e de rede.
3. `Sync-CloudSaves` procura saves por correspondência aproximada do nome e modificação recente (janela de 60 minutos), sem restauração/conflitos/manifestos confiáveis. **Não pode ser a autoridade de sincronização remota da nova versão.**
4. O pré-download multidisco é condicionado a `LaunchAfter`; o caminho de execução pelo launcher frequentemente usa `LaunchAfter:$false`. Corrigir acionamento e tornar prefetch opcional e de baixa prioridade.
5. Há flags de configuração como `enable_cloud_save_sync` e `enable_multi_disc_prefetch` que não são respeitadas uniformemente. Consolidar leitura, schema e testes.
6. `core_mapping.json` usa diretórios fixos, inclui um item `DETECT` para Wii U e possui labels de core inconsistentes com o caminho real em pelo menos um caso. Não assumir que um mapeamento significa um core instalado ou funcional.
7. `Publicar_no_GitHub.cmd` possui fallback de `git push --force`. **Remover fallback destrutivo**; instruir correção segura de divergência de branches.
8. O cliente atual **não tem** autenticação multiusuário, quotas de perfis no servidor ou gateway privado com acesso a saves por identidade.
9. Diretórios de saves/registro/cache devem ser segregados de diretórios compartilhados de jogos; aplicar controles de acesso.

**Procedimento inicial do Codex:** comparar a branch real com a baseline acima; gerar inventário de código, dependências, testes existentes e migrações necessárias; não presumir que tudo do README funciona de forma completa. Criar testes antes de alterar rotinas sensíveis.

---

## 2. Arquitetura proposta: Core / Host / Client / Adapters

```text
                      NUVEM DO ADMINISTRADOR
           Google Drive (origem privada de ROMs/CHD)
                          e Saves privados
                              ▲
                              │ acesso somente no Host
                              ▼
┌──────────────────────────────────────────────────────────────┐
│ CloudCartridge Host — máquina do proprietário               │
│ - Gateway/API privada e autenticada                         │
│ - Controle de até 5 perfis convidados                       │
│ - Catálogo SQLite/manifesto                                 │
│ - Entrega de arquivos sob demanda                           │
│ - Save Guardian + versões + locks                           │
│ - Eventos de download, sessões e telemetria                 │
│ - Painel ADMIN opcional em terminal                          │
└──────────────────────────────────────────────────────────────┘
                              ▲
                     rede privada segura
                              ▼
┌──────────────────────────────────────────────────────────────┐
│ CloudCartridge Client — PC de cada convidado                │
│ - Identidade local e credencial protegida                   │
│ - Detector/adapter RetroArch e standalone                   │
│ - Playlists, thumbnails e perfil de configuração            │
│ - Download/cache 3 dias por padrão, personalizável          │
│ - Save Guardian local + fila offline                        │
│ - CLI e logs; sem GUI / daemon pesado                       │
└──────────────────────────────────────────────────────────────┘
                    │                         │
             RetroArch + cores        Standalone / MiSTer

```

### Requisitos estruturais

- **Núcleo único de regras** para catálogo, downloads, políticas, saves e diagnóstico; separar adaptadores por nuvem, plataforma, emulador e SO.
- Host e Client **não precisam usar obrigatoriamente a mesma implementação de processo**. Reaproveitar a base PowerShell como compatibilidade/instalador enquanto se avalia um serviço leve e testável para autenticação, armazenamento e transmissão; justificar qualquer mudança de linguagem com medidas de memória/CPU e custo de manutenção.
- Operação em segundo plano por serviço leve/eventos ou agendamento; nenhum terminal permanentemente aberto é exigido no cliente.
- Janela do terminal **somente sob comando** do usuário (`status`, `monitor`, `doctor`, `config`).
- **Sem servidor web de apresentação**: API de comunicação privada é permitida; dashboard HTML/site não será desenvolvido.
- Comunicação de arquivos e saves com autenticação, autorização, reintentos idempotentes, cache, manifesto e logs estruturados.
- Na versão privada, usar Drive como origem, mantendo adaptadores para armazenamento S3/WebDAV/NAS **futuros**, sem obrigar a contratação agora.
- Host Windows com Drive para Desktop: nenhuma credencial/atalho montado será copiado ao cliente. Arquivos são servidos exclusivamente pelo Host após autorização de cada operação.
- A disponibilidade do Host é necessária para novos downloads remotos/sync; se ele estiver desligado, clientes continuam jogando seus conteúdos locais e enfileiram sincronizações.

### Rede e custo

- **Sem domínio nem mensalidade adicional obrigatória**: MVP na mesma LAN; para amigos em redes distintas, estudar Tailscale Personal (no momento documenta até 6 usuários no plano pessoal) ou WireGuard configurado com segurança; a opção deve ser abstraída, não hardcoded.
- Mesmo com VPN, aplicar **autorização de aplicativo por perfil**, não confiar somente na rede privada.
- Sem expor a API diretamente à internet; sem port-forward público por padrão.
- Considerar capacidade de upload do Host e impacto no desempenho local; oferecer limites de banda e horários opcionais.
- O administrador continua responsável pelo custo e limites operacionais do Drive; aplicar backoff em 429/403, cache de metadados e proteção de sobrecarga.

---

## 3. Identidade de usuário: administrador + 5 convidados

### Regras do cadastro

- **Máximo de 5 convidados ativos**, além da conta do administrador. É limite de **perfis autorizados a guardar saves**, NÃO limite de saves/jogos por pessoa e NÃO exigência de que todos estejam online.
- Cada convidado fornece um `display_name` livre (ex.: Israel), apenas para apresentação no terminal do dono.
- Cada convidado escolhe ou gera um **código de perfil de 8 caracteres** `[A-Z0-9]{8}` (ex.: `K7M4P9XA`). Garantir unicidade entre perfis e tratar comparação case-insensitive.
- **Importante:** código de 8 caracteres é um **ID de apresentação**, **não** um hash criptográfico completo e **não é senha/autorização**. Mesmo que se chame 'hash' no terminal para familiaridade, no modelo de dados usar `profile_code`.
- ID canônico interno será UUID aleatório imutável (`profile_id`). Nome/código são aliases; renomear não quebra a estrutura dos saves.
- Um convite individual aprovado pelo administrador vincula perfil, credencial e dispositivo inicial; copiar instalador não autoriza outro usuário.
- **Chave de recuperação** criptograficamente forte gerada na configuração, exibida uma vez, com confirmação pelo usuário. Pode autenticar restabelecimento da conta/dispositivo, mas nunca entrar em logs ou repositório.
- Armazenar credenciais locais protegidas (DPAPI/Credential Manager no Windows; armazenamento seguro equivalente no Linux), com permissões restritas. Servidor guarda apenas verificadores/segredos necessários de forma segura; permitir revogação e rotação.
- Em outro PC/reinstalação, `profile_code + recovery_key` iniciam fluxo de recuperação, com regras anti-replay, rate limit, nova credencial de dispositivo e auditoria. **Não permitir que o código sozinho recupere saves**.
- Se perder todas as credenciais e não houver outro método autorizado, **não prometer recuperação impossível**.

### Aviso obrigatório no terminal durante onboarding

```text
ATENÇÃO — GUARDE SUA CHAVE DE RECUPERAÇÃO
Este código secreto é necessário para recuperar o acesso
à sua pasta privada de saves ao reinstalar o CloudCartridge.
O código curto de 8 caracteres NÃO substitui a chave.
Salve a chave em um gerenciador de senhas ou local protegido.
Sem a chave e sem outro dispositivo autenticado, pode não
ser possível recuperar o perfil e seus saves.
Confirme sua cópia digitando a chave quando solicitado.
```

- Mostrar claramente a diferença entre código de perfil e chave de recuperação.
- Permitir `profile recovery-check` sem revelar a chave; redigir logs e backups.
- Usuários revogados: **não apagar saves automaticamente**; conservar dados segundo política definida pelo administrador e oferecer exportação/reativação.
- Slots ocupados por usuários desativados não precisam bloquear novos cadastros, desde que não ultrapasse **5 usuários ativos**. Auditar histórico do slot.

### Estrutura física sugerida

```text
CloudCartridgeData/
  library_manifest/              # catálogo lógico, sem jogos salvos aqui
  admin/
    users.sqlite                 # nomes, profile_code, UUID, slots, dispositivos
    audit/                        # logs com redação de segredos
  saves/
    <profile-uuid>/
      retroarch/
      standalone/
      mister/
      versions/
      manifest.json
  temp/                           # staging de uploads/downloads
```

**No painel:** mostrar `Israel` normalmente; opção de detalhe para `Israel — K7M4P9XA — UUID — dispositivos` ao administrador. Não depender do nome para localizar pasta.

### Permissões

| Operação | Administrador | Convidado autenticado | Sem autenticação |
|---|---|---|---|
| Ver usuários e códigos | Sim | Apenas seu perfil | Não |
| Gerenciar convites e vagas | Sim | Não | Não |
| Baixar conteúdo autorizado | Sim | Sim | Não |
| Consultar perfil e saves | Todos (administração da nuvem) | Apenas os próprios | Não |
| Escrever saves | Mediante política administrativa | Apenas os próprios | Não |
| Ver telemetria central | Sim | Apenas local | Não |
| Alterar regras globais | Sim | Não | Não |
| Alterar retenção de cache pessoal | Sim | Sim (limites seguros) | Não |

---

## 4. Proteção do Google Drive: Gateway de arquivos

### Regra absoluta

**NUNCA distribuir** com o Client: OAuth token do proprietário, refresh token, sessão Google Drive para Desktop, pastas compartilhadas abertas, links permanentes de arquivos, API keys privadas ou acesso SMB irrestrito à biblioteca/saves.

- Toda credencial de origem permanece apenas no Host (configuração pessoal fora do Git).
- Client recebe `catalog_id`, metadados permitidos e uma rota autenticada ao Gateway. Não recebe ID/path interno do Drive quando desnecessário.
- Gateway valida perfil, escopo, tipo de arquivo, status da conta e autorização para o recurso específico.
- Fluxo de transferência por streaming autenticado/chunks; suporte a `Range`/retomada quando implementado com validação de limites. Nunca apontar o cliente diretamente para o Drive privado.
- O cliente receberá naturalmente os bytes do jogo que pedir. **Não prometer impedir cópia do arquivo já obtido**.
- Host protege nomes internos do Drive, evita traversal em caminhos, delimita diretórios permitidos, impede download arbitrário de todo o Drive e faz auditoria de solicitações.
- Se usar Google Drive para Desktop, controlar explicitamente leitura/hidratação e erros de sincronização; não confiar que Drive + junções NTFS oferecem o mesmo comportamento em um Host headless.
- A camada de saves usa endpoints separados e autorização `profile_id` derivada da sessão **no servidor**, jamais um `profile_id` recebido do cliente como garantia de acesso.
- Reduzir visibilidade dos caminhos, não 'criptografar' um URL permanente dentro do programa.

### Limites de uso: não confundir com cache

- **3 downloads simultâneos por cliente (padrão)**, configurável; fila prioriza jogo explicitamente aberto > retomada > prefetch opcional > manutenção/thumbnails.
- **Sem limites fixos diários/semanais de GB por convidado na configuração normal**. A pessoa pode experimentar muitos jogos.
- No Host, permitir teto de conexões, banda e transferência **global de emergência**, rate limit para abuso de API e proteção contra loop de requisições; evitar penalizar uso legítimo.
- Cache local tem retenção de 3 dias por **última execução/uso registrado**, não por data de download. Estender ou desativar por usuário.
- Ocupação máxima do cache (`cache_max_gb`) e reserva mínima de espaço livre opcionais e independentes da retenção.
- A limpeza **nunca** toca arquivos-fonte no Drive, saves, savestates, arquivos fixados, processo em execução, transferências em progresso ou arquivos fora do cache gerenciado.
- Um jogo manualmente copiado pelo convidado para fora do cache é propriedade local dele; o CloudCartridge não o rastreia nem tenta apagá-lo.
- Offline: jogo baixado integralmente abre; sync de saves é enfileirado para quando voltar a conectividade.

### Confiabilidade de download

- Escrita em arquivo temporário `.partial` fora dos diretórios ativos, retomada segura, verificação de tamanho e `SHA-256`, rename atômico apenas após validação.
- Se upload/download interromper, não apresentar jogo parcial como disponível e não iniciar core contra arquivo incompleto.
- Priorizar downloads sob demanda; disco adicional do mesmo título somente prefetch se habilitado pelo usuário e se a rede/SSD estiverem ociosos.
- Indexar conteúdo com `catalog_id`, hash, tamanho, versão, sistema, região, caminho lógico e política de compatibilidade.
- Separar taxa do arquivo lido do cache vs taxa **real** de bytes trafegados no Gateway.
- Respeitar limites da API e usar backoff exponencial com jitter.

---

## 5. Save Guardian — módulo crítico e não destrutivo

> **Incidente de referência, informado pelo proprietário:** um save aparentemente perdido foi restaurado; um agente descobriu que a forma de reconhecimento/localização/nomeação de saves no RetroArch havia mudado. Tratar isso como regressão obrigatória em TODAS as futuras atualizações.

### Princípios

1. **Nunca sobrescrever ou apagar saves divergentes** silenciosamente.
2. **Hora não é autoridade de progresso**: RTC/NTP em UTC ajudam a auditar, mas relógios atrasados, relógios locais diferentes e metadados copiados podem enganar.
3. Utilizar merge de **três vias**: estado local atual, último estado sincronizado neste dispositivo e estado remoto atual; detectar mudanças independentes.
4. Calcular hashes do conteúdo e usar versões/gerações de arquivo. Em conflito, criar cópias preservadas de ambos os lados e registrar ação necessária.
5. Guardar histórico versionado, inicialmente últimas **5 versões confirmadas por save** (configurável), e uma cópia de segurança antes de qualquer renomeação, restauração ou sobrescrita.
6. Usar escrita temporária, fsync conforme plataforma, validação e operação atômica ou compare-and-swap quando suportado; tolerar desligamentos no meio da gravação.
7. Só sincronizar quando o emulador/núcleo descarregar conteúdo ou após o arquivo permanecer estável e não estar em uso; detectar múltiplos emuladores acessando o mesmo save.
8. Nunca sincronizar dois motores concorrentes no mesmo diretório sem coordenação: detectar Cloud Sync nativo do RetroArch e oferecer migração/integração sem corrida de escrita.
9. Saves do PC e MiSTer somente são intercambiáveis quando houver compatibilidade **comprovada por adaptador e teste**. Savestates são normalmente específicos do núcleo e versão: mantê-los separados, sem conversão universal presumida.

### Reconhecimento do save após atualização (requisito central)

- Detectar versão real do RetroArch, executável, core, versões de núcleo e configuração efetiva, inclusive overrides por core/diretório/jogo.
- Capturar `savefile_directory`, `savestate_directory` e opções de ordenação por nome de core/diretório de conteúdo; resolver nomes por ROM, core, playlist e IDs estáveis.
- Montar um **manifesto de localizações conhecido** por dispositivo e por versão do RetroArch; detectar diferenças após atualização.
- Antes de criar qualquer save novo numa pasta aparentemente vazia, fazer `save doctor`: procurar candidatos nos caminhos atuais e antigos, backups, diretórios configurados e variantes de nome/extensão.
- Reportar `found_legacy_save`, `path_changed`, `name_changed`, `core_changed`, `format_incompatible`, `conflict` e `no_save_found`, sem declarar perdido um arquivo ainda detectável.
- Migração entre diretórios é por **cópia + teste de leitura + backup**, não `move` destrutivo. Nunca sobrescrever o destino sem versão preservada.
- Tratar cartões/arquivos de memória de PCSX2, Dolphin, DuckStation, RPCS3 e MiSTer por adaptadores específicos; não depender exclusivamente de extensões `.srm` e prefixos de nome.
- O mesmo nome de jogo em regiões/editions diferentes pode ter saves incompatíveis: chave interna deve incluir `game_id`, core/emulador, região/serial quando conhecido e formato.
- Manter logs que permitam explicar a causa de um save não detectado **sem revelar o conteúdo do save**.

### Exemplos de decisões de sincronização

| Local | Remoto | Última base sincronizada | Resultado |
|---|---|---|---|
| Igual | Igual | Qualquer | Nenhuma transferência |
| Modificado | Inalterado | Conhecida | Upload versionado |
| Inalterado | Modificado | Conhecida | Download após backup local |
| Modificado | Modificado | Conhecida | Conflito: guardar os dois, sem promover automaticamente |
| Arquivo não encontrado | Existente | Conhecida | Verificar caminho/configuração antes de baixar ou criar |
| Relógio divergente | Qualquer | Qualquer | Priorizar manifesto/hash, não timestamp |
| Núcleo mudou savepath | Save antigo encontrado | Conhecida | Diagnóstico + migração em cópia + validação |
| Cliente offline | Save local modificado | Conhecida | Fila durável; reconciliar ao reconectar |

### Salvaguardas adicionais

- Saves não consomem a mesma cota/fila de ROMs; pequenos uploads têm prioridade operacional adequada.
- `save restore` só escolhe versão mediante seleção explícita ou regra indiscutível provada por manifesto; `--dry-run` obrigatório para ações de recuperação sensíveis.
- Administrador pode verificar perfil/estado, mas telemetria por padrão não expõe dados pessoais além de nome e status.

---

## 6. Descoberta de emuladores em PCs diferentes

### Regra de produto

- CloudCartridge **detecta** emuladores e cores instalados. **Não instala emuladores automaticamente.**
- Se ausente, reporta o nome correto, link **oficial** de obtenção quando validado, impacto e 'pendente de instalação manual'.
- Depois que a pessoa instala o emulador, executar novamente a bateria: `detect --refresh` / `doctor --emulators` (nomes propostos).
- Separar estados: `not_installed`, `detected`, `configured`, `validated`, `unsupported_version`, `broken`, `offline` (MiSTer).
- Configurar apenas emuladores detectados e suportados, sem sobrescrever perfis de usuários; backups e diffs de alterações.

### Estratégia de busca no Windows

1. Procurar caminhos configurados existentes e validar binário, versão e integridade básica;
2. procurar instalações em Registro (`Uninstall` por usuário/máquina), diretórios usuais, Program Files, Launchers/Steam, `PATH`, instalações portáteis, Scoop/winget quando presente;
3. localizar diretórios de dados/configuração reais, não adivinhar com base apenas no `.exe`;
4. detectar núcleos do RetroArch pelo arquivo real, `cores`, `info`, plataformas suportadas e dados declarados por core;
5. produzir diagnóstico com confiança e múltiplas instalações encontradas, sem escolher arbitrariamente a instalação errada;
6. permitir cadastro manual do caminho pelo terminal e reaplicar detecção incremental;
7. revarrer após instalações/atualizações e quando o usuário solicitar; evitar watchers custosos permanentes.

### Emuladores standalone previstos

| Emulador | Plataformas principais | Existência no projeto atual | Resultado esperado do detector |
|---|---|---|---|
| **PCSX2** | PlayStation 2 | Template standalone | Detectar executável, versão, dados, BIOS fornecida pelo usuário e diretórios de saves |
| **Dolphin** | GameCube, Wii | Template standalone | Detectar versões, configuração, pastas, jogos RVZ/formatos compatíveis e saves |
| **Cemu** | Wii U | Template standalone | Detectar instalação e formatos efetivamente suportados |
| **RPCS3** | PlayStation 3 | Template standalone | Detectar instalação e saves, sem assumir compatibilidade universal de ISO |
| **Citra / forks compatíveis** | Nintendo 3DS | Citra no template | Detectar binário real e compatibilidade; **não buscar distribuições não confiáveis** |
| **DuckStation** | PlayStation 1 | Mencionado no README/Watcher; não está no template examinado | Completar adaptador standalone e caminhos de save |
| **PPSSPP** | PSP | Proposto no plano mestre RetroArch | Adaptador futuro condicional, após auditoria |
| **Demais emuladores** | Conforme plugins | Futuro | Não anunciar compatibilidade sem adaptador/testes |

**Distinção:** 'compatível com o sistema' ≠ 'emulador já encontrado' ≠ 'core encontrado' ≠ 'jogo comprovadamente executado'.

### Matriz real das 46 entradas do `core_mapping.json` da baseline

> **Fonte:** arquivo atual do GitHub, não lista de núcleos necessariamente instalados em qualquer PC. `CorePath` está preso a `C:\RetroArch-Win64\cores\...`; substituir por identificação dinâmica. Quando rótulo e DLL divergirem, tratar DLL e metadados reais como objetos a validar, não corrigir silenciosamente por suposição.

| # | Sistema/pasta mapeada | Core do repositório / DLL | Status da entrada |
|---:|---|---|---|
| 1 | Mattel - Intellivision | FreeIntv / `freeintv_libretro.dll` | Mapeado |
| 2 | Atari - 2600 | Stella / `stella_libretro.dll` | Mapeado |
| 3 | SNK - Neo Geo | Geolith / `geolith_libretro.dll` | **Rótulo atual diz MAME 2010; revisar** |
| 4 | SNK - Neo Geo Pocket Color | Beetle NeoPop / `mednafen_ngp_libretro.dll` | Mapeado |
| 5 | Nintendo - Game Boy Advance | mGBA / `mgba_libretro.dll` | Mapeado |
| 6 | Magnavox - Odyssey2 | O2EM / `o2em_libretro.dll` | Mapeado |
| 7 | Sega - Dreamcast | Flycast / `flycast_libretro.dll` | Mapeado |
| 8 | Bandai - WonderSwan | Beetle WonderSwan / `mednafen_wswan_libretro.dll` | Mapeado |
| 9 | SNK - Neo Geo Pocket | Beetle NeoPop / `mednafen_ngp_libretro.dll` | Mapeado |
| 10 | RCA - Studio II | MAME 2010 / `mame2010_libretro.dll` | **Compatibilidade a validar** |
| 11 | GCE - Vectrex | VecX / `vecx_libretro.dll` | Mapeado |
| 12 | Sega - 32X | PicoDrive / `picodrive_libretro.dll` | Mapeado |
| 13 | NEC - PC Engine SuperGrafx | Beetle PCE Fast / `mednafen_pce_fast_libretro.dll` | Mapeado |
| 14 | Nintendo - Nintendo Entertainment System | Mesen / `mesen_libretro.dll` | Mapeado |
| 15 | Sega - Master System - Mark III | Gearsystem / `gearsystem_libretro.dll` | Mapeado |
| 16 | Sega - Saturn | Beetle Saturn / `mednafen_saturn_libretro.dll` | Mapeado |
| 17 | Nintendo - Wii | Dolphin core / `dolphin_libretro.dll` | Mapeado; **preferir verificar standalone** |
| 18 | Atari - Jaguar | Virtual Jaguar / `virtualjaguar_libretro.dll` | Mapeado |
| 19 | Atari - 5200 | Atari800 / `atari800_libretro.dll` | Mapeado |
| 20 | Sega - Mega Drive - Genesis | Genesis Plus GX / `genesis_plus_gx_libretro.dll` | Mapeado |
| 21 | SNK - Neo Geo CD | NeoCD / `neocd_libretro.dll` | Mapeado |
| 22 | Nintendo - Nintendo 64 | Mupen64Plus-Next / `mupen64plus_next_libretro.dll` | Mapeado |
| 23 | Nintendo - Super Nintendo Entertainment System | Snes9x / `snes9x_libretro.dll` | Mapeado; **plano pessoal prefere bsnes Accuracy** |
| 24 | Nintendo - Nintendo 64DD | Mupen64Plus-Next / `mupen64plus_next_libretro.dll` | Condicional |
| 25 | NEC - PC Engine - TurboGrafx 16 | Beetle PCE Fast / `mednafen_pce_fast_libretro.dll` | Mapeado |
| 26 | Atari - Lynx | Handy / `handy_libretro.dll` | Mapeado |
| 27 | Fairchild - Channel F | FreeChaF / `freechaf_libretro.dll` | Mapeado |
| 28 | Sony - PlayStation | SwanStation / `swanstation_libretro.dll` | Mapeado; **plano pessoal prefere Beetle PSX HW** |
| 29 | Nintendo - Game Boy | Gambatte / `gambatte_libretro.dll` | Mapeado; **plano pessoal prefere SameBoy** |
| 30 | Nintendo - Virtual Boy | Beetle VB / `mednafen_vb_libretro.dll` | Mapeado |
| 31 | Watara - Supervision | Potator / `potator_libretro.dll` | Mapeado |
| 32 | Bandai - WonderSwan Color | Beetle WonderSwan / `mednafen_wswan_libretro.dll` | Mapeado |
| 33 | Nintendo - GameCube | Dolphin core / `dolphin_libretro.dll` | Mapeado; **verificar standalone** |
| 34 | Coleco - ColecoVision | blueMSX / `bluemsx_libretro.dll` | Mapeado |
| 35 | MAME 2010 | MAME 2010 / `mame2010_libretro.dll` | Mapeado |
| 36 | Nintendo - Game Boy Color | Gambatte / `gambatte_libretro.dll` | Mapeado; **plano pessoal prefere SameBoy** |
| 37 | Nintendo - Family Computer Disk System | Mesen / `mesen_libretro.dll` | Mapeado |
| 38 | Sega - Game Gear | Gearsystem / `gearsystem_libretro.dll` | Mapeado |
| 39 | Atari - 7800 | ProSystem / `prosystem_libretro.dll` | Mapeado |
| 40 | Nintendo - Wii U | `DETECT` / `DETECT` | **Incompleto: Cemu standalone** |
| 41 | Nintendo - Pokemon Mini | PokeMini / `pokemini_libretro.dll` | Mapeado |
| 42 | Sega - SG-1000 | Gearsystem / `gearsystem_libretro.dll` | Mapeado |
| 43 | Emerson - Arcadia 2001 | MAME 2010 / `mame2010_libretro.dll` | **Compatibilidade a validar** |
| 44 | Sony - PlayStation 2 | LRPS2/PCSX2 / `pcsx2_libretro.dll` | Mapeado; standalone preferencial quando aplicável |
| 45 | Nintendo - Nintendo DS | melonDS DS / `melondsds_libretro.dll` | Mapeado |
| 46 | MAME | MAME 2003-Plus / `mame2003_plus_libretro.dll` | Mapeado; plano pessoal prefere MAME Current conforme compatibilidade |

**Não remover núcleos apenas porque existe uma preferência mais recente.** Preferências globais por sistema e perfis pessoais são separados, validados por disponibilidade, compatibilidade e sem afetar saves.

### Perfis de RetroArch já definidos em estudo anterior

O proprietário mantém o documento `RetroArch_4K_Plano_Mestre.md` (03/10/2026). O Codex deverá **localizar e utilizar esse estudo, quando disponível no workspace**, respeitando:

- Retro clássico 4:3 em janela redimensionável e persistente, moderno 16:9 quando pertinente;
- configurações específicas por core em overrides, `.opt`, `.slangp`, remaps e BIOS/firmware fornecidos legalmente pelo usuário;
- shaders/scanlines adequados por geração, perfis Accurate/Enhanced por núcleo;
- seleção enxuta de cores atuais, sem baixar indiscriminadamente cores legados;
- thumbnails sob demanda; preservar thumbnails personalizados;
- modo de telas duplas separadas do DS **não faz parte do projeto**;
- **não presumir** GPU ou áudio do proprietário em máquinas de convidados: detectar hardware e manter perfis não destrutivos.

---

## 7. Organizador de playlists e thumbnails

### Integração do projeto local existente

Existe um **outro projeto local do proprietário** que já cria/organiza playlists e pré-configura RetroArch. Seu caminho/fonte ainda não foi fornecido neste contexto. **Codex deverá localizar no workspace autorizado, identificar a implementação e reaproveitar scripts e regras.** Se não estiver acessível, relatar o bloqueio e implementar somente interfaces/contratos e testes; não fingir que o código foi integrado.

### Playlists `.lpl`

- Detectar raiz de ROMs e playlists existentes; ler schema e preservar campos extras, configurações manuais, favoritos, históricos e associações válidas.
- Idempotência: execuções repetidas **não criam duplicatas**, não removem entradas válidas do usuário e não redefinem overrides.
- Adicionar novos jogos conforme catálogo sem baixa-los antecipadamente; validar caminhos lógicos/virtuais e configuração de core.
- Preferir playlists portáteis onde útil, mas garantir tradução de paths por dispositivo e sistema operacional.
- Processar bibliotecas volumosas por delta (manifesto/mtime/hash), não rescans custosos completos a cada inicialização.
- Não gravar playlists/configurações enquanto o RetroArch estiver alterando arquivos; backup, escrita atômica e reconstrução segura em falha.

### Thumbnails

- Auditar `Named_Boxarts`, `Named_Snaps`, `Named_Titles` em pasta correspondente ao `db_name`/nome exato da playlist.
- Detectar ausências e baixar apenas faltantes, evitando download de pacotes completos.
- Casar nomes de jogo, labels e regras de sanitização do RetroArch; permitir variantes regionais.
- Preservar customizações, preferências de imagem e backups de artes próprias.
- Limitar requisições e permitir execução em horário ocioso.
- O CloudCartridge não apresenta capas em interface própria; organiza imagens **para o RetroArch**.

---

## 8. MiSTer FPGA — integração futura, isolada e correta

- Criar `MisterAdapter` separado. Fase 1 pode usar PC/Host como intermediário por SFTP/SSH/SMB/CIFS/NFS conforme suporte/segurança, sem processo pesado no MiSTer.
- Detectar endereços/dispositivos explicitamente autorizados; consultar estrutura, espaço livre e núcleos instalados. Não aceitar controle remoto irrestrito.
- Oferecer download/instalação apenas para plataformas e formatos suportados pelo núcleo real.
- CHD será o formato preferencial **para mídias de disco quando tanto o core do PC quanto o MiSTer suportarem**. Não impor CHD para ROMs de cartucho; não converter indevidamente RVZ de GameCube/Wii que é usado pelo Dolphin no PC.
- Para o core PSX do MiSTer, organizar arquivos CHD/BIN+CUE em **pasta individual por jogo** quando a especificação do core exigir para save correto.
- Wii, Wii U, GameCube, PS2, PS3 etc. não se tornam compatíveis com MiSTer FPGA convencional apenas por existirem no catálogo.
- Espaço remoto limitado, opções de download por solicitação vs compartilhamento NAS, limpeza independente por dispositivo e saves separados por core/versão.
- MiSTer offline deve ser estado normal, não erro global para o PC.

---

## 9. Terminal exclusivo: cliente e administrador

### Objetivo visual

- Interface CLI/TUI somente texto/Unicode, sem navegador, Electron, web frontend, GPU ou dependências gráficas.
- **Processos leves sem janela** para sincronizar, escutar eventos e manter cache; terminal aberto quando solicitado.
- Cores discretas, alinhamento por colunas, largura adaptável, navegação por teclado, suporte a alto contraste, modo sem cor e saída legível por leitor de tela.
- Identificadores visuais para emuladores: usar `[RA]`, `[PS2]`, `[GC]`, `[PS3]`, `[FPGA]`, ícones Unicode quando suportados; gráficos/ícones PNG somente se o terminal tiver suporte opcional. **Nunca exigir fonte externa**.
- Explicitar diferença entre **instalado**, **configurado**, **validado** e **conectado**.
- Nunca contar jogos realmente em execução sem observação confiável do processo ou integração com emulador.

### Painel administrativo — exemplo fictício

```text
┌──────────────────────── CLOUDCARTRIDGE HOST ──────────────────────┐
│ Perfis convidados: 3/5   Online: 2   Downloads: 2   Host: OK      │
│ Biblioteca: 4.821 jogos  Origem: Drive privado  Saves: Sincron.  │
├──────────────────────────────────────────────────────────────────┤
│ USUÁRIOS                                                         │
│ Israel       ONLINE   Jogando Final Fantasy VII [se autorizado]   │
│ Rafael       ONLINE   Baixando Panzer Dragoon 64% | 8,4 MB/s      │
│ Lucas        OFFLINE  Última sincronização: ontem                  │
│ Vagas livres: 2                                                   │
├──────────────────────────────────────────────────────────────────┤
│ EMULADORES — PC DE ISRAEL                                         │
│ [RA] RetroArch    VALIDADO   24 cores encontrados                 │
│ [PS2] PCSX2       VALIDADO   versão detectada                     │
│ [GC] Dolphin      CONFIGURADO                                     │
│ [PS3] RPCS3       NÃO INSTALADO                                   │
│ [FPGA] MiSTer     OFFLINE                                         │
├──────────────────────────────────────────────────────────────────┤
│ [1] Usuários [2] Downloads [3] Emuladores [4] Saves [5] Logs     │
└──────────────────────────────────────────────────────────────────┘
```

A lista 'jogando' depende de telemetria autenticada **explicitamente conhecida e opcional para o convidado**. Se a pessoa desabilitar isso: mostrar `online, jogo não compartilhado`, não inferir ou bisbilhotar aplicativos. Atividades de download e sincronização podem aparecer no Host para operação, conforme política de privacidade informada ao participante.

### Comandos desejados (CONTRATO PROPOSTO, não comandos existentes)

```bash
cloudcartridge status
cloudcartridge doctor --json
cloudcartridge detect --refresh
cloudcartridge emulators list
cloudcartridge cores list --available
cloudcartridge retroarch playlists sync --dry-run
cloudcartridge retroarch thumbnails repair --missing-only
cloudcartridge cache status
cloudcartridge cache policy --retention-days 7
cloudcartridge cache pin <catalog_id>
cloudcartridge saves doctor --profile current
cloudcartridge saves recover --dry-run
cloudcartridge profile init
cloudcartridge profile recovery-check
cloudcartridge host monitor
cloudcartridge host users list
cloudcartridge host users invite --name Israel
cloudcartridge host users revoke <profile_code>
cloudcartridge client reconnect
cloudcartridge mister detect
```

- Cada comando administrativo com `--json` para agentes e scripts, saída humana legível padrão, `--dry-run` quando altera arquivos e `--yes` restrito a operações seguras autorizadas.
- Códigos de retorno consistentes, mensagens em pt-BR, logs estruturados sem tokens/chaves/URLs permanentes.
- Usar comandos de exemplo como especificação de interface. Codex deverá ajustar nomenclatura por consistência e documentar eventual diferença.

---

## 10. Regras do cache e política individual de retenção

### Defaults

```json
{
  "cache": {
    "retention_days": 3,
    "cleanup_enabled": true,
    "max_gb": null,
    "min_free_gb": null,
    "max_concurrent_downloads": 3,
    "pin_excludes_auto_cleanup": true,
    "purge_on_last_played_expiry": true,
    "preserve_manual_copies": true
  }
}
```

- Cliente pode selecionar 3/7/14/30 dias ou `null`/`off` para não limpar automaticamente por tempo; não impor três dias para todos.
- Ao **iniciar novamente** uma partida a data de último uso é renovada; se o emulador fecha após segundos, contabilizar tentativa/uso sem causar loop destrutivo.
- Cache indexado por hash/catálogo, com registro de lock por jogo em execução; crash recovery impede que um lock antigo cause retenção infinita.
- Limpeza é idempotente, fica suspensa em erro de Drive e nunca pode apagar saves; dry-run disponível.
- Priorização de SSD/cotas de cache é por dispositivo, não por proprietário.
- Não usar os 3 dias para bloquear transferência voluntária de arquivos para outra pasta.

---

## 11. Modelo de dados mínimo (sugestão, evoluir no desenho técnico)

```text
UserProfile(profile_id UUID PK, display_name, profile_code UNIQUE,
            role, status, created_at_utc, recovery_verifier_ref)
Device(device_id UUID PK, profile_id FK, public_key_or_credential_ref,
       status, last_seen_at_utc, created_at_utc)
Invite(invite_id, intended_name, status, expires_at_utc, issued_by)
CatalogItem(catalog_id PK, platform_id, title, region, serial, format,
            content_size, sha256, source_locator_private, compatibility)
DownloadJob(job_id, device_id, catalog_id, priority, state,
            bytes_downloaded, total_bytes, started_at_utc)
CacheEntry(device_id, catalog_id, local_path, verified_sha256,
           last_played_at_utc, pinned, state)
EmulatorInstall(device_id, emulator_id, executable_path, version,
                config_path, core_count, status, last_scan_at_utc)
SaveObject(save_id, profile_id, device_id, game_id, emulator_id,
           core_id, format_id, logical_slot, sha256, generation)
SaveVersion(save_id, generation, parent_generation, sha256,
            storage_locator_private, created_at_utc, origin_device)
SyncCursor(profile_id, device_id, save_id, last_ack_generation)
TelemetryEvent(profile_id, device_id, type, timestamp_utc,
               detail_redacted, expires_at_utc)
```

- SQLite serve para registros do Host; não armazenar saves inteiros em tabelas. Configurações de usuário não sensíveis em JSON válido com schema versionado.
- Migrações forward/back com backup; segredo/credencial via mecanismo seguro separado.
- Catálogo público do cliente não deve conter `source_locator_private`.
- Política de expiração do histórico de telemetria, com retenção curta e alteração pelo admin; limitar minimização de dados.
- Separar estatísticas locais de dados enviados ao Host e permitir o usuário entender/desativar conteúdo do status de jogo.

---

## 12. Agent Skill para Codex e outras IAs

Criar `.agents/skills/cloudcartridge/SKILL.md`, com referências compactas. A skill **não** executa lógica própria de download por conta; invoca a CLI documentada e interpreta JSON/erros.

Estrutura sugerida:

```text
.agents/skills/cloudcartridge/
  SKILL.md
  references/
    commands.md
    troubleshooting.md
    emulator-compatibility.md
    save-guardian.md
    security-and-privacy.md
  scripts/
    doctor-wrapper.*           # opcional, apenas se necessário
```

Modelo mínimo de metadados de `SKILL.md`:

```yaml
---
name: cloudcartridge
description: Configure, diagnose and maintain CloudCartridge, RetroArch playlists, emulators, thumbnails, cache, cloud profiles and save recovery using its CLI. Use only when the user requests CloudCartridge setup, diagnosis or maintenance.
---
```

Regras que a skill deve instruir à IA:

1. Verificar autorização para ler/modificar configurações e executar processos naquele PC.
2. Rodar `doctor` e `detect` antes de editar algo.
3. **Priorizar `--dry-run`**, backups e diffs; solicitar aprovação para alteração destrutiva ou mudança de conta/perfil.
4. Nunca imprimir, copiar ao prompt ou enviar segredos e chaves de recuperação.
5. Nunca inventar emuladores instalados; utilizar detecção real.
6. Nunca presumir que arquivos de save ausentes foram apagados; investigar caminhos/versionamento conforme Save Guardian.
7. Não baixar jogos que o usuário não selecionou e não instalar núcleos/BIOS/emuladores sem permissão.
8. Gerar relatório final conciso: detectado, corrigido, pendente, caminhos afetados e backups.
9. Operar com erros controlados, sem loops automáticos de correção.
10. Ser extensível a agentes que reconhecem o padrão Agent Skills; não afirmar que cada assistente tem acesso automático ao PC.

Também criar `AGENTS.md` sucinto na raiz com regras invariantes para contribuições ao projeto. Skill de suporte não deve ser necessária para uso normal da CLI.

---

## 13. Fases de implementação com gates

### Fase 0 — Auditoria de código (sem alterar dados pessoais)

- Verificar HEAD e ler README, scripts e configurações.
- Capturar inventário do código/fluxos, dependências e testes.
- Localizar o organizador de playlists local. Se ausente, documentar lacuna e preparar contrato de integração.
- Criar backup do repositório e das configurações do RetroArch antes de editar arquivos.
- Não tocar Google Drive real nem pasta de saves pessoais durante testes automatizados.

**Saída:** relatório de compatibilidade atual vs planejada e plano de refatoração incremental.

### Fase 1 — Estabilizar o cliente Windows

- Centralizar configuração, corrigir paths hardcoded, CLI, detecção de emuladores e estados.
- Corrigir bugs de flags, launcher/watchers, tracking de sessão, re-download e prefetch.
- Implementar testes de integridade/retomada, locks de cache e limpeza segura.
- Preservar comportamento atual de Google Drive para o administrador.

**Gate:** todos os cenários locais sem Host passam com fixture; sem regressão nos scripts existentes.

### Fase 2 — Save Guardian e migração do save antigo

- Manifestos 3-way, versionamento, detecção de caminhos, tratamento de saves de RetroArch/standalone, recuperação não destrutiva.
- Detectar mudanças do RetroArch/core e comparar configuração efetiva.
- Reproduzir o incidente relatado de save existente não reconhecido.

**Gate:** não existe cenário de teste em que save divergente seja sobrescrito ou descartado automaticamente.

### Fase 3 — Playlists, thumbnails e catálogo

- Integrar organizador local se disponível; implementar índice persistente.
- Atualizar playlists `.lpl` sem duplicatas, reparar apenas thumbnails ausentes, preservar customizações.
- Expor inventário por sistema e compatibilidade.

**Gate:** duas varreduras sucessivas produzem o mesmo resultado e nenhuma alteração indevida em configurações personalizadas.

### Fase 4 — Host privado e cinco convidados

- API/Gateway privada, autenticação por convites, cinco vagas, identificação nome + 8 chars + UUID + recovery key.
- Saves no Drive isolados e acesso a jogos autorizado por catálogo.
- Monitoração do Host em terminal e eventos de clientes.
- Testar LAN sem domínio e opção Tailscale/WireGuard para redes separadas.

**Gate:** convidado 6 é negado, cliente sem credencial não acessa nada e usuário A não lê/escreve saves de B mesmo alterando requests/código local.

### Fase 5 — MiSTer FPGA

- Descoberta, compatibilidade real de núcleos e distribuição de jogos via rede.
- Testar CHD, estrutura de pastas e saves com core PSX e outros suportados.
- Não confundir plataformas PC-only com MiSTer.

**Gate:** PC e MiSTer coexistem e MiSTer offline não impede download/cache local.

### Fase 6 — Agent Skill, empacotamento e documentação

- CLI estável com `--json`, `--dry-run`, códigos de saída e skill.
- Instalador seguro e atualização com migração de config.
- Manual técnico e manual iniciante, documentação de recuperação/credenciais e termos de privacidade.

**Gate:** um PC de teste sem IA consegue instalar/configurar manualmente; um agente pode executar o mesmo fluxo usando a skill e apenas comandos autorizados.

---

## 14. Bateria de testes de aceitação — cenários obrigatórios

| ID | Cenário | Resultado obrigatório |
|---|---|---|
| T01 | PC novo com RetroArch portátil em disco diferente | Detecta raiz e cores, não exige caminho fixo |
| T02 | PC sem PCSX2 | Marca ausente e não instala automaticamente |
| T03 | PCSX2 instalado depois | `detect --refresh` integra sem reconfigurar tudo |
| T04 | Core ausente / mapeamento incorreto | Playlist não aponta falsamente para core válido |
| T05 | Abre jogo não presente localmente | Transfere um arquivo, verifica SHA-256 e inicia |
| T06 | Abre mesmo jogo novamente | Reusa cache completo, sem baixar novamente |
| T07 | Usuário testa dez jogos | Permite sem quota diária arbitrária; até três transfers paralelos |
| T08 | Baixar disc 1 de multidisco | Prefetch opcional, abaixo da prioridade do jogo atual |
| T09 | Última partida há menos de 3 dias | Não remove o jogo |
| T10 | Última partida acima da retenção | Limpa somente cache gerenciado, nunca saves |
| T11 | Usuário escolhe 14 dias ou `off` | Respeita política pessoal persistente |
| T12 | Jogo fixado ou ativo | Nunca é removido pela limpeza |
| T13 | Usuário copiou ROM para fora do cache | Cópia manual permanece intocada |
| T14 | Host offline | Jogo local segue abrindo e saves aguardam sync |
| T15 | Primeiro cadastro com chave | Exige confirmação de recuperação e grava credencial segura |
| T16 | Cinco convidados ativos e novo convite | Sexto rejeitado sem apagar/perder saves |
| T17 | Instalador compartilhado com terceiro | Não cria acesso ao Drive nem saves sem autorização |
| T18 | Apenas código de 8 caracteres informado | Não concede acesso ao perfil remoto |
| T19 | Usuário A altera profile_id de uma requisição | Host rejeita acesso ao save de B |
| T20 | Reinstalação com código + recovery key | Recupera identidade e saves sem acessar Drive diretamente |
| T21 | Recovery key perdida e sem outro dispositivo | Não promete recuperação; protege conta |
| T22 | Dois PCs alteram o mesmo save offline | Mantém ambas versões, conflito explicitado |
| T23 | Relógio local adiantado/atrasado | Hash+gerações prevalecem sobre timestamp |
| T24 | RetroArch muda ordenação/pasta de saves | Detecta arquivo legado, não cria falsa perda |
| T25 | Atualização altera nome de core | Detecta e oferece migração por cópia/teste |
| T26 | RetroArch e Cloud Sync nativo ativos | Detecta concorrência e evita dupla sincronização |
| T27 | Desligar PC durante download/save | Arquivo parcial não vira ativo; retomada segura |
| T28 | Biblioteca com 20 mil títulos | Pesquisa por índice incremental sem download massivo |
| T29 | Thumbnail ausente e capa personalizada | Baixa ausente, preserva personalizada |
| T30 | Rodar playlist sync duas vezes | Idempotente, sem duplicar entradas |
| T31 | Convidado opta por não compartilhar o jogo atual | Host mostra conectado sem divulgar título |
| T32 | Tailscale/LAN indisponível | Terminal informa indisponibilidade e mantém operação local |
| T33 | MiSTer desconectado | Estado offline sem bloquear PC |
| T34 | CHD no MiSTer PSX | Estrutura correta e save/cartão testados |
| T35 | Wii U/PS3 no catálogo | Não é oferecido como núcleo compatível MiSTer |
| T36 | Segredo em `config.json`/log/repo | Testes impedem inclusão de token/chave privada |
| T37 | Dois downloads do mesmo jogo em paralelo | Deduplicar job e preservar checksum |
| T38 | Limpeza após falha de rede | Não apaga fonte nem saves e não marca cache incorretamente |
| T39 | Usuário atualiza versão de RetroArch | `doctor` compara versão, caminhos, opções de save e core |
| T40 | Administrador revoga amigo | Bloqueia novos acessos, preserva saves até ação explícita |

Implementar testes unitários, integração com servidor fake/Drive mock e E2E em sandbox. Não testar com saves reais sem backups e aprovação explícita.

---

## 15. Requisitos não funcionais e restrições

- **Desempenho:** mínimo overhead idle, sem loops intensivos de polling, sem renderização ou GPU; propor metas de CPU/RAM depois de benchmark de baseline em PCs reais.
- **Instalação:** poucas dependências, instalador/CLI que não muda configurações arbitrárias, opção de remover sem deletar jogos/saves.
- **Compatibilidade:** Windows principal, Linux/MiSTer por adaptador; não afirmar suporte macOS antes de testes.
- **Confiabilidade:** operações idempotentes, journal durável para jobs, recuperação após crash, lock por save e cache, logs redigidos.
- **Segurança:** princípio de menor privilégio, tokens revogáveis, credenciais protegidas, autorização server-side em todas operações, entradas/paths validados.
- **Privacidade:** coletar o mínimo necessário, informar dados de status enviados, permitir desabilitar `now_playing`/jogo atual; limpeza periódica de logs históricos.
- **Acessibilidade:** terminal em pt-BR, legível sem símbolos/cores, e saída JSON para automação.
- **Legalidade:** distribuir somente ROMs/BIOS/firmwares/imagens com direitos ou autorização de distribuição; não incluir conteúdos comerciais protegidos no GitHub, skill ou pacote.
- **Design do projeto:** engenharia modular, configurações claras, erros recuperáveis, UX de terminal consistente e comandos previsíveis; **não criar GUI**.

---

## 16. Critérios de entrega exigidos do Codex

Ao encerrar cada fase, produzir:

1. Diff/commits pequenos e coerentes, sem force push e sem credenciais reais.
2. Resumo do que estava implementado, do que foi corrigido e do que continua planejado.
3. Lista dos emuladores e cores de fato detectados **na máquina testada**, separados da matriz de suporte teórico.
4. Evidência de testes executados, quais passaram/falharam e lacunas por falta de dispositivo real (ex.: MiSTer).
5. Backups/restauração, plano de rollback e logs sem segredos.
6. Atualização de README, changelog, exemplos de configuração, avisos de recuperação e skill quando pertinente.
7. Documentação das decisões de arquitetura, inclusive trade-off da camada Host em comparação ao PowerShell atual.

**Prioridade máxima absoluta:** não perder saves e não quebrar bibliotecas existentes. Se houver conflito entre implementar recurso novo e proteger dados, interromper a mudança de risco, preservar os dados e informar o usuário.

---

## 17. Fontes e referências para revisão pelo Codex

**Código atual:**
- https://github.com/forjaRPGtv/CloudCartridge
- https://github.com/forjaRPGtv/CloudCartridge/blob/main/CloudROM_Launcher.ps1
- https://github.com/forjaRPGtv/CloudCartridge/blob/main/CloudROM_Telemetry.ps1
- https://github.com/forjaRPGtv/CloudCartridge/blob/main/CloudROM_Watcher.ps1
- https://github.com/forjaRPGtv/CloudCartridge/blob/main/core_mapping.json
- https://github.com/forjaRPGtv/CloudCartridge/blob/main/standalone_emulators.template.json

**RetroArch/Libretro:**
- Playlists e thumbnails: https://docs.libretro.com/guides/roms-playlists-thumbnails/
- Cloud Sync e três vias/manifestos: https://docs.libretro.com/guides/retroarch-cloud-sync/
- Instalação/configuração: https://docs.libretro.com/guides/install-windows/
- Interface de controle/consulta: https://docs.libretro.com/development/retroarch/network-control-interface/

**MiSTer:**
- PSX MiSTer, CHD, cartões e pastas: https://github.com/MiSTer-devel/PSX_MiSTer
- Montagem CIFS: https://github.com/MiSTer-devel/Scripts_MiSTer/blob/master/cifs_mount.sh

**Skills e rede privada:**
- Padrão de skills para ChatGPT/Codex: https://learn.chatgpt.com/docs/build-skills
- Tailscale Personal: https://tailscale.com/pricing

**Documento complementar do proprietário:** `RetroArch_4K_Plano_Mestre.md` (03/10/2026), se disponível no workspace local. Esta especificação resume decisões relevantes, mas não substitui configurações detalhadas de shaders, overrides, áudio e vídeo nele descritas.

---

## 18. Instrução final para iniciar a execução

> Codex: abra o repositório `forjaRPGtv/CloudCartridge` na cópia local autorizada; verifique o HEAD atual; leia este documento inteiro e compare suas exigências ao código. **Não recomece o projeto do zero.** Inicie a **Fase 0 (auditoria)**, crie testes de regressão e siga as fases em ordem, entregando mudanças pequenas e verificáveis. Priorize estabilização dos scripts existentes, o Save Guardian e sua recuperação de caminhos de saves. Em seguida integre o organizador local de playlists se encontrar sua origem, o catálogo, o Host privado de 5 convidados, a telemetria TUI, o MiSTer e a Agent Skill. Não peça credenciais em logs e não modifique saves reais sem backups e autorização. Se não houver acesso ao computador do usuário, ao projeto local de playlists, ao Drive ou ao MiSTer, registre a limitação e avance com implementações e testes simulados, sem alegar validação real. Gere relatório de resultados por fase.
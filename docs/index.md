---
layout: default
title: CloudCartridge
description: Automação cloud-first para bibliotecas de emulação no Windows
---

# CloudCartridge

**Sua biblioteca em nuvem, seus emuladores e seus saves sob controle.**

O CloudCartridge é uma camada de automação para Windows que integra Google Drive para Desktop, RetroArch e emuladores standalone. Ele organiza downloads sob demanda, cache, playlists e saves sem substituir o emulador e sem exigir IA para funcionar.

[Ver código no GitHub](https://github.com/forjaRPGtv/CloudCartridge){: .btn .btn-primary }
[Começar pelo manual](MANUAL_INICIANTE.md){: .btn }

<div class="feature-grid">
  <div class="feature-card">
    <h3>Biblioteca cloud-first</h3>
    <p>Integra arquivos transmitidos pelo Google Drive sem baixar toda a coleção antecipadamente.</p>
  </div>
  <div class="feature-card">
    <h3>Save Guardian</h3>
    <p>Hashes de três vias, conflitos preservados, versões, locks e fila offline.</p>
  </div>
  <div class="feature-card">
    <h3>RetroArch e standalone</h3>
    <p>Detecção conservadora, playlists idempotentes e integração sem instalação silenciosa.</p>
  </div>
  <div class="feature-card">
    <h3>Privacidade por padrão</h3>
    <p>Host local, autenticação obrigatória e isolamento de saves para até cinco convidados.</p>
  </div>
</div>

## Situação atual

- **45 testes automatizados aprovados** em fixtures isoladas;
- fluxo local de produção operacional no Windows;
- 45/45 cores RetroArch e seis mapeamentos standalone detectados no ambiente de referência;
- DPAPI e save sintético versionado validados;
- pacote sanitizado sem segredos ou dados de runtime;
- cache do Google Drive configurado no disco de dados.

Os testes entre dois PCs físicos e em um MiSTer físico permanecem como gates externos. O Google Drive administra seu próprio cache e não oferece, no volume virtual observado, uma interface suportada para garantir expulsão física exatamente após três dias.

## Escolha seu caminho

### Quero instalar

Leia o [Manual do iniciante](MANUAL_INICIANTE.md). Ele cobre requisitos, configuração com prévia, primeiros testes e recuperação.

### Quero administrar ou diagnosticar

Consulte o [Manual técnico](MANUAL_TECNICO.md) e a documentação de [Privacidade e recuperação](PRIVACIDADE_E_RECUPERACAO.md).

### Quero entender a validação

Veja o [Gate de produção](GATE_PRODUCAO_20261117.md), as fases de engenharia e o [changelog](https://github.com/forjaRPGtv/CloudCartridge/blob/main/CHANGELOG.md).

### Quero contribuir

Leia o [guia de contribuição](https://github.com/forjaRPGtv/CloudCartridge/blob/main/CONTRIBUTING.md), execute a suíte no Windows e nunca use dados pessoais em testes.

## Início rápido

```cmd
CloudCartridge.cmd doctor --json
CloudCartridge.cmd detect --refresh --json
Testar_CloudCartridge.cmd
```

O repositório não inclui ROMs, BIOS, firmwares, credenciais ou saves. Use somente conteúdo próprio ou autorizado.

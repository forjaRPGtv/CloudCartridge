# Fase 6 — Skill, instalação, empacotamento e documentação

## Entregas

- `Setup_CloudROM.ps1`: prévia por padrão, confirmação literal em modo interativo, aplicação explícita em automação, backup de configuração e preservação de destinos existentes.
- `CloudCartridge.HostMonitor.ps1`: painel contínuo opcional e modo `-Once`, sem exibir tokens, recovery keys ou verificadores.
- `.agents/skills/cloudcartridge/`: Skill operacional e referências compactas.
- `Criar_Pacote.ps1`: prévia e ZIP sanitizado com manifesto SHA-256.
- manuais iniciante/técnico e política de privacidade/recuperação.
- README atualizado para separar implementação fixture de validação física.

## Gate executado

- Instalação/configuração automatizada em cópia temporária sem IA: prévia, aplicação e atualização com backup aprovadas.
- Monitor fixture aprovado e redigido.
- Empacotamento fixture aprovado, sem dados de runtime ou segredos.
- Estrutura/frontmatter e limites da Skill cobertos pela suíte.
- Suíte integral atual: **45 testes aprovados, 0 falhas**.

O validador oficial da Skill não iniciou porque o Python disponível não possui PyYAML. A dependência não foi instalada sem autorização; a mesma estrutura essencial está coberta pela regressão local.

## Validações externas pendentes

DPAPI interativo e Save Guardian com armazenamento real foram aprovados em 2026-11-17. O Google Drive streaming observado gerencia o cache em volume virtual e não fornece estado CFAPI confirmável por `attrib`. Dois PCs em rede privada e MiSTer físico continuam pendentes; nenhum deles foi inferido a partir dos fixtures.

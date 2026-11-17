# Manual do iniciante

## Antes de começar

Instale o Google Drive para Desktop em modo de streaming e o RetroArch. O CloudCartridge não instala emuladores, BIOS, cores nem jogos. Mantenha uma cópia segura de saves importantes.

## Configuração

1. Feche o RetroArch.
2. Abra `Instalar_Configurar.cmd`.
3. Informe a pasta da biblioteca no Google Drive, a pasta local gerenciada e o caminho do `retroarch.exe`.
4. Revise a prévia. Se estiver correta, digite `APLICAR`.
5. Execute `CloudCartridge.cmd doctor --json` e corrija apenas os itens indicados como pendentes.
6. Execute `Testar_CloudCartridge.cmd`. Os testes usam pastas temporárias e não sua biblioteca.

O instalador não substitui uma pasta já existente por junção. Se houver conflito, ele informa `preserve_existing` para revisão manual.

## Jogar e acompanhar

- `Jogar.cmd`: busca e inicia um jogo com o launcher legado.
- `Abrir_RetroArch_com_Telemetria.cmd`: abre o RetroArch com telemetria.
- `Ver_Telemetria_e_Downloads.cmd`: mostra cache e transferências.
- `Monitorar_Host.cmd`: painel contínuo do Host privado.

A retenção padrão é três dias, mas pode ser alterada ou desativada. Um jogo fixado não entra na limpeza automática. Saves, fontes na nuvem e cópias manuais fora do cache gerenciado não podem ser removidos pela limpeza. No Google Drive para Desktop em modo streaming, o cache físico é administrado pelo próprio Google Drive; o CloudCartridge só confirma desidratação quando o provedor expõe estado Windows Files On-Demand/CFAPI verificável.

## Se algo der errado

- Save ausente: não inicie um jogo para criar outro; rode o diagnóstico do Save Guardian e preserve as duas versões em caso de conflito.
- Download interrompido: o parcial não deve ser ativado; rode o diagnóstico e retome pela fila.
- Host offline: jogos já locais continuam utilizáveis e saves aguardam sincronização.
- Credencial/recovery key perdida: consulte o administrador; sem recovery key ou outro dispositivo válido, a recuperação não é garantida.


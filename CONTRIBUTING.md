# Como contribuir

Obrigado por ajudar o CloudCartridge. O projeto prioriza segurança de saves, operação previsível e compatibilidade conservadora.

## Antes de começar

1. Abra uma issue descrevendo o problema ou a proposta.
2. Não inclua ROMs, BIOS, firmwares, saves, credenciais, logs pessoais ou caminhos privados.
3. Trabalhe em uma branch curta a partir de `main`.
4. Preserve o comportamento existente salvo quando a mudança estiver documentada e coberta por teste.

## Ambiente

- Windows 10 ou 11;
- Windows PowerShell 5.1 e, quando possível, PowerShell 7+;
- Git.

Nenhum jogo, emulador ou conta do Google é necessário para executar a suíte automatizada.

## Validação obrigatória

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

Antes do pull request:

- confirme que todos os testes passam;
- execute `git diff --check`;
- use fixtures temporárias para qualquer cenário de save, cache ou Host;
- adicione teste de regressão para correções funcionais;
- atualize README, manuais ou changelog quando o comportamento público mudar.

## Regras de segurança

- Nunca teste com saves reais sem autorização explícita e backup.
- Use dry-run e prévia antes de alterar configurações, playlists ou cache.
- Não instale emuladores, cores, BIOS ou jogos automaticamente.
- Não exponha o listener diretamente na Internet.
- Não reduza autenticação, isolamento de perfis ou redação de segredos.
- Não use `git push --force` como fluxo de publicação.

## Pull request

Explique o problema, a solução, os riscos, os testes executados e qualquer gate físico ainda pendente. Mudanças pequenas e verificáveis são preferidas.

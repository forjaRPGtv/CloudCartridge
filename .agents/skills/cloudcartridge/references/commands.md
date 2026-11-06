# Command reference

Run from the repository root with PowerShell 5.1 or newer.

## Read-only first

```powershell
.\CloudCartridge.cmd status --json
.\CloudCartridge.cmd doctor --json
.\CloudCartridge.cmd detect --refresh --json
.\CloudCartridge.cmd emulators list --json
.\CloudCartridge.cmd cores list --available --json
.\CloudCartridge.cmd host monitor --json
```

Use `.\CloudCartridge.cmd host monitor --watch` only for an attended continuous terminal.

## Preview before applying

```powershell
.\Instalar_Configurar.cmd
.\CloudCartridge.cmd playlist sync --rom-root <pasta> --playlist <arquivo.lpl> --core-path <core.dll> --core-name <nome> --dry-run --json
.\CloudCartridge.cmd host users invite --name <nome> --dry-run --json
.\CloudCartridge.cmd host users revoke <codigo> --dry-run --json
```

The installer previews by default and requires the exact confirmation `APLICAR`. Non-interactive automation must pass `-Apply` explicitly to `Setup_CloudROM.ps1`.

## Tests

```powershell
.\Testar_CloudCartridge.cmd
```

Tests use temporary fixtures. Do not repoint them to personal libraries or saves.


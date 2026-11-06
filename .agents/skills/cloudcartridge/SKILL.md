---
name: cloud-cartridge
description: Configure, diagnose, test, package, and maintain the CloudCartridge PowerShell client, its RetroArch playlists and thumbnails, cache policy, Save Guardian, private Host profiles, and MiSTer adapter. Use for work inside the CloudCartridge repository or when the user explicitly asks to operate CloudCartridge; do not use for generic RetroArch or cloud-storage questions.
---

# CloudCartridge

Work from the current repository state. Read the nearest `AGENTS.md`, `CloudCartridge_vNext_PLANO_MESTRE_CODEX.md`, and `CONTINUAR_AQUI.md` before structural changes.

## Safe workflow

1. Inspect `git status` and preserve unrelated work.
2. Run `CloudCartridge.cmd doctor --json` and the relevant read-only inventory command before editing user configuration.
3. Prefer preview mode. Use `--yes` or `-Apply` only after the user authorizes the described mutation.
4. Back up configuration or metadata before migration. Never test with real saves, ROMs, playlists, or credentials.
5. Keep RetroArch closed before changing its configuration, playlists, or ROM directories.
6. Run `Testar_CloudCartridge.cmd` after code changes. State which fixture tests passed and which hardware checks remain pending.

## Hard boundaries

- Never print, copy into prompts, commit, or log device tokens, recovery keys, Drive locators, or credential verifiers.
- Never infer that a missing save was deleted. Use Save Guardian manifests, generations, hashes, path detection, and explicit conflict recovery.
- Never install emulators, cores, BIOS, games, VPNs, or dependencies without explicit permission.
- Never expose the Host on a public or wildcard address. LAN binding is opt-in and must remain private and authenticated.
- Do not give clients Google Drive credentials. The Host retains private source locators and exposes only authorized catalog/download operations.
- Preserve manual ROM copies, custom playlist entries, and custom thumbnails.
- Treat mock/fixture validation separately from real Google Drive CFAPI, two-PC networking, DPAPI user-profile, and physical MiSTer validation.
- Stop on controlled errors; do not run automatic repair loops.

Read [commands.md](references/commands.md) for the supported command patterns and [troubleshooting.md](references/troubleshooting.md) for failure routing.

Finish with a concise report: detected, changed, tests passed, pending external checks, affected paths, and backups.


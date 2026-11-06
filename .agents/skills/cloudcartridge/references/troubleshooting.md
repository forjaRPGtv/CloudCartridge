# Troubleshooting

## Save appears missing

Run the save doctor and inspect detected emulator/core paths, manifests, generations, and conflicts. Do not create an empty replacement or overwrite either side. Restore only a selected version to a separate path first.

## Host refuses a request

Keep the default loopback listener while diagnosing. Check private bind validation, profile state, device credential, request timestamp, nonce replay, and rate limit. Logs must remain redacted.

## Cache or download problem

Inspect the managed registry and download journal. A partial file must never become active without its expected SHA-256. Cleanup may affect only managed cache entries, never source files, manual copies, or saves.

## MiSTer offline or incompatible

An offline MiSTer must not block PC operation. Confirm the installed core and compatibility table before planning a transfer. PC-only platforms must be denied. Fixture success is not physical hardware validation.

## Environment-dependent checks

Report these as pending unless observed directly: Google Drive placeholder hydration/dehydration, DPAPI under the signed-in Windows profile, private networking between two PCs, and MiSTer transfer/save behavior on hardware.

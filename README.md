# Infrastructure

Server-wide runbooks and scripts that span more than one app (C001.261031T2215).

| Path | What |
|---|---|
| `Documentation/C001.261031T2215 Deploy Separation Runbook.md` | Per-app deploy users and keys on GlyphScribe / GlyphWarden (DSEP) |
| `server/discover-deploy-state.sh` | Read-only discovery for DSEP00.03 |
| `Scripts/new-deploy-key.ps1` | DSEP01.01: an app's deploy key (passphrase, locked, in ssh-agent) |
| `Scripts/deploy-user.ps1` | DSEP01.02: stage / take / return an app's deploy user on a server, as `glyphops` |
| `Scripts/check-separation.ps1` | DSEP01.03: prove the deploy user can touch only its own app |
| `Scripts/discover.sh`, `Scripts/stage-glyphops.sh` | DSEP00 discovery and `glyphops` set-up |
| `Tests/run-tests.ps1` | Guards: run-log wiring, no credential parameters, LF, `bash -n` |

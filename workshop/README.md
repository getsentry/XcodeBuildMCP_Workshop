# Workshop — Weather demo branches

Five acts that drive the Sentry XcodeBuildMCP workshop. Prompts live in
[`PROMPTS.md`](PROMPTS.md); Q&A talking points in [`WORKSHOP-QA.md`](WORKSHOP-QA.md).

## Live demo flow

```bash
./workshop/switch-stage.sh           # interactive picker (or pass 1..5 / 1-done..5)
cd app && claude                     # launch Claude Code rooted in app/
```

`switch-stage.sh` handles everything the host would otherwise do by hand:

- Discards uncommitted edits from the previous act
- Switches branch and wipes XcodeBuildMCP DerivedData (cold rebuild)
- Writes (or strips, for Act 1) `app/.mcp.json` so the project loads XcodeBuildMCP
- Ensures the backend (`npm run dev`) is running for acts 3, 4, 5
- Prints + pbcopies the verbatim attendee prompt for the act

The agent's workspace is `app/`. Anything outside (`backend/`, `workshop/`,
`.git/`) is invisible — the workshop bug in Act 4 must be diagnosed from the
running app + LLDB, not by reading the backend source.

## Recreating stage branches from patches

The repo ships `main` (anchor) and `stage/*` (one per act). If a branch gets
corrupted or a patch is edited:

```bash
./workshop/build-stages.sh
```

Idempotent: each `stage/*` is recreated as `main + workshop/patches/N.patch`.
`stage/4-bug-fixed` points at `main` (the fix lives on `main` so the patch is
empty by design).

## Backend control

```bash
./workshop/backend-control.sh {start|stop|ensure|status|restart}
```

`ensure` is a no-op if the server is already healthy on `:3001`; otherwise it
starts `npm run dev` in the background and writes the PID + log path under
`workshop/.backend.{pid,log}`. `switch-stage.sh` calls `ensure` for the acts
that need it.

## Acts at a glance

| Act | Branch | Pre-state |
|---|---|---|
| 1 — install XcodeBuildMCP | `stage/1-setup-start` | No `app/.mcp.json`, no `app/.xcodebuildmcp/config.yaml` |
| 1 done | `main` | Both present |
| 2 — build & run | `stage/2-build-run-clean` | Planted parser error in `SunMiniCard.swift` |
| 2 done | `main` | Clean |
| 3 — feature wire-up | `stage/3-feature-start` | Settings toggle bound but unused; `// TODO` marker |
| 3 done | `stage/3-feature-done` | `SevereWeatherAlertBanner` wired through |
| 4 — runtime crash | `stage/4-bug-planted` | Mapper-side wind-direction defense stripped |
| 4 done | `stage/4-bug-fixed` (= `main`) | Coerce `0 → 360` in DTO mapper |
| 5 — canonical (Sentry handoff) | `stage/5-canonical` | Working app + alerts banner; ready for live Sentry wiring |

## Fallback (act derails on stage)

For acts 2/3/4, `./workshop/switch-stage.sh N-done` jumps to the reference
state. Narrate over the diff instead of restarting the agent.

# Workshop prompts

Canonical stripped-down prompts for each act. Paste verbatim into Claude Code
during the live demo — these mirror what a real workshop attendee would
naturally type, with no foreknowledge of where the bugs live or what the fix
shape is.

The agent has to discover the problem from the prompt + the running app +
LLDB / UI automation. That's the whole demo.

Branch and short-form numbering match act numbering. Each act has a `start`
branch (the live state) and a `done` reference branch the host can fall back
to if the agent derails.

---

## Act 1 — Setup XcodeBuildMCP

Branch: `stage/1-setup-start`
Run: `./workshop/switch-stage.sh 1`

```
Show me the current XcodeBuildMCP session defaults for this project.
```

Host-led: from `app/`, the host installs XcodeBuildMCP in Claude Code
(writes `.mcp.json`, approves) and creates the project's
`.xcodebuildmcp/config.yaml`. The start branch is `main` minus the config
file, so the host can demonstrate the install picking up an unconfigured
project. Once the config is in place, restart Claude Code (the MCP server
reads config only at boot), paste the prompt above — the agent runs
`session_show_defaults` and the audience sees the workshop's defaults
come back (Weather.xcodeproj, scheme Weather, iPhone 17 Pro,
`com.sentry.weather.Weather`). That proves the config was loaded.

> `switch-stage.sh` writes `app/.mcp.json` automatically for every act
> except this one (Act 1 starts with it absent). Demoing the install
> from a totally clean slate is the whole point.

The done state (`./workshop/switch-stage.sh 1-done`, which switches to
`main`) ships the config pre-filled. Use this if the host wants to skip
the live config-writing step.

---

## Act 2 — Build & run loop

Branch: `stage/2-build-run-clean`
Run: `./workshop/switch-stage.sh 2`

```
Build and run the Weather app on the iPhone 17 Pro simulator.
```

The app defaults to mock weather data in this stage, so no backend is required.
The build will fail with a Swift compile error. The agent has to read the
diagnostic, locate the file, fix it, and rebuild — implicit in "build and run".
No "there's a bug somewhere" hint.

---

## Act 3 — Adding a feature: alerts toggle

Branch: `stage/3-feature-start`
Run: `./workshop/switch-stage.sh 3`

```
The "Severe weather alerts" toggle in Settings doesn't seem to do anything. Make it work — when alerts are enabled and the current condition is severe (thunderstorms or heavy rain), the user should see an alert banner near the top of the screen.
```

Frames the work as a user complaint plus a feature description. This stage uses
app-default mock weather data, so no backend is required. The agent has to
discover that `alertsEnabled` is currently bound but unconsumed, design the
banner component (matching the existing `WeatherLoadingBanner` visual style is
on them to spot), thread the state through, and verify by toggling in the
running simulator.

If the agent designs something wildly off-spec, fall back to `stage/3-feature-done`
as the reference solution.

---

## Act 4 — Frontend runtime crash (LLDB)

Branch: `stage/4-bug-planted`
Run: `./workshop/switch-stage.sh 4`

```
Attach the debugger to the Weather app, then browse each saved location and confirm the forecast loads cleanly.
```

This stage uses production backend data. The agent taps through saved locations
one by one. SF/Portland/Aspen/New Orleans/Tokyo/Lisbon load fine. **The crash
fires the moment Reykjavík is selected**: the API uses `0°` to represent due
north (standard meteorological convention), `WindDirection.init` asserts
`degrees >= 1 && degrees <= 360`, and the precondition trap fires.

The bug is **not** discoverable from iOS-side code review alone — the
model invariant looks defensible in isolation. The agent has to attach
LLDB at the trap site, inspect the `dto` value, see
`windDirectionDegrees == 0`, and realize the API contract `0...360`
(0 = north) doesn't line up with the model's `1...360` (which assumed 0
was reserved). The fix is a contract translation in the DTO mapper:
treat the API's `0` as the app's `360`.

Stack frame: `WeatherClientDTOs.swift` inside `CurrentWeather.init(dto:)`,
called from `WeatherReport.init(dto:)`. LLDB will show
`dto.windDirectionDegrees = 0` and `id = "weather-current-loc-is-reykjavik"`.

If the agent can't reproduce within ~90s, nudge gently:

```
Try Reykjavík specifically.
```

If still stuck, `stage/4-bug-fixed` is the reference solution. It keeps
production backend data and re-introduces a guard `(0...360).contains(...)`,
then coerces `0 → 360` before constructing `WindDirection`, preserving the
model's `1...360` invariant.

> A sharper agent may instead propose modelling "calm" as a separate
> state (`WindDirection?` or an enum like `WindReading { case calm,
> .direction(WindDirection) }`) — that's the semantically faithful
> answer if the API ever needs to distinguish "no wind" from "wind from
> due north". The shipped reference fix is the simpler coerce; both are
> defensible talking points during the demo.

---

## Act 5 — Sentry end-to-end

Branch: `stage/5-canonical`
Run: `./workshop/switch-stage.sh 5`

The canonical app: `main` + the Act 3 alerts banner + production backend data.
All saved locations load without crashing.

The canonical branch is intentionally clean of any Sentry wiring. Installing
the SDK, pointing the production `WeatherAPIConfiguration.baseURL` at the
workshop backend URL, and exercising the planted backend crash are all the
*live* work of Act 5 — owned by the separate host.

The backend service, its Sentry instrumentation, and the planted bug live
outside this repo.

No prompt here — when the host hands off to Act 5, attendees see this app
running cleanly and watch the host wire up Sentry on top.

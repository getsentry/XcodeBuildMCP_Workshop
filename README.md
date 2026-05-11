# Atmos Weather

Atmos Weather is a native SwiftUI weather app with a Node.js backend API. The
repo doubles as the example project for the Sentry XcodeBuildMCP workshop —
see [`workshop/README.md`](workshop/README.md) for the per-act flow.

## Project structure

```
.
  app/       iOS app (Xcode project; the agent's workspace during the workshop)
  backend/   API server (Hono + Node.js)
  workshop/  Stage branches, patches, switch script, host docs
```

## Workshop flow (host)

```bash
./workshop/switch-stage.sh           # interactive act picker
cd app && claude                     # launch Claude Code rooted in app/
```

Launching Claude from `app/` is the boundary that keeps `backend/` and
`workshop/` invisible to the iOS-side agent. `app/.mcp.json` (managed by the
switch script) registers XcodeBuildMCP; `app/.xcodebuildmcp/config.yaml`
provides session defaults. Acts that hit the real network (3/4/5) get the
backend started automatically by `switch-stage.sh`.

## Backend

Start the API server:

```bash
cd backend
npm install
npm run dev
```

The server runs on `http://localhost:3001` by default. Set `PORT` to change it.

## iOS app

Build and run with XcodeBuildMCP from the `app/` directory:

```bash
cd app
xcodebuildmcp simulator build-and-run
```

### Mock mode

Relaunch with mock data (no backend required):

```bash
xcodebuildmcp simulator launch-app \
  --bundle-id com.sentry.weather.Weather \
  --args=--mock-weather-api
```

### Tests

```bash
xcodebuildmcp simulator test
```

UI tests inject `--mock-weather-api` so they do not depend on the backend.

## API endpoints

The backend serves three `GET` endpoints under `/v1`:

| Purpose | Path | Params |
| --- | --- | --- |
| Default locations | `/v1/locations/default` | None |
| Search locations | `/v1/locations/search` | `?query=<string>` |
| Weather report | `/v1/weather/:locationID` | Path param |

### JSON schemas

Schema files in `backend/schemas/` describe the expected response shapes:

- `default-locations.schema.json`
- `search-locations.schema.json`
- `weather-report.schema.json`

### Test fixtures

Fixture JSON files in `app/WeatherTests/Fixtures/` are used by unit tests.

#!/usr/bin/env bash
# Manage the local Hono backend used by the workshop's iOS app.
# Acts that hit the real network (4, 5) require this; mock-only acts (1, 2, 3) don't.
#
# Subcommands:
#   start    install deps if needed, kill any stale instance, launch `npm run dev` in
#            the background. PID + log path written to .pid / .log under workshop/.
#   stop     kill the tracked PID (and anything still bound to the port).
#   status   print whether the server is up and the /v1/locations/default response.
#   restart  stop then start.
#   ensure   start only if not already healthy. Cheap to call between acts.
#
# The PID file lives at workshop/.backend.pid and the log at workshop/.backend.log so
# the host can `tail -f` it in another pane during the demo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel)"
BACKEND_DIR="${REPO_ROOT}/backend"
PID_FILE="${SCRIPT_DIR}/.backend.pid"
LOG_FILE="${SCRIPT_DIR}/.backend.log"
PORT="${PORT:-3001}"
HEALTH_URL="http://localhost:${PORT}/v1/locations/default"

is_running() {
    if [[ -f "${PID_FILE}" ]]; then
        local pid
        pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

is_healthy() {
    curl -sf --max-time 1 "${HEALTH_URL}" >/dev/null 2>&1
}

wait_for_health() {
    local attempts=30
    while (( attempts-- > 0 )); do
        if is_healthy; then return 0; fi
        sleep 0.25
    done
    return 1
}

kill_pid_file() {
    if [[ -f "${PID_FILE}" ]]; then
        local pid
        pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            # tsx watch spawns a child; kill the whole process group.
            kill -- "-${pid}" 2>/dev/null || kill "${pid}" 2>/dev/null || true
            # Give it a moment to exit cleanly before SIGKILL.
            for _ in 1 2 3 4 5; do
                kill -0 "${pid}" 2>/dev/null || break
                sleep 0.2
            done
            kill -9 -- "-${pid}" 2>/dev/null || kill -9 "${pid}" 2>/dev/null || true
        fi
        rm -f "${PID_FILE}"
    fi
}

kill_port_squatter() {
    # If something else is bound to the port (a previous `npm run dev` without
    # a PID file), evict it so start doesn't immediately exit.
    local pids
    pids="$(lsof -ti tcp:"${PORT}" 2>/dev/null || true)"
    if [[ -n "${pids}" ]]; then
        echo "  evicting existing listener on :${PORT} (pids: ${pids})"
        echo "${pids}" | xargs kill -9 2>/dev/null || true
    fi
}

ensure_deps() {
    if [[ ! -d "${BACKEND_DIR}/node_modules" ]]; then
        echo "  installing backend dependencies (first run)..."
        (cd "${BACKEND_DIR}" && npm install --silent)
    fi
}

cmd_start() {
    if is_running && is_healthy; then
        echo "backend already running and healthy on :${PORT} (pid $(cat "${PID_FILE}"))"
        return 0
    fi
    kill_pid_file
    kill_port_squatter
    ensure_deps

    echo "starting backend on :${PORT}..."
    : > "${LOG_FILE}"
    (
        cd "${BACKEND_DIR}"
        # setsid so we can later kill the whole process group; fall back to plain
        # background if setsid is unavailable.
        if command -v setsid >/dev/null 2>&1; then
            setsid env PORT="${PORT}" npm run dev >>"${LOG_FILE}" 2>&1 &
        else
            env PORT="${PORT}" npm run dev >>"${LOG_FILE}" 2>&1 &
        fi
        echo $! >"${PID_FILE}"
    )

    if wait_for_health; then
        echo "backend up. pid $(cat "${PID_FILE}"), log ${LOG_FILE}"
    else
        echo "error: backend did not become healthy within timeout. tail of log:" >&2
        tail -n 30 "${LOG_FILE}" >&2 || true
        return 1
    fi
}

cmd_stop() {
    if ! is_running && ! is_healthy; then
        echo "backend not running."
        rm -f "${PID_FILE}"
        return 0
    fi
    echo "stopping backend..."
    kill_pid_file
    kill_port_squatter
    echo "stopped."
}

cmd_status() {
    if is_running; then
        echo "tracked pid: $(cat "${PID_FILE}") (alive)"
    else
        echo "tracked pid: none"
    fi
    if is_healthy; then
        echo "health: OK (${HEALTH_URL})"
        echo "sample response (first location):"
        curl -s "${HEALTH_URL}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("  "+json.dumps(d["locations"][0], indent=2).replace("\n","\n  "))' 2>/dev/null || true
    else
        echo "health: DOWN"
    fi
}

cmd_restart() {
    cmd_stop
    cmd_start
}

cmd_ensure() {
    if is_running && is_healthy; then
        return 0
    fi
    cmd_start
}

case "${1:-status}" in
    start)    cmd_start ;;
    stop)     cmd_stop ;;
    status)   cmd_status ;;
    restart)  cmd_restart ;;
    ensure)   cmd_ensure ;;
    *)
        echo "usage: $0 {start|stop|status|restart|ensure}" >&2
        exit 2
        ;;
esac

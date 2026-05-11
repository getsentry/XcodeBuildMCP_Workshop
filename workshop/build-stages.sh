#!/usr/bin/env bash
# Recreate workshop stage branches from patches.
# Idempotent: deletes and recreates each stage branch from main + the matching
# patch. Switches with git switch; bails out cleanly if the working tree is
# dirty or a previous git am stalled. Runs from any cwd inside the repo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

PATCHES_DIR="workshop/patches"
ANCHOR="main"

if ! git rev-parse --verify "${ANCHOR}" >/dev/null 2>&1; then
    echo "error: branch ${ANCHOR} does not exist." >&2
    exit 1
fi

if [[ -d .git/rebase-apply || -d .git/rebase-merge ]]; then
    echo "error: in-progress rebase or git am detected." >&2
    echo "run 'git am --abort' or 'git rebase --abort' before retrying." >&2
    exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "error: working tree dirty. Commit or stash before running." >&2
    git status --short >&2
    exit 1
fi

stages=(
    "1-setup-start"
    "2-build-run-clean"
    "3-feature-start"
    "3-feature-done"
    "4-bug-planted"
    "4-bug-fixed"
    "5-canonical"
)

# Park on the anchor so we can freely delete stage branches.
git switch "${ANCHOR}"

for stage in "${stages[@]}"; do
    branch="stage/${stage}"
    patch="${PATCHES_DIR}/${stage}.patch"
    git switch "${ANCHOR}"
    git branch -D "${branch}" 2>/dev/null || true
    if [[ ! -f "${patch}" ]]; then
        # 4-bug-fixed is intentionally byte-identical to main (the fix lives on
        # main already), so format-patch yields nothing. Create the branch
        # anyway so switch-stage.sh's 4-done lookup resolves cleanly.
        echo "=== creating ${branch} = ${ANCHOR} (no patch — fix already on main) ==="
        git switch -c "${branch}" "${ANCHOR}"
        continue
    fi
    echo "=== rebuilding ${branch} from ${patch} ==="
    git switch -c "${branch}" "${ANCHOR}"
    if ! git am "${patch}"; then
        echo "error: failed to apply ${patch}." >&2
        git am --abort 2>/dev/null || true
        git switch "${ANCHOR}"
        exit 1
    fi
done

git switch "${ANCHOR}"
echo "done. all stage branches rebuilt from ${PATCHES_DIR}/"

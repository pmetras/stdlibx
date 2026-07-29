#!/usr/bin/env bash
#
# deploy.sh - Export the 4 fossil sub-projects (bitsx, formatx, mathx, stdlibx)
# to git and publish them to GitHub under the pmetras account.
#
# Usage: ./deploy.sh
#
# Requires: fossil, git, a configured GitHub remote access
# (SSH key) for git@github.com:pmetras/<project>.git

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECTS=(bitsx formatx mathx stdlibx)
GITHUB_USER="pmetras"
WORK_DIR="$(mktemp -d /tmp/stdlibx-deploy.XXXXXX)"

log() {
    printf '\n=== %s ===\n' "$1"
}

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command '$1' not found in PATH"
}

require_command fossil
require_command git
#require_command git-filter-repo

log "Checking fossil working trees are clean"
for project in "${PROJECTS[@]}"; do
    project_dir="$ROOT_DIR/$project"
    [ -d "$project_dir" ] || fail "project directory not found: $project_dir"

    status="$(cd "$project_dir" && fossil status)"
    if printf '%s\n' "$status" | grep -qE '^(EDITED|ADDED|DELETED|MISSING|CONFLICT|RENAMED)'; then
        printf '%s\n' "$status" >&2
        fail "$project has uncommitted changes; commit or stash them before deploying"
    fi
    echo "$project: clean"
done

log "Exporting fossil repositories to git"
for project in "${PROJECTS[@]}"; do
    project_dir="$ROOT_DIR/$project"
    export_file="$WORK_DIR/$project.fastexport"
    git_dir="$WORK_DIR/$project"

    echo "Exporting $project..."
    (cd "$project_dir" && fossil export --git) > "$export_file"

    mkdir "$git_dir"
    (
        cd "$git_dir"
        git init -q
        git fast-import --quiet < "$export_file"
        git checkout -q main 2>/dev/null || git branch -m trunk main
        git checkout -q main
    )
done

log "Adding project-wide README to stdlibx"
cp "$ROOT_DIR/README.md" "$WORK_DIR/stdlibx/README.md"
(
    cd "$WORK_DIR/stdlibx"
    git add README.md
    git commit -q -m "Add project-wide README with GitHub repository links"
)
log "Adding deploy.sh to stdlibx"
cp -p "$ROOT_DIR/deploy.sh" "$WORK_DIR/stdlibx/deploy.sh"
(
    cd "$WORK_DIR/stdlibx"
    git add deploy.sh
    git commit -q -m "Add deploy.sh"
)

log "Verifying symlinks survived the export"
for project in "${PROJECTS[@]}"; do
    git_dir="$WORK_DIR/$project"
    symlink_count=$(find "$git_dir" -type l | wc -l)
    echo "$project: $symlink_count symlink(s) found"
done

log "Running make unit-tests on exported clones"
for project in "${PROJECTS[@]}"; do
    git_dir="$WORK_DIR/$project"
    echo "Testing $project..."
    (cd "$git_dir" && make unit-tests) || fail "make unit-tests failed for $project (see $git_dir)"
done

log "Pushing to GitHub"
for project in "${PROJECTS[@]}"; do
    git_dir="$WORK_DIR/$project"
    (
        cd "$git_dir"
        git remote add origin "git@github.com:$GITHUB_USER/$project.git" 2>/dev/null || \
            git remote set-url origin "git@github.com:$GITHUB_USER/$project.git"
        git push --force -u origin main
    )
    echo "$project pushed to git@github.com:$GITHUB_USER/$project.git"
done

log "Done"
echo "Working directory kept at: $WORK_DIR"
echo "Remove it manually once you've verified the push: rm -rf '$WORK_DIR'"

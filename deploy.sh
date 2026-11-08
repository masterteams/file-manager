#!/usr/bin/env bash
# Lifecycle helper for running this fork on the local machine while it is developed.
#
#   ./deploy.sh start [debug|permanent] | stop | restart [mode] | status
#   ./deploy.sh build | push | pull | logs [-f]
#
# Modes:
#   debug      (default) Tauri dev + Vite HMR. Edits show up live. Data in the debug data dir.
#   permanent  Release build installed under ~/.local/opt and run as a normal app, with the
#              app's standard XDG data dirs and single-instance enabled.
#              Refresh it after finishing a feature with: ./deploy.sh build
#
# Linux only (the app itself stays cross-platform; use `npm run tauri:dev` elsewhere).
# No sudo is needed or used. Never run it as root.

set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRANCH="development"
REMOTE="origin"
EXPECTED_GH_USER="masterteams"
VITE_PORT=1420

DEV_DATA="${SFM_DEV_DATA_DIR:-$HOME/.local/share/masterteams-file-manager-dev}"
RUN_DIR="$DEV_DATA/run"
PID_FILE="$RUN_DIR/app.pid"
LOG_FILE="$RUN_DIR/app.log"
MODE_FILE="$RUN_DIR/mode"

INSTALL_DIR="$HOME/.local/opt/masterteams-file-manager"
INSTALLED_BIN="$INSTALL_DIR/sigma-file-manager"
RELEASE_BIN="$PROJECT/src-tauri/target/release/sigma-file-manager"

log() { printf '[deploy] %s\n' "$*"; }
die() { printf '[deploy] ERROR: %s\n' "$*" >&2; exit 1; }

cd "$PROJECT"

[[ "$(uname -s)" == "Linux" ]] || die "deploy.sh supports Linux only; use 'npm run tauri:dev' on other platforms"
[[ $EUID -ne 0 ]] || die "do not run as root"
[[ -f package.json ]] || die "package.json not found in $PROJECT"

# ---------- helpers ----------

required_node_version() {
  node -p "require('./package.json').volta.node" 2>/dev/null || echo "24.16.0"
}

# Put the Node version pinned in package.json (volta.node) on PATH.
use_pinned_node() {
  local want node_dir have
  want="$(required_node_version)"
  node_dir="$HOME/.nvm/versions/node/v$want/bin"
  if [[ -x "$node_dir/node" ]]; then
    export PATH="$node_dir:$PATH"
  fi
  have="$(node --version | sed 's/^v//')"
  if [[ "$have" != "$want" ]]; then
    log "warning: Node $have in use, package.json pins $want (install with: nvm install $want)"
  fi
}

current_branch() { git rev-parse --abbrev-ref HEAD; }

require_branch() {
  local branch
  branch="$(current_branch)"
  [[ "$branch" == "$BRANCH" ]] \
    || die "on branch '$branch', expected '$BRANCH'. Not switching branches automatically."
}

pid_alive() {
  [[ -f "$PID_FILE" ]] || return 1
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

current_mode() { cat "$MODE_FILE" 2>/dev/null || echo "-"; }

port_in_use() { ss -ltn "( sport = :$VITE_PORT )" 2>/dev/null | grep -q LISTEN; }

wait_for() { # wait_for <seconds> <command...>
  local seconds="$1"; shift
  local i
  for ((i = 0; i < seconds * 2; i++)); do
    if "$@"; then return 0; fi
    sleep 0.5
  done
  return 1
}

# Reinstall dependencies only when the lockfile changed since the last install.
ensure_dependencies() {
  local installed="node_modules/.package-lock.json"
  if [[ ! -d node_modules || ! -f "$installed" || package-lock.json -nt "$installed" ]]; then
    log "installing dependencies (npm ci)"
    npm ci
  fi
}

# launch <mode> <command...>: run detached in its own session/process group so stop can
# kill the whole tree. exec keeps $$ as the group leader.
launch() {
  local mode="$1"; shift
  mkdir -p "$RUN_DIR"
  chmod 700 "$DEV_DATA"
  : > "$LOG_FILE"
  echo "$mode" > "$MODE_FILE"
  setsid bash -c 'echo $$ > "$1"; shift; exec "$@"' _ "$PID_FILE" "$@" \
    >> "$LOG_FILE" 2>&1 < /dev/null &
  disown
}

# ---------- commands ----------

cmd_build() {
  require_branch
  use_pinned_node
  command -v cargo >/dev/null || die "cargo not found"
  ensure_dependencies
  log "building release binary (the first build takes several minutes)"
  npm run tauri:build:linux -- --no-bundle
  [[ -x "$RELEASE_BIN" ]] || die "release binary not found: $RELEASE_BIN"
  mkdir -p "$INSTALL_DIR"
  # Copy to a temp name then rename, so a running copy is never overwritten in place.
  install -m 755 "$RELEASE_BIN" "$INSTALLED_BIN.new"
  mv -f "$INSTALLED_BIN.new" "$INSTALLED_BIN"
  log "installed: $INSTALLED_BIN"
  if pid_alive && [[ "$(current_mode)" == "permanent" ]]; then
    log "the running permanent app still uses the old build; apply with: ./deploy.sh restart permanent"
  fi
}

cmd_start() {
  local mode="${1:-debug}"
  require_branch
  if pid_alive; then
    log "already running in $(current_mode) mode (pid $(cat "$PID_FILE")). Use restart."
    return 0
  fi

  case "$mode" in
    debug)
      if port_in_use; then
        die "port $VITE_PORT is in use by another process (stale Vite?). Check: ss -ltnp 'sport = :$VITE_PORT'"
      fi
      use_pinned_node
      command -v cargo >/dev/null || die "cargo not found"
      ensure_dependencies
      # SFM_E2E_DATA_DIR keeps debug data separate from the permanent install (debug builds
      # only; it also disables single-instance, so run one debug instance per data dir).
      export SFM_E2E_DATA_DIR="$DEV_DATA"
      export WEBKIT_DISABLE_COMPOSITING_MODE=1
      launch debug npm run tauri:dev:webkit-igpu
      log "starting debug mode (log: $LOG_FILE)"
      if wait_for 60 port_in_use; then
        log "Vite is up on 127.0.0.1:$VITE_PORT. The first Rust build can take minutes; follow with: ./deploy.sh logs -f"
      else
        log "Vite did not come up within 60s. Last log lines:"
        tail -n 20 "$LOG_FILE" || true
        pid_alive || die "process exited during startup"
      fi
      ;;
    permanent)
      [[ -x "$INSTALLED_BIN" ]] || die "no installed build. Run: ./deploy.sh build"
      export WEBKIT_DISABLE_COMPOSITING_MODE=1
      launch permanent "$INSTALLED_BIN"
      log "starting permanent mode (log: $LOG_FILE)"
      sleep 2
      pid_alive || { tail -n 20 "$LOG_FILE" || true; die "process exited during startup"; }
      ;;
    *) die "unknown mode '$mode' (use debug or permanent)" ;;
  esac
}

cmd_stop() {
  if ! pid_alive; then
    log "not running"
    rm -f "$PID_FILE" "$MODE_FILE"
    return 0
  fi
  local pid
  pid="$(cat "$PID_FILE")"
  log "stopping $(current_mode) mode (process group $pid)"
  kill -TERM -- "-$pid" 2>/dev/null || true
  if ! wait_for 15 bash -c "! kill -0 $pid 2>/dev/null"; then
    log "did not exit in 15s, sending SIGKILL"
    kill -KILL -- "-$pid" 2>/dev/null || true
  fi
  rm -f "$PID_FILE" "$MODE_FILE"
  if port_in_use; then
    log "warning: port $VITE_PORT is still in use by a process outside this script's group"
  else
    log "stopped"
  fi
}

cmd_restart() {
  local mode="${1:-$(current_mode)}"
  [[ "$mode" == "-" ]] && mode="debug"
  cmd_stop
  cmd_start "$mode"
}

cmd_status() {
  use_pinned_node
  if pid_alive; then
    log "app: RUNNING in $(current_mode) mode (pid $(cat "$PID_FILE"))"
  else
    log "app: STOPPED"
  fi
  if port_in_use; then log "vite port $VITE_PORT: listening"; else log "vite port $VITE_PORT: free"; fi
  if [[ -x "$INSTALLED_BIN" ]]; then
    log "permanent build installed: $INSTALLED_BIN ($(date -r "$INSTALLED_BIN" '+%F %T'))"
  else
    log "permanent build: not installed (./deploy.sh build)"
  fi
  log "debug data dir: $DEV_DATA"
  log "log file: $LOG_FILE"
  log "node: $(node --version) (pinned: $(required_node_version))"
  log "branch: $(current_branch) (expected: $BRANCH)"

  local dirty
  dirty="$(git status --porcelain | wc -l)"
  log "uncommitted changes: $dirty"

  if git rev-parse --verify -q "$REMOTE/$BRANCH" >/dev/null; then
    local ahead behind
    read -r behind ahead < <(git rev-list --left-right --count "$REMOTE/$BRANCH...HEAD")
    log "vs $REMOTE/$BRANCH: ahead $ahead, behind $behind (as of last fetch)"
  else
    log "$REMOTE/$BRANCH not found; push has not happened yet"
  fi

  local user
  user="$(gh api user --jq .login 2>/dev/null || echo unknown)"
  log "gh active account: $user (push requires $EXPECTED_GH_USER)"
}

cmd_logs() {
  [[ -f "$LOG_FILE" ]] || die "no log yet: $LOG_FILE"
  # arboard prints one Wayland data-control warning per clipboard poll; hide that noise.
  local noise='arboard::platform::linux.*wayland data control'
  if [[ "${1:-}" == "-f" ]]; then
    tail -n 50 -f "$LOG_FILE" | grep --line-buffered -Ev "$noise"
  else
    grep -Ev "$noise" "$LOG_FILE" | tail -n 100
  fi
}

cmd_push() {
  require_branch
  command -v gh >/dev/null || die "gh CLI not installed"
  local user
  user="$(gh api user --jq .login 2>/dev/null)" || die "gh is not authenticated"
  [[ "$user" == "$EXPECTED_GH_USER" ]] \
    || die "gh active account is '$user', need '$EXPECTED_GH_USER'. Run: gh auth switch --hostname github.com --user $EXPECTED_GH_USER"

  if [[ -n "$(git status --porcelain)" ]]; then
    log "note: uncommitted changes are NOT pushed (only commits):"
    git status --short
  fi

  log "commits to push:"
  git log --oneline "$REMOTE/$BRANCH..HEAD" 2>/dev/null || git log --oneline -5

  # Use gh's credentials for this one command only, so other stored accounts
  # (e.g. pay24-dev) cannot be picked up and cause a 403.
  git -c credential.helper= \
      -c 'credential.helper=!gh auth git-credential' \
      push -u "$REMOTE" "$BRANCH"
}

cmd_pull() {
  require_branch
  if [[ -n "$(git status --porcelain)" ]]; then
    die "uncommitted changes present. Commit or stash them first (pull is fast-forward only)."
  fi
  local before_lock after_lock
  before_lock="$(git rev-parse HEAD:package-lock.json)"
  git fetch --prune "$REMOTE"
  git pull --ff-only "$REMOTE" "$BRANCH"
  after_lock="$(git rev-parse HEAD:package-lock.json)"

  if [[ "$before_lock" != "$after_lock" ]]; then
    use_pinned_node
    log "package-lock.json changed, reinstalling dependencies"
    npm ci
  fi
  if pid_alive; then
    case "$(current_mode)" in
      debug) log "debug app is running: Vue/CSS hot-reload, Rust rebuilds automatically. If it looks stale: ./deploy.sh restart" ;;
      permanent) log "permanent app keeps the old build; refresh with: ./deploy.sh build && ./deploy.sh restart permanent" ;;
    esac
  fi
}

usage() {
  cat <<EOF
Usage: ./deploy.sh <command>

  start [mode]    start the app in the background; mode = debug (default) | permanent
  stop            stop the whole process tree
  restart [mode]  stop, then start (keeps the current mode unless given)
  status          mode, process, port, installed build, node, branch, ahead/behind, gh account
  build           release build, installed to $INSTALL_DIR (for permanent mode)
  push            git push of $BRANCH to $REMOTE using the $EXPECTED_GH_USER gh account
  pull            fast-forward $BRANCH from $REMOTE (reinstalls deps if the lockfile changed)
  logs [-f]       show (or follow) the log with Wayland clipboard noise filtered out
EOF
}

case "${1:-}" in
  start)   shift; cmd_start "${1:-debug}" ;;
  stop)    cmd_stop ;;
  restart) shift; cmd_restart "${1:-}" ;;
  status)  cmd_status ;;
  build)   cmd_build ;;
  push)    cmd_push ;;
  pull)    cmd_pull ;;
  logs)    shift; cmd_logs "${1:-}" ;;
  -h|--help|help|"") usage ;;
  *) usage; exit 1 ;;
esac

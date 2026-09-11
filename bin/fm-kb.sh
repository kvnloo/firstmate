#!/usr/bin/env bash
# fm-kb.sh - bounded frontier-kb search and put for firstmate homes.
#
# Usage:
#   fm-kb.sh search --q <query> [--limit <n>]
#   fm-kb.sh put --id <id> --path <path> --title <title> --type <type> [--status <status>] [--body <text>] [--cas <n>]
#   fm-kb.sh status
#   fm-kb.sh --help
#
# Sources the operator frontier-kb env file without printing secrets.
# Requires FRONTIER_KB_DSN or DATABASE_URL after sourcing.
# KB_WRITER defaults per home when unset in the env file; see docs/configuration.md
# "Frontier knowledge base".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_HOME="${FM_HOME:-$(cd "$SCRIPT_DIR/.." && pwd)}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
KB_ENV_FILE="${FRONTIER_KB_ENV_FILE:-${FM_KB_ENV_FILE:-$HOME/.config/frontier-kb/env}}"

usage() {
  cat <<'EOF'
Usage:
  fm-kb.sh search --q <query> [--limit <n>]
  fm-kb.sh put --id <id> --path <path> --title <title> --type <type> [--status <status>] [--body <text>] [--cas <n>]
  fm-kb.sh status
  fm-kb.sh --help

Sources ~/.config/frontier-kb/env (override with FRONTIER_KB_ENV_FILE or FM_KB_ENV_FILE).
Never prints the database DSN. Refuses when the env file or DSN is missing.
EOF
}

fm_kb_load_env_file() {
  local file=$1 line key val
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in
      ''|\#*) continue ;;
      export\ *) line="${line#export }" ;;
    esac
    case "$line" in
      *=*) ;;
      *) continue ;;
    esac
    key="${line%%=*}"
    key="${key#"${key%%[![:space:]]*}"}"
    val="${line#*=}"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    case "$val" in
      \"*\") val=${val#\"}; val=${val%\"} ;;
      \'*\') val=${val#\'}; val=${val%\'} ;;
    esac
    if [ -n "$key" ] && [ -z "${!key:-}" ]; then
      export "$key=$val"
    fi
  done < "$file"
}

fm_kb_source_env() {
  if [ ! -f "$KB_ENV_FILE" ]; then
    echo "fm-kb: missing frontier-kb env file: $KB_ENV_FILE" >&2
    echo "fm-kb: create it with FRONTIER_KB_DSN (never commit or paste the DSN)" >&2
    return 1
  fi
  fm_kb_load_env_file "$KB_ENV_FILE"
}

fm_kb_require_dsn() {
  if [ -z "${FRONTIER_KB_DSN:-}" ] && [ -z "${DATABASE_URL:-}" ]; then
    echo "fm-kb: missing FRONTIER_KB_DSN or DATABASE_URL after sourcing $KB_ENV_FILE" >&2
    return 1
  fi
}

fm_kb_resolve_writer() {
  local writer_file host
  if [ -n "${KB_WRITER:-}" ]; then
    return 0
  fi
  writer_file="$CONFIG/kb-writer"
  if [ -f "$writer_file" ]; then
    IFS= read -r KB_WRITER <"$writer_file" || KB_WRITER=
    KB_WRITER="${KB_WRITER//$'\r'/}"
    KB_WRITER="${KB_WRITER#"${KB_WRITER%%[![:space:]]*}"}"
    KB_WRITER="${KB_WRITER%"${KB_WRITER##*[![:space:]]}"}"
  fi
  if [ -z "${KB_WRITER:-}" ]; then
    host=$(hostname -s 2>/dev/null || hostname)
    host=$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9.-' '-')
    KB_WRITER="firstmate-$host"
  fi
  export KB_WRITER
}

fm_kb_resolve_root() {
  local candidate
  KB_ROOT="${FRONTIER_KB_ROOT:-${FM_KB_ROOT:-}}"
  if [ -z "$KB_ROOT" ] && [ -f "$CONFIG/kb-root" ]; then
    IFS= read -r KB_ROOT <"$CONFIG/kb-root" || KB_ROOT=
    KB_ROOT="${KB_ROOT//$'\r'/}"
    KB_ROOT="${KB_ROOT#"${KB_ROOT%%[![:space:]]*}"}"
    KB_ROOT="${KB_ROOT%"${KB_ROOT##*[![:space:]]}"}"
  fi
  if [ -z "$KB_ROOT" ]; then
    for candidate in "$HOME/workspace/frontier-kb" "$HOME/frontier-kb"; do
      if [ -f "$candidate/scripts/kb_store.py" ]; then
        KB_ROOT=$candidate
        break
      fi
    done
  fi
  if [ -z "$KB_ROOT" ] || [ ! -f "$KB_ROOT/scripts/kb_store.py" ]; then
    echo "fm-kb: frontier-kb checkout not found; set config/kb-root or FRONTIER_KB_ROOT" >&2
    return 1
  fi
}

fm_kb_python() {
  local venv_py="$KB_ROOT/.venv/bin/python"
  if [ -x "$venv_py" ]; then
    printf '%s\n' "$venv_py"
    return 0
  fi
  command -v python3
}

fm_kb_store() {
  local py
  py=$(fm_kb_python) || {
    echo "fm-kb: python3 required" >&2
    return 1
  }
  [ -n "$py" ] || {
    echo "fm-kb: python3 required" >&2
    return 1
  }
  KB_STORE="$KB_ROOT/scripts/kb_store.py"
  KB_WRITER="$KB_WRITER" "$py" "$KB_STORE" "$@"
}

fm_kb_status() {
  fm_kb_source_env || return 1
  fm_kb_require_dsn || return 1
  fm_kb_resolve_writer
  fm_kb_resolve_root || return 1
  printf 'kb env: %s\n' "$KB_ENV_FILE"
  printf 'kb root: %s\n' "$KB_ROOT"
  printf 'kb writer: %s\n' "$KB_WRITER"
  printf 'kb dsn: configured\n'
}

cmd=${1:-}
case "$cmd" in
  -h|--help|help)
    usage
    exit 0
    ;;
  status)
    fm_kb_status
    ;;
  search)
    shift
    fm_kb_source_env || exit 1
    fm_kb_require_dsn || exit 1
    fm_kb_resolve_writer
    fm_kb_resolve_root || exit 1
    fm_kb_store search "$@"
    ;;
  put)
    shift
    fm_kb_source_env || exit 1
    fm_kb_require_dsn || exit 1
    fm_kb_resolve_writer
    fm_kb_resolve_root || exit 1
    fm_kb_store put "$@"
    ;;
  '')
    usage >&2
    exit 1
    ;;
  *)
    echo "fm-kb: unknown subcommand: $cmd" >&2
    usage >&2
    exit 1
    ;;
esac

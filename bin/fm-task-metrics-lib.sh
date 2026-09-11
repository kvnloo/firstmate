# shellcheck shell=bash
# Default-off opt-in for automatic per-task metrics emission at guarded teardown.
#
# Usage: . bin/fm-task-metrics-lib.sh
#
# Enablement (see docs/configuration.md):
#   config/task-metrics   presence flag under the home config dir enables
#                         automatic prepare/commit during teardown.
#   FM_TASK_METRICS       env override: 1/on/true/yes enables, any other
#                         non-empty value disables, and unset or empty defers
#                         to the file.
#
# Home-local gitignored storage under data/ is not consent by itself.
# Manual `bin/fm-task-metrics.sh emit` is always available to the operator and
# does not consult this gate.

fm_task_metrics_enabled() {  # <config-dir>
  local config_dir=$1 v
  if [ -n "${FM_TASK_METRICS:-}" ]; then
    v=$(printf '%s' "$FM_TASK_METRICS" | tr '[:upper:]' '[:lower:]')
    case "$v" in
      1 | on | true | yes) return 0 ;;
      *) return 1 ;;
    esac
  fi
  [ -f "$config_dir/task-metrics" ]
}

#!/usr/bin/env bash
# Behavior tests for bin/fm-kb.sh.
#
# These tests exercise configuration, writer defaults, delegation to kb_store.py,
# and the refusal to print secrets. They never contact a real Postgres database.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

KB="$ROOT/bin/fm-kb.sh"
TMP_ROOT=$(fm_test_tmproot fm-kb)
HOME_DIR="$TMP_ROOT/home"
CONFIG_DIR="$HOME_DIR/config"
KB_ROOT="$TMP_ROOT/frontier-kb"
FAKEBIN=$(fm_fakebin "$TMP_ROOT")
mkdir -p "$HOME_DIR" "$CONFIG_DIR" "$KB_ROOT/scripts"

cat > "$KB_ROOT/scripts/kb_store.py" <<'PY'
#!/usr/bin/env python3
import json
import os
import sys

cmd = sys.argv[1] if len(sys.argv) > 1 else ""
writer = os.environ.get("KB_WRITER", "")
if cmd == "search":
    print(json.dumps([{"id": "stub", "writer": writer, "argv": sys.argv[2:]}]))
elif cmd == "put":
    print(json.dumps({"ok": True, "writer": writer, "argv": sys.argv[2:]}))
else:
    print(json.dumps({"ok": False, "error": "unknown", "cmd": cmd}))
    sys.exit(2)
PY
chmod +x "$KB_ROOT/scripts/kb_store.py"

write_env() {
  local file=$1
  mkdir -p "$(dirname "$file")"
  cat >"$file" <<'EOF'
FRONTIER_KB_DSN=postgresql://frontier:secret-pass@127.0.0.1:55432/frontier_kb
EOF
}

run_kb() {
  env -u FRONTIER_KB_DSN -u DATABASE_URL -u KB_WRITER \
    HOME="$TMP_ROOT/fakehome" \
    FM_HOME="$HOME_DIR" \
    FM_CONFIG_OVERRIDE="$CONFIG_DIR" \
    FRONTIER_KB_ENV_FILE="$TMP_ROOT/frontier-kb.env" \
    FRONTIER_KB_ROOT="$KB_ROOT" \
    PATH="$FAKEBIN:$PATH" \
    "$KB" "$@"
}

test_missing_env_fails_closed() {
  local rc err
  rm -f "$TMP_ROOT/frontier-kb.env"
  run_kb status >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" || rc=$?
  rc=${rc:-0}
  err=$(cat "$TMP_ROOT/err")
  expect_code 1 "$rc" "status without env file must fail"
  assert_contains "$err" "missing frontier-kb env file" "missing-env error names the env file"
  assert_not_contains "$err" "secret-pass" "missing-env error never leaks the DSN"
  pass "fm-kb: missing env file fails closed"
}

test_missing_dsn_fails_closed() {
  local rc err
  mkdir -p "$(dirname "$TMP_ROOT/frontier-kb.env")"
  printf '%s\n' '# no dsn here' >"$TMP_ROOT/frontier-kb.env"
  run_kb status >"$TMP_ROOT/out" 2>"$TMP_ROOT/err" || rc=$?
  rc=${rc:-0}
  err=$(cat "$TMP_ROOT/err")
  expect_code 1 "$rc" "status without DSN must fail"
  assert_contains "$err" "FRONTIER_KB_DSN" "missing-dsn error names the required variable family"
  assert_not_contains "$err" "postgresql://" "missing-dsn error never prints a DSN"
  pass "fm-kb: missing DSN fails closed"
}

test_status_never_prints_dsn() {
  local out
  write_env "$TMP_ROOT/frontier-kb.env"
  out=$(run_kb status 2>&1)
  assert_contains "$out" "kb writer:" "status prints the writer"
  assert_contains "$out" "kb dsn: configured" "status reports DSN presence abstractly"
  assert_not_contains "$out" "secret-pass" "status never prints the password"
  assert_not_contains "$out" "postgresql://" "status never prints the DSN"
  pass "fm-kb: status never prints secrets"
}

test_writer_defaults_with_firstmate_prefix() {
  local out
  write_env "$TMP_ROOT/frontier-kb.env"
  out=$(run_kb status 2>&1)
  assert_contains "$out" "kb writer: firstmate-" "writer defaults to firstmate-<hostname>"
  pass "fm-kb: writer defaults from hostname"
}

test_writer_from_config_file() {
  local out
  write_env "$TMP_ROOT/frontier-kb.env"
  printf '%s\n' 'firstmate-kernel-mbp' >"$CONFIG_DIR/kb-writer"
  out=$(run_kb status 2>&1)
  assert_contains "$out" "kb writer: firstmate-kernel-mbp" "config/kb-writer overrides the default"
  pass "fm-kb: config/kb-writer supplies the writer"
}

test_search_delegates_to_kb_store() {
  local out rc
  write_env "$TMP_ROOT/frontier-kb.env"
  out=$(run_kb search --q 'SWE-2' --limit 3 2>&1) || rc=$?
  rc=${rc:-0}
  expect_code 0 "$rc" "search must succeed against the stub store"
  assert_contains "$out" '"id": "stub"' "search returns stub JSON"
  assert_contains "$out" 'firstmate-' "search passes the resolved writer through the environment"
  assert_contains "$out" '--q' "search forwards query arguments"
  pass "fm-kb: search delegates to kb_store.py"
}

test_put_delegates_to_kb_store() {
  local out rc
  write_env "$TMP_ROOT/frontier-kb.env"
  out=$(run_kb put --id lit-test --path literature/lit-test.md --title 'Test' --type literature --body 'hello' 2>&1) || rc=$?
  rc=${rc:-0}
  expect_code 0 "$rc" "put must succeed against the stub store"
  assert_contains "$out" '"ok": true' "put returns stub success JSON"
  assert_contains "$out" '--id' "put forwards id arguments"
  pass "fm-kb: put delegates to kb_store.py"
}

test_help_lists_subcommands() {
  local out rc
  out=$(run_kb --help 2>&1) || rc=$?
  rc=${rc:-0}
  expect_code 0 "$rc" "--help must exit 0"
  assert_contains "$out" "search" "--help lists search"
  assert_contains "$out" "put" "--help lists put"
  assert_contains "$out" "status" "--help lists status"
  pass "fm-kb: --help lists every subcommand"
}

test_missing_env_fails_closed
test_missing_dsn_fails_closed
test_status_never_prints_dsn
test_writer_defaults_with_firstmate_prefix
test_writer_from_config_file
test_search_delegates_to_kb_store
test_put_delegates_to_kb_store
test_help_lists_subcommands

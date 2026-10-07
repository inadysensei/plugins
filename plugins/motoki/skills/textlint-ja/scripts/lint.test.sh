#!/usr/bin/env bash
# textlint-ja の lint.sh を、ネットワークと実パッケージ無しで検査する。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$ROOT/scripts/lint.sh"
STAMP="$ROOT/scripts/runtime-package.json"
failed=0

run_case() {
  local name="$1"
  shift
  local status=0
  # if の条件として実行すると set -e が無効になり、途中の失敗が消える。
  set +e
  ( set -euo pipefail; "$@" )
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    printf 'ok - %s\n' "$name"
  else
    printf 'not ok - %s\n' "$name" >&2
    failed=1
  fi
}

test_lint_sh_syntax() {
  bash -n "$LINT"
}

test_runtime_package_uses_latest() {
  node "$ROOT/scripts/check-latest-spec.js" "$STAMP" >/dev/null
}

assert_viewed_every_dependency() {
  local name
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    grep -q -F "npm view ${name} version" "$LOG"
  done < <(node "$ROOT/scripts/check-latest-spec.js" "$STAMP")
}

dependency_count() {
  node -p 'Object.keys(require(process.argv[1]).dependencies || {}).length' "$STAMP"
}

line_no() {
  local file="$1"
  local pattern="$2"
  local which="${3:-head}"
  grep -n "$pattern" "$file" | "$which" -1 | cut -d: -f1
}

prepare_case() {
  WORK="$(mktemp -d)"
  BIN="$WORK/bin"
  CACHE="$WORK/cache"
  LOG="$WORK/calls.log"
  mkdir -p "$BIN"
  : > "$LOG"
  cat > "$BIN/npm" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "npm $*" >> "$CALL_LOG"
cmd="${1:-}"
case "$cmd" in
  view)
    if [[ "${NPM_VIEW_FAIL:-0}" == "1" ]]; then
      exit 1
    fi
    printf '%s\n' "${NPM_VIEW_VERSION:-1.2.3}"
    ;;
  install)
    if [[ "$(pwd)" != "$TEXTLINT_JA_HOME" ]]; then
      printf 'npm install の作業ディレクトリがキャッシュではありません: %s\n' "$(pwd)" >&2
      exit 99
    fi
    node << 'NODE'
const fs = require("fs");
const path = require("path");
const version = process.env.NPM_VIEW_VERSION || "1.2.3";
const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
for (const name of Object.keys(pkg.dependencies || {})) {
  const dir = path.join("node_modules", name);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "package.json"), JSON.stringify({ name, version }) + "\n");
}
NODE
    mkdir -p node_modules/.bin
    cat > node_modules/.bin/textlint << 'SHIM'
#!/usr/bin/env bash
printf '%s\n' "textlint $*" >> "$CALL_LOG"
exit 0
SHIM
    chmod +x node_modules/.bin/textlint
    ;;
  update)
    if [[ "$(pwd)" != "$TEXTLINT_JA_HOME" ]]; then
      printf 'npm update の作業ディレクトリがキャッシュではありません: %s\n' "$(pwd)" >&2
      exit 99
    fi
    if [[ "${NPM_UPDATE_FAIL:-0}" == "1" ]]; then
      exit 1
    fi
    ;;
  *)
    printf 'unexpected npm command: %s\n' "$*" >&2
    exit 99
    ;;
esac
EOF
  chmod +x "$BIN/npm"
  printf '本文です。\n' > "$WORK/sample.md"
  export CALL_LOG="$LOG"
  export PATH="$BIN:${PATH}"
  export TEXTLINT_JA_HOME="$CACHE"
  unset NPM_VIEW_FAIL || true
  unset NPM_UPDATE_FAIL || true
  export NPM_VIEW_VERSION="${NPM_VIEW_VERSION:-1.2.3}"
}

finish_case() {
  local status=$?
  if [[ -n "${WORK:-}" ]]; then
    rm -rf "$WORK"
  fi
  exit "$status"
}

preseed_cache() {
  local version="$1"
  mkdir -p "$CACHE"
  cp "$STAMP" "$CACHE/package.json"
  node -e '
    const fs = require("fs");
    const path = require("path");
    const version = process.argv[1];
    const cache = process.argv[2];
    const stamp = process.argv[3];
    const pkg = JSON.parse(fs.readFileSync(stamp, "utf8"));
    for (const name of Object.keys(pkg.dependencies || {})) {
      const dir = path.join(cache, "node_modules", name);
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, "package.json"), JSON.stringify({ name, version }) + "\n");
    }
  ' "$version" "$CACHE" "$STAMP"
  mkdir -p "$CACHE/node_modules/.bin"
  cat > "$CACHE/node_modules/.bin/textlint" << 'SHIM'
#!/usr/bin/env bash
printf '%s\n' "textlint $*" >> "$CALL_LOG"
exit 0
SHIM
  chmod +x "$CACHE/node_modules/.bin/textlint"
}

run_lint() {
  (
    cd "$WORK"
    bash "$LINT" "$WORK/sample.md"
  )
}

test_updates_before_textlint_when_stale() {
  prepare_case
  trap finish_case RETURN
  preseed_cache "0.0.0"
  export NPM_VIEW_VERSION="9.9.9"
  run_lint
  local views last_view update_line textlint_line expected
  expected="$(dependency_count)"
  views="$(grep -c '^npm view ' "$LOG" || true)"
  [[ "$views" -eq "$expected" ]]
  assert_viewed_every_dependency
  last_view="$(line_no "$LOG" '^npm view ' tail)"
  update_line="$(line_no "$LOG" '^npm update ' head)"
  textlint_line="$(line_no "$LOG" '^textlint ' head)"
  [[ -n "$last_view" && -n "$update_line" && -n "$textlint_line" ]]
  [[ "$last_view" -lt "$update_line" && "$update_line" -lt "$textlint_line" ]]
  ! grep -q '^npm install ' "$LOG"
}

test_skips_update_when_current() {
  prepare_case
  trap finish_case RETURN
  preseed_cache "1.2.3"
  export NPM_VIEW_VERSION="1.2.3"
  run_lint
  local views last_view textlint_line expected
  expected="$(dependency_count)"
  views="$(grep -c '^npm view ' "$LOG" || true)"
  [[ "$views" -eq "$expected" ]]
  assert_viewed_every_dependency
  last_view="$(line_no "$LOG" '^npm view ' tail)"
  textlint_line="$(line_no "$LOG" '^textlint ' head)"
  [[ -n "$last_view" && -n "$textlint_line" && "$last_view" -lt "$textlint_line" ]]
  ! grep -q '^npm update ' "$LOG"
  ! grep -q '^npm install ' "$LOG"
}

test_aborts_when_latest_check_fails() {
  prepare_case
  trap finish_case RETURN
  preseed_cache "1.2.3"
  export NPM_VIEW_FAIL=1
  local status=0
  run_lint || status=$?
  [[ "$status" -ne 0 ]]
  assert_viewed_every_dependency
  ! grep -q '^textlint ' "$LOG"
  ! grep -q '^npm update ' "$LOG"
  ! grep -q '^npm install ' "$LOG"
}

test_aborts_when_update_fails() {
  prepare_case
  trap finish_case RETURN
  preseed_cache "0.0.0"
  export NPM_VIEW_VERSION="9.9.9"
  export NPM_UPDATE_FAIL=1
  local status=0
  run_lint || status=$?
  [[ "$status" -ne 0 ]]
  ! grep -q '^textlint ' "$LOG"
  grep -q '^npm update ' "$LOG"
}

test_aborts_when_spec_is_not_latest() {
  local pinned status=0 output
  pinned="$(mktemp)"
  cat > "$pinned" << 'EOF'
{
  "private": true,
  "dependencies": {
    "textlint": "^15.8.0"
  }
}
EOF
  output="$(node "$ROOT/scripts/check-latest-spec.js" "$pinned" 2>&1)" || status=$?
  rm -f "$pinned"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"latest を参照してください"* ]]
}

test_installs_then_checks_latest_when_cache_missing() {
  prepare_case
  trap finish_case RETURN
  export NPM_VIEW_VERSION="1.2.3"
  run_lint
  local install_line last_view textlint_line expected views
  expected="$(dependency_count)"
  views="$(grep -c '^npm view ' "$LOG" || true)"
  [[ "$views" -eq "$expected" ]]
  assert_viewed_every_dependency
  install_line="$(line_no "$LOG" '^npm install ' head)"
  last_view="$(line_no "$LOG" '^npm view ' tail)"
  textlint_line="$(line_no "$LOG" '^textlint ' head)"
  [[ -n "$install_line" && -n "$last_view" && -n "$textlint_line" ]]
  [[ "$install_line" -lt "$last_view" && "$last_view" -lt "$textlint_line" ]]
  ! grep -q '^npm update ' "$LOG"
}

test_project_config_skips_registry() {
  prepare_case
  trap finish_case RETURN
  printf '{}\n' > "$WORK/.textlintrc"
  cat > "$BIN/textlint" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "textlint $*" >> "$CALL_LOG"
exit 0
EOF
  chmod +x "$BIN/textlint"
  run_lint
  grep -q '^textlint ' "$LOG"
  ! grep -q '^npm ' "$LOG"
}

run_case "lint.sh の構文" test_lint_sh_syntax
run_case "runtime-package.json は latest を参照する" test_runtime_package_uses_latest
run_case "古いときは textlint の前に更新する" test_updates_before_textlint_when_stale
run_case "最新のときは確認だけで更新しない" test_skips_update_when_current
run_case "最新の確認に失敗したら実行しない" test_aborts_when_latest_check_fails
run_case "更新に失敗したら実行しない" test_aborts_when_update_fails
run_case "latest 以外の指定では実行しない" test_aborts_when_spec_is_not_latest
run_case "未インストールなら導入してから最新を確認する" test_installs_then_checks_latest_when_cache_missing
run_case "プロジェクトの設定ではレジストリを見ない" test_project_config_skips_registry

exit "$failed"

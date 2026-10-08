#!/usr/bin/env bash
# motoki 単体リポジトリの配置を検査する。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
failed=0

ok() {
  printf 'ok - %s\n' "$1"
}

not_ok() {
  printf 'not ok - %s\n' "$1" >&2
  failed=1
}

assert_absent() {
  local relative="$1"
  if [[ -e "$ROOT/$relative" ]]; then
    not_ok "$relative が残っている"
  else
    ok "$relative が無い"
  fi
}

assert_file() {
  local relative="$1"
  if [[ -f "$ROOT/$relative" ]]; then
    ok "$relative がある"
  else
    not_ok "$relative が無い"
  fi
}

assert_dir() {
  local relative="$1"
  if [[ -d "$ROOT/$relative" ]]; then
    ok "$relative がある"
  else
    not_ok "$relative が無い"
  fi
}

json_field() {
  local relative="$1"
  local expression="$2"
  node -e 'const fs=require("fs"); const data=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); const value=Function("data", "return ("+process.argv[2]+")")(data); if (value === undefined) process.exit(2); process.stdout.write(String(value));' "$ROOT/$relative" "$expression"
}

assert_json() {
  local relative="$1"
  local expression="$2"
  local expected="$3"
  local actual=""
  if [[ ! -f "$ROOT/$relative" ]]; then
    not_ok "$relative の $expression を読めない"
    return
  fi
  if ! actual="$(json_field "$relative" "$expression" 2>/dev/null)"; then
    not_ok "$relative の $expression を読めない"
    return
  fi
  if [[ "$actual" == "$expected" ]]; then
    ok "$relative の $expression は $expected"
  else
    not_ok "$relative の $expression は $expected である (実際は ${actual})"
  fi
}

assert_absent ".cursor-plugin/marketplace.json"
assert_absent "plugins"
assert_file "plugin.json"
assert_file ".cursor-plugin/plugin.json"
assert_file "assets/logo.svg"
assert_dir "skills"
assert_file "skills/textlint-ja/SKILL.md"
assert_json "plugin.json" "data.name" "motoki"
assert_json ".cursor-plugin/plugin.json" "data.name" "motoki"
assert_json "plugin.json" "data.homepage" "https://github.com/inadysensei/motoki"
assert_json "plugin.json" "data.repository" "https://github.com/inadysensei/motoki"
assert_json ".cursor-plugin/plugin.json" "data.homepage" "https://github.com/inadysensei/motoki"
assert_json ".cursor-plugin/plugin.json" "data.repository" "https://github.com/inadysensei/motoki"
assert_json ".cursor-plugin/plugin.json" "data.logo" "assets/logo.svg"

if node "$ROOT/scripts/validate-plugin.mjs" >/dev/null; then
  ok "validate-plugin"
else
  not_ok "validate-plugin"
fi

exit "$failed"

#!/usr/bin/env bash
# motoki に追加したスキルが、訳文を持ち、URL と機能マップ例を同梱しないかを検査する。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS="$ROOT/plugins/motoki/skills"
failed=0

ok() {
  printf 'ok - %s\n' "$1"
}

ng() {
  printf 'not ok - %s\n' "$1" >&2
  failed=1
}

require_file() {
  local path="$1"
  if [[ -f "$path" ]]; then
    ok "ファイルがある: ${path#"$ROOT"/}"
  else
    ng "ファイルが無い: ${path#"$ROOT"/}"
  fi
}

reject_path() {
  local path="$1"
  local label="$2"
  if [[ -e "$path" ]]; then
    ng "$label"
  else
    ok "$label"
  fi
}

reject_line() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if [[ -f "$path" ]] && grep -q -F -- "$pattern" "$path"; then
    ng "$label"
  else
    ok "$label"
  fi
}

require_line() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if [[ -f "$path" ]] && grep -q -F -- "$pattern" "$path"; then
    ok "$label"
  else
    ng "$label"
  fi
}

frontmatter_name() {
  local path="$1"
  local expected="$2"
  require_line "$path" "name: ${expected}" "${expected} の name はスラッグのまま"
}

description_is_japanese() {
  local path="$1"
  local slug="$2"
  if [[ ! -f "$path" ]]; then
    ng "${slug} の description が日本語"
    return
  fi
  local description
  description="$(
    awk '
      BEGIN { in_front = 0; capture = 0 }
      NR == 1 && $0 == "---" { in_front = 1; next }
      in_front && $0 == "---" { exit }
      in_front && $0 ~ /^description:/ {
        sub(/^description:[[:space:]]*/, "")
        gsub(/^["'\'']|["'\'']$/, "")
        printf "%s", $0
        if ($0 ~ />/ || $0 == "") capture = 1
        next
      }
      capture && /^[[:space:]]/ { printf " %s", $0; next }
      capture { exit }
    ' "$path"
  )"
  if printf '%s' "$description" | grep -q '[ぁ-ん]'; then
    ok "${slug} の description が日本語"
  else
    ng "${slug} の description が日本語"
  fi
}

IN_YOUR="$SKILLS/in-your-own-words/SKILL.md"
CREATE="$SKILLS/create-verification-skill/SKILL.md"
REFERENCES="$SKILLS/create-verification-skill/references"

require_file "$IN_YOUR"
frontmatter_name "$IN_YOUR" "in-your-own-words"
description_is_japanese "$IN_YOUR" "in-your-own-words"
require_line "$IN_YOUR" "disable-model-invocation: true" "in-your-own-words はモデルからの自動起動を止める"
require_line "$IN_YOUR" "言い直す" "in-your-own-words は目的の言い直しを指示する"
reject_line "$IN_YOUR" "https://" "in-your-own-words に URL が無い"

require_file "$CREATE"
frontmatter_name "$CREATE" "create-verification-skill"
description_is_japanese "$CREATE" "create-verification-skill"
require_line "$CREATE" "disable-model-invocation: true" "create-verification-skill はモデルからの自動起動を止める"
require_line "$CREATE" ".cursor/skills/verify-<app>/" "生成先はプロジェクト内の verify スキル"
reject_line "$CREATE" "https://" "create-verification-skill に URL が無い"
require_line "$CREATE" "/maintain-verification-skill" "保守スキルへの案内がある"
require_line "$CREATE" "下位機能" "機能マップの見出し契約に下位機能がある"
require_line "$CREATE" "到達方法（利用者の視点）" "機能マップの見出し契約に到達方法がある"
require_line "$CREATE" "注意点" "機能マップの見出し契約に注意点がある"
reject_path "$REFERENCES" "create-verification-skill は references を同梱しない"
if [[ -f "$CREATE" ]] && grep -q -F -- "references/" "$CREATE"; then
  ng "SKILL.md は references を参照しない"
else
  ok "SKILL.md は references を参照しない"
fi

exit "$failed"

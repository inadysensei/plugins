#!/usr/bin/env bash
# 日本語を textlint で検査する。
# プロジェクトに textlint 設定があるときはそれを使う。無いときは同梱の設定を使う。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${TEXTLINT_JA_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/motoki-textlint-ja}"

mode="general"
fix=0
files=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix)
      fix=1
      shift
      ;;
    --technical)
      mode="technical"
      shift
      ;;
    --)
      shift
      files+=("$@")
      break
      ;;
    -*)
      echo "不明なオプション: $1" >&2
      exit 2
      ;;
    *)
      files+=("$1")
      shift
      ;;
  esac
done

if [[ ${#files[@]} -eq 0 ]]; then
  echo "検査するファイルを指定してください。" >&2
  exit 2
fi

# textlint 15 が自分で読む名前だけ。見つけても --config には渡さない。
find_project_config() {
  local dir="$PWD"
  local name
  while [[ "$dir" != "/" ]]; do
    for name in \
      .textlintrc \
      .textlintrc.json \
      .textlintrc.yaml \
      .textlintrc.yml \
      .textlintrc.js \
      .textlintrc.cjs
    do
      if [[ -f "$dir/$name" ]]; then
        printf '%s\n' "$dir/$name"
        return 0
      fi
    done
    if [[ -f "$dir/package.json" ]] && node -e 'const p=require(process.argv[1]); if(!p.textlint) process.exit(1)' "$dir/package.json"; then
      printf '%s\n' "$dir/package.json"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

find_project_textlint() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -x "$dir/node_modules/.bin/textlint" ]]; then
      printf '%s\n' "$dir/node_modules/.bin/textlint"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  if command -v textlint >/dev/null 2>&1; then
    command -v textlint
    return 0
  fi
  return 1
}

run_textlint() {
  local bin="$1"
  shift
  if [[ "$fix" -eq 1 ]]; then
    "$bin" --fix "$@"
  else
    "$bin" "$@"
  fi
}

if config="$(find_project_config)"; then
  echo "mode: project" >&2
  echo "config: $config" >&2
  if ! bin="$(find_project_textlint)"; then
    echo "textlint の設定はありますが、textlint が入っていません。プロジェクトにはインストールしません。" >&2
    exit 2
  fi
  set +e
  run_textlint "$bin" "${files[@]}"
  status=$?
  set -e
  exit "$status"
fi

stamp="$ROOT/scripts/runtime-package.json"
if [[ ! -x "$CACHE/node_modules/.bin/textlint" ]] || [[ ! -f "$CACHE/package.json" ]] || ! cmp -s "$stamp" "$CACHE/package.json"; then
  echo "textlint を準備しています。" >&2
  mkdir -p "$CACHE"
  cp "$stamp" "$CACHE/package.json"
  if ! (cd "$CACHE" && npm install --no-fund --no-audit); then
    rm -f "$CACHE/package.json" "$CACHE/node_modules/.bin/textlint"
    echo "textlint の準備に失敗しました。" >&2
    exit 2
  fi
fi

bundled="$ROOT/textlintrc.${mode}.json"
echo "mode: $mode" >&2
echo "config: $bundled" >&2
run_textlint "$CACHE/node_modules/.bin/textlint" --config "$bundled" "${files[@]}"

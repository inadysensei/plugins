#!/usr/bin/env bash
# save-grok-usage が、使用量を減らす手順とバージョン更新を持つかを検査する。
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$SKILL_DIR/../../../.." && pwd)"
SKILL="$SKILL_DIR/SKILL.md"
failed=0

run_case() {
  local name="$1"
  shift
  local status=0
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

require_file() {
  [[ -f "$SKILL" ]]
}

require_text() {
  local pattern="$1"
  grep -q -F -- "$pattern" "$SKILL"
}

json_field() {
  local file="$1"
  local expr="$2"
  python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); print(data[sys.argv[2]] if "." not in sys.argv[2] else data[sys.argv[2].split(".")[0]][sys.argv[2].split(".")[1]])' "$file" "$expr"
}

test_skill_name() {
  require_file
  require_text "name: save-grok-usage"
  require_text "トークン使用量"
}

test_premise() {
  require_file
  require_text "メッセージの数"
  require_text "ツール"
  require_text "ブラウザ"
  require_text "サブエージェント"
  require_text "読み直"
}

test_new_chat_per_task() {
  require_file
  require_text "新しいチャット"
  require_text "8万"
  require_text "9万"
}

test_connector_before_browser() {
  require_file
  require_text "コネクター"
  require_text "55万"
  require_text "1.2万"
}

test_fewer_routines() {
  require_file
  require_text "起動"
  require_text "読み込み"
  require_text "2回から3回"
  require_text "トリガー"
  require_text "読んでいない"
}

test_one_request() {
  require_file
  require_text "1通"
  require_text "何をする"
  require_text "どこで"
  require_text "何を使う"
  require_text "小分け"
  require_text "最初の指示"
}

test_one_role() {
  require_file
  require_text "役割"
  require_text "1つ"
}

test_stable_description() {
  require_file
  require_text "説明文"
  require_text "キャッシュ"
  require_text "別ファイル"
  require_text "日付"
  require_text "今週の話題"
}

test_cloud_agent() {
  require_file
  require_text "クラウドエージェント"
  require_text "計画"
  require_text "確認"
  require_text "別枠"
}

test_retry_limit() {
  require_file
  require_text "3回失敗"
  require_text "詰まった"
  require_text "返事"
  require_text "ファイルに保存"
}

test_measure_first() {
  require_file
  require_text "減らす前"
  require_text "範囲を絞った"
  require_text "週の回数"
}

test_no_citation() {
  require_file
  if grep -q -E 'https?://' "$SKILL"; then
    echo "出典 URL があります" >&2
    exit 1
  fi
  if grep -q -F "出典" "$SKILL"; then
    echo "出典の表記があります" >&2
    exit 1
  fi
  if grep -q -F "著者" "$SKILL"; then
    echo "著者の表記があります" >&2
    exit 1
  fi
}

test_versions() {
  local motoki_a motoki_b hub_a hub_b market
  motoki_a="$(json_field "$REPO/plugins/motoki/plugin.json" version)"
  motoki_b="$(json_field "$REPO/plugins/motoki/.cursor-plugin/plugin.json" version)"
  hub_a="$(json_field "$REPO/plugins/aws-security-hub/plugin.json" version)"
  hub_b="$(json_field "$REPO/plugins/aws-security-hub/.cursor-plugin/plugin.json" version)"
  market="$(json_field "$REPO/.cursor-plugin/marketplace.json" metadata.version)"
  [[ "$motoki_a" == "1.7.3" ]]
  [[ "$motoki_b" == "1.7.3" ]]
  [[ "$hub_a" == "1.1.3" ]]
  [[ "$hub_b" == "1.1.3" ]]
  [[ "$market" == "1.8.3" ]]
}

run_case "スキル名と使用量" test_skill_name
run_case "使用量の決まり方" test_premise
run_case "作業ごとの新しいチャット" test_new_chat_per_task
run_case "コネクターを先にする" test_connector_before_browser
run_case "ルーティンの回数" test_fewer_routines
run_case "依頼は1通" test_one_request
run_case "ボット1体に役割1つ" test_one_role
run_case "説明文の先頭を保つ" test_stable_description
run_case "大きなコード作業の切り分け" test_cloud_agent
run_case "やり直しの上限" test_retry_limit
run_case "減らす前に測る" test_measure_first
run_case "出典を書かない" test_no_citation
run_case "minor バージョン" test_versions

exit "$failed"

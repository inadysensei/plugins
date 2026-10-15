#!/usr/bin/env bash
# pm-daily-standup が、チケット作成候補を選ばれたときだけ作るかを検査する。
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
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

test_ticket_candidates() {
  require_file
  require_text "C: チケット作成候補"
  require_text "C1"
  require_text "仮タイトル"
  require_text "担当候補"
  require_text "期限候補"
  require_text "元スレッド"
  require_text "依頼"
  require_text "質問"
  require_text "障害報告"
  require_text "新しい作業"
  require_text "関連するSlackのチャンネルとスレッド"
}

test_create_only_when_picked() {
  require_file
  require_text "Step 6で選ばれたC"
  require_text "この段階では、チケットを作りません。"
  require_text "選ばれていないCは、作りません。"
  require_text "Notionには書きません。"
  require_text "更新案"
  require_text "推測では足しません。"
}

test_keep_ab_and_nudge() {
  require_file
  require_text "## A: 催促候補"
  require_text "### B: 自分の作業"
  require_text "AIが進める"
  require_text "送信はしません"
  require_text "stop-ai-slop"
  require_text "スレッドへの返信では、チケットのリンクを貼らない"
  require_text "新規の場合は貼る"
  require_text "メンションは、今動いてほしい人だけにする"
  require_text "聞きたいことは疑問形にする"
  require_text "期日を決定する理由を短く添える"
  require_text "文面は2行か3行にする"
  require_text "絵文字は、最低1つつける。"
}

run_case "Cは仮タイトルと担当と期限と元スレッド" test_ticket_candidates
run_case "選ばれたCだけ作り、他は更新案" test_create_only_when_picked
run_case "AとBと催促文の形を残す" test_keep_ab_and_nudge

exit "$failed"

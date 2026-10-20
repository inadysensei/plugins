#!/usr/bin/env bash
# スキルの name とフォルダ名、agent id のスラッグを検査する。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/scripts/check-skill-names.mjs"
VALIDATE="$ROOT/scripts/validate-plugin.mjs"
SYNC="$ROOT/scripts/sync-to-production.sh"
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

new_root() {
  local dir
  dir="$(mktemp -d)"
  printf '%s\n' "$dir"
}

write_skill() {
  local root="$1"
  local folder="$2"
  local name="$3"
  local dir="$root/plugins/demo/skills/$folder"
  mkdir -p "$dir"
  cat > "$dir/SKILL.md" << EOF
---
name: ${name}
description: test
---

# test
EOF
}

write_agent() {
  local root="$1"
  local file="$2"
  local name="$3"
  mkdir -p "$root/plugins/demo/agents"
  cat > "$root/plugins/demo/agents/$file" << EOF
---
name: ${name}
description: test
---

# agent
EOF
}

write_marketplace() {
  local root="$1"
  mkdir -p "$root/.cursor-plugin" "$root/plugins/demo/.cursor-plugin"
  cat > "$root/.cursor-plugin/marketplace.json" << 'EOF'
{
  "name": "fixture",
  "owner": { "name": "test" },
  "plugins": [
    { "name": "demo", "source": "./plugins/demo" }
  ]
}
EOF
  cat > "$root/plugins/demo/plugin.json" << 'EOF'
{
  "$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json",
  "name": "demo",
  "version": "1.0.0"
}
EOF
  cat > "$root/plugins/demo/.cursor-plugin/plugin.json" << 'EOF'
{
  "name": "demo",
  "version": "1.0.0"
}
EOF
}

assert_fails_with() {
  local root="$1"
  local needle="$2"
  local status=0
  local out
  set +e
  out="$(node "$CHECK" "$root" 2>&1)"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    printf '検査が成功してしまった\n%s\n' "$out" >&2
    exit 1
  fi
  if ! printf '%s\n' "$out" | grep -F -q -- "$needle"; then
    printf '出力に %q が無い\n%s\n' "$needle" "$out" >&2
    exit 1
  fi
}

assert_passes() {
  local root="$1"
  node "$CHECK" "$root" >/dev/null
}

test_script_syntax() {
  node --check "$CHECK"
}

test_name_must_match_folder() {
  local root
  root="$(new_root)"
  write_skill "$root" "make-bot-ui" "Make Bot UI"
  assert_fails_with "$root" "make-bot-ui"
  assert_fails_with "$root" "Make Bot UI"
}

test_different_slug_fails() {
  local root
  root="$(new_root)"
  write_skill "$root" "make-bot-ui" "other-skill"
  assert_fails_with "$root" "make-bot-ui"
  assert_fails_with "$root" "other-skill"
}

test_missing_or_empty_name_fails() {
  local root dir
  root="$(new_root)"
  dir="$root/plugins/demo/skills/make-bot-ui"
  mkdir -p "$dir"
  cat > "$dir/SKILL.md" << 'EOF'
---
description: test
---
EOF
  assert_fails_with "$root" "make-bot-ui"
  cat > "$dir/SKILL.md" << 'EOF'
---
name:
description: test
---
EOF
  assert_fails_with "$root" "make-bot-ui"
}

test_quoted_name_must_match_folder() {
  local root dir
  root="$(new_root)"
  dir="$root/plugins/demo/skills/poteto-mode"
  mkdir -p "$dir"
  cat > "$dir/SKILL.md" << 'EOF'
---
name: "Poteto Mode"
description: test
---
EOF
  assert_fails_with "$root" "poteto-mode"
  assert_fails_with "$root" "Poteto Mode"
}

test_quoted_matching_slug_passes() {
  local root dir
  root="$(new_root)"
  dir="$root/plugins/demo/skills/make-bot-ui"
  mkdir -p "$dir" "$root/plugins/demo/agents"
  cat > "$dir/SKILL.md" << 'EOF'
---
name: "make-bot-ui"
description: test
---
EOF
  cat > "$root/plugins/demo/agents/comment-sicko.md" << 'EOF'
---
name: "comment-sicko"
description: test
---
EOF
  assert_passes "$root"
}

test_quoted_different_slug_fails() {
  local root dir
  root="$(new_root)"
  dir="$root/plugins/demo/skills/make-bot-ui"
  mkdir -p "$dir"
  cat > "$dir/SKILL.md" << 'EOF'
---
name: "other-skill"
description: test
---
EOF
  assert_fails_with "$root" "other-skill"
}

test_frontmatter_can_end_at_eof() {
  local root dir
  root="$(new_root)"
  dir="$root/plugins/demo/skills/make-bot-ui"
  mkdir -p "$dir"
  printf '%s' $'---\nname: make-bot-ui\ndescription: test\n---' > "$dir/SKILL.md"
  assert_passes "$root"
}

test_folder_with_space_fails_even_when_name_matches() {
  local root
  root="$(new_root)"
  write_skill "$root" "Make Bot UI" "Make Bot UI"
  assert_fails_with "$root" "Make Bot UI"
}

test_uppercase_skill_fails() {
  local root
  root="$(new_root)"
  write_skill "$root" "Poteto" "Poteto"
  assert_fails_with "$root" "Poteto"
}

test_underscore_and_period_fail() {
  local root
  root="$(new_root)"
  write_skill "$root" "comment_sicko" "comment_sicko"
  write_skill "$root" "comment.sicko" "comment.sicko"
  assert_fails_with "$root" "comment_sicko"
  assert_fails_with "$root" "comment.sicko"
}

test_broken_hyphen_and_length_fail() {
  local root long
  root="$(new_root)"
  write_skill "$root" "a--b" "a--b"
  write_skill "$root" "-ab" "-ab"
  write_skill "$root" "ab-" "ab-"
  long="$(printf 'a%.0s' {1..65})"
  write_skill "$root" "$long" "$long"
  assert_fails_with "$root" "a--b"
  assert_fails_with "$root" "-ab"
  assert_fails_with "$root" "ab-"
  assert_fails_with "$root" "$long"
}

test_valid_slug_passes() {
  local root long
  root="$(new_root)"
  long="$(printf 'a%.0s' {1..64})"
  write_skill "$root" "make-bot-ui" "make-bot-ui"
  write_skill "$root" "tdd" "tdd"
  write_skill "$root" "skill2" "skill2"
  write_skill "$root" "$long" "$long"
  write_agent "$root" "comment-sicko.md" "comment-sicko"
  write_agent "$root" "security-hub-agent.md" "security-hub-agent"
  assert_passes "$root"
}

test_reports_every_skill() {
  local root out status=0
  root="$(new_root)"
  write_skill "$root" "make-bot-ui" "Make Bot UI"
  write_skill "$root" "poteto-mode" "Poteto Mode"
  set +e
  out="$(node "$CHECK" "$root" 2>&1)"
  status=$?
  set -e
  [[ "$status" -ne 0 ]]
  printf '%s\n' "$out" | grep -F -q "make-bot-ui"
  printf '%s\n' "$out" | grep -F -q "poteto-mode"
}

test_agent_id_with_space_fails() {
  local root
  root="$(new_root)"
  write_skill "$root" "no-comments" "no-comments"
  write_agent "$root" "comment-sicko.md" "Comment Sicko"
  assert_fails_with "$root" "Comment Sicko"
}

test_agent_id_uses_same_slug_rules() {
  local root long file
  root="$(new_root)"
  write_skill "$root" "no-comments" "no-comments"
  long="$(printf 'a%.0s' {1..65})"
  for file in "comment.sicko" "comment_sicko" "Comment" "a--b" "-ab" "ab-" "$long"; do
    write_agent "$root" "comment-sicko.md" "$file"
    assert_fails_with "$root" "$file"
  done
}

test_quoted_agent_id_fails() {
  local root
  root="$(new_root)"
  write_skill "$root" "no-comments" "no-comments"
  mkdir -p "$root/plugins/demo/agents"
  cat > "$root/plugins/demo/agents/comment-sicko.md" << 'EOF'
---
name: "Comment Sicko"
description: test
---
EOF
  assert_fails_with "$root" "Comment Sicko"
}

test_repo_passes() {
  assert_passes "$ROOT"
}

test_ignores_cursor_skills() {
  local root
  root="$(new_root)"
  mkdir -p "$root/.cursor/skills/bump-version"
  cat > "$root/.cursor/skills/bump-version/SKILL.md" << 'EOF'
---
name: bump-plugin-version
description: test
---
EOF
  assert_passes "$root"
}

test_skill_file_symlink_outside_root_fails() {
  local root outside dir
  root="$(new_root)"
  outside="$(mktemp)"
  dir="$root/plugins/demo/skills/make-bot-ui"
  mkdir -p "$dir"
  printf '%s\n' "---" "name: make-bot-ui" "description: hidden-body" "---" > "$outside"
  ln -s "$outside" "$dir/SKILL.md"
  assert_fails_with "$root" "make-bot-ui"
  if node "$CHECK" "$root" 2>&1 | grep -F -q "hidden-body"; then
    printf '検査対象の外の本文が出力されている\n' >&2
    exit 1
  fi
}

test_symlink_outside_root_fails() {
  local root outside
  root="$(new_root)"
  outside="$(mktemp -d)"
  mkdir -p "$outside/secret-skill" "$root/plugins/demo/skills"
  printf '%s\n' "---" "name: secret-skill" "description: hidden" "---" > "$outside/secret-skill/SKILL.md"
  ln -s "$outside/secret-skill" "$root/plugins/demo/skills/secret-skill"
  assert_fails_with "$root" "secret-skill"
  if node "$CHECK" "$root" 2>&1 | grep -F -q "hidden"; then
    printf '検査対象の外の本文が出力されている\n' >&2
    exit 1
  fi
}

test_validate_plugin_rejects_spaced_folder() {
  local root status=0 out
  root="$(new_root)"
  write_marketplace "$root"
  write_skill "$root" "Make Bot UI" "Make Bot UI"
  set +e
  out="$(node "$VALIDATE" "$root" 2>&1)"
  status=$?
  set -e
  [[ "$status" -ne 0 ]]
  printf '%s\n' "$out" | grep -F -q "Make Bot UI"
}

test_validate_plugin_accepts_slug() {
  local root
  root="$(new_root)"
  write_marketplace "$root"
  write_skill "$root" "make-bot-ui" "make-bot-ui"
  write_agent "$root" "comment-sicko.md" "comment-sicko"
  node "$VALIDATE" "$root" >/dev/null
}

test_sync_skill_mentions_check() {
  grep -F -q "check-skill-names.mjs" "$ROOT/.cursor/skills/sync-to-production/SKILL.md"
  grep -F -q "check-skill-names.mjs" "$ROOT/.cursor/skills/bump-version/SKILL.md"
}

test_sync_dry_run_aborts_on_bad_skill_name() {
  local src prod before status=0 out
  src="$(mktemp -d)"
  prod="$(mktemp -d)"
  git -C "$prod" init -q -b main
  git -C "$prod" config user.email test@example.com
  git -C "$prod" config user.name test
  git -C "$prod" config commit.gpgsign false
  mkdir -p "$src/plugins/motoki" "$src/.cursor-plugin" "$prod/plugins/motoki" "$prod/.cursor-plugin"
  printf '%s\n' "new" > "$src/README.md"
  printf '%s\n' "plugin" > "$src/plugins/motoki/README.md"
  printf '%s\n' "{}" > "$src/.cursor-plugin/marketplace.json"
  write_skill "$src" "make-bot-ui" "other-skill"
  printf '%s\n' "old" > "$prod/README.md"
  printf '%s\n' "plugin" > "$prod/plugins/motoki/README.md"
  printf '%s\n' "{}" > "$prod/.cursor-plugin/marketplace.json"
  git -C "$prod" add -A
  git -C "$prod" commit -q -m "production history"
  before="$(git -C "$prod" rev-parse HEAD)"
  set +e
  out="$(bash "$SYNC" --source "$src" --production-dir "$prod" --dry-run 2>&1)"
  status=$?
  set -e
  [[ "$status" -ne 0 ]]
  [[ "$(git -C "$prod" rev-parse HEAD)" == "$before" ]]
  [[ "$(cat "$prod/README.md")" == "old" ]]
  printf '%s\n' "$out" | grep -F -q "other-skill"
  if printf '%s\n' "$out" | grep -F -q "dry-run: commit も push もしません。"; then
    printf '不正な名前でも dry-run が最後まで進んだ\n' >&2
    exit 1
  fi
}

test_sync_aborts_on_bad_skill_name() {
  local src prod before status=0 out
  src="$(mktemp -d)"
  prod="$(mktemp -d)"
  git -C "$prod" init -q -b main
  git -C "$prod" config user.email test@example.com
  git -C "$prod" config user.name test
  git -C "$prod" config commit.gpgsign false
  mkdir -p "$src/plugins/motoki" "$src/.cursor-plugin" "$prod/plugins/motoki" "$prod/.cursor-plugin"
  printf '%s\n' "new" > "$src/README.md"
  printf '%s\n' "plugin" > "$src/plugins/motoki/README.md"
  printf '%s\n' "{}" > "$src/.cursor-plugin/marketplace.json"
  write_skill "$src" "make-bot-ui" "Make Bot UI"
  printf '%s\n' "old" > "$prod/README.md"
  printf '%s\n' "plugin" > "$prod/plugins/motoki/README.md"
  printf '%s\n' "{}" > "$prod/.cursor-plugin/marketplace.json"
  git -C "$prod" add -A
  git -C "$prod" commit -q -m "production history"
  before="$(git -C "$prod" rev-parse HEAD)"
  set +e
  out="$(bash "$SYNC" --source "$src" --production-dir "$prod" --no-push 2>&1)"
  status=$?
  set -e
  [[ "$status" -ne 0 ]]
  [[ "$(git -C "$prod" rev-parse HEAD)" == "$before" ]]
  [[ "$(cat "$prod/README.md")" == "old" ]]
  printf '%s\n' "$out" | grep -F -q "Make Bot UI"
}

test_sync_allows_valid_skill_name() {
  local src prod
  src="$(mktemp -d)"
  prod="$(mktemp -d)"
  git -C "$prod" init -q -b main
  git -C "$prod" config user.email test@example.com
  git -C "$prod" config user.name test
  git -C "$prod" config commit.gpgsign false
  mkdir -p "$src/plugins/motoki" "$src/.cursor-plugin" "$prod/plugins/motoki" "$prod/.cursor-plugin"
  printf '%s\n' "new" > "$src/README.md"
  printf '%s\n' "plugin" > "$src/plugins/motoki/README.md"
  printf '%s\n' "{}" > "$src/.cursor-plugin/marketplace.json"
  write_skill "$src" "make-bot-ui" "make-bot-ui"
  write_agent "$src" "comment-sicko.md" "comment-sicko"
  printf '%s\n' "old" > "$prod/README.md"
  printf '%s\n' "plugin" > "$prod/plugins/motoki/README.md"
  printf '%s\n' "{}" > "$prod/.cursor-plugin/marketplace.json"
  git -C "$prod" add -A
  git -C "$prod" commit -q -m "production history"
  bash "$SYNC" --source "$src" --production-dir "$prod" --no-push
  [[ "$(cat "$prod/plugins/demo/skills/make-bot-ui/SKILL.md")" == *"name: make-bot-ui"* ]]
}

run_case "syntax" test_script_syntax
run_case "name matches folder" test_name_must_match_folder
run_case "different slug fails" test_different_slug_fails
run_case "missing or empty name fails" test_missing_or_empty_name_fails
run_case "quoted name matches folder" test_quoted_name_must_match_folder
run_case "quoted matching slug passes" test_quoted_matching_slug_passes
run_case "quoted different slug fails" test_quoted_different_slug_fails
run_case "frontmatter can end at eof" test_frontmatter_can_end_at_eof
run_case "folder with space fails" test_folder_with_space_fails_even_when_name_matches
run_case "uppercase skill fails" test_uppercase_skill_fails
run_case "underscore and period fail" test_underscore_and_period_fail
run_case "broken hyphen and length fail" test_broken_hyphen_and_length_fail
run_case "valid slug passes" test_valid_slug_passes
run_case "reports every skill" test_reports_every_skill
run_case "agent id with space fails" test_agent_id_with_space_fails
run_case "agent id uses same slug rules" test_agent_id_uses_same_slug_rules
run_case "quoted agent id fails" test_quoted_agent_id_fails
run_case "repo passes" test_repo_passes
run_case "ignores cursor skills" test_ignores_cursor_skills
run_case "symlink outside root fails" test_symlink_outside_root_fails
run_case "skill file symlink outside root fails" test_skill_file_symlink_outside_root_fails
run_case "validate-plugin rejects spaced folder" test_validate_plugin_rejects_spaced_folder
run_case "validate-plugin accepts slug" test_validate_plugin_accepts_slug
run_case "skills mention the check" test_sync_skill_mentions_check
run_case "sync dry-run aborts on bad skill name" test_sync_dry_run_aborts_on_bad_skill_name
run_case "sync aborts on bad skill name" test_sync_aborts_on_bad_skill_name
run_case "sync allows valid skill name" test_sync_allows_valid_skill_name

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

#!/usr/bin/env bash
# Cursor hook が push を確認にし、秘密の commit を拒否することを検査する。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../" && pwd)"
GUARD="$ROOT/.cursor/hooks/guard.py"
HOOKS_JSON="$ROOT/.cursor/hooks.json"
AGENTS="$ROOT/AGENTS.md"
failed=0

aws_key() {
  printf 'AKIA%s' 'IOSFODNN7EXAMPLE'
}

github_token() {
  printf 'ghp_%s' 'abcdefghijklmnopqrst'
}

private_key_line() {
  printf '%s %s %s' '-----BEGIN' 'OPENSSH' 'PRIVATE KEY-----'
}

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

new_repo() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  printf '%s\n' "$dir"
}

shell_input() {
  local command="$1"
  local cwd="$2"
  python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1], "cwd": sys.argv[2], "sandbox": False}))' "$command" "$cwd"
}

mcp_input() {
  local tool="$1"
  python3 -c 'import json,sys; print(json.dumps({"tool_name": sys.argv[1], "tool_input": "{}", "mcp_server_name": "plugin-github-github"}))' "$tool"
}

run_guard() {
  local mode="$1"
  local json="$2"
  python3 "$GUARD" "$mode" <<<"$json"
}

permission_of() {
  python3 -c 'import json,sys; print(json.load(sys.stdin)["permission"])'
}

assert_perm() {
  local mode="$1"
  local json="$2"
  local want="$3"
  local out perm
  out="$(run_guard "$mode" "$json")"
  perm="$(printf '%s' "$out" | permission_of)"
  if [[ "$perm" != "$want" ]]; then
    printf 'want %s, got %s\n%s\n' "$want" "$perm" "$out" >&2
    exit 1
  fi
  printf '%s' "$out"
}

test_hooks_json() {
  python3 - "$HOOKS_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["version"] == 1
shell = data["hooks"]["beforeShellExecution"][0]
mcp = data["hooks"]["beforeMCPExecution"][0]
assert shell["failClosed"] is True
assert mcp["failClosed"] is True
assert "guard.py" in shell["command"] and "shell" in shell["command"]
assert "guard.py" in mcp["command"] and "mcp" in mcp["command"]
PY
}

test_agents_md() {
  grep -q "ユーザーが確認してから" "$AGENTS"
  grep -q "認証情報、秘密、顧客データ、アカウント識別子" "$AGENTS"
  if grep -q "mainブランチへpushします" "$AGENTS"; then
    echo "AGENTS.md が確認なしの push を指示しています" >&2
    exit 1
  fi
}

test_git_status_allows() {
  local repo
  repo="$(new_repo)"
  assert_perm shell "$(shell_input "git status" "$repo")" allow >/dev/null
}

test_git_push_asks() {
  local repo
  repo="$(new_repo)"
  assert_perm shell "$(shell_input "git push" "$repo")" ask >/dev/null
  assert_perm shell "$(shell_input "git push --no-verify" "$repo")" ask >/dev/null
  assert_perm shell "$(shell_input "git -C \"$repo\" push origin HEAD" "$repo")" ask >/dev/null
  assert_perm shell "$(shell_input "git status && git push" "$repo")" ask >/dev/null
  assert_perm shell "$(shell_input "FOO=1 git push" "$repo")" ask >/dev/null
  assert_perm shell "$(shell_input "bash -lc 'git push origin HEAD'" "$repo")" ask >/dev/null
}

test_echo_git_push_allows() {
  local repo
  repo="$(new_repo)"
  assert_perm shell "$(shell_input "echo \"git push\"" "$repo")" allow >/dev/null
}

test_commit_message_mentioning_push_allows() {
  local repo
  repo="$(new_repo)"
  printf 'hello\n' > "$repo/README.md"
  git -C "$repo" add README.md
  assert_perm shell "$(shell_input "git -C \"$repo\" commit -m \"please git push\"" "/tmp")" allow >/dev/null
}

test_staged_secret_denies_without_leaking() {
  local repo out
  repo="$(new_repo)"
  printf 'key=%s\n' "$(aws_key)" > "$repo/notes.md"
  git -C "$repo" add notes.md
  out="$(assert_perm shell "$(shell_input "git commit --no-verify -m add" "$repo")" deny)"
  if printf '%s' "$out" | grep -q -F "$(aws_key)"; then
    echo "hook output contains the secret" >&2
    exit 1
  fi
  if ! printf '%s' "$out" | grep -q 'aws-access-key'; then
    echo "hook output missing rule id" >&2
    exit 1
  fi
}

test_secret_patterns() {
  local repo label content
  repo="$(new_repo)"
  while IFS=$'\t' read -r label content; do
    [[ -z "$label" ]] && continue
    printf '%s\n' "$content" > "$repo/secret.txt"
    git -C "$repo" add secret.txt
    out="$(assert_perm shell "$(shell_input "git commit -m add" "$repo")" deny)"
    if ! printf '%s' "$out" | grep -q "$label"; then
      printf 'missing rule %s\n%s\n' "$label" "$out" >&2
      exit 1
    fi
    git -C "$repo" reset -q
  done <<EOF
github-token	$(github_token)
private-key	$(private_key_line)
EOF
}

test_commit_a_scans_unstaged() {
  local repo
  repo="$(new_repo)"
  printf 'ok\n' > "$repo/notes.md"
  git -C "$repo" add notes.md
  git -C "$repo" commit -q -m init
  printf 'key=%s\n' "$(aws_key)" > "$repo/notes.md"
  assert_perm shell "$(shell_input "git commit -am update" "$repo")" deny >/dev/null
}

test_add_and_commit_scans_working_tree() {
  local repo
  repo="$(new_repo)"
  printf 'ok\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m init
  printf 'key=%s\n' "$(aws_key)" > "$repo/secret.txt"
  assert_perm shell "$(shell_input "git add secret.txt && git commit -m add" "$repo")" deny >/dev/null
}

test_add_all_and_commit() {
  local repo
  repo="$(new_repo)"
  printf 'ok\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m init
  printf 'key=%s\n' "$(aws_key)" > "$repo/secret.txt"
  assert_perm shell "$(shell_input "git add . && git commit -m add" "$repo")" deny >/dev/null
}

test_add_path_matches_commit_pathspec() {
  local repo
  repo="$(new_repo)"
  printf 'key=%s\n' "$(aws_key)" > "$repo/secret.txt"
  assert_perm shell "$(shell_input "git add secret.txt && git commit -m add -- secret.txt" "$repo")" deny >/dev/null
}

test_add_then_commit_pathspec_ignores_other_file() {
  local repo
  repo="$(new_repo)"
  printf 'ok\n' > "$repo/README.md"
  git -C "$repo" add README.md
  printf 'key=%s\n' "$(aws_key)" > "$repo/secret.txt"
  assert_perm shell "$(shell_input "git add secret.txt && git commit -m add -- README.md" "$repo")" allow >/dev/null
}

test_sensitive_filename() {
  local repo
  repo="$(new_repo)"
  printf 'PORT=1\n' > "$repo/.env"
  git -C "$repo" add .env
  assert_perm shell "$(shell_input "git commit -m add" "$repo")" deny >/dev/null
  git -C "$repo" reset -q
  printf 'PORT=1\n' > "$repo/.env.example"
  git -C "$repo" add .env.example
  assert_perm shell "$(shell_input "git commit -m add" "$repo")" allow >/dev/null
}

test_unstaged_secret_without_add_allows() {
  local repo
  repo="$(new_repo)"
  printf 'ok\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m init
  printf 'key=%s\n' "$(aws_key)" > "$repo/README.md"
  assert_perm shell "$(shell_input "git commit -m empty" "$repo")" allow >/dev/null
}

test_commit_outside_repo_denies() {
  assert_perm shell "$(shell_input "git commit -m x" "/tmp")" deny >/dev/null
}

test_invalid_json_denies() {
  assert_perm shell '{' deny >/dev/null
  assert_perm mcp '{' deny >/dev/null
}

test_mcp_writes_ask_reads_allow() {
  assert_perm mcp "$(mcp_input push_files)" ask >/dev/null
  assert_perm mcp "$(mcp_input create_or_update_file)" ask >/dev/null
  assert_perm mcp "$(mcp_input delete_file)" ask >/dev/null
  assert_perm mcp "$(mcp_input get_file_contents)" allow >/dev/null
  assert_perm mcp '{}' deny >/dev/null
}

run_case hooks-json test_hooks_json
run_case agents-md test_agents_md
run_case git-status-allows test_git_status_allows
run_case git-push-asks test_git_push_asks
run_case echo-git-push-allows test_echo_git_push_allows
run_case commit-message-mentioning-push-allows test_commit_message_mentioning_push_allows
run_case staged-secret-denies test_staged_secret_denies_without_leaking
run_case secret-patterns test_secret_patterns
run_case commit-a-scans-unstaged test_commit_a_scans_unstaged
run_case add-and-commit-scans-working-tree test_add_and_commit_scans_working_tree
run_case add-all-and-commit test_add_all_and_commit
run_case add-path-matches-commit-pathspec test_add_path_matches_commit_pathspec
run_case add-then-commit-pathspec-ignores-other-file test_add_then_commit_pathspec_ignores_other_file
run_case sensitive-filename test_sensitive_filename
run_case unstaged-secret-without-add-allows test_unstaged_secret_without_add_allows
run_case commit-outside-repo-denies test_commit_outside_repo_denies
run_case invalid-json-denies test_invalid_json_denies
run_case mcp-writes-ask-reads-allow test_mcp_writes_ask_reads_allow

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

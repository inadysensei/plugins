#!/usr/bin/env python3
"""Cursor hook: ask before a remote push, and deny commits that contain secrets."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys

REMOTE_WRITE_TOOLS = {
    "push_files",
    "create_or_update_file",
    "delete_file",
}

ENV_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
SHELLS = {"bash", "sh", "zsh", "dash"}
GIT_GLOBAL_WITH_VALUE = {
    "-C",
    "-c",
    "--git-dir",
    "--work-tree",
    "--namespace",
    "--exec-path",
    "--config-env",
    "--super-prefix",
}
COMMIT_WITH_VALUE = {
    "-m",
    "--message",
    "-F",
    "--file",
    "--author",
    "--date",
    "--cleanup",
    "-u",
    "--untracked-files",
    "--fixup",
    "--squash",
    "-c",
    "-C",
    "--reuse-message",
    "--reedit-message",
    "--pathspec-from-file",
    "--trailer",
    "-S",
}
SECRET_RULES = [
    ("private-key", re.compile(r"-----BEGIN (?:[A-Z0-9]+ )?PRIVATE KEY-----")),
    ("aws-access-key", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("aws-temp-key", re.compile(r"\bASIA[0-9A-Z]{16}\b")),
    ("github-token", re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}\b")),
    ("github-pat", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b")),
    ("gitlab-pat", re.compile(r"\bglpat-[A-Za-z0-9\-_]{20,}\b")),
    ("slack-token", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}")),
    ("npm-token", re.compile(r"\bnpm_[A-Za-z0-9]{36}\b")),
    ("google-api-key", re.compile(r"\bAIza[0-9A-Za-z\-_]{35}\b")),
    ("stripe-live-key", re.compile(r"\b(?:sk|rk)_live_[A-Za-z0-9]{16,}\b")),
]
ALLOWED_ENV_NAMES = {".env.example", ".env.sample", ".env.template"}
SENSITIVE_BASENAMES = {
    "id_rsa",
    "id_dsa",
    "id_ecdsa",
    "id_ed25519",
    "credentials.json",
    "secrets.json",
    "service-account.json",
}
SENSITIVE_SUFFIXES = (".pem", ".p12", ".pfx", ".keystore", ".jks", ".key")


class ScanError(Exception):
    pass


class AddSpec:
    def __init__(self, repo: str, untracked: bool, tracked: bool, paths: list[str]) -> None:
        self.repo = repo
        self.untracked = untracked
        self.tracked = tracked
        self.paths = paths


class CommitSpec:
    def __init__(
        self,
        repo: str,
        all_tracked: bool,
        pathspecs: list[str],
        adds: list[AddSpec],
    ) -> None:
        self.repo = repo
        self.all_tracked = all_tracked
        self.pathspecs = pathspecs
        self.adds = adds


def emit(permission: str, user_message: str = "", agent_message: str = "") -> None:
    payload: dict[str, str] = {"permission": permission}
    if user_message:
        payload["user_message"] = user_message
    if agent_message:
        payload["agent_message"] = agent_message
    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


def split_statements(command: str) -> list[list[str]]:
    statements: list[list[str]] = []
    current: list[str] = []
    buf: list[str] = []
    i = 0
    quote: str | None = None

    def flush_word() -> None:
        if buf:
            current.append("".join(buf))
            buf.clear()

    def flush_stmt() -> None:
        flush_word()
        if current:
            statements.append(list(current))
            current.clear()

    while i < len(command):
        char = command[i]
        if quote:
            if char == quote:
                quote = None
                i += 1
                continue
            if char == "\\" and quote == '"' and i + 1 < len(command):
                buf.append(command[i + 1])
                i += 2
                continue
            buf.append(char)
            i += 1
            continue
        if char in "\"'":
            quote = char
            i += 1
            continue
        if char == "\\" and i + 1 < len(command):
            buf.append(command[i + 1])
            i += 2
            continue
        if char.isspace():
            flush_word()
            if char == "\n":
                flush_stmt()
            i += 1
            continue
        if command.startswith("&&", i) or command.startswith("||", i):
            flush_stmt()
            i += 2
            continue
        if char in ";&|":
            flush_stmt()
            i += 1
            continue
        buf.append(char)
        i += 1
    flush_stmt()
    return statements


def strip_prefixes(words: list[str]) -> list[str]:
    index = 0
    while index < len(words) and ENV_ASSIGN.match(words[index]):
        index += 1
    while index < len(words) and words[index] in {"sudo", "command", "exec", "nohup"}:
        if words[index] == "sudo":
            index += 1
            while index < len(words) and words[index].startswith("-"):
                flag = words[index]
                index += 1
                if flag in {"-u", "-g", "-p"} and index < len(words):
                    index += 1
            continue
        index += 1
    return words[index:]


def shell_script(words: list[str]) -> str | None:
    index = 1
    while index < len(words):
        word = words[index]
        if word == "-c" or (
            word.startswith("-") and not word.startswith("--") and "c" in word[1:]
        ):
            if index + 1 < len(words):
                return words[index + 1]
            return None
        if word == "--" or not word.startswith("-"):
            return None
        index += 1
    return None


def git_invocation(words: list[str]) -> tuple[str | None, str | None, list[str]] | None:
    if not words or os.path.basename(words[0]) != "git":
        return None
    cwd: str | None = None
    index = 1
    while index < len(words):
        arg = words[index]
        if arg == "--":
            return cwd, None, []
        if arg in GIT_GLOBAL_WITH_VALUE:
            if index + 1 >= len(words):
                return cwd, None, []
            if arg == "-C":
                cwd = words[index + 1]
            index += 2
            continue
        if arg.startswith("-C") and len(arg) > 2:
            cwd = arg[2:]
            index += 1
            continue
        if arg.startswith("-c") and arg != "-c":
            index += 1
            continue
        if any(
            arg.startswith(prefix + "=")
            for prefix in (
                "--git-dir",
                "--work-tree",
                "--namespace",
                "--exec-path",
                "--config-env",
                "--super-prefix",
            )
        ):
            index += 1
            continue
        if arg.startswith("-"):
            index += 1
            continue
        return cwd, arg, words[index + 1 :]
    return cwd, None, []


def parse_commit_args(args: list[str]) -> tuple[bool, list[str]]:
    all_tracked = False
    pathspecs: list[str] = []
    index = 0
    while index < len(args):
        arg = args[index]
        if arg == "--":
            pathspecs.extend(args[index + 1 :])
            break
        if arg in {"-a", "--all"}:
            all_tracked = True
            index += 1
            continue
        if arg.startswith("-") and not arg.startswith("--") and len(arg) > 2:
            consumes = False
            for char in arg[1:]:
                if char == "a":
                    all_tracked = True
                elif char in {"m", "F", "c", "C", "u", "S"}:
                    consumes = True
            index += 2 if consumes and index + 1 < len(args) else 1
            continue
        if arg.startswith("-m") and arg != "-m" and not arg.startswith("--"):
            index += 1
            continue
        if arg in COMMIT_WITH_VALUE:
            index += 2 if index + 1 < len(args) else 1
            continue
        if arg.startswith("--") and "=" in arg:
            index += 1
            continue
        if arg.startswith("-"):
            index += 1
            continue
        pathspecs.append(arg)
        index += 1
    return all_tracked, pathspecs


def parse_add_args(args: list[str]) -> tuple[bool, bool, list[str]]:
    untracked = False
    tracked = False
    paths: list[str] = []
    index = 0
    while index < len(args):
        arg = args[index]
        if arg == "--":
            paths.extend(args[index + 1 :])
            break
        if arg in {"-A", "--all", "."}:
            untracked = True
            tracked = True
            index += 1
            continue
        if arg in {"-u", "--update"}:
            tracked = True
            index += 1
            continue
        if arg.startswith("-") and not arg.startswith("--") and len(arg) > 2:
            if "A" in arg[1:]:
                untracked = True
                tracked = True
            if "u" in arg[1:]:
                tracked = True
            index += 1
            continue
        if arg.startswith("-"):
            index += 1
            continue
        paths.append(arg)
        index += 1
    return untracked, tracked, paths


def resolve_repo(base: str, git_c: str | None) -> str:
    if not git_c:
        path = base
    elif os.path.isabs(git_c):
        path = git_c
    else:
        path = os.path.join(base, git_c)
    return os.path.realpath(path)


def walk(command: str, base_cwd: str, depth: int = 0) -> tuple[list[CommitSpec], bool]:
    commits: list[CommitSpec] = []
    push = False
    if depth > 5:
        return commits, push
    pending: list[AddSpec] = []
    for words in split_statements(command):
        words = strip_prefixes(words)
        if not words:
            continue
        if os.path.basename(words[0]) in SHELLS:
            script = shell_script(words)
            if script:
                nested_commits, nested_push = walk(script, base_cwd, depth + 1)
                commits.extend(nested_commits)
                push = push or nested_push
            continue
        parsed = git_invocation(words)
        if not parsed:
            continue
        git_c, sub, args = parsed
        if sub is None:
            continue
        repo = resolve_repo(base_cwd, git_c)
        if sub == "add":
            untracked, tracked, paths = parse_add_args(args)
            pending.append(AddSpec(repo, untracked, tracked, paths))
        elif sub == "commit":
            all_tracked, pathspecs = parse_commit_args(args)
            relevant = [item for item in pending if item.repo == repo]
            commits.append(CommitSpec(repo, all_tracked, pathspecs, relevant))
            pending = [item for item in pending if item.repo != repo]
        elif sub == "push":
            push = True
    return commits, push


def git_out(repo: str, args: list[str]) -> str:
    result = subprocess.run(
        ["git", "-C", repo, *args],
        capture_output=True,
        text=True,
        errors="replace",
    )
    if result.returncode != 0:
        raise ScanError("git の検査コマンドが失敗しました")
    return result.stdout


def ensure_work_tree(repo: str) -> None:
    result = subprocess.run(
        ["git", "-C", repo, "rev-parse", "--is-inside-work-tree"],
        capture_output=True,
        text=True,
        errors="replace",
    )
    if result.returncode != 0 or result.stdout.strip() != "true":
        raise ScanError("git リポジトリとして検査できません")


def has_head(repo: str) -> bool:
    result = subprocess.run(
        ["git", "-C", repo, "rev-parse", "--verify", "HEAD"],
        capture_output=True,
    )
    return result.returncode == 0


def is_tracked(repo: str, path: str) -> bool:
    result = subprocess.run(
        ["git", "-C", repo, "ls-files", "--error-unmatch", "--", path],
        capture_output=True,
    )
    return result.returncode == 0


def added_lines(diff: str) -> list[tuple[str, str]]:
    path = "?"
    found: list[tuple[str, str]] = []
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            path = line[6:]
        elif line.startswith("+++ /dev/null"):
            path = "?"
        elif line.startswith("+") and not line.startswith("+++"):
            found.append((path, line[1:]))
    return found


def sensitive_path(path: str) -> str | None:
    name = os.path.basename(path).lower()
    if name in ALLOWED_ENV_NAMES:
        return None
    if name == ".env" or name.startswith(".env."):
        return "sensitive-file"
    if name in SENSITIVE_BASENAMES or name.endswith(SENSITIVE_SUFFIXES):
        return "sensitive-file"
    return None


def normalize(path: str) -> str:
    return path.replace("\\", "/").rstrip("/")


def matches_pathspec(path: str, spec: str) -> bool:
    path = normalize(path)
    spec = normalize(spec)
    return path == spec or path.startswith(spec + "/") or spec.startswith(path + "/")


def selected(path: str, pathspecs: list[str]) -> bool:
    if not pathspecs:
        return True
    return any(matches_pathspec(path, spec) for spec in pathspecs)


def diff_pair(repo: str, cached: bool, paths: list[str] | None) -> tuple[str, list[str]]:
    diff_cmd = ["diff", "--no-color", "--unified=0"]
    name_cmd = ["diff", "--name-only"]
    if cached:
        diff_cmd.insert(1, "--cached")
        name_cmd.insert(1, "--cached")
    if paths:
        diff_cmd += ["--", *paths]
        name_cmd += ["--", *paths]
    diff = git_out(repo, diff_cmd)
    names = [name for name in git_out(repo, name_cmd).splitlines() if name]
    return diff, names


def untracked_files(repo: str, path: str | None = None) -> list[str]:
    cmd = ["ls-files", "-o", "--exclude-standard"]
    if path:
        cmd += ["--", path]
    return [name for name in git_out(repo, cmd).splitlines() if name]


def read_file(repo: str, path: str) -> str:
    full = os.path.join(repo, path)
    if not os.path.isfile(full):
        return ""
    with open(full, "r", encoding="utf-8", errors="replace") as handle:
        return handle.read(2_000_000)


def mark_name(path: str, findings: list[tuple[str, str]]) -> None:
    rule = sensitive_path(path)
    if rule:
        findings.append((rule, path))


def absorb_path(
    repo: str,
    path: str,
    pathspecs: list[str],
    lines: list[tuple[str, str]],
    findings: list[tuple[str, str]],
) -> None:
    if not selected(path, pathspecs):
        return
    full = os.path.join(repo, path)
    if os.path.isdir(full):
        for name in untracked_files(repo, path):
            if not selected(name, pathspecs):
                continue
            mark_name(name, findings)
            lines.append((name, read_file(repo, name)))
        if has_head(repo):
            diff = git_out(repo, ["diff", "--no-color", "--unified=0", "HEAD", "--", path])
            lines.extend(added_lines(diff))
            for name in git_out(repo, ["diff", "--name-only", "HEAD", "--", path]).splitlines():
                if name and selected(name, pathspecs):
                    mark_name(name, findings)
        return
    if not selected(path, pathspecs):
        return
    mark_name(path, findings)
    if is_tracked(repo, path) and has_head(repo):
        diff = git_out(repo, ["diff", "--no-color", "--unified=0", "HEAD", "--", path])
        lines.extend(added_lines(diff))
        return
    lines.append((path, read_file(repo, path)))


def scan_commit(spec: CommitSpec) -> list[tuple[str, str]]:
    ensure_work_tree(spec.repo)
    findings: list[tuple[str, str]] = []
    lines: list[tuple[str, str]] = []
    limit = spec.pathspecs or None

    def take_diff(cached: bool) -> None:
        diff, names = diff_pair(spec.repo, cached, limit)
        lines.extend(added_lines(diff))
        for name in names:
            if selected(name, spec.pathspecs):
                mark_name(name, findings)

    take_diff(True)
    if spec.all_tracked or any(add.tracked for add in spec.adds):
        take_diff(False)

    for add in spec.adds:
        if add.untracked:
            for name in untracked_files(spec.repo):
                if not selected(name, spec.pathspecs):
                    continue
                mark_name(name, findings)
                lines.append((name, read_file(spec.repo, name)))
        for path in add.paths:
            absorb_path(spec.repo, path, spec.pathspecs, lines, findings)

    for path, text in lines:
        for rule_id, pattern in SECRET_RULES:
            if pattern.search(text):
                findings.append((rule_id, path))

    unique: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for item in findings:
        if item in seen:
            continue
        seen.add(item)
        unique.append(item)
    return unique


def format_findings(findings: list[tuple[str, str]]) -> str:
    shown = findings[:5]
    parts = [f"{rule}: {path}" for rule, path in shown]
    text = "、".join(parts)
    extra = len(findings) - len(shown)
    if extra:
        text += f"、ほか {extra} 件"
    return text


def deny_secrets(findings: list[tuple[str, str]]) -> None:
    summary = format_findings(findings)
    emit(
        "deny",
        f"commit に秘密情報が含まれているため、中止しました。{summary}",
        "秘密情報を取り除いてから、改めて commit してください。",
    )


def deny_scan() -> None:
    emit(
        "deny",
        "commit 前の秘密検査が失敗したため、中止しました。",
        "git リポジトリを検査できないため、この commit は拒否しました。",
    )


def ask_push() -> None:
    emit(
        "ask",
        "remote への push を実行する前に確認してください。",
        "git push はユーザーの確認が必要です。承認されるまで待ってください。",
    )


def ask_mcp(tool: str) -> None:
    emit(
        "ask",
        f"GitHub 上のリポジトリを変更する前に確認してください。対象: {tool}",
        "この MCP 呼び出しは remote のファイルを変更します。ユーザーの承認が必要です。",
    )


def deny_input() -> None:
    emit(
        "deny",
        "フックの入力を読めないため、中止しました。",
        "hook の入力が不正なため、この操作は拒否しました。",
    )


def handle_shell(data: dict) -> None:
    command = data.get("command")
    cwd = data.get("cwd") or os.getcwd()
    if not isinstance(command, str) or not isinstance(cwd, str):
        deny_input()
        return
    commits, push = walk(command, cwd)
    findings: list[tuple[str, str]] = []
    try:
        for spec in commits:
            findings.extend(scan_commit(spec))
    except ScanError:
        deny_scan()
        return
    if findings:
        deny_secrets(findings)
        return
    if push:
        ask_push()
        return
    emit("allow")


def handle_mcp(data: dict) -> None:
    tool = data.get("tool_name")
    if not isinstance(tool, str) or not tool:
        deny_input()
        return
    if tool in REMOTE_WRITE_TOOLS:
        ask_mcp(tool)
        return
    emit("allow")


def main() -> None:
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        deny_input()
        return
    if not isinstance(data, dict):
        deny_input()
        return
    if mode == "shell":
        handle_shell(data)
        return
    if mode == "mcp":
        handle_mcp(data)
        return
    deny_input()


if __name__ == "__main__":
    main()

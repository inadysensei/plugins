#!/usr/bin/env node

import { readFileSync, readdirSync, realpathSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

// cursor/plugins#702 の SKILL_NAME。小文字の英数字をハイフンでつなぎ、64文字まで。
const SLUG = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const SLUG_MAX = 64;
const SLUG_RULE = "小文字の英数字をハイフンでつないだ64文字以内";

export function parseFrontmatter(content) {
  const normalized = content.replaceAll("\r\n", "\n");
  if (!normalized.startsWith("---\n")) {
    return null;
  }

  // 閉じの --- の直後が改行でもファイル末尾でも、そこで frontmatter を終える。
  const match = normalized.slice(4).match(/^([\s\S]*?)\n---(?:\n|$)/);
  if (!match) {
    return null;
  }

  const fields = {};
  const lines = match[1].split("\n");
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (!line.trim() || line.trim().startsWith("#") || /^\s/.test(line)) {
      continue;
    }

    const separator = line.indexOf(":");
    if (separator === -1) {
      continue;
    }

    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if (value === ">-" || value === ">" || value === "|" || value === "|-" || value === "|+") {
      const parts = [];
      while (index + 1 < lines.length) {
        const next = lines[index + 1];
        if (next.trim() !== "" && !/^\s/.test(next)) {
          break;
        }
        index += 1;
        if (next.trim() !== "") {
          parts.push(next.trim());
        }
      }
      value = value.startsWith(">") ? parts.join(" ") : parts.join("\n");
    } else if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    fields[key] = value;
  }

  return fields;
}

function isSlug(value) {
  return typeof value === "string" && value.length <= SLUG_MAX && SLUG.test(value);
}

function listDirectories(dir) {
  let entries;
  try {
    entries = readdirSync(dir);
  } catch {
    return [];
  }

  return entries.filter((entry) => {
    if (entry.startsWith(".")) {
      return false;
    }
    try {
      return statSync(path.join(dir, entry)).isDirectory();
    } catch {
      return false;
    }
  });
}

function readText(filePath) {
  try {
    return readFileSync(filePath, "utf8");
  } catch {
    return null;
  }
}

function locate(rootReal, target) {
  let real;
  try {
    real = realpathSync(target);
  } catch {
    return "missing";
  }
  if (real === rootReal || real.startsWith(`${rootReal}${path.sep}`)) {
    return "inside";
  }
  return "outside";
}

function checkSkill(rootReal, pluginName, skillsDir, folder, errors) {
  const label = `plugins/${pluginName}/skills/${folder}`;
  const skillDir = path.join(skillsDir, folder);
  if (locate(rootReal, skillDir) === "outside") {
    errors.push(`${label} は検査対象の外を指している`);
    return;
  }
  if (!statSync(skillDir).isDirectory()) {
    errors.push(`${label} はディレクトリである`);
    return;
  }

  if (!isSlug(folder)) {
    errors.push(`${label} は${SLUG_RULE}である`);
  }

  const skillFile = path.join(skillDir, "SKILL.md");
  const skillPlace = locate(rootReal, skillFile);
  if (skillPlace === "outside") {
    errors.push(`${label}/SKILL.md は検査対象の外を指している`);
    return;
  }
  if (skillPlace === "missing") {
    errors.push(`${label}/SKILL.md が無い`);
    return;
  }
  const content = readText(skillFile);
  if (content === null) {
    errors.push(`${label}/SKILL.md が無い`);
    return;
  }

  const frontmatter = parseFrontmatter(content);
  const name = frontmatter?.name;
  if (name !== folder) {
    errors.push(`${label}/SKILL.md の name は ${folder} である（今は ${JSON.stringify(name ?? "")}）`);
  }
  if (!isSlug(name)) {
    errors.push(`${label}/SKILL.md の name は${SLUG_RULE}である（今は ${JSON.stringify(name ?? "")}）`);
  }
}

function checkAgent(rootReal, pluginName, agentsDir, file, errors) {
  const label = `plugins/${pluginName}/agents/${file}`;
  const agentPath = path.join(agentsDir, file);
  if (locate(rootReal, agentPath) === "outside") {
    errors.push(`${label} は検査対象の外を指している`);
    return;
  }
  const content = readText(agentPath);
  if (content === null) {
    errors.push(`${label} が読めない`);
    return;
  }

  const name = parseFrontmatter(content)?.name;
  if (!isSlug(name)) {
    errors.push(`${label} の name は${SLUG_RULE}である（今は ${JSON.stringify(name ?? "")}）`);
  }
}

export function checkSkillNames(root) {
  const errors = [];
  let rootReal;
  try {
    rootReal = realpathSync(root);
  } catch {
    return [`${root} が無い`];
  }
  const pluginsDir = path.join(root, "plugins");

  for (const pluginName of listDirectories(pluginsDir)) {
    const pluginDir = path.join(pluginsDir, pluginName);
    if (locate(rootReal, pluginDir) === "outside") {
      errors.push(`plugins/${pluginName} は検査対象の外を指している`);
      continue;
    }
    const skillsDir = path.join(pluginDir, "skills");
    for (const folder of listDirectories(skillsDir)) {
      checkSkill(rootReal, pluginName, skillsDir, folder, errors);
    }

    const agentsDir = path.join(pluginDir, "agents");
    let agentEntries = [];
    try {
      agentEntries = readdirSync(agentsDir);
    } catch {
      agentEntries = [];
    }
    for (const file of agentEntries) {
      if (!file.endsWith(".md") || file.startsWith(".")) {
        continue;
      }
      const agentPath = path.join(agentsDir, file);
      try {
        if (!statSync(agentPath).isFile()) {
          continue;
        }
      } catch {
        continue;
      }
      checkAgent(rootReal, pluginName, agentsDir, file, errors);
    }
  }

  return errors;
}

function isDirectRun() {
  const entry = process.argv[1];
  if (!entry) {
    return false;
  }
  return import.meta.url === pathToFileURL(path.resolve(entry)).href;
}

if (isDirectRun()) {
  const defaultRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
  const root = process.argv[2] ? path.resolve(process.argv[2]) : defaultRoot;
  const errors = checkSkillNames(root);
  if (errors.length > 0) {
    console.error("検査に失敗した:");
    for (const error of errors) {
      console.error(`- ${error}`);
    }
    process.exit(1);
  }
  console.log("検査に通った。");
}

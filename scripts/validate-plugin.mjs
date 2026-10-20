#!/usr/bin/env node

import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { checkSkillNames, parseFrontmatter } from "./check-skill-names.mjs";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const defaultRoot = path.resolve(scriptDir, "..");
const root = process.argv[2] ? path.resolve(process.argv[2]) : defaultRoot;
const cursorNamePattern = /^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$/;
const marketplaceNamePattern = /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/;
const errors = [];

function addError(message) {
  errors.push(message);
}

function readJsonFile(filePath, label) {
  let raw;
  try {
    raw = readFileSync(filePath, "utf8");
  } catch {
    addError(`${label} が無い`);
    return null;
  }

  try {
    return JSON.parse(raw);
  } catch (error) {
    addError(`${label} の JSON が壊れている: ${error.message}`);
    return null;
  }
}

function readJson(relativePath) {
  return readJsonFile(path.join(root, relativePath), relativePath);
}

function pointer(instancePath, key) {
  const token = String(key).replaceAll("~", "~0").replaceAll("/", "~1");
  return `${instancePath}/${token}`;
}

function validateSchema(data, schema, instancePath) {
  if (schema.const !== undefined && data !== schema.const) {
    addError(`${instancePath} は ${JSON.stringify(schema.const)} である`);
    return;
  }

  if (schema.type === "object") {
    if (data === null || typeof data !== "object" || Array.isArray(data)) {
      addError(`${instancePath} は object である`);
      return;
    }

    for (const key of schema.required ?? []) {
      if (!Object.hasOwn(data, key)) {
        addError(`${pointer(instancePath, key)} が無い`);
      }
    }

    const properties = schema.properties ?? {};
    for (const [key, value] of Object.entries(data)) {
      const childPath = pointer(instancePath, key);
      if (Object.hasOwn(properties, key)) {
        validateSchema(value, properties[key], childPath);
        continue;
      }

      if (schema.additionalProperties === false) {
        addError(`${childPath} はスキーマに無い`);
        continue;
      }

      if (schema.additionalProperties && typeof schema.additionalProperties === "object") {
        validateSchema(value, schema.additionalProperties, childPath);
      }
    }
    return;
  }

  if (schema.type === "array") {
    if (!Array.isArray(data)) {
      addError(`${instancePath} は array である`);
      return;
    }

    if (schema.items) {
      for (const [index, item] of data.entries()) {
        validateSchema(item, schema.items, pointer(instancePath, index));
      }
    }
    return;
  }

  if (schema.type === "string") {
    if (typeof data !== "string") {
      addError(`${instancePath} は string である`);
      return;
    }

    if (schema.minLength !== undefined && data.length < schema.minLength) {
      addError(`${instancePath} は ${schema.minLength} 文字以上である`);
    }
    if (schema.maxLength !== undefined && data.length > schema.maxLength) {
      addError(`${instancePath} は ${schema.maxLength} 文字以下である`);
    }
    if (schema.pattern !== undefined && !new RegExp(schema.pattern, "u").test(data)) {
      addError(`${instancePath} が pattern に合わない`);
    }
  }
}

function sameIdentity(label, manifest, agent) {
  if (!manifest) {
    return;
  }

  if (manifest.name !== agent.name) {
    addError(`${label} の name が plugin.json と違う`);
  }
  if (typeof manifest.version !== "string" || manifest.version.length === 0) {
    addError(`${label} の version が無い`);
    return;
  }
  if (manifest.version !== agent.version) {
    addError(`${label} の version が plugin.json と違う`);
  }
}

function validateCursor(manifest, label) {
  if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) {
    addError(`${label} は object である`);
    return;
  }

  if (typeof manifest.name !== "string" || !cursorNamePattern.test(manifest.name)) {
    addError(`${label} の name は小文字の英数字、ハイフン、ピリオドである`);
  }

  for (const key of ["description", "displayName", "license"]) {
    if (Object.hasOwn(manifest, key) && typeof manifest[key] !== "string") {
      addError(`${label} の ${key} は string である`);
    }
  }

  if (Object.hasOwn(manifest, "author")) {
    const author = manifest.author;
    if (author === null || typeof author !== "object" || Array.isArray(author)) {
      addError(`${label} の author は object である`);
    } else if (Object.hasOwn(author, "name") && typeof author.name !== "string") {
      addError(`${label} の author.name は string である`);
    }
  }

  if (Object.hasOwn(manifest, "keywords")) {
    if (!Array.isArray(manifest.keywords) || manifest.keywords.some((item) => typeof item !== "string")) {
      addError(`${label} の keywords は string の配列である`);
    }
  }
}

function normalizeSource(source) {
  return path.posix.normalize(String(source).replaceAll("\\", "/")).replace(/^\.\//, "");
}

function isPluginSource(source) {
  if (typeof source !== "string" || source.length === 0 || path.isAbsolute(source)) {
    return false;
  }
  const normalized = normalizeSource(source);
  return (
    normalized.startsWith("plugins/") &&
    normalized !== "plugins" &&
    !normalized.startsWith("../") &&
    !normalized.includes("/../")
  );
}

function validateSkills(source) {
  const skillsLabel = `${source}/skills`;
  const skillsDir = path.join(root, source, "skills");
  let entries;
  try {
    entries = readdirSync(skillsDir);
  } catch {
    addError(`${skillsLabel}/ が無い`);
    return;
  }

  const skillDirs = entries.filter((entry) => !entry.startsWith("."));
  if (skillDirs.length === 0) {
    addError(`${skillsLabel}/ にスキルが無い`);
    return;
  }

  for (const entry of skillDirs) {
    const skillDir = path.join(skillsDir, entry);
    const skillLabel = `${skillsLabel}/${entry}`;
    if (!statSync(skillDir).isDirectory()) {
      addError(`${skillLabel} はディレクトリである`);
      continue;
    }

    let content;
    try {
      content = readFileSync(path.join(skillDir, "SKILL.md"), "utf8");
    } catch {
      addError(`${skillLabel}/SKILL.md が無い`);
      continue;
    }

    const frontmatter = parseFrontmatter(content);
    if (!frontmatter) {
      addError(`${skillLabel}/SKILL.md に frontmatter が無い`);
      continue;
    }

    if (!frontmatter.description) {
      addError(`${skillLabel}/SKILL.md の description が無い`);
    }
  }
}

function validateMarketplace(manifest, label) {
  if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) {
    addError(`${label} は object である`);
    return false;
  }

  if (typeof manifest.name !== "string" || !marketplaceNamePattern.test(manifest.name)) {
    addError(`${label} の name は小文字のケバブケースである`);
  }
  if (!manifest.owner || typeof manifest.owner.name !== "string" || manifest.owner.name.length === 0) {
    addError(`${label} の owner.name が無い`);
  }
  if (!Array.isArray(manifest.plugins) || manifest.plugins.length === 0) {
    addError(`${label} の plugins は空でない配列である`);
    return false;
  }

  return true;
}

function rejectRootPlugin() {
  for (const relativePath of [
    "plugin.json",
    ".cursor-plugin/plugin.json",
    "skills",
  ]) {
    try {
      statSync(path.join(root, relativePath));
      addError(`${relativePath} はルートに置かない。plugins/ の中に置く`);
    } catch {
      // ルートは marketplace なので、プラグイン本体が無いのが正しい。
    }
  }
}

function validatePluginFile(source, fileValue, label) {
  if (fileValue.startsWith("http://") || fileValue.startsWith("https://")) {
    return;
  }
  if (path.isAbsolute(fileValue)) {
    addError(`${label} はプラグイン内の相対パスである`);
    return;
  }

  const normalized = path.posix.normalize(fileValue.replaceAll("\\", "/"));
  if (normalized.startsWith("../") || normalized === "..") {
    addError(`${label} はプラグイン内の相対パスである`);
    return;
  }

  const filePath = path.join(root, source, normalized);
  try {
    if (!statSync(filePath).isFile()) {
      addError(`${label} はファイルである`);
    }
  } catch {
    addError(`${source}/${normalized} が無い`);
  }
}

function validatePlugin(entry, label) {
  if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
    addError(`${label} は object である`);
    return;
  }
  if (typeof entry.name !== "string" || !cursorNamePattern.test(entry.name)) {
    addError(`${label} の name は小文字の英数字、ハイフン、ピリオドである`);
    return;
  }
  if (!isPluginSource(entry.source)) {
    addError(`${label} の source は plugins/ 以下の相対パスである`);
    return;
  }

  const source = normalizeSource(entry.source);
  if (path.posix.basename(source) !== entry.name) {
    addError(`${label} の source のディレクトリ名は ${entry.name} である`);
  }

  const pluginDir = path.join(root, source);
  try {
    if (!statSync(pluginDir).isDirectory()) {
      addError(`${source} はディレクトリである`);
      return;
    }
  } catch {
    addError(`${source} が無い`);
    return;
  }

  const agentLabel = `${source}/plugin.json`;
  const agent = readJson(agentLabel);
  if (schema && agent) {
    validateSchema(agent, schema, agentLabel);
  }
  if (agent && (typeof agent.version !== "string" || agent.version.length === 0)) {
    addError(`${agentLabel} の version が無い`);
  }
  if (!agent) {
    return;
  }

  const cursorLabel = `${source}/.cursor-plugin/plugin.json`;
  const cursor = readJson(cursorLabel);
  validateCursor(cursor, cursorLabel);
  if (cursor && typeof cursor.logo === "string") {
    validatePluginFile(source, cursor.logo, `${cursorLabel} の logo`);
  }
  sameIdentity(cursorLabel, cursor, agent);
  validateSkills(source);
}

const schema = readJsonFile(
  path.join(scriptDir, "schemas/agent-plugins-1.0.0-plugin.schema.json"),
  "scripts/schemas/agent-plugins-1.0.0-plugin.schema.json",
);
rejectRootPlugin();

const cursorMarketplace = readJson(".cursor-plugin/marketplace.json");
const cursorOk = validateMarketplace(cursorMarketplace, ".cursor-plugin/marketplace.json");

if (cursorOk) {
  const seen = new Set();
  for (const [index, entry] of cursorMarketplace.plugins.entries()) {
    const label = `.cursor-plugin/marketplace.json plugins[${index}]`;
    if (entry && seen.has(entry.name)) {
      addError(`${label} の name が重複している`);
    }
    if (entry?.name) {
      seen.add(entry.name);
    }
    validatePlugin(entry, label);
  }
}

for (const message of checkSkillNames(root)) {
  addError(message);
}

if (errors.length > 0) {
  console.error("検査に失敗した:");
  for (const error of errors) {
    console.error(`- ${error}`);
  }
  process.exit(1);
}

console.log("検査に通った。");

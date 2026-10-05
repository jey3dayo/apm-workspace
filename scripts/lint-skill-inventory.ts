#!/usr/bin/env tsx

import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, "..");

const manifestPath = process.env.APM_LINT_SKILL_INVENTORY_MANIFEST ?? path.join(REPO_ROOT, "apm.yml");
const lockPath = process.env.APM_LINT_SKILL_INVENTORY_LOCK ?? path.join(REPO_ROOT, "apm.lock.yaml");
const inventoryPath =
  process.env.APM_LINT_SKILL_INVENTORY_DOC ?? path.join(REPO_ROOT, "docs", "skill-inventory.md");

const LOCAL_CATALOG_REPO = "jey3dayo/apm-workspace";
const EXTERNAL_SKILLS_HEADING = "## global（外部スキル: root apm.yml）";

function parseApmMcpNames(manifest: string): string[] {
  const names: string[] = [];
  for (const line of manifest.split("\n")) {
    const match = line.match(/^    - name: (\S+)/);
    if (match) names.push(match[1]);
  }
  return names.sort();
}

function parseInventoryMcpNames(inventory: string): string[] | null {
  const heading = "## global MCP";
  const start = inventory.indexOf(heading);
  if (start === -1) return null;

  const afterHeading = inventory.slice(start + heading.length);
  for (const line of afterHeading.split("\n")) {
    const trimmed = line.trim();
    if (trimmed.length === 0) continue;
    if (trimmed.startsWith("##")) break;
    if (!trimmed.startsWith("`")) continue;
    const names = [...trimmed.matchAll(/`([^`]+)`/g)].map((match) => match[1]);
    return names.sort();
  }
  return null;
}

function parseLockExternalSkillNames(lock: string): string[] {
  const names = new Set<string>();
  let inDependencies = false;
  let isExternal = false;
  for (const line of lock.split("\n")) {
    if (!line.startsWith(" ") && !line.startsWith("-")) {
      inDependencies = line.trim() === "dependencies:";
      continue;
    }
    if (!inDependencies) continue;
    const repo = line.match(/^- repo_url: (\S+)/);
    if (repo) {
      isExternal = repo[1] !== LOCAL_CATALOG_REPO;
      continue;
    }
    if (!isExternal) continue;
    const skill = line.match(/^ {2}- \.claude\/skills\/([^/\s]+)$/);
    if (skill) names.add(skill[1]);
  }
  return [...names].sort();
}

function parseInventoryExternalSkillNames(inventory: string): string[] | null {
  const start = inventory.indexOf(EXTERNAL_SKILLS_HEADING);
  if (start === -1) return null;

  const names = new Set<string>();
  for (const line of inventory.slice(start + EXTERNAL_SKILLS_HEADING.length).split("\n")) {
    if (line.startsWith("## ")) break;
    for (const match of line.matchAll(/`([^`]+)`/g)) {
      if (/^[a-z0-9][a-z0-9-]*$/.test(match[1])) names.add(match[1]);
    }
  }
  return [...names].sort();
}

function setsEqual(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  return a.every((value, index) => value === b[index]);
}

function checkMcp(inventory: string): number {
  if (!fs.existsSync(manifestPath)) {
    console.error(`Missing manifest: ${manifestPath}`);
    return 1;
  }

  const manifest = fs.readFileSync(manifestPath, "utf8");

  const manifestNames = parseApmMcpNames(manifest);
  const inventoryNames = parseInventoryMcpNames(inventory);

  if (inventoryNames === null) {
    console.error(
      `${inventoryPath}: could not find a backtick MCP list under "## global MCP"`,
    );
    return 1;
  }

  if (manifestNames.length === 0) {
    console.error(`${manifestPath}: no MCP entries found (expected "    - name:" lines)`);
    return 1;
  }

  if (!setsEqual(manifestNames, inventoryNames)) {
    console.error("docs/skill-inventory.md global MCP list does not match apm.yml:");
    console.error(`  apm.yml:           ${manifestNames.join(", ")}`);
    console.error(`  skill-inventory:   ${inventoryNames.join(", ")}`);
    console.error(
      "Update the backtick line under \"## global MCP\" in docs/skill-inventory.md.",
    );
    return 1;
  }

  return 0;
}

function checkExternalSkills(inventory: string): number {
  if (!fs.existsSync(lockPath)) {
    console.error(`Missing lockfile: ${lockPath}`);
    return 1;
  }

  const lockNames = parseLockExternalSkillNames(fs.readFileSync(lockPath, "utf8"));
  const inventoryNames = parseInventoryExternalSkillNames(inventory);

  if (inventoryNames === null) {
    console.error(`${inventoryPath}: could not find "${EXTERNAL_SKILLS_HEADING}"`);
    return 1;
  }

  if (lockNames.length === 0) {
    console.error(
      `${lockPath}: no external skills found (expected "  - .claude/skills/<name>" entries)`,
    );
    return 1;
  }

  const onlyInLock = lockNames.filter((name) => !inventoryNames.includes(name));
  const onlyInInventory = inventoryNames.filter((name) => !lockNames.includes(name));
  if (onlyInLock.length > 0 || onlyInInventory.length > 0) {
    console.error("docs/skill-inventory.md global external skill list does not match apm.lock.yaml:");
    console.error(`  only in apm.lock.yaml:   ${onlyInLock.join(", ")}`);
    console.error(`  only in skill-inventory: ${onlyInInventory.join(", ")}`);
    console.error(`Update the list under "${EXTERNAL_SKILLS_HEADING}" in docs/skill-inventory.md.`);
    return 1;
  }

  return 0;
}

function main(): number {
  if (!fs.existsSync(inventoryPath)) {
    console.error(`Missing inventory doc: ${inventoryPath}`);
    return 1;
  }

  const inventory = fs.readFileSync(inventoryPath, "utf8");
  const mcpStatus = checkMcp(inventory);
  const skillsStatus = checkExternalSkills(inventory);
  return mcpStatus === 0 && skillsStatus === 0 ? 0 : 1;
}

process.exit(main());

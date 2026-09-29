#!/usr/bin/env tsx

import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, "..");

const manifestPath = process.env.APM_LINT_SKILL_INVENTORY_MANIFEST ?? path.join(REPO_ROOT, "apm.yml");
const inventoryPath =
  process.env.APM_LINT_SKILL_INVENTORY_DOC ?? path.join(REPO_ROOT, "docs", "skill-inventory.md");

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

function setsEqual(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  return a.every((value, index) => value === b[index]);
}

function main(): number {
  if (!fs.existsSync(manifestPath)) {
    console.error(`Missing manifest: ${manifestPath}`);
    return 1;
  }
  if (!fs.existsSync(inventoryPath)) {
    console.error(`Missing inventory doc: ${inventoryPath}`);
    return 1;
  }

  const manifest = fs.readFileSync(manifestPath, "utf8");
  const inventory = fs.readFileSync(inventoryPath, "utf8");

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

process.exit(main());

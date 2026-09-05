#!/usr/bin/env tsx

// Validates YAML frontmatter in the managed catalog (catalog/agents,
// catalog/skills, catalog/commands, catalog/rules). `mise run check` never
// parsed frontmatter, so an unquoted "key: value: more" in a `description`
// field (broken YAML: a colon+space inside a plain scalar) passed the gate
// and was distributed as-is (five catalog agent files, fixed in commit
// 5efd532).
//
// yamllint is delegated to for syntax validation rather than reimplementing
// a YAML parser here: it is already mise-managed (pipx:yamllint) and
// `-d relaxed` reports the broken-colon case as an `error` (syntax) while
// keeping line-length and other style nits as non-failing warnings, so a
// well-formed but verbose `description` does not fail the gate.

import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import * as os from "node:os";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, "..");

const DEFAULT_TARGET_SUBDIRS = ["catalog/agents", "catalog/skills", "catalog/commands", "catalog/rules"];

// Files under these subdirs must additionally declare `name` and
// `description` keys in frontmatter (value contents are not checked, only
// key presence).
function requiresNameAndDescription(filePath: string): boolean {
  const base = path.basename(filePath);
  if (base === "SKILL.md") return true;
  // Matches catalog/agents/*.md in the real catalog, and an "agents/*.md"
  // fixture directory in tests (which does not sit under a "catalog" root).
  const parentDir = path.basename(path.dirname(filePath));
  if (parentDir === "agents" && base.endsWith(".md")) return true;
  return false;
}

interface FrontmatterBlock {
  /** Frontmatter content (lines between the two `---` delimiters), joined with \n. */
  content: string;
  /** 1-based line number in the original file where the frontmatter content starts. */
  startLine: number;
}

function extractFrontmatter(fileContent: string): FrontmatterBlock | null | "unterminated" {
  const eol = fileContent.includes("\r\n") ? "\r\n" : "\n";
  const lines = fileContent.split(eol);

  if (lines.length === 0 || lines[0].trim() !== "---") {
    return null;
  }

  for (let i = 1; i < lines.length; i++) {
    if (lines[i].trim() === "---") {
      const contentLines = lines.slice(1, i);
      return { content: contentLines.join("\n"), startLine: 2 };
    }
  }

  return "unterminated";
}

function collectMarkdownFiles(targetDirs: string[]): string[] {
  const files = new Set<string>();

  const walk = (currentDir: string) => {
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(currentDir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const fullPath = path.join(currentDir, entry.name);
      if (entry.isDirectory()) {
        walk(fullPath);
        continue;
      }
      if (entry.isFile() && fullPath.endsWith(".md")) {
        files.add(fullPath);
      }
    }
  };

  for (const dir of targetDirs) {
    if (!fs.existsSync(dir)) continue;
    const stat = fs.statSync(dir);
    if (stat.isDirectory()) {
      walk(dir);
    } else if (stat.isFile() && dir.endsWith(".md")) {
      files.add(dir);
    }
  }

  return Array.from(files).sort();
}

function checkYamllintAvailable(): boolean {
  const result = spawnSync("yamllint", ["--version"], { encoding: "utf8" });
  return result.status === 0;
}

interface FailureLine {
  filePath: string;
  message: string;
}

// yamllint -d relaxed output lines look like:
//   2:36      error    syntax error: mapping values are not allowed here (syntax)
// We only care about `error`-level lines; `warning`-level lines (e.g.
// line-length) must not fail the gate.
const YAMLLINT_LINE_PATTERN = /^\s*(\d+):(\d+)\s+error\s+(.+)$/;

function lintFrontmatterYaml(filePath: string, block: { content: string; startLine: number }): FailureLine[] {
  const tmpFile = path.join(os.tmpdir(), `lint-frontmatter-${process.pid}-${Math.random().toString(36).slice(2)}.yaml`);
  const failures: FailureLine[] = [];

  try {
    // Always end the extracted block with a newline: yamllint's
    // new-line-at-end-of-file rule would otherwise fire as an artifact of
    // extraction (the source file's frontmatter is fine) rather than a real
    // problem in the source file.
    fs.writeFileSync(tmpFile, `${block.content}\n`, "utf8");
    const result = spawnSync("yamllint", ["-d", "relaxed", tmpFile], { encoding: "utf8" });

    if (result.status !== 0) {
      const outputLines = (result.stdout || "").split("\n");
      let matchedAny = false;
      for (const line of outputLines) {
        const match = line.match(YAMLLINT_LINE_PATTERN);
        if (!match) continue;
        matchedAny = true;
        const relativeLine = Number.parseInt(match[1], 10);
        const col = match[2];
        const message = match[3];
        const actualLine = block.startLine + relativeLine - 1;
        failures.push({
          filePath,
          message: `${actualLine}:${col} ${message}`,
        });
      }
      if (!matchedAny) {
        // yamllint failed but produced no line we recognize as an error;
        // surface the raw output so the failure is not silently dropped.
        failures.push({
          filePath,
          message: `yamllint failed (exit ${result.status}): ${(result.stdout || result.stderr || "").trim()}`,
        });
      }
    }
  } finally {
    fs.rmSync(tmpFile, { force: true });
  }

  return failures;
}

function hasKey(yamlContent: string, key: string): boolean {
  const pattern = new RegExp(`^${key}\\s*:`, "m");
  return pattern.test(yamlContent);
}

function main() {
  const args = process.argv.slice(2);
  const targetDirs =
    args.length > 0
      ? args.map((arg) => path.resolve(process.cwd(), arg))
      : DEFAULT_TARGET_SUBDIRS.map((sub) => path.join(REPO_ROOT, sub));

  if (!checkYamllintAvailable()) {
    console.error("yamllint is required (mise-managed as pipx:yamllint) but was not found on PATH.");
    console.error("Run `mise install` or ensure the mise shims directory is on PATH.");
    process.exit(1);
  }

  const files = collectMarkdownFiles(targetDirs);
  const failures: FailureLine[] = [];
  let checkedCount = 0;

  for (const filePath of files) {
    const raw = fs.readFileSync(filePath, "utf8");
    const extracted = extractFrontmatter(raw);

    if (extracted === null) {
      // No frontmatter block: many reference .md files intentionally have
      // none. Not a failure.
      continue;
    }

    checkedCount += 1;

    if (extracted === "unterminated") {
      failures.push({
        filePath,
        message: "1:1 frontmatter block opened with '---' but never closed",
      });
      continue;
    }

    const yamlFailures = lintFrontmatterYaml(filePath, extracted);
    failures.push(...yamlFailures);

    if (requiresNameAndDescription(filePath)) {
      if (!hasKey(extracted.content, "name")) {
        failures.push({ filePath, message: "frontmatter is missing required key 'name'" });
      }
      if (!hasKey(extracted.content, "description")) {
        failures.push({ filePath, message: "frontmatter is missing required key 'description'" });
      }
    }
  }

  if (failures.length > 0) {
    console.error(`Frontmatter lint failed (${failures.length} issue(s)):`);
    for (const failure of failures) {
      console.error(`  ${failure.filePath}:${failure.message}`);
    }
    process.exit(1);
  }

  console.log(`Frontmatter lint passed: checked ${checkedCount} file(s) with frontmatter.`);
}

main();

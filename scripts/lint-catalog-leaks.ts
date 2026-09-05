#!/usr/bin/env tsx

// Checks the managed catalog for repository-specific values and references to
// agents that are not present in catalog/agents. Only catalog agents and
// skills are in scope; commands and rules deliberately remain untouched.

import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, "..");
const DEFAULT_TARGET_SUBDIRS = ["catalog/agents", "catalog/skills"];

const EXCLUDED_AGENTS = new Set([
  "Explore",
  "Plan",
  "general-purpose",
  "claude",
  "statusline-setup",
  "output-style-setup",
]);

interface Issue {
  filePath: string;
  line: number;
  message: string;
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
      } else if (entry.isFile() && fullPath.endsWith(".md")) {
        files.add(fullPath);
      }
    }
  };

  for (const targetDir of targetDirs) {
    if (!fs.existsSync(targetDir)) continue;
    const stat = fs.statSync(targetDir);
    if (stat.isDirectory()) walk(targetDir);
    else if (stat.isFile() && targetDir.endsWith(".md")) files.add(targetDir);
  }

  return Array.from(files).sort();
}

function findAgentDirectory(targetDirs: string[]): string {
  const explicitAgentsDir = targetDirs.find((targetDir) => path.basename(targetDir) === "agents");
  if (explicitAgentsDir) return explicitAgentsDir;

  const catalogDir = targetDirs.find((targetDir) => path.basename(targetDir) === "catalog");
  if (catalogDir) return path.join(catalogDir, "agents");

  const siblingAgentsDir = targetDirs
    .map((targetDir) => path.join(path.dirname(targetDir), "agents"))
    .find((candidate) => fs.existsSync(candidate));
  if (siblingAgentsDir) return siblingAgentsDir;

  return path.join(REPO_ROOT, "catalog", "agents");
}

function collectAgentNames(agentDirectory: string): Set<string> {
  return new Set(
    collectMarkdownFiles([agentDirectory]).map((filePath) => path.basename(filePath, ".md")),
  );
}

interface AgentReference {
  name: string;
  index: number;
}

function collectAgentReferences(content: string): AgentReference[] {
  // The reference syntax is intentionally explicit. The lowercase name
  // pattern prevents ordinary prose from being treated as an agent reference.
  const patterns = [
    /\(use[ \t]+([a-z][a-z0-9-]*)\)/g,
    /Agent:[ \t]*([a-z][a-z0-9-]*)/g,
    /`([a-z][a-z0-9-]*)`\s+agent\b/g,
    /\b([a-z][a-z0-9-]*)\s+agent連携/g,
    /→\s*([a-z][a-z0-9-]*)\s+agent\b/g,
  ];

  const references: AgentReference[] = [];
  for (const pattern of patterns) {
    for (const match of content.matchAll(pattern)) {
      const name = match[1];
      const index = match.index ?? 0;
      if (!EXCLUDED_AGENTS.has(name)) references.push({ name, index });
    }
  }

  return references.sort((left, right) => left.index - right.index);
}

function lineNumberAt(content: string, index: number): number {
  return content.slice(0, index).split("\n").length;
}

function addAgentReferenceFailures(
  filePath: string,
  content: string,
  agentNames: Set<string>,
  failures: Issue[],
) {
  const reported = new Set<string>();
  for (const reference of collectAgentReferences(content)) {
    if (agentNames.has(reference.name)) continue;

    const line = lineNumberAt(content, reference.index);
    const key = `${line}:${reference.name}`;
    if (reported.has(key)) continue;
    reported.add(key);
    failures.push({
      filePath,
      line,
      message: `unresolved agent reference: ${reference.name}`,
    });
  }
}

function addWarnings(filePath: string, content: string, warnings: Issue[]) {
  const warningPatterns = [
    {
      pattern: /--profile\s+([^\s"'`]+)/g,
      message: (match: RegExpMatchArray) => `repository-specific profile value: ${match[1]}`,
      shouldReport: (match: RegExpMatchArray) => {
        const value = match[1];
        return !value.startsWith("$") && !value.startsWith("<") && !value.startsWith("{") && !value.startsWith("your-");
      },
    },
    {
      pattern: /arn:aws:[^:]*:[^:]*:[0-9]{12}:/g,
      message: () => "account ID in AWS ARN",
      shouldReport: () => true,
    },
    {
      pattern: /\/Users\/[^/]+\/src\//g,
      message: () => "absolute repository checkout path",
      shouldReport: () => true,
    },
  ];

  for (const { pattern, message, shouldReport } of warningPatterns) {
    for (const match of content.matchAll(pattern)) {
      const asArray = Array.from(match) as RegExpMatchArray;
      if (!shouldReport(asArray)) continue;
      warnings.push({
        filePath,
        line: lineNumberAt(content, match.index ?? 0),
        message: message(asArray),
      });
    }
  }
}

function main() {
  const args = process.argv.slice(2);
  const targetDirs =
    args.length > 0
      ? args.map((arg) => path.resolve(process.cwd(), arg))
      : DEFAULT_TARGET_SUBDIRS.map((subdir) => path.join(REPO_ROOT, subdir));
  const files = collectMarkdownFiles(targetDirs);
  const agentNames = collectAgentNames(findAgentDirectory(targetDirs));
  const failures: Issue[] = [];
  const warnings: Issue[] = [];

  for (const filePath of files) {
    const content = fs.readFileSync(filePath, "utf8");
    addAgentReferenceFailures(filePath, content, agentNames, failures);
    addWarnings(filePath, content, warnings);
  }

  if (failures.length > 0) {
    console.error(`Catalog leak lint failed (${failures.length} issue(s)):`);
    for (const issue of failures) {
      console.error(`  ${issue.filePath}:${issue.line}: ${issue.message}`);
    }
    process.exit(1);
  }

  if (warnings.length > 0) {
    console.error(`Catalog leak lint: ${warnings.length} warning(s):`);
    for (const warning of warnings) {
      console.error(`  ${warning.filePath}:${warning.line}: ${warning.message}`);
    }
  }

  console.log(`Catalog leak lint passed: checked ${files.length} file(s).`);
}

main();

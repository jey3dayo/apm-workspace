#!/usr/bin/env tsx

// Checks the managed catalog for repository-specific values and references to
// agents that are not present in catalog/.apm/agents. Only catalog agents and
// skills are in scope; commands and rules deliberately remain untouched.
//
// Organization names must not appear anywhere in this public repository, but
// the list of names cannot be committed either. When a local denylist file
// exists (APM_LEAK_DENYLIST, default
// ${XDG_DATA_HOME:-~/.local/share}/apm-workspace/leak-denylist.txt, one term
// per line, `#` comments), every listed term fails the lint. With no
// arguments the denylist covers every git-tracked text file; with arguments it
// covers every text file under them. Listed terms are redacted from all output.

import { execFileSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, "..");
const DEFAULT_TARGET_SUBDIRS = ["catalog/.apm/agents", "catalog/.apm/skills"];

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
  if (catalogDir) return path.join(catalogDir, ".apm", "agents");

  const siblingAgentsDir = targetDirs
    .map((targetDir) => path.join(path.dirname(targetDir), "agents"))
    .find((candidate) => fs.existsSync(candidate));
  if (siblingAgentsDir) return siblingAgentsDir;

  return path.join(REPO_ROOT, "catalog", ".apm", "agents");
}

function collectAgentNames(agentDirectory: string): Set<string> {
  return new Set(
    collectMarkdownFiles([agentDirectory]).map((filePath) => path.basename(filePath).replace(/\.agent\.md$/, "")),
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

function denylistPath(): string {
  if (process.env.APM_LEAK_DENYLIST) return process.env.APM_LEAK_DENYLIST;
  const dataHome = process.env.XDG_DATA_HOME || path.join(os.homedir(), ".local", "share");
  return path.join(dataHome, "apm-workspace", "leak-denylist.txt");
}

function loadDenylist(): RegExp[] {
  const filePath = denylistPath();
  if (!fs.existsSync(filePath)) return [];
  return fs
    .readFileSync(filePath, "utf8")
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith("#"))
    .map((term) => {
      const escaped = term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      // Alphanumeric neighbours are excluded so a short term does not match
      // inside hashes or ordinary words.
      return new RegExp(`(?<![A-Za-z0-9])${escaped}(?![A-Za-z0-9])`, "gi");
    });
}

function collectTextFiles(targetDirs: string[]): string[] {
  const files = new Set<string>();
  const walk = (current: string) => {
    let stat: fs.Stats;
    try {
      stat = fs.statSync(current);
    } catch {
      return;
    }
    if (stat.isDirectory()) {
      if (path.basename(current) === ".git") return;
      for (const entry of fs.readdirSync(current)) walk(path.join(current, entry));
    } else if (stat.isFile()) {
      files.add(current);
    }
  };
  for (const targetDir of targetDirs) walk(targetDir);
  return Array.from(files).sort();
}

function collectTrackedFiles(): string[] {
  try {
    return execFileSync("git", ["-C", REPO_ROOT, "ls-files", "-z"], { encoding: "utf8" })
      .split("\0")
      .filter((file) => file.length > 0)
      .map((file) => path.join(REPO_ROOT, file))
      .filter((file) => fs.existsSync(file) && fs.statSync(file).isFile())
      .sort();
  } catch {
    return collectTextFiles([REPO_ROOT]);
  }
}

function readText(filePath: string): string | null {
  const buffer = fs.readFileSync(filePath);
  return buffer.includes(0) ? null : buffer.toString("utf8");
}

function redact(text: string, denylist: RegExp[]): string {
  return denylist.reduce((current, pattern) => current.replace(pattern, "<redacted>"), text);
}

function addDenylistPathFailure(filePath: string, denylist: RegExp[], failures: Issue[]) {
  const relativePath = path.relative(REPO_ROOT, filePath);
  if (denylist.some((pattern) => relativePath.search(pattern) !== -1)) {
    failures.push({ filePath, line: 0, message: "denylisted organization term in path" });
  }
}

function addDenylistFailures(filePath: string, content: string, denylist: RegExp[], failures: Issue[]) {
  for (const pattern of denylist) {
    for (const match of content.matchAll(pattern)) {
      // The matched text is not echoed so CI logs do not repeat the name.
      failures.push({
        filePath,
        line: lineNumberAt(content, match.index ?? 0),
        message: "denylisted organization term",
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
  const denylist = loadDenylist();
  const denylistFiles =
    denylist.length === 0 ? [] : args.length > 0 ? collectTextFiles(targetDirs) : collectTrackedFiles();
  const agentNames = collectAgentNames(findAgentDirectory(targetDirs));
  const failures: Issue[] = [];
  const warnings: Issue[] = [];

  for (const filePath of files) {
    const content = fs.readFileSync(filePath, "utf8");
    addAgentReferenceFailures(filePath, content, agentNames, failures);
    addWarnings(filePath, content, warnings);
  }

  for (const filePath of denylistFiles) {
    addDenylistPathFailure(filePath, denylist, failures);
    const content = readText(filePath);
    if (content !== null) addDenylistFailures(filePath, content, denylist, failures);
  }

  if (failures.length > 0) {
    console.error(`Catalog leak lint failed (${failures.length} issue(s)):`);
    for (const issue of failures) {
      console.error(redact(`  ${issue.filePath}:${issue.line}: ${issue.message}`, denylist));
    }
    process.exit(1);
  }

  if (warnings.length > 0) {
    console.error(`Catalog leak lint: ${warnings.length} warning(s):`);
    for (const warning of warnings) {
      console.error(redact(`  ${warning.filePath}:${warning.line}: ${warning.message}`, denylist));
    }
  }

  console.log(`Catalog leak lint passed: checked ${files.length} file(s).`);
}

try {
  main();
} catch (error) {
  // Unexpected errors (unreadable files etc.) can carry paths; redact them too.
  let denylist: RegExp[];
  try {
    denylist = loadDenylist();
  } catch {
    // Without the denylist nothing can be redacted, so print no details.
    console.error("Catalog leak lint crashed (details hidden: the denylist could not be read).");
    process.exit(2);
  }
  const message = error instanceof Error ? error.message : String(error);
  console.error(redact(`Catalog leak lint crashed: ${message}`, denylist));
  process.exit(2);
}

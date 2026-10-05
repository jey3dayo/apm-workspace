#!/usr/bin/env tsx

import { execFileSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const LOCK_NAME = "apm.lock.yaml";

interface Lock {
  commits: Map<string, string>;
  artifacts: Set<string>;
  targetCounts: Map<string, number>;
}

class LockDiffError extends Error {}

function unquote(value: string): string {
  return value.trim().replace(/^(['"])(.*)\1$/, "$2");
}

function parseLock(text: string, label: string): Lock {
  const commits = new Map<string, string>();
  const artifacts = new Set<string>();
  const targetCounts = new Map<string, number>();

  let section = "";
  let seenDependencies = false;
  let seenDeployments = false;
  let repoUrl = "";
  let virtualPath = "";
  let resolvedCommit = "";

  const flushDependency = () => {
    if (repoUrl) commits.set(virtualPath ? `${repoUrl} (${virtualPath})` : repoUrl, resolvedCommit);
    repoUrl = "";
    virtualPath = "";
    resolvedCommit = "";
  };

  for (const line of text.split("\n")) {
    const topLevel = line.match(/^([A-Za-z_][\w-]*):/);
    if (topLevel) {
      if (section === "dependencies") flushDependency();
      section = topLevel[1];
      seenDependencies ||= section === "dependencies";
      seenDeployments ||= section === "deployments";
      continue;
    }

    if (section === "dependencies") {
      const item = line.match(/^- repo_url:\s*(.+)$/);
      if (item) {
        flushDependency();
        repoUrl = unquote(item[1]);
        continue;
      }
      const field = line.match(/^ {2}(resolved_commit|virtual_path):\s*(.+)$/);
      if (field?.[1] === "resolved_commit") resolvedCommit = unquote(field[2]);
      if (field?.[1] === "virtual_path") virtualPath = unquote(field[2]);
    } else if (section === "deployments") {
      const field = line.match(/^(?:- | {2})(target|value):\s*(.+)$/);
      if (field?.[1] === "target") {
        const target = unquote(field[2]);
        targetCounts.set(target, (targetCounts.get(target) ?? 0) + 1);
      }
      if (field?.[1] === "value") artifacts.add(unquote(field[2]));
    }
  }
  if (section === "dependencies") flushDependency();

  if (!seenDependencies) throw new LockDiffError(`${label}: missing 'dependencies:' section`);
  if (!seenDeployments) throw new LockDiffError(`${label}: missing 'deployments:' section`);
  return { commits, artifacts, targetCounts };
}

function readFile(filePath: string, label: string): string {
  try {
    return fs.readFileSync(filePath, "utf8");
  } catch (error) {
    throw new LockDiffError(
      `cannot read ${label} (${filePath}): ${error instanceof Error ? error.message : String(error)}`,
    );
  }
}

function readBase(ref: string): { text: string; label: string } {
  const override = process.env.APM_LOCK_DIFF_BASE;
  if (override) return { text: readFile(override, "base"), label: `base (${override})` };
  if (ref.startsWith("-")) throw new LockDiffError(`invalid ref: ${ref}`);
  try {
    const text = execFileSync("git", ["show", `${ref}:${LOCK_NAME}`], {
      cwd: REPO_ROOT,
      encoding: "utf8",
      maxBuffer: 256 * 1024 * 1024,
      stdio: ["ignore", "pipe", "pipe"],
    });
    return { text, label: `base (${ref}:${LOCK_NAME})` };
  } catch (error) {
    const stderr = error instanceof Error && "stderr" in error ? String(error.stderr).trim() : "";
    throw new LockDiffError(`cannot read ${ref}:${LOCK_NAME}: ${stderr || String(error)}`);
  }
}

function readHead(): { text: string; label: string } {
  const filePath = process.env.APM_LOCK_DIFF_HEAD || path.join(REPO_ROOT, LOCK_NAME);
  return { text: readFile(filePath, "head"), label: `head (${filePath})` };
}

const short = (sha: string): string => sha.slice(0, 7);
const sorted = (values: Iterable<string>): string[] => [...values].sort();

function render(base: Lock, head: Lock): string {
  const out: string[] = [];

  out.push("== resolved_commit moves ==");
  const moved: string[] = [];
  const added: string[] = [];
  const removed: string[] = [];
  for (const key of sorted(head.commits.keys())) {
    const before = base.commits.get(key);
    const after = head.commits.get(key) ?? "";
    if (before === undefined) added.push(`${key} @ ${short(after)}`);
    else if (before !== after) moved.push(`${key}: ${short(before)} -> ${short(after)}`);
  }
  for (const key of sorted(base.commits.keys())) {
    if (!head.commits.has(key)) removed.push(`${key} @ ${short(base.commits.get(key) ?? "")}`);
  }
  if (moved.length + added.length + removed.length === 0) out.push("none");
  else {
    out.push(...moved);
    if (added.length > 0) out.push("added packages:", ...added.map((l) => `  ${l}`));
    if (removed.length > 0) out.push("removed packages:", ...removed.map((l) => `  ${l}`));
  }

  out.push("", "== deployment artifacts ==");
  const removedArtifacts = sorted(base.artifacts).filter((v) => !head.artifacts.has(v));
  const addedArtifacts = sorted(head.artifacts).filter((v) => !base.artifacts.has(v));
  out.push(`removed: ${removedArtifacts.length}`, ...removedArtifacts.map((v) => `  - ${v}`));
  out.push(`added: ${addedArtifacts.length}`, ...addedArtifacts.map((v) => `  + ${v}`));

  out.push("", "== target counts ==");
  const rows = sorted(new Set([...base.targetCounts.keys(), ...head.targetCounts.keys()]))
    .map((t) => ({ t, before: base.targetCounts.get(t) ?? 0, after: head.targetCounts.get(t) ?? 0 }))
    .filter((r) => r.before !== r.after)
    .map((r) => `${r.t}: ${r.before} -> ${r.after}`);
  out.push(...(rows.length > 0 ? rows : ["unchanged"]));

  return `${out.join("\n")}\n`;
}

try {
  const base = readBase(process.argv[2] ?? "HEAD");
  const head = readHead();
  process.stdout.write(render(parseLock(base.text, base.label), parseLock(head.text, head.label)));
} catch (error) {
  if (!(error instanceof LockDiffError)) throw error;
  process.stderr.write(`lock-diff: ${error.message}\n`);
  process.exit(1);
}
